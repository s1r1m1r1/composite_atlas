import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
// Direct imports for internal models since they are not exported by the main library
import 'package:flame_texturepacker/src/model/page.dart';
import 'package:flame_texturepacker/src/model/region.dart';

import 'composite_atlas.dart';
import 'bake_request.dart';
import 'internal_models.dart';

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
      final Map<RegionFilterKey, List<PendingBake>> groupedTasks = {};
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

            final RegionFilterKey bakeKey = RegionFilterKey(
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

            final pending = PendingBake(
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

          final RegionFilterKey bakeKey = RegionFilterKey(
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
          final pending = PendingBake(
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
          final RegionFilterKey bakeKey = RegionFilterKey(
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
          final pending = PendingBake(
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

      final List<PendingBake> spritesToBake = [];
      final Map<RegionFilterKey, SpriteBakeInfo> keyToInfo = {};

      // 2. Perform analysis - OPTIMIZED: only scan if decorator is present
      for (final entry in groupedTasks.entries) {
        final key = entry.key;
        final pending = entry.value;
        final first = pending.first;

        SpriteBakeInfo info;
        if (first.decorator == null && first.sprite is TexturePackerSprite) {
          // FAST PATH: Use existing metadata for pre-packed atlas sprites
          final s = first.sprite as TexturePackerSprite;
          info = SpriteBakeInfo(
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
          info = await SpriteBakeInfo.analyze(
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

      final List<RegionFilterKey> sortedKeys = keyToInfo.keys.toList();
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

      final Map<RegionFilterKey, ui.Offset> drawingPositions = {};

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
