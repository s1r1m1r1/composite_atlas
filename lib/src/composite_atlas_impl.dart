import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/rendering.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
// Direct imports for internal models since they are not exported by the main library
import 'package:flame_texturepacker/src/model/page.dart';
import 'package:flame_texturepacker/src/model/region.dart';

/// A runtime-composed texture atlas that merges multiple [BakeRequest]
/// sources into a single [ui.Image] to minimize draw calls.
abstract class CompositeAtlas {
  ui.Image get image;
  Sprite? findSpriteByName(String name);
  List<Sprite> findSpritesByName(String name);
  void dispose();

  /// Creates a [ui.ColorFilter] that shifts the hue by the given [radians].
  static ui.ColorFilter hue(double radians) =>
      CompositeAtlasImpl.hueFilter(radians);

  /// Bakes multiple [BakeRequest] instances into a single [CompositeAtlas].
  static Future<CompositeAtlas> bake(List<BakeRequest> requests) =>
      CompositeAtlasImpl.bake(requests);

  /// Creates a simple wrapper for a regular [TexturePackerAtlas] without baking.
  static CompositeAtlas fromAtlas(TexturePackerAtlas atlas) =>
      CompositeAtlasImpl.fromAtlas(atlas);
}

/// Represents a request to bake assets into a [CompositeAtlas].
abstract class BakeRequest {
  final ui.ColorFilter? filter;
  final Decorator? decorator;
  final String? keyPrefix;

  BakeRequest({this.filter, this.decorator, this.keyPrefix});
}

/// Request to bake an entire [TexturePackerAtlas] (optionally filtered by whitelist).
class AtlasBakeRequest extends BakeRequest {
  final TexturePackerAtlas atlas;
  final List<String>? whiteList;

  AtlasBakeRequest(
    this.atlas, {
    super.filter,
    super.decorator,
    super.keyPrefix,
    this.whiteList,
  });
}

/// Request to bake a standalone [Sprite] as a specific entry in the atlas.
class SpriteBakeRequest extends BakeRequest {
  final Sprite sprite;
  final String name;

  SpriteBakeRequest(
    this.sprite, {
    required this.name,
    super.filter,
    super.decorator,
    super.keyPrefix,
  });
}

/// Request to bake a raw [ui.Image] as a specific entry in the atlas.
class ImageBakeRequest extends BakeRequest {
  final ui.Image image;
  final String name;

  ImageBakeRequest(
    this.image, {
    required this.name,
    super.filter,
    super.decorator,
    super.keyPrefix,
  });
}

/// Implementation of the [CompositeAtlas] interface.
class CompositeAtlasImpl implements CompositeAtlas {
  @override
  final ui.Image image;
  final Map<String, Sprite> _spriteMap;

  CompositeAtlasImpl._(this.image, this._spriteMap);

  Map<String, Sprite> get spriteMap => _spriteMap;

  /// Global lock to prevent concurrent baking processes from overloading the GPU context.
  static Future<void>? _activeBake;

  /// Wraps a standard atlas into a [CompositeAtlas] interface without baking.
  static CompositeAtlas fromAtlas(TexturePackerAtlas atlas) {
    if (atlas.sprites.isEmpty) {
      throw StateError('Cannot wrap an empty atlas.');
    }
    final image = atlas.sprites.first.image;

    // Build a direct sprite map for lookup
    final Map<String, Sprite> spriteMap = {};
    for (final s in atlas.sprites) {
      final name = s.region.index == -1
          ? s.region.name
          : '${s.region.name}#${s.region.index}';
      spriteMap[name] = s;
    }

    return CompositeAtlasImpl._(image, spriteMap);
  }

