import 'dart:async';
import 'dart:math' as math;
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

/// Context provided to [AtlasDecorator]s during the baking process.
/// This allows shaders to sample from the original atlas using correctly
/// mapping global texture coordinates.
class AtlasContext {
  final ui.Image atlasImage;
  final ui.Rect srcRect;
  final ui.Size atlasSize;
  final ui.Size localSize;
  final int? itemIndex;
  final int? itemCount;

  AtlasContext({
    required this.atlasImage,
    required this.srcRect,
    required this.atlasSize,
    required this.localSize,
    this.itemIndex,
    this.itemCount,
  });
}

/// An interface for [Decorator]s that require access to the source atlas context.
/// This is particularly useful for fragment shaders that need to sample from
/// an atlas.
abstract class AtlasDecorator {
  void updateAtlasContext(AtlasContext context);
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
      final Map<String, int> animationLengths =
          {}; // Total frames per animation name

      for (final request in requests) {
        if (request is AtlasBakeRequest) {
          // Track per-request lengths to avoid sharing state between requests
          final Map<String, int> localLengths = {};
          for (final sprite in request.atlas.sprites) {
            final name = sprite.region.name;
            if (request.whiteList == null ||
                request.whiteList!.any(
                  (w) => name == w || name.startsWith(w),
                )) {
              localLengths[name] = (localLengths[name] ?? 0) + 1;
            }
          }
          // Merge into global store for the keys
          for (final entry in localLengths.entries) {
            final existing = animationLengths[entry.key] ?? 0;
            // Use maximum for the shared key property
            animationLengths[entry.key] = math.max(
              existing,
              entry.key.contains(RegExp(r'\d')) ? 1 : entry.value,
            );
          }
        }
      }

      for (final request in requests) {
        final prefix = request.keyPrefix ?? '';
        final Map<String, int> localIndices =
            {}; // Track indices for non-indexed sprites per request

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

            final int itemIndex = (sprite.region.index != -1)
                ? sprite.region.index
                : (localIndices[region.name] ?? 0);
            localIndices[region.name] = (localIndices[region.name] ?? 0) + 1;

            final int itemCount = animationLengths[region.name] ?? 1;

            final double offsetX = sprite.region.offsetX;
            final double offsetY = sprite.region.offsetY;
            final double originalWidth = sprite.region.originalWidth;
            final double originalHeight = sprite.region.originalHeight;

            final _RegionFilterKey bakeKey = _RegionFilterKey(
              sprite.image,
              sprite.src,
              request.filter,
              request.decorator,
              itemIndex,
              itemCount,
              offsetX,
              offsetY,
              originalWidth,
              originalHeight,
            );

            final pending = _PendingBake(
              sprite,
              prefix,
              region.name,
              request.filter,
              request.decorator,
              itemIndex,
              itemCount,
              bakeKey,
            );

            groupedTasks.putIfAbsent(bakeKey, () => []).add(pending);
          }
        } else if (request is SpriteBakeRequest) {
          final double offsetX = (request.sprite is TexturePackerSprite)
              ? (request.sprite as TexturePackerSprite).region.offsetX
              : 0;
          final double offsetY = (request.sprite is TexturePackerSprite)
              ? (request.sprite as TexturePackerSprite).region.offsetY
              : 0;
          final double originalWidth = (request.sprite is TexturePackerSprite)
              ? (request.sprite as TexturePackerSprite).region.originalWidth
              : request.sprite.src.width;
          final double originalHeight = (request.sprite is TexturePackerSprite)
              ? (request.sprite as TexturePackerSprite).region.originalHeight
              : request.sprite.src.height;

          final _RegionFilterKey bakeKey = _RegionFilterKey(
            request.sprite.image,
            request.sprite.src,
            request.filter,
            request.decorator,
            0,
            1,
            offsetX,
            offsetY,
            originalWidth,
            originalHeight,
          );
          final pending = _PendingBake(
            request.sprite,
            prefix,
            request.name,
            request.filter,
            request.decorator,
            0,
            1,
            bakeKey,
          );
          groupedTasks.putIfAbsent(bakeKey, () => []).add(pending);
        } else if (request is ImageBakeRequest) {
          final sprite = Sprite(request.image);
          final _RegionFilterKey bakeKey = _RegionFilterKey(
            sprite.image,
            sprite.src,
            request.filter,
            request.decorator,
            0,
            1,
            0,
            0,
            sprite.src.width,
            sprite.src.height,
          );
          final pending = _PendingBake(
            sprite,
            prefix,
            request.name,
            request.filter,
            request.decorator,
            0,
            1,
            bakeKey,
          );
          groupedTasks.putIfAbsent(bakeKey, () => []).add(pending);
        }
      }

      final List<_PendingBake> spritesToBake = [];
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
            itemIndex: first.itemIndex,
            itemCount: first.itemCount,
            bakeKey: key,
          );
        } else {
          // ANALYSIS PATH: Pre-render and scan (required for decorators/standalone sprites)
          info = await _SpriteBakeInfo.analyze(
            key: key,
            sprite: first.sprite,
            filter: first.filter,
            decorator: first.decorator,
            prefix: first.prefix,
            name: first.name,
            itemIndex: first.itemIndex,
            itemCount: first.itemCount,
          );
        }

        keyToInfo[key] = info;
        spritesToBake.addAll(pending);
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

      for (final pending in spritesToBake) {
        final pos = drawingPositions[pending.bakeKey]!;
        final bakeInfo = keyToInfo[pending.bakeKey]!;

        final newRegion = Region(
          page: megaPage,
          name: pending.name,
          left: pos.dx,
          top: pos.dy,
          width: bakeInfo.trimmedSrc.width,
          height: bakeInfo.trimmedSrc.height,
          offsetX: bakeInfo.offsetX,
          offsetY: bakeInfo.offsetY,
          originalWidth: bakeInfo.originalWidth,
          originalHeight: bakeInfo.originalHeight,
          degrees: 0,
          rotate: false,
          index:
              (pending.itemCount == 1 &&
                  (pending.sprite is! TexturePackerSprite ||
                      (pending.sprite as TexturePackerSprite).region.index ==
                          -1))
              ? -1
              : (pending.itemIndex ?? -1),
        );

        final newSprite = TexturePackerSprite(newRegion);
        newSprite.srcSize = newSprite.originalSize;

        final baseKey = newRegion.index == -1
            ? pending.name
            : '${pending.name}#${newRegion.index}';
        spriteMap['${pending.prefix}$baseKey'] = newSprite;
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
  final int? itemIndex;
  final int? itemCount;
  final _RegionFilterKey bakeKey;

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
    this.itemIndex,
    this.itemCount,
    required this.bakeKey,
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
      itemIndex: itemIndex,
      itemCount: itemCount,
      bakeKey: bakeKey,
    );
  }

  /// Analyzes a sprite to compute its non-transparent bounding box for trimming.
  static Future<_SpriteBakeInfo> analyze({
    required _RegionFilterKey key,
    required Sprite sprite,
    required ui.ColorFilter? filter,
    required Decorator? decorator,
    required String prefix,
    required String name,
    required int? itemIndex,
    required int? itemCount,
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
        if (decorator is AtlasDecorator) {
          (decorator as AtlasDecorator).updateAtlasContext(
            AtlasContext(
              atlasImage: sprite.image,
              srcRect: sprite.src,
              atlasSize: ui.Size(
                sprite.image.width.toDouble(),
                sprite.image.height.toDouble(),
              ),
              localSize: sprite.src.size,
              itemIndex: itemIndex,
              itemCount: itemCount,
            ),
          );
        }

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
        itemIndex: itemIndex,
        itemCount: itemCount,
        bakeKey: key,
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
        bakedImage: null,
        itemIndex: itemIndex,
        itemCount: itemCount,
        bakeKey: key,
      );
    }
  }
}

