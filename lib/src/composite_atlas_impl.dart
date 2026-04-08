import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/painting.dart';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';

import 'composite_atlas.dart';
import 'internal_models.dart';
import 'atlas_decorator.dart';
import 'bake_request.dart';

// ignore_for_file: implementation_imports
import 'package:flame_texturepacker/src/model/page.dart';
import 'package:flame_texturepacker/src/model/region.dart';

class BakeInfo {
  final ui.Rect trimmedSrc;
  final double offsetX;
  final double offsetY;
  final double originalWidth;
  final double originalHeight;
  ui.Image? bakedImage;
  bool rotate;
  double? effectiveWidth;
  double? effectiveHeight;

  BakeInfo(
    this.trimmedSrc,
    this.offsetX,
    this.offsetY,
    this.originalWidth,
    this.originalHeight, {
    this.rotate = false,
    this.effectiveWidth,
    this.effectiveHeight,
  });
}

/// A simple implementation of the Guillotine packing algorithm.
class GuillotinePacker {
  final double maxWidth;
  final List<ui.Rect> _freeRects = [];
  double currentHeight;

  GuillotinePacker(this.maxWidth, {this.currentHeight = 0});

  /// Tries to pack a rectangle of size [w]x[h].
  /// Returns a record with the position and whether it was rotated.
  ({ui.Offset offset, bool rotated})? pack(
    double w,
    double h, {
    bool allowRotation = true,
  }) {
    int bestRectIndex = -1;
    double bestArea = double.infinity;
    bool rotated = false;

    // 1. Find best fitting free rectangle (Best Area Fit heuristic)
    for (int i = 0; i < _freeRects.length; i++) {
      final rect = _freeRects[i];

      // Try original orientation
      if (rect.width >= w - 0.0001 && rect.height >= h - 0.0001) {
        final area = rect.width * rect.height;
        if (area < bestArea) {
          bestArea = area;
          bestRectIndex = i;
          rotated = false;
        }
      }

      // Try rotated orientation
      if (allowRotation &&
          rect.width >= h - 0.0001 &&
          rect.height >= w - 0.0001) {
        final area = rect.width * rect.height;
        if (area < bestArea) {
          bestArea = area;
          bestRectIndex = i;
          rotated = true;
        }
      }
    }

    if (bestRectIndex != -1) {
      final rect = _freeRects.removeAt(bestRectIndex);
      final double useW = rotated ? h : w;
      final double useH = rotated ? w : h;

      _split(rect, useW, useH);
      return (offset: ui.Offset(rect.left, rect.top), rotated: rotated);
    }

    return null;
  }

  void _split(ui.Rect rect, double w, double h) {
    // Shorter Side Split rule
    final double freeW = rect.width - w;
    final double freeH = rect.height - h;

    if (freeW > freeH) {
      // Split vertically
      if (freeW > 0.0001) {
        _freeRects.add(ui.Rect.fromLTWH(rect.left + w, rect.top, freeW, h));
      }
      if (freeH > 0.0001 || rect.width > w + 0.0001) {
        _freeRects.add(
          ui.Rect.fromLTWH(rect.left, rect.top + h, rect.width, freeH),
        );
      }
    } else {
      // Split horizontally
      if (freeH > 0.0001) {
        _freeRects.add(ui.Rect.fromLTWH(rect.left, rect.top + h, w, freeH));
      }
      if (freeW > 0.0001 || rect.height > h + 0.0001) {
        _freeRects.add(
          ui.Rect.fromLTWH(rect.left + w, rect.top, freeW, rect.height),
        );
      }
    }
  }

  void addNewSpace(double additionalHeight) {
    _freeRects.add(
      ui.Rect.fromLTWH(0, currentHeight, maxWidth, additionalHeight),
    );
    currentHeight += additionalHeight;
  }

  void addFreeRect(ui.Rect rect) {
    _freeRects.add(rect);
    currentHeight = math.max(currentHeight, rect.bottom);
  }
}

class CompositeAtlasImpl extends CompositeAtlas {
  @override
  final ui.Image image;
  final Map<String, TexturePackerSprite> _internalSpriteMap;
  final Set<String> _prefixes;