  /// Bakes multiple [BakeRequest] instances into a single [CompositeAtlas].
  static Future<CompositeAtlasImpl> bake(List<BakeRequest> requests) async {
    // 0. Global synchronization to prevent "two GrContexts" GPU errors
    final previousBake = _activeBake;
    final completer = Completer<void>();
    _activeBake = completer.future;

    if (previousBake != null) {
      await previousBake;
    }

    try {
      // 1. Group requests by unique visual representation
      final Map<_RegionFilterKey, List<_PendingBake>> groupedTasks = {};

      for (final request in requests) {
        final prefix = request.keyPrefix ?? '';

        if (request is AtlasBakeRequest) {
          for (final sprite in request.atlas.sprites) {
            final region = sprite.region;
            if (request.whiteList != null) {
              if (!request.whiteList!.any(
                (w) => region.name == w || region.name.startsWith(w),
              )) {
                continue;
              }
            }
            final key = _RegionFilterKey(
              sprite.image,
              sprite.src,
              request.filter,
              request.decorator,
            );
            groupedTasks
                .putIfAbsent(key, () => [])
                .add(
                  _PendingBake(
                    sprite,
                    prefix,
                    region.name,
                    request.filter,
                    request.decorator,
                  ),
                );
          }
        } else if (request is SpriteBakeRequest) {
          final key = _RegionFilterKey(
            request.sprite.image,
            request.sprite.src,
            request.filter,
            request.decorator,
          );
          groupedTasks
              .putIfAbsent(key, () => [])
              .add(
                _PendingBake(
                  request.sprite,
                  prefix,
                  request.name,
                  request.filter,
                  request.decorator,
                ),
              );
        } else if (request is ImageBakeRequest) {
          final sprite = Sprite(request.image);
          final key = _RegionFilterKey(
            sprite.image,
            sprite.src,
            request.filter,
            request.decorator,
          );
          groupedTasks
              .putIfAbsent(key, () => [])
              .add(
                _PendingBake(
                  sprite,
                  prefix,
                  request.name,
                  request.filter,
                  request.decorator,
                ),
              );
        }
      }

      final List<_SpriteBakeInfo> spritesToBake = [];
      final Map<_RegionFilterKey, _SpriteBakeInfo> keyToInfo = {};

      // 2. Perform analysis - OPTIMIZED: only scan if decorator is present
      for (final entry in groupedTasks.entries) {
        final key = entry.key;
        final pending = entry.value;
        final first = pending.first;

        _SpriteBakeInfo info;
        if (first.decorator == null && first.sprite is TexturePackerSprite) {
          // FAST PATH: Use existing metadata for pre-packed atlas sprites
          final s = first.sprite as TexturePackerSprite;
          info = _SpriteBakeInfo(
            originalSprite: s,
            filter: first.filter,
            decorator: null,
            prefix: first.prefix,
            nameInAtlas: first.name,
            trimmedSrc: s.src,
            offsetX: s.region.offsetX,
            offsetY: s.region.offsetY,
            originalWidth: s.region.originalWidth,
            originalHeight: s.region.originalHeight,
            bakedImage: null,
          );
        } else {
          // ANALYSIS PATH: Pre-render and scan (required for decorators/standalone sprites)
          info = await _SpriteBakeInfo.analyze(
            sprite: first.sprite,
            filter: first.filter,
            decorator: first.decorator,
            prefix: first.prefix,
            name: first.name,
          );
        }

        keyToInfo[key] = info;

        for (final p in pending) {
          spritesToBake.add(info.withIdentity(prefix: p.prefix, name: p.name));
        }
      }

      if (spritesToBake.isEmpty) {
        throw StateError('No sprites found matching the bake requests.');
      }

      final List<_RegionFilterKey> sortedKeys = keyToInfo.keys.toList();
      sortedKeys.sort(
        (a, b) => keyToInfo[b]!.trimmedSrc.height.compareTo(
          keyToInfo[a]!.trimmedSrc.height,
        ),
      );

      // 3. Layout
      const double maxAtlasWidth = 1024.0; // Revert to stable width
      const double padding = 2.0;
      double currentX = 0;
      double currentY = 0;
      double currentRowHeight = 0;
      double maxWidth = 0;

      final Map<_RegionFilterKey, ui.Offset> drawingPositions = {};

      for (final key in sortedKeys) {
        final info = keyToInfo[key]!;
        final w = info.trimmedSrc.width;
        final h = info.trimmedSrc.height;

        if (currentX + w + padding > maxAtlasWidth && currentX > 0) {
          currentX = 0;
          currentY += currentRowHeight + padding;
          currentRowHeight = 0;
        }

        drawingPositions[key] = ui.Offset(currentX, currentY);
        maxWidth = math.max(maxWidth, currentX + w);
        currentRowHeight = math.max(currentRowHeight, h);
        currentX += w + padding;
      }

      final totalHeight = currentY + currentRowHeight;

      // 4. Draw
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final basePaint = ui.Paint()..filterQuality = ui.FilterQuality.none;

      for (final key in sortedKeys) {
        final pos = drawingPositions[key]!;
        final info = keyToInfo[key]!;

        // APPLY FILTER AT DRAW TIME IF NOT PRE-BAKED VIA DECORATOR
        final drawPaint = ui.Paint()
          ..filterQuality = ui.FilterQuality.none
          ..colorFilter = key.filter;

        final dst = ui.Rect.fromLTWH(
          pos.dx,
          pos.dy,
          info.trimmedSrc.width,
          info.trimmedSrc.height,
        );

        if (info.bakedImage != null) {
          // Decorators already draw with filter if set, so use basePaint
          canvas.drawImageRect(
            info.bakedImage!,
            info.trimmedSrc,
            dst,
            basePaint,
          );
        } else {
          canvas.drawImageRect(key.image, info.trimmedSrc, dst, drawPaint);
        }
      }

      final megaImage = await recorder.endRecording().toImage(
        maxWidth.ceil(),
        totalHeight.ceil(),
      );

      // 5. Cleanup temporary images
      for (final info in keyToInfo.values) {
        info.bakedImage?.dispose();
      }

      // 6. Build final Sprite map
      final spriteMap = <String, Sprite>{};
      final megaPage = Page()
        ..texture = megaImage
        ..width = megaImage.width
        ..height = megaImage.height;

      for (final info in spritesToBake) {
        final key = _RegionFilterKey(
          info.originalSprite.image,
          info.originalSprite.src,
          info.filter,
          info.decorator,
        );
        final pos = drawingPositions[key]!;

        final newRegion = Region(
          page: megaPage,
          name: info.nameInAtlas,
          left: pos.dx,
          top: pos.dy,
          width: info.trimmedSrc.width,
          height: info.trimmedSrc.height,
          offsetX: info.offsetX,
          offsetY: info.offsetY,
          originalWidth: info.originalWidth,
          originalHeight: info.originalHeight,
          degrees: 0,
          rotate: false,
          index: (info.originalSprite is TexturePackerSprite)
              ? (info.originalSprite as TexturePackerSprite).region.index
              : -1,
        );

        final newSprite = TexturePackerSprite(newRegion);
        newSprite.srcSize = newSprite.originalSize;

        final baseKey = newRegion.index == -1
            ? info.nameInAtlas
            : '${info.nameInAtlas}#${newRegion.index}';
        spriteMap['${info.prefix}$baseKey'] = newSprite;
      }

      return CompositeAtlasImpl._(megaImage, spriteMap);
    } finally {
      completer.complete();
    }
  }

