import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/painting.dart';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/rendering.dart';
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
  double? effectiveWidth;
  double? effectiveHeight;

  BakeInfo(
    this.trimmedSrc,
    this.offsetX,
    this.offsetY,
    this.originalWidth,
    this.originalHeight, {
    this.effectiveWidth,
    this.effectiveHeight,
  });
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

        if (template is TexturePackerSprite) {
          final decorator = key.decorator;
          final padding = (decorator is BakePadding)
              ? (decorator as BakePadding).padding
              : EdgeInsets.zero;

          info = BakeInfo(
            template.src,
            template.region.offsetX - padding.left,
            template.region.offsetY - padding.top,
            template.region.originalWidth,
            template.region.originalHeight,
            effectiveWidth: template.src.width + padding.horizontal,
            effectiveHeight: template.src.height + padding.vertical,
          );
        } else {
          final decorator = key.decorator;
          final padding = (decorator is BakePadding)
              ? (decorator as BakePadding).padding
              : EdgeInsets.zero;

          info = BakeInfo(
            template.src,
            -padding.left,
            -padding.top,
            template.src.width,
            template.src.height,
            effectiveWidth: template.src.width + padding.horizontal,
            effectiveHeight: template.src.height + padding.vertical,
          );
        }

        if (key.decorator != null) {
          final decorator = key.decorator!;
          final padding =
              (decorator is BakePadding) ? (decorator as BakePadding).padding : EdgeInsets.zero;

          final double targetW = info.effectiveWidth ?? info.trimmedSrc.width;
          final double targetH = info.effectiveHeight ?? info.trimmedSrc.height;

          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          final drawRect = ui.Rect.fromLTWH(
            0,
            0,
            info.trimmedSrc.width,
            info.trimmedSrc.height,
          );

          if (decorator is AtlasDecorator) {
            (decorator as AtlasDecorator).updateAtlasContext(AtlasContext(
              atlasImage: key.image,
              srcRect: info.trimmedSrc,
              atlasSize: ui.Size(
                  key.image.width.toDouble(), key.image.height.toDouble()),
              localSize: ui.Size(info.trimmedSrc.width, info.trimmedSrc.height),
              itemIndex: key.itemIndex,
              itemCount: key.itemCount,
              padding: padding,
            ));
          }

          decorator.applyChain((canvas) {
            canvas.save();
            canvas.translate(padding.left, padding.top);
            canvas.drawImageRect(
              key.image,
              info.trimmedSrc,
              drawRect,
              ui.Paint()..filterQuality = ui.FilterQuality.none,
            );
            canvas.restore();
          }, canvas);

          final baked = await recorder.endRecording().toImage(
                targetW.ceil(),
                targetH.ceil(),
              );
          info.bakedImage = baked;
        }

        keyToInfo[key] = info;
        spritesToBake.addAll(pending);
      }

      final List<RegionFilterKey> sortedKeys = keyToInfo.keys.toList();
      sortedKeys.sort(
        (a, b) => keyToInfo[b]!.trimmedSrc.height.compareTo(
          keyToInfo[a]!.trimmedSrc.height,
        ),
      );

      const double maxAtlasWidth = 1024.0;
      const double padding = 2.0;
      double currentX = 0;
      double currentY = 0;
      double currentRowHeight = 0;
      double maxWidth = 0;

      final Map<RegionFilterKey, ui.Offset> drawingPositions = {};

      for (final key in sortedKeys) {
        final info = keyToInfo[key]!;
        final w = info.effectiveWidth ?? info.trimmedSrc.width;
        final h = info.effectiveHeight ?? info.trimmedSrc.height;

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

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final basePaint = ui.Paint()..filterQuality = ui.FilterQuality.none;

      for (final key in sortedKeys) {
        final pos = drawingPositions[key]!;
        final info = keyToInfo[key]!;
        final drawPaint = ui.Paint()
          ..filterQuality = ui.FilterQuality.none
          ..colorFilter = key.filter;

        final dst = ui.Rect.fromLTWH(
          pos.dx,
          pos.dy,
          info.effectiveWidth ?? info.trimmedSrc.width,
          info.effectiveHeight ?? info.trimmedSrc.height,
        );

        if (info.bakedImage != null) {
          canvas.drawImageRect(
            info.bakedImage!,
            ui.Rect.fromLTWH(
                0, 0, info.bakedImage!.width.toDouble(), info.bakedImage!.height.toDouble()),
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
          // Use base name (no frame index suffix) for the Region name.
          // This allows TexturePackerAtlas to group frames into animations.
          name: '${pending.prefix}${pending.name}',
          left: pos.dx,
          top: pos.dy,
          width: bakeInfo.effectiveWidth ?? bakeInfo.trimmedSrc.width,
          height: bakeInfo.effectiveHeight ?? bakeInfo.trimmedSrc.height,
          offsetX: bakeInfo.offsetX,
          offsetY: bakeInfo.offsetY,
          originalWidth: bakeInfo.originalWidth,
          originalHeight: bakeInfo.originalHeight,
          degrees: 0,
          rotate: false,
          index: (pending.itemCount == 1 &&
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
      print('[CompositeAtlas] Sprite animation lookup failed for: "$name" (checked ${_internalSpriteMap.length} entries)');
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

    return SpriteAnimation.spriteList(
      filtered,
      stepTime: stepTime,
      loop: loop,
    );
  }

  static ui.ColorFilter hueFilter(double radians) {
    final cosT = math.cos(radians);
    final sinT = math.sin(radians);
    return ui.ColorFilter.matrix(<double>[
      0.213 + 0.787 * cosT - 0.213 * sinT,
      0.715 - 0.715 * cosT - 0.715 * sinT,
      0.072 - 0.072 * cosT + 0.928 * sinT,
      0, 0,
      0.213 - 0.213 * cosT + 0.143 * sinT,
      0.715 + 0.285 * cosT + 0.140 * sinT,
      0.072 - 0.072 * cosT - 0.283 * sinT,
      0, 0,
      0.213 - 0.213 * cosT - 0.787 * sinT,
      0.715 - 0.715 * cosT + 0.715 * sinT,
      0.072 + 0.928 * cosT + 0.072 * sinT,
      0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  @override
  void dispose() => image.dispose();
}