  /// External access for tests
  Map<String, TexturePackerSprite> get spriteMap => _internalSpriteMap;

  CompositeAtlasImpl._(this.image, this._internalSpriteMap, this._prefixes)
    : super(_internalSpriteMap.values.toSet().toList());

  static CompositeAtlas fromAtlas(TexturePackerAtlas atlas) {
    final spriteMap = <String, TexturePackerSprite>{};
    for (final s in atlas.sprites) {
      final name = s.region.index == -1
          ? s.region.name
          : '${s.region.name}#${s.region.index}';
      spriteMap[name] = s;

      if (s.region.name != name) {
        spriteMap[s.region.name] = s;
      }
    }
    final firstImage = atlas.sprites.first.region.page.texture!;
    return CompositeAtlasImpl._(firstImage, spriteMap, {});
  }

  static Future<CompositeAtlas> bake(
    List<BakeRequest> requests, {
    double maxAtlasWidth = 1024.0,
    bool allowRotation = true,
    bool forceSquare = false,
    Images? images,
  }) async {
    final Map<RegionFilterKey, List<PendingBake>> groupedTasks = {};
    final Map<String, int> animationLengths = {};
    final Set<String> prefixes = {};

    // 1. Pre-calculate animation lengths for proper indexing
    for (final request in requests) {
      if (request.keyPrefix != null) prefixes.add(request.keyPrefix!);
      if (request is AtlasBakeRequest) {
        for (final sprite in request.atlas.sprites) {
          var name = sprite.region.name;
          if (sprite.region.index == -1) {
            final match = RegExp(r'^(.+)_(\d+)$').firstMatch(name);
            if (match != null) {
              name = match.group(1)!;
            }
          }
          animationLengths[name] = (animationLengths[name] ?? 0) + 1;
        }
      }
    }

    // 2. Group by visual identity (Image + Rect + Filter + Decorator)
    final Map<String, int> localIndices = {};
    for (final request in requests) {
      final prefix = request.keyPrefix ?? '';
      if (request is ImageBakeRequest) {
        final bakeKey = RegionFilterKey(
          request.image,
          ui.Rect.fromLTWH(
            0,
            0,
            request.image.width.toDouble(),
            request.image.height.toDouble(),
          ),
          request.filter,
          request.decorator,
          -1,
          1,
          0,
          0,
          request.image.width.toDouble(),
          request.image.height.toDouble(),
        );

        final pending = PendingBake(
          Sprite(request.image),
          prefix,
          request.name,
          request.filter,
          request.decorator,
          -1,
          1,
          bakeKey,
        );

        groupedTasks.putIfAbsent(bakeKey, () => []).add(pending);
      } else if (request is AtlasBakeRequest) {
        for (final sprite in request.atlas.sprites) {
          final region = sprite.region;
          if (request.whiteList != null) {
            if (!request.whiteList!.any(
              (w) => region.name == w || region.name.startsWith(w),
            )) {
              continue;
            }
          }

          var name = region.name;
          final originalName = region.name;
          var baseItemIndex = region.index;

          if (baseItemIndex == -1) {
            final match = RegExp(r'^(.+)_(\d+)$').firstMatch(name);
            if (match != null) {
              name = match.group(1)!;
              baseItemIndex = int.parse(match.group(2)!);
            }
          }

          final int finalIndex = (baseItemIndex != -1)
              ? baseItemIndex
              : (localIndices[name] ?? 0);
          localIndices[name] = (localIndices[name] ?? 0) + 1;

          final int itemCount = animationLengths[name] ?? 1;

          final RegionFilterKey bakeKey = RegionFilterKey(
            sprite.image,
            sprite.src,
            request.filter,
            request.decorator,
            finalIndex,
            itemCount,
            region.offsetX,
            region.offsetY,
            region.originalWidth,
            region.originalHeight,
          );

          final pending = PendingBake(
            sprite,
            prefix,
            name,
            request.filter,
            request.decorator,
            finalIndex,
            itemCount,
            bakeKey,
            originalName: originalName,
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

        var name = request.name;
        final originalName = request.name;
        var itemIndex = 0;

        final match = RegExp(r'^(.+)_(\d+)$').firstMatch(name);
        if (match != null) {
          name = match.group(1)!;
          itemIndex = int.parse(match.group(2)!);
        }

        final RegionFilterKey bakeKey = RegionFilterKey(
          request.sprite.image,
          request.sprite.src,
          request.filter,
          request.decorator,
          itemIndex,
          1,
          offsetX,
          offsetY,
          originalWidth,
          originalHeight,
        );

        final pending = PendingBake(
          request.sprite,
          request.keyPrefix ?? '',
          name,
          request.filter,
          request.decorator,
          itemIndex,
          1,
          bakeKey,
          originalName: originalName,
        );

        groupedTasks.putIfAbsent(bakeKey, () => []).add(pending);
      }
    }

    if (groupedTasks.isEmpty) {
      throw StateError('No bake requests found.');
    }

    final completer = Completer<void>();
    try {
      final Map<RegionFilterKey, BakeInfo> keyToInfo = {};
      final List<PendingBake> spritesToBake = [];

      for (final entry in groupedTasks.entries) {
        final key = entry.key;
        final pending = entry.value;

        final template = pending.first.sprite;
        BakeInfo info;

        final decorator = key.decorator;
        final padding = (decorator is BakePadding)
            ? (decorator as BakePadding).padding
            : EdgeInsets.zero;

        final bool isRotated =
            template is TexturePackerSprite && template.region.rotate;
        final bool needsAnalysis = decorator != null || isRotated;

        if (needsAnalysis) {
          // Use the original visual size (un-rotated) as the reference for baking.
          // Sprite.render() will handle placing the packed pixels at the correct
          // visual offsetX/offsetY within this original frame.
          final double bakedW = template.originalSize.x;
          final double bakedH = template.originalSize.y;

          double baseOX = 0;
          double baseOY = 0;
          if (isRotated) {
            baseOX = key.offsetX;
            baseOY = key.offsetY;
          }

          info = BakeInfo(
            template.src,
            baseOX,
            baseOY,
            template.originalSize.x,
            template.originalSize.y,
            effectiveWidth: bakedW + padding.horizontal,
            effectiveHeight: bakedH + padding.vertical,
          );
        } else {
          // Optimization: For simple sprites, preserve the original trimming and offsets exactly.
          final double baseOX = (template is TexturePackerSprite)
              ? template.region.offsetX
              : 0;
          final double baseOY = (template is TexturePackerSprite)
              ? template.region.offsetY
              : 0;
          final double baseOW = (template is TexturePackerSprite)
              ? template.region.originalWidth
              : template.src.width;
          final double baseOH = (template is TexturePackerSprite)
              ? template.region.originalHeight
              : template.src.height;

          info = BakeInfo(
            template.src,
            baseOX - padding.left,
            baseOY - padding.top,
            baseOW,
            baseOH,
            effectiveWidth: template.src.width + padding.horizontal,
            effectiveHeight: template.src.height + padding.vertical,
          );
        }

        if (key.decorator != null || isRotated) {
          final decorator = key.decorator;
          final padding = (decorator is BakePadding)
              ? (decorator as BakePadding).padding
              : EdgeInsets.zero;

          final double targetW = info.effectiveWidth ?? info.trimmedSrc.width;
          final double targetH = info.effectiveHeight ?? info.trimmedSrc.height;

          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);

          if (decorator is AtlasDecorator) {
            (decorator as AtlasDecorator).updateAtlasContext(
              AtlasContext(
                atlasImage: key.image,
                srcRect: info.trimmedSrc,
                atlasSize: ui.Size(
                  key.image.width.toDouble(),
                  key.image.height.toDouble(),
                ),
                localSize: ui.Size(
                  info.trimmedSrc.width,
                  info.trimmedSrc.height,
                ),
                itemIndex: key.itemIndex,
                itemCount: key.itemCount,
                padding: padding,
              ),
            );
          }

          void draw(ui.Canvas canvas) {
            canvas.save();
            canvas.translate(padding.left, padding.top);

            // TexturePackerSprite and other sprites know how to render themselves
            // correctly within their original frame using their internal offsets.
            // We pass originalSize to ensure 1:1 rendering without auto-scaling.
            template.render(
              canvas,
              size: template.originalSize,
              overridePaint: ui.Paint()..filterQuality = ui.FilterQuality.none,
            );

            canvas.restore();
          }

          if (decorator != null) {
            decorator.applyChain(draw, canvas);
          } else {
            draw(canvas);
          }

          final baked = await recorder.endRecording().toImage(
            targetW.ceil(),
            targetH.ceil(),
          );

          final trimResult = await _trimImage(baked);
          if (trimResult != null) {
            if (trimResult.image != baked) {
              baked.dispose();
            }
            final newInfo = BakeInfo(
              info.trimmedSrc,
              info.offsetX + trimResult.trimRect.left,
              info.offsetY + trimResult.trimRect.top,
              info.originalWidth,
              info.originalHeight,
              effectiveWidth: trimResult.trimRect.width,
              effectiveHeight: trimResult.trimRect.height,
            );
            newInfo.bakedImage = trimResult.image;
            info = newInfo;
          } else {
            info.bakedImage = baked;
          }
        }

        keyToInfo[key] = info;
        spritesToBake.addAll(pending);
      }

      // ignore: avoid_print
      print('[CompositeAtlas] Unique slots to bake: ${keyToInfo.length}');

      final List<RegionFilterKey> sortedKeys = keyToInfo.keys.toList();
      // Sort by AREA (Descending) - Best for Guillotine packing density.
      sortedKeys.sort((a, b) {
        final infoA = keyToInfo[a]!;
        final infoB = keyToInfo[b]!;
        final areaA =
            (infoA.effectiveWidth ?? infoA.trimmedSrc.width) *
            (infoA.effectiveHeight ?? infoA.trimmedSrc.height);
        final areaB =
            (infoB.effectiveWidth ?? infoB.trimmedSrc.width) *
            (infoB.effectiveHeight ?? infoB.trimmedSrc.height);
        return areaB.compareTo(areaA);
      });

      const double padding = 2.0;
      final packer = GuillotinePacker(forceSquare ? 4096.0 : maxAtlasWidth);

      double currentSide = 0;
      if (forceSquare) {
        // Start with a small square power-of-two (e.g. 64) OR based on max sprite size
        double maxSpriteDim = 64.0;
        for (final key in sortedKeys) {
          final info = keyToInfo[key]!;
          final w = (info.effectiveWidth ?? info.trimmedSrc.width) + padding;
          final h = (info.effectiveHeight ?? info.trimmedSrc.height) + padding;
          maxSpriteDim = math.max(maxSpriteDim, math.max(w, h));
        }
        currentSide = math
            .pow(2, (math.log(maxSpriteDim) / math.ln2).ceil())
            .toDouble();
        packer.addFreeRect(ui.Rect.fromLTWH(0, 0, currentSide, currentSide));
      } else {
        // Start with a small workspace to encourage filling the width before growing
        packer.addNewSpace(256);
      }

      final Map<RegionFilterKey, ui.Offset> drawingPositions = {};

      for (final key in sortedKeys) {
        final info = keyToInfo[key]!;
        final w = (info.effectiveWidth ?? info.trimmedSrc.width) + padding;
        final h = (info.effectiveHeight ?? info.trimmedSrc.height) + padding;

        var result = packer.pack(w, h, allowRotation: allowRotation);

        // If it doesn't fit anywhere, expand the atlas vertically (or grow square)
        while (result == null) {
          if (forceSquare) {
            // Expand square: current area is currentSide x currentSide.
            // Add block to the right: (currentSide, 0, currentSide, currentSide)
            // Add block below: (0, currentSide, currentSide*2, currentSide)
            packer.addFreeRect(
              ui.Rect.fromLTWH(currentSide, 0, currentSide, currentSide),
            );
            packer.addFreeRect(
              ui.Rect.fromLTWH(0, currentSide, currentSide * 2, currentSide),
            );
            currentSide *= 2;
          } else {
            packer.addNewSpace(256);
          }
          result = packer.pack(w, h, allowRotation: allowRotation);
        }

        drawingPositions[key] = result.offset;
        info.rotate = result.rotated;
      }

      // Calculate the tight bounding box of all packed sprites to minimize texture size
      double actualMaxY = 0;
      double actualMaxX = 0;
      for (final key in sortedKeys) {
        final pos = drawingPositions[key]!;
        final info = keyToInfo[key]!;
        // When rotated, the width and height in the atlas are the same as effective
        final w = info.effectiveWidth ?? info.trimmedSrc.width;
        final h = info.effectiveHeight ?? info.trimmedSrc.height;

        actualMaxY = math.max(actualMaxY, pos.dy + h + padding);
        actualMaxX = math.max(actualMaxX, pos.dx + w + padding);
      }

      actualMaxY;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final basePaint = ui.Paint()..filterQuality = ui.FilterQuality.none;

      for (final key in sortedKeys) {
        final pos = drawingPositions[key]!;
        final info = keyToInfo[key]!;

        canvas.save();
        canvas.translate(pos.dx, pos.dy);

        final drawPaint = ui.Paint()
          ..filterQuality = ui.FilterQuality.none
          ..colorFilter = key.filter;

        final dst = ui.Rect.fromLTWH(
          0,
          0,
          info.effectiveWidth ?? info.trimmedSrc.width,
          info.effectiveHeight ?? info.trimmedSrc.height,
        );

        if (info.bakedImage != null) {
          canvas.drawImageRect(
            info.bakedImage!,
            ui.Rect.fromLTWH(
              0,
              0,
              info.bakedImage!.width.toDouble(),
              info.bakedImage!.height.toDouble(),
            ),
            dst,
            basePaint,
          );
        } else {
          canvas.drawImageRect(key.image, info.trimmedSrc, dst, drawPaint);
        }
        canvas.restore();
      }

      final megaImage = await recorder.endRecording().toImage(
        actualMaxX.ceil(),
        actualMaxY.ceil(),
      );

      for (final info in keyToInfo.values) {
        info.bakedImage?.dispose();
      }

      final spriteMap = <String, TexturePackerSprite>{};
      final megaPage = Page()
        ..texture = megaImage
        ..width = megaImage.width
        ..height = megaImage.height;

      for (final pending in spritesToBake) {
        final pos = drawingPositions[pending.bakeKey]!;
        final bakeInfo = keyToInfo[pending.bakeKey]!;

        final newRegion = Region(
          page: megaPage,
          name: '${pending.prefix}${pending.name}',
          left: pos.dx,
          top: pos.dy,
          width: bakeInfo.effectiveWidth ?? bakeInfo.trimmedSrc.width,
          height: bakeInfo.effectiveHeight ?? bakeInfo.trimmedSrc.height,
          offsetX: bakeInfo.offsetX,
          offsetY: bakeInfo.offsetY,
          originalWidth: bakeInfo.originalWidth,
          originalHeight: bakeInfo.originalHeight,
          rotate: bakeInfo.rotate,
          index:
              (pending.itemCount == 1 &&
                  (pending.itemIndex == null || pending.itemIndex == -1) &&
                  (pending.sprite is! TexturePackerSprite ||
                      (pending.sprite as TexturePackerSprite).region.index ==
                          -1))
              ? -1
              : (pending.itemIndex ?? -1),
        );

        final newSprite = TexturePackerSprite(newRegion);
        newSprite.srcSize = newSprite.originalSize;

        final primaryKey = newRegion.index == -1
            ? newRegion.name
            : '${newRegion.name}#${newRegion.index}';
        spriteMap[primaryKey] = newSprite;

        // Also map original name with prefix for direct frame lookups
        if (pending.originalName != null) {
          final prefOrig = '${pending.prefix}${pending.originalName}';
          if (prefOrig != primaryKey && prefOrig != newRegion.name) {
            spriteMap[prefOrig] = newSprite;
          }
        }
      }

      return CompositeAtlasImpl._(megaImage, spriteMap, prefixes);
    } finally {
      completer.complete();
    }
  }

  @override
  List<String> get allSpriteNames => _internalSpriteMap.keys.toList();

  @override
  TexturePackerSprite? findSpriteByName(String name) {
    if (_internalSpriteMap.containsKey(name)) return _internalSpriteMap[name];

    // Try prefix-unaware lookup
    for (final prefix in _prefixes) {
      final combined = '$prefix$name';
      if (_internalSpriteMap.containsKey(combined)) {
        return _internalSpriteMap[combined];
      }
    }

    return super.findSpriteByName(name);
  }

  @override
  List<TexturePackerSprite> findSpritesByName(String name) {
    // 1. Try exact/super lookup (efficient)
    final results = super.findSpritesByName(name);
    if (results.isNotEmpty) {
      return results.cast<TexturePackerSprite>().toList();
    }

    // 2. Try prefix-aware lookup (one prefix at a time to prevent mixing)
    for (final prefix in _prefixes) {
      final combined = '$prefix$name';
      final prefixedResults = super.findSpritesByName(combined);
      if (prefixedResults.isNotEmpty) {
        return prefixedResults.cast<TexturePackerSprite>().toList();
      }
    }

    // 3. Fallback to manual search (legacy or indexed lookups)
    final Set<TexturePackerSprite> found = {};
    final lookupNames = <String>{name, ..._prefixes.map((p) => '$p$name')};

    for (final lookup in lookupNames) {
      // Check if the lookup exactly matches a key in the internal map
      if (_internalSpriteMap.containsKey(lookup)) {
        found.add(_internalSpriteMap[lookup]!);
      }

      // Check for indexed keys (e.g., name#0, name#1)
      final indexedPattern = RegExp('^${RegExp.escape(lookup)}#(\\d+)\$');
      for (final key in _internalSpriteMap.keys) {
        if (indexedPattern.hasMatch(key)) {
          found.add(_internalSpriteMap[key]!);
        }
      }

      // If we found something for this specific prefix/lookup, return it without mixing others
      if (found.isNotEmpty) break;
    }

    final casted = found.toList();
    if (casted.isEmpty) {
      // ignore: avoid_print
      print(
        '[CompositeAtlas] Sprite animation lookup failed for: "$name" (checked ${_internalSpriteMap.length} entries)',
      );
    }

    casted.sort((a, b) => a.region.index.compareTo(b.region.index));
    return casted;
  }

  @override
  SpriteAnimation getAnimation(
    String name, {
    double stepTime = 0.1,
    bool loop = true,
    bool useIndexedSpritesOnly = false,
  }) {
    // We override getAnimation to ensure we use our naturally sorted findSpritesByName
    final animationSprites = findSpritesByName(name);
    if (animationSprites.isEmpty) {
      throw Exception('No sprites found with name "$name" in atlas');
    }

    var filtered = animationSprites;
    if (useIndexedSpritesOnly) {
      filtered = animationSprites.where((s) => s.region.index >= 0).toList();
      if (filtered.isEmpty) filtered = animationSprites;
    }

    return SpriteAnimation.spriteList(filtered, stepTime: stepTime, loop: loop);
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

  static Future<({ui.Image image, ui.Rect trimRect})?> _trimImage(
    ui.Image image,
  ) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return null;

    final buffer = byteData.buffer.asUint8List();
    final int width = image.width;
    final int height = image.height;

    int minX = width;
    int maxX = -1;
    int minY = height;
    int maxY = -1;
    bool found = false;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int index = (y * width + x) * 4 + 3;
        if (buffer[index] > 3) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          found = true;
        }
      }
    }

    if (!found) {
      // For empty frames, return a 1x1 transparent rect to avoid null handling issues
      return (image: image, trimRect: ui.Rect.fromLTWH(0, 0, 1, 1));
    }

    final trimRect = ui.Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );

    if (minX == 0 && minY == 0 && maxX == width - 1 && maxY == height - 1) {
      return (image: image, trimRect: trimRect);
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      trimRect,
      ui.Rect.fromLTWH(0, 0, trimRect.width, trimRect.height),
      ui.Paint(),
    );
    final cropped = await recorder.endRecording().toImage(
      trimRect.width.toInt(),
      trimRect.height.toInt(),
    );

    return (image: cropped, trimRect: trimRect);
  }
}