class _RegionFilterKey {
  final ui.Image image;
  final ui.Rect src;
  final ui.ColorFilter? filter;
  final Decorator? decorator;
  final int? itemIndex;
  final int? itemCount;
  final double offsetX;
  final double offsetY;
  final double originalWidth;
  final double originalHeight;

  _RegionFilterKey(
    this.image,
    this.src,
    this.filter,
    this.decorator,
    this.itemIndex,
    this.itemCount,
    this.offsetX,
    this.offsetY,
    this.originalWidth,
    this.originalHeight,
  );

  double get width => src.width;
  double get height => src.height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _RegionFilterKey &&
          image == other.image &&
          src == other.src &&
          filter == other.filter &&
          decorator == other.decorator &&
          offsetX == other.offsetX &&
          offsetY == other.offsetY &&
          originalWidth == other.originalWidth &&
          originalHeight == other.originalHeight &&
          (decorator is! AtlasDecorator ||
              (itemIndex == other.itemIndex && itemCount == other.itemCount)));

  @override
  int get hashCode => Object.hash(
    image,
    src,
    filter,
    decorator,
    offsetX,
    offsetY,
    originalWidth,
    originalHeight,
    decorator is AtlasDecorator ? Object.hash(itemIndex, itemCount) : null,
  );
}

/// A internal record of a request to bake a sprite with specific settings.
class _PendingBake {
  final Sprite sprite;
  final String prefix;
  final String name;
  final ui.ColorFilter? filter;
  final Decorator? decorator;
  final int? itemIndex;
  final int? itemCount;
  final _RegionFilterKey bakeKey;

  _PendingBake(
    this.sprite,
    this.prefix,
    this.name,
    this.filter,
    this.decorator,
    this.itemIndex,
    this.itemCount,
    this.bakeKey,
  );
}