  @override
  Sprite? findSpriteByName(String name) {
    if (_spriteMap.containsKey(name)) return _spriteMap[name];
    final lowerName = name.toLowerCase();
    for (final entry in _spriteMap.entries) {
      if (entry.key.toLowerCase() == lowerName) return entry.value;
    }
    return null;
  }

  @override
  List<Sprite> findSpritesByName(String name) {
    final List<TexturePackerSprite> result = [];
    final search = name.toLowerCase();
    final animPattern = RegExp('^${RegExp.escape(search)}[_-]?(#?\\d+)?\$');

    _spriteMap.forEach((key, sprite) {
      final lowerKey = key.toLowerCase();
      if (animPattern.hasMatch(lowerKey) && sprite is TexturePackerSprite) {
        result.add(sprite);
      }
    });

    if (result.isEmpty) return [];

    result.sort((a, b) {
      if (a.region.index != -1 && b.region.index != -1) {
        return a.region.index.compareTo(b.region.index);
      }
      final aNum = _extractTrailingNumber(a.region.name);
      final bNum = _extractTrailingNumber(b.region.name);
      if (aNum != bNum) return aNum.compareTo(bNum);
      return a.region.name.compareTo(b.region.name);
    });

    return result;
  }

  int _extractTrailingNumber(String s) {
    final match = RegExp(r'(\d+)$').firstMatch(s);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  static ui.ColorFilter hueFilter(double radians) {
    final cosT = math.cos(radians);
    final sinT = math.sin(radians);
    return ui.ColorFilter.matrix(<double>[
      0.213 + 0.787 * cosT - 0.213 * sinT,
      0.715 - 0.715 * cosT - 0.715 * sinT,
      0.072 - 0.072 * cosT + 0.928 * sinT,
      0,
      0,
      0.213 - 0.213 * cosT + 0.143 * sinT,
      0.715 + 0.285 * cosT + 0.140 * sinT,
      0.072 - 0.072 * cosT - 0.283 * sinT,
      0,
      0,
      0.213 - 0.213 * cosT - 0.787 * sinT,
      0.715 - 0.715 * cosT + 0.715 * sinT,
      0.072 + 0.928 * cosT + 0.072 * sinT,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  @override
  void dispose() => image.dispose();
}

class _SpriteBakeInfo {
  final Sprite originalSprite;
  final ui.ColorFilter? filter;
  final Decorator? decorator;
  final String prefix;
  final String nameInAtlas;
  final ui.Rect trimmedSrc;
  final double offsetX;
  final double offsetY;
  final double originalWidth;
  final double originalHeight;
  final ui.Image? bakedImage;

  _SpriteBakeInfo({
    required this.originalSprite,
    this.filter,
    this.decorator,
    required this.prefix,
    required this.nameInAtlas,
    required this.trimmedSrc,
    required this.offsetX,
    required this.offsetY,
    required this.originalWidth,
    required this.originalHeight,
    this.bakedImage,
  });

  /// Creates a copy of this info with a different prefix and name.
  _SpriteBakeInfo withIdentity({required String prefix, required String name}) {
    return _SpriteBakeInfo(
      originalSprite: originalSprite,
      filter: filter,
      decorator: decorator,
      prefix: prefix,
      nameInAtlas: name,
      trimmedSrc: trimmedSrc,
      offsetX: offsetX,
      offsetY: offsetY,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
      bakedImage: bakedImage,
    );
  }

  /// Analyzes a sprite to compute its non-transparent bounding box for trimming.
  static Future<_SpriteBakeInfo> analyze({
    required Sprite sprite,
    required ui.ColorFilter? filter,
    required Decorator? decorator,
    required String prefix,
    required String name,
  }) async {
    try {
      ui.Image targetImage = sprite.image;
      ui.Rect scanSrc = sprite.src;
      const double margin = 10.0;
      bool found = false;

      bool isTemporary = false;
      if (decorator != null) {
        final double width = sprite.src.width + margin * 2;
        final double height = sprite.src.height + margin * 2;

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
        if (filter != null) paint.colorFilter = filter;

        final drawRect = ui.Rect.fromLTWH(
          margin,
          margin,
          sprite.src.width,
          sprite.src.height,
        );
        decorator.applyChain((ui.Canvas c) {
          c.drawImageRect(sprite.image, sprite.src, drawRect, paint);
        }, canvas);

        targetImage = await recorder.endRecording().toImage(
          width.ceil().toInt(),
          height.ceil().toInt(),
        );
        scanSrc = ui.Rect.fromLTWH(0, 0, width, height);
        isTemporary = true;
      }

      final byteData = await targetImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      ui.Rect trimmedSrc = isTemporary
          ? ui.Rect.fromLTWH(
              margin,
              margin,
              sprite.src.width,
              sprite.src.height,
            )
          : sprite.src;

      double offsetX = (sprite is TexturePackerSprite)
          ? sprite.region.offsetX
          : 0;
      double offsetY = (sprite is TexturePackerSprite)
          ? sprite.region.offsetY
          : 0;

      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        int minX = scanSrc.right.toInt();
        int maxX = scanSrc.left.toInt();
        int minY = scanSrc.bottom.toInt();
        int maxY = scanSrc.top.toInt();

        final int startX = scanSrc.left.toInt();
        final int startY = scanSrc.top.toInt();
        final int width = scanSrc.width.toInt();
        final int height = scanSrc.height.toInt();

        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final index =
                ((startY + y) * targetImage.width + (startX + x)) * 4 + 3;
            if (buffer[index] > 5) {
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
              found = true;
            }
          }
        }

        if (found) {
          final double baseOX = (sprite is TexturePackerSprite)
              ? sprite.region.offsetX
              : 0;
          final double baseOY = (sprite is TexturePackerSprite)
              ? sprite.region.offsetY
              : 0;

          trimmedSrc = ui.Rect.fromLTWH(
            startX + minX.toDouble(),
            startY + minY.toDouble(),
            (maxX - minX + 1).toDouble(),
            (maxY - minY + 1).toDouble(),
          );

          if (isTemporary) {
            offsetX = baseOX + (minX.toDouble() - margin);
            offsetY = baseOY + (minY.toDouble() - margin);
          } else {
            offsetX = baseOX + minX.toDouble();
            offsetY = baseOY + minY.toDouble();
          }
        }
      }

      return _SpriteBakeInfo(
        originalSprite: sprite,
        filter: filter,
        decorator: decorator,
        prefix: prefix,
        nameInAtlas: name,
        trimmedSrc: trimmedSrc,
        offsetX: offsetX,
        offsetY: offsetY,
        originalWidth: (sprite is TexturePackerSprite)
            ? sprite.region.originalWidth
            : sprite.src.width,
        originalHeight: (sprite is TexturePackerSprite)
            ? sprite.region.originalHeight
            : sprite.src.height,
        bakedImage: isTemporary ? targetImage : null,
      );
    } catch (e, stack) {
      // ignore: avoid_print
      print(
        '[CompositeAtlas ERROR] Failed to analyze sprite "$name": $e\n$stack',
      );
      return _SpriteBakeInfo(
        originalSprite: sprite,
        filter: filter,
        decorator: null,
        prefix: prefix,
        nameInAtlas: name,
        trimmedSrc: sprite.src,
        offsetX: (sprite is TexturePackerSprite) ? sprite.region.offsetX : 0,
        offsetY: (sprite is TexturePackerSprite) ? sprite.region.offsetY : 0,
        originalWidth: (sprite is TexturePackerSprite)
            ? sprite.region.originalWidth
            : sprite.src.width,
        originalHeight: (sprite is TexturePackerSprite)
            ? sprite.region.originalHeight
            : sprite.src.height,
      );
    }
  }
}

class _RegionFilterKey {
  final ui.Image image;
  final ui.Rect src;
  final ui.ColorFilter? filter;
  final Decorator? decorator;

  _RegionFilterKey(this.image, this.src, this.filter, this.decorator);

  double get width => src.width;
  double get height => src.height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _RegionFilterKey &&
          image == other.image &&
          src == other.src &&
          filter == other.filter &&
          decorator == other.decorator);

  @override
  int get hashCode => Object.hash(image, src, filter, decorator);
}

/// A internal record of a request to bake a sprite with specific settings.
class _PendingBake {
  final Sprite sprite;
  final String prefix;
  final String name;
  final ui.ColorFilter? filter;
  final Decorator? decorator;

  _PendingBake(
    this.sprite,
    this.prefix,
    this.name,
    this.filter,
    this.decorator,
  );
}
