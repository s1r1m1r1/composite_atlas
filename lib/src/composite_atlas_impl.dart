import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';

import 'composite_atlas.dart';
import 'internal_models.dart';
import 'bake_request.dart';
import 'packers.dart';

// ignore_for_file: implementation_imports
import 'package:flame_texturepacker/src/model/page.dart';
import 'package:flame_texturepacker/src/model/region.dart';

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
    bool trim = true,
    Images? images,
  }) async {
    final Map<RegionFilterKey, List<PendingBake>> groupedTasks = {};
    final Map<String, int> animationLengths = {};
    final Set<String> prefixes = {};

    // 1. Pre-calculate animation lengths for proper indexing
    for (final request in requests) {
      if (request.keyPrefix != null) prefixes.add(request.keyPrefix!);
      switch (request) {
        case AtlasBakeRequest():
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

        case SpritesheetBakeRequest(:final frames):
          if (frames != null) {
            for (final frame in frames) {
              var name = frame.name;
              final match = RegExp(r'^(.+)_(\d+)$').firstMatch(name);
              if (match != null) {
                name = match.group(1)!;
              }
              animationLengths[name] = (animationLengths[name] ?? 0) + 1;
            }
          } else {
            animationLengths[request.name] =
                (animationLengths[request.name] ?? 0) +
                (request.frameCount ?? 1);
          }
        case SpriteBakeRequest():
        case ImageBakeRequest():
          break;
      }
    }

    // 2. Group by visual identity (Image + Rect + Filter + Decorator + rotation)
    final Map<String, int> localIndices = {};
    for (final request in requests) {
      final prefix = request.keyPrefix ?? '';
      switch (request) {
        case ImageBakeRequest():
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
            request.nameTransformer != null
                ? request.nameTransformer!(request.name)
                : request.name,
            request.filter,
            request.decorator,
            -1,
            1,
            bakeKey,
          );

          groupedTasks.putIfAbsent(bakeKey, () => []).add(pending);
        case AtlasBakeRequest():
          for (final sprite in request.atlas.sprites) {
            final region = sprite.region;
            if (request.whiteList != null) {
              if (!request.whiteList!.any(
                (w) => region.name == w || region.name.startsWith(w),
              )) {
                continue;
              }
            }

            var name = request.nameTransformer != null
                ? request.nameTransformer!(region.name)
                : region.name;
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
                : (animationLengths[name] == 1
                      ? -1
                      : (localIndices[name] ?? 0));
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
              rotate: region.rotate,
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
        case SpriteBakeRequest():
          final sr = request.sourceRegion;
          final Sprite actualSprite = request.sprite;

          final double offsetX;
          final double offsetY;
          final double originalWidth;
          final double originalHeight;

          if (sr != null) {
            offsetX = (sr.originalWidth - sr.width) / 2.0;
            offsetY = (sr.originalHeight - sr.height) / 2.0;
            originalWidth = sr.originalWidth;
            originalHeight = sr.originalHeight;
          } else if (actualSprite is TexturePackerSprite) {
            final region = actualSprite.region;
            offsetX = region.offsetX;
            offsetY = region.offsetY;
            originalWidth = region.originalWidth;
            originalHeight = region.originalHeight;
          } else {
            offsetX = 0;
            offsetY = 0;
            originalWidth = actualSprite.src.width;
            originalHeight = actualSprite.src.height;
          }

          var name = request.name;
          final originalName = request.name;
          var itemIndex = -1;

          final match = RegExp(r'^(.+)_(\d+)$').firstMatch(name);
          if (match != null) {
            name = match.group(1)!;
            itemIndex = int.parse(match.group(2)!);
          }

          final ui.Rect srcRect = sr?.toRect() ?? actualSprite.src;

          final RegionFilterKey bakeKey = RegionFilterKey(
            actualSprite.image,
            srcRect,
            request.filter,
            request.decorator,
            itemIndex,
            1,
            offsetX,
            offsetY,
            originalWidth,
            originalHeight,
            rotate: sr?.rotate ?? false,
          );

          final pending = PendingBake(
            actualSprite,
            request.keyPrefix ?? '',
            request.nameTransformer != null
                ? request.nameTransformer!(name)
                : name,
            request.filter,
            request.decorator,
            itemIndex,
            1,
            bakeKey,
            originalName: originalName,
            sourceRegion: sr,
          );

          groupedTasks.putIfAbsent(bakeKey, () => []).add(pending);
        case SpritesheetBakeRequest():
          final List<SpritesheetFrame> frames = [];
          if (request.frames != null) {
            frames.addAll(request.frames!);
          } else {
            final fw = request.frameWidth!;
            final fh = request.frameHeight!;
            final cols = (request.image.width / fw).floor();
            final count =
                request.frameCount ??
                (cols * (request.image.height / fh).floor());

            for (int i = 0; i < count; i++) {
              final x = (i % cols) * fw;
              final y = (i / cols).floor() * fh;
              frames.add(
                SpritesheetFrame(
                  name: '${request.name}_$i',
                  x: x.toDouble(),
                  y: y.toDouble(),
                  width: fw,
                  height: fh,
                ),
              );
            }
          }

          for (final frame in frames) {
            var name = frame.name;
            final originalName = frame.name;
            var itemIndex = -1;

            final match = RegExp(r'^(.+)_(\d+)$').firstMatch(name);
            if (match != null) {
              name = match.group(1)!;
              itemIndex = int.parse(match.group(2)!);
            }

            final double ow = frame.originalWidth ?? frame.width;
            final double oh = frame.originalHeight ?? frame.height;
            final double ox = (ow - frame.width) / 2.0;
            final double oy = (oh - frame.height) / 2.0;

            final bakeKey = RegionFilterKey(
              request.image,
              ui.Rect.fromLTWH(frame.x, frame.y, frame.width, frame.height),
              request.filter,
              request.decorator,
              itemIndex,
              animationLengths[name] ?? 1,
              ox,
              oy,
              ow,
              oh,
            );

            final pending = PendingBake(
              Sprite(
                request.image,
                srcPosition: Vector2(frame.x, frame.y),
                srcSize: Vector2(frame.width, frame.height),
              ),
              prefix,
              request.nameTransformer != null
                  ? request.nameTransformer!(name)
                  : name,
              request.filter,
              request.decorator,
              itemIndex,
              animationLengths[name] ?? 1,
              bakeKey,
              originalName: originalName,
              sourceRegion: SpriteSourceRegion(
                x: frame.x,
                y: frame.y,
                width: frame.width,
                height: frame.height,
                originalWidth: ow,
                originalHeight: oh,
              ),
            );

            groupedTasks.putIfAbsent(bakeKey, () => []).add(pending);
          }
      }
    }

    if (groupedTasks.isEmpty) {
      throw StateError('No bake requests found.');
    }

    // 3. Analyze & trim each unique slot (scan alpha, crop tight bounds)
    final Map<RegionFilterKey, BakeInfo> keyToInfo = {};
    final List<PendingBake> spritesToBake = [];

    int analyzedCount = 0;
    for (final entry in groupedTasks.entries) {
      final key = entry.key;
      final pending = entry.value;
      final template = pending.first.sprite;
      final decorator = key.decorator;

      final bool isRotated = key.rotate;
      final bool hasExplicitRegion = pending.first.sourceRegion != null;
      final bool isRawSprite = template is! TexturePackerSprite;

      // Decide whether to run alpha analysis (trim)
      // - If trim is enabled AND (explicit GDX region OR raw sprite), analyze
      // - For AtlasBakeRequest (TexturePackerSprite), GDX already trimmed,
      //   so we use the source data directly unless a decorator is present
      final bool needsAlphaAnalysis =
          trim && (hasExplicitRegion || isRawSprite || decorator != null);

      BakeInfo info;

      // GDX atlas sources: use original trimmed bounds and offsets directly.
      // No alpha re-scanning needed — GDX already did optimal trimming.
      final isGdxSource = template is TexturePackerSprite && !hasExplicitRegion;

      if (isGdxSource && decorator == null) {
        // Use GDX metadata as-is, but with visual (un-rotated) dimensions
        // for packing. GDX stores rotated sprites with swapped w/h in src,
        // so the visual size is src.height × src.width.
        final visualW = isRotated ? key.src.height : key.src.width;
        final visualH = isRotated ? key.src.width : key.src.height;

        info = BakeInfo(
          key.src, // trimmed bounds from GDX (may be rotated)
          key.offsetX, // original GDX offset X
          key.offsetY, // original GDX offset Y
          key.originalWidth,
          key.originalHeight,
          rotate: isRotated,
          effectiveWidth: visualW,
          effectiveHeight: visualH,
        );
        // No bakedImage needed — we'll draw directly from the source atlas
      } else if (needsAlphaAnalysis) {
        // Use SpriteBakeInfo.analyze to scan alpha and crop
        final bakeInfo = await SpriteBakeInfo.analyze(
          key: key,
          sprite: template,
          filter: key.filter,
          decorator: key.decorator,
          prefix: pending.first.prefix,
          name: pending.first.name,
          itemIndex: key.itemIndex,
          itemCount: key.itemCount,
          sourceRegion: pending.first.sourceRegion,
        );

        final bool isSpritesheet = pending.first.sourceRegion != null;

        if (isSpritesheet) {
          // For spritesheets: pack at original frame size to avoid scaling.
          // Create a full-frame image with content positioned at the correct offset.
          final ow = bakeInfo.originalWidth;
          final oh = bakeInfo.originalHeight;
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.drawImageRect(
            bakeInfo.bakedImage ?? template.image,
            bakeInfo.trimmedSrc,
            ui.Rect.fromLTWH(
              bakeInfo.offsetX,
              bakeInfo.offsetY,
              bakeInfo.trimmedSrc.width,
              bakeInfo.trimmedSrc.height,
            ),
            ui.Paint()..filterQuality = ui.FilterQuality.none,
          );
          final fullFrame = await recorder.endRecording().toImage(
            ow.ceil(),
            oh.ceil(),
          );

          info = BakeInfo(
            ui.Rect.fromLTWH(0, 0, ow, oh),
            0, // offset is 0 since content is already positioned
            0,
            ow,
            oh,
            rotate: isRotated,
            effectiveWidth: ow,
            effectiveHeight: oh,
          );
          info.bakedImage = fullFrame;
        } else {
          // For non-spritesheets: pack at trimmed size with offsets (GDX-style)
          info = BakeInfo(
            bakeInfo.trimmedSrc,
            bakeInfo.offsetX,
            bakeInfo.offsetY,
            bakeInfo.originalWidth,
            bakeInfo.originalHeight,
            rotate: isRotated,
            effectiveWidth: bakeInfo.trimmedSrc.width,
            effectiveHeight: bakeInfo.trimmedSrc.height,
          );
          info.bakedImage = bakeInfo.bakedImage;
        }
      } else {
        // Fallback: use sprite's src rect directly (no trim, no GDX metadata)
        info = BakeInfo(
          template.src,
          0,
          0,
          template.src.width,
          template.src.height,
          rotate: isRotated,
          effectiveWidth: template.src.width,
          effectiveHeight: template.src.height,
        );
      }

      keyToInfo[key] = info;
      spritesToBake.addAll(pending);

      analyzedCount++;
      // ignore: avoid_print
      print(
        '[CompositeAtlas] Slot $analyzedCount/${groupedTasks.length}: '
        '${pending.first.name} (${info.trimmedSrc.width.toInt()}x${info.trimmedSrc.height.toInt()})'
        '${needsAlphaAnalysis ? ' [trimmed]' : ' [direct]'}',
      );
    }

    // ignore: avoid_print
    print('[CompositeAtlas] Unique slots to bake: ${keyToInfo.length}');

    // 3.5. Deduplicate sprites with identical visual content
    // Compare actual pixel data from the source image, not just metadata.
    // This catches duplicates even when they have different bounds/positions in the atlas.
    Future<String> _computePixelHash(
      RegionFilterKey key,
      PendingBake pending,
    ) async {
      final info = keyToInfo[key]!;
      final sw = key.src.width.toInt();
      final sh = key.src.height.toInt();
      // final sx = key.src.left.toInt();
      // final sy = key.src.top.toInt();

      final ew = (info.effectiveWidth ?? sw).toInt();
      final eh = (info.effectiveHeight ?? sh).toInt();
      final ox = info.offsetX.toInt();
      final oy = info.offsetY.toInt();
      final ow = info.originalWidth.toInt();
      final oh = info.originalHeight.toInt();
      final rot = info.rotate ? 1 : 0;
      final metaSig = '${ew}_${eh}_${ox}_${oy}_${ow}_${oh}_${rot}_${sw}_$sh';

      // Pixel-level hash
      int pixelHash = 0;
      final ui.Image targetImg = info.bakedImage ?? key.image;
      final ui.Rect targetRect = info.bakedImage != null
          ? info
                .trimmedSrc // If it's baked, we only care about the trimmed grayscale pixels
          : key.src;

      final byteData = await targetImg.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        final tw = targetImg.width;
        final tx = targetRect.left.toInt();
        final ty = targetRect.top.toInt();
        final tW = targetRect.width.toInt();
        final tH = targetRect.height.toInt();

        for (int y = 0; y < tH; y++) {
          for (int x = 0; x < tW; x++) {
            final idx = ((ty + y) * tw + (tx + x)) * 4;
            final r = buffer[idx];
            final g = buffer[idx + 1];
            final b = buffer[idx + 2];
            final a = buffer[idx + 3];
            pixelHash = (pixelHash * 31 + r) ^ (g * 37) ^ (b * 41) ^ (a * 43);
          }
        }
      }
      return '${metaSig}_ph${pixelHash}_img${targetImg.hashCode}';
    }

    // Build a map: bakeKey → first pending for that key
    final Map<RegionFilterKey, PendingBake> keyToPending = {};
    for (final pending in spritesToBake) {
      if (!keyToPending.containsKey(pending.bakeKey)) {
        keyToPending[pending.bakeKey] = pending;
      }
    }

    // Compute signatures for all keys
    final Map<RegionFilterKey, String> keySigs = {};
    for (final key in keyToInfo.keys) {
      keySigs[key] = await _computePixelHash(key, keyToPending[key]!);
    }

    // Group duplicates
    final Map<RegionFilterKey, RegionFilterKey> dedupMap = {};
    final Set<RegionFilterKey> masterKeys = {};
    for (final key in keyToInfo.keys) {
      final sig = keySigs[key]!;
      final existing = masterKeys.where((m) => keySigs[m] == sig).firstOrNull;
      if (existing != null) {
        dedupMap[key] = existing;
        // ignore: avoid_print
        print(
          '[CompositeAtlas] Dedup: ${sig.substring(0, sig.indexOf('_img'))} → master',
        );
      } else {
        masterKeys.add(key);
      }
    }

    if (dedupMap.isNotEmpty) {
      // ignore: avoid_print
      print(
        '[CompositeAtlas] Dedup: ${dedupMap.length} duplicate(s) will reuse master slots',
      );
    }
    // ignore: avoid_print
    print(
      '[CompositeAtlas] After dedup: ${masterKeys.length} master slots (from ${keyToInfo.length})',
    );

    // 4. Sort sprites for better packing density
    final List<RegionFilterKey> sortedKeys = masterKeys.toList();
    if (allowRotation) {
      // For rotation: sort by shortest side (descending) — better for mixed sizes
      sortedKeys.sort((a, b) {
        final infoA = keyToInfo[a]!;
        final infoB = keyToInfo[b]!;
        final shortA = math.min(
          infoA.effectiveWidth ?? infoA.trimmedSrc.width,
          infoA.effectiveHeight ?? infoA.trimmedSrc.height,
        );
        final shortB = math.min(
          infoB.effectiveWidth ?? infoB.trimmedSrc.height,
          infoB.effectiveHeight ?? infoB.trimmedSrc.height,
        );
        return shortB.compareTo(shortA);
      });
    } else {
      // Without rotation: sort by height (descending) — shelf packing
      // Taller sprites go first, shorter ones fill horizontal gaps above
      sortedKeys.sort((a, b) {
        final infoA = keyToInfo[a]!;
        final infoB = keyToInfo[b]!;
        final hA = infoA.effectiveHeight ?? infoA.trimmedSrc.height;
        final hB = infoB.effectiveHeight ?? infoB.trimmedSrc.height;
        return hB.compareTo(hA);
      });
    }

    const double padding = 2.0;

    // Calculate initial atlas size
    double maxSpriteDim = 64.0;
    double totalArea = 0;
    for (final key in sortedKeys) {
      final info = keyToInfo[key]!;
      final w = (info.effectiveWidth ?? info.trimmedSrc.width) + padding;
      final h = (info.effectiveHeight ?? info.trimmedSrc.height) + padding;
      maxSpriteDim = math.max(maxSpriteDim, math.max(w, h));
      totalArea += w * h;
    }

    // Start with power-of-two based on total area, not just max sprite
    // This avoids constant growToFit calls that waste space between rows
    final double areaSide = math.sqrt(totalArea);
    double initialSide = math.max(maxSpriteDim, areaSide);
    initialSide = _nextPow2(initialSide.ceil()).toDouble();
    initialSide = math.max(initialSide, 64.0);

    AtlasPacker packer = GuillotinePacker(initialSide);

    // 5. Pack all sprites
    final Map<RegionFilterKey, ui.Offset> drawingPositions = {};

    for (final key in sortedKeys) {
      final info = keyToInfo[key]!;
      final w = (info.effectiveWidth ?? info.trimmedSrc.width) + padding;
      final h = (info.effectiveHeight ?? info.trimmedSrc.height) + padding;

      var result = packer.pack(w, h, allowRotation: allowRotation);

      int growAttempts = 0;
      while (result == null && growAttempts < 20) {
        packer.growToFit(w, h, allowRotation: allowRotation);
        if (packer is GuillotinePacker) packer.mergeFreeRects();
        result = packer.pack(w, h, allowRotation: allowRotation);
        growAttempts++;
      }

      if (result == null) {
        // ignore: avoid_print
        print(
          '[CompositeAtlas] WARNING: Failed to pack "${key.src.width.toInt()}x${key.src.height.toInt()}" '
          '(tried $growAttempts grows, atlas exceeded)',
        );
        continue;
      }

      drawingPositions[key] = result.offset;
      info.rotate = result.rotated;
    }

    // 6. Calculate actual bounds and round up to power-of-two
    double actualMaxY = 0;
    double actualMaxX = 0;
    for (final key in sortedKeys) {
      final pos = drawingPositions[key]!;
      final info = keyToInfo[key]!;
      final visualW = info.effectiveWidth ?? info.trimmedSrc.width;
      final visualH = info.effectiveHeight ?? info.trimmedSrc.height;
      final sheetW = info.rotate ? visualH : visualW;
      final sheetH = info.rotate ? visualW : visualH;

      actualMaxY = math.max(actualMaxY, pos.dy + sheetH + padding);
      actualMaxX = math.max(actualMaxX, pos.dx + sheetW + padding);
    }

    // Round up to power-of-two (64, 128, 256, 512, 1024, 2048)
    final texWidth = _nextPow2(actualMaxX.ceil());
    final texHeight = _nextPow2(actualMaxY.ceil());

    // ignore: avoid_print
    print(
      '[CompositeAtlas] Final size: ${texWidth}x$texHeight '
      '(used: ${actualMaxX.toInt()}x${actualMaxY.toInt()}, '
      '${(totalArea / (texWidth * texHeight) * 100).toStringAsFixed(1)}% fill)',
    );

    // 6. Render the final atlas
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final basePaint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    // Only render master slots — duplicates will reference the same pixels
    for (final key in masterKeys) {
      final pos = drawingPositions[key]!;
      final info = keyToInfo[key]!;

      canvas.save();
      canvas.translate(pos.dx, pos.dy);

      final visualW = info.effectiveWidth ?? info.trimmedSrc.width;
      final visualH = info.effectiveHeight ?? info.trimmedSrc.height;

      if (info.rotate) {
        canvas.translate(0, visualW);
        canvas.rotate(-math.pi / 2);
      }

      final dst = ui.Rect.fromLTWH(0, 0, visualW, visualH);

      if (info.bakedImage != null) {
        canvas.drawImageRect(
          info.bakedImage!,
          info.trimmedSrc, // Fix: only draw the trimmed/processed portion of the baked image
          dst,
          basePaint,
        );
      } else {
        // GDX source: draw directly from the source atlas.
        // If the sprite is rotated in the source GDX atlas, un-rotate it
        // into a temp buffer first so the new atlas stores it upright.
        if (key.rotate) {
          // Source is rotated in GDX — un-rotate to get visual pixels.
          // This produces a buffer of the correct visual dimensions.
          final unrotW = key.src.height;
          final unrotH = key.src.width;
          final unrotRecorder = ui.PictureRecorder();
          final unrotCanvas = ui.Canvas(unrotRecorder);
          unrotCanvas.translate(unrotW, 0);
          unrotCanvas.rotate(math.pi / 2);
          unrotCanvas.drawImageRect(
            key.image,
            key.src,
            ui.Rect.fromLTWH(0, 0, key.src.width, key.src.height),
            basePaint,
          );
          final unrotated = await unrotRecorder.endRecording().toImage(
            unrotW.ceil(),
            unrotH.ceil(),
          );

          // Draw at the visual size (un-rotated dimensions).
          // The canvas transform (info.rotate) will handle atlas-level rotation.
          canvas.drawImageRect(
            unrotated,
            ui.Rect.fromLTWH(0, 0, unrotW, unrotH),
            ui.Rect.fromLTWH(0, 0, unrotW, unrotH),
            basePaint,
          );
          unrotated.dispose();
        } else {
          canvas.drawImageRect(key.image, info.trimmedSrc, dst, basePaint);
        }
      }
      canvas.restore();
    }

    final megaImage = await recorder.endRecording().toImage(
      texWidth,
      texHeight,
    );

    for (final info in keyToInfo.values) {
      info.bakedImage?.dispose();
    }

    // 7. Build sprite map with GDX-compatible metadata
    final spriteMap = <String, TexturePackerSprite>{};
    final megaPage = Page()
      ..texture = megaImage
      ..width = megaImage.width
      ..height = megaImage.height;

    for (final pending in spritesToBake) {
      // Resolve deduplication: use master key's position if this is a duplicate
      final effectiveKey = dedupMap[pending.bakeKey] ?? pending.bakeKey;
      final pos = drawingPositions[effectiveKey]!;
      final bakeInfo = keyToInfo[effectiveKey]!;

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
                    (pending.sprite as TexturePackerSprite).region.index == -1))
            ? -1
            : (pending.itemIndex ?? -1),
      );

      final newSprite = TexturePackerSprite(newRegion);
      newSprite.srcSize = newSprite.originalSize;

      final primaryKey = newRegion.index == -1
          ? newRegion.name
          : '${newRegion.name}#${newRegion.index}';
      spriteMap[primaryKey] = newSprite;

      if (pending.originalName != null) {
        final prefOrig = '${pending.prefix}${pending.originalName}';
        if (prefOrig != primaryKey && prefOrig != newRegion.name) {
          spriteMap[prefOrig] = newSprite;
        }
      }
    }

    return CompositeAtlasImpl._(megaImage, spriteMap, prefixes);
  }

  @override
  List<String> get allSpriteNames => _internalSpriteMap.keys.toList();

  @override
  TexturePackerSprite? findSpriteByName(String name) {
    if (_internalSpriteMap.containsKey(name)) return _internalSpriteMap[name];

    // 1. Try prefix-unaware lookup
    for (final prefix in _prefixes) {
      final combined = '$prefix$name';
      if (_internalSpriteMap.containsKey(combined)) {
        return _internalSpriteMap[combined];
      }
    }

    // 2. Handle indexed fallback for singular lookup
    // If we asked for 'lake', it might be stored as 'lake#0'
    final lookupNames = <String>{name, ..._prefixes.map((p) => '$p$name')};
    for (final lookup in lookupNames) {
      final indexedKey = '$lookup#0';
      if (_internalSpriteMap.containsKey(indexedKey)) {
        return _internalSpriteMap[indexedKey];
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

  @override
  void dispose() => image.dispose();

  @override
  String generateGDXAtlasContent(String imageName) {
    final sb = StringBuffer();
    sb.writeln(imageName);
    sb.writeln('size:${image.width},${image.height}');
    sb.writeln('filter:Nearest,Nearest');
    sb.writeln('repeat:none');

    // Sort sprites by name then index for GDX compatibility
    final sortedSprites =
        List<TexturePackerSprite>.from(sprites.cast<TexturePackerSprite>())
          ..sort((a, b) {
            final nameComp = a.region.name.compareTo(b.region.name);
            if (nameComp != 0) return nameComp;
            return a.region.index.compareTo(b.region.index);
          });

    for (final sprite in sortedSprites) {
      final r = sprite.region;
      sb.writeln(r.name);
      sb.writeln('index:${r.index}');
      sb.writeln(
        'bounds:${r.left.toInt()},${r.top.toInt()},${r.width.toInt()},${r.height.toInt()}',
      );
      sb.writeln(
        'offsets:${r.offsetX.toInt()},${r.offsetY.toInt()},${r.originalWidth.toInt()},${r.originalHeight.toInt()}',
      );
    }

    return sb.toString();
  }

  /// Rounds up to the nearest power-of-two, minimum 64.
  /// Sequence: 64, 128, 256, 512, 1024, 2048, 4096
  static int _nextPow2(int value) {
    if (value <= 64) return 64;
    int pot = 64;
    while (pot < value) {
      pot <<= 1;
    }
    return pot;
  }
}
