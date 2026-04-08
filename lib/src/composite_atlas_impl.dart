import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';

import 'composite_atlas.dart';
import 'internal_models.dart';
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

// ─── Common packer interface ───────────────────────────────────────────────

abstract class _AtlasPacker {
  ({ui.Offset offset, bool rotated})? pack(
    double w,
    double h, {
    bool allowRotation,
  });

  void growToFit(double w, double h, {bool allowRotation});
}

// ─── Fast Guillotine (runtime) ──────────────────────────────────────────────
/// Guillotine bin-packing with Shortest-Axis-First split heuristic.
/// O(n log n) speed, good for runtime atlas baking.
class _GuillotinePacker implements _AtlasPacker {
  final double maxWidth;
  final List<ui.Rect> _freeRects = [];
  double _currentWidth;
  double _currentHeight;

  _GuillotinePacker(double initialSide)
    : maxWidth = 4096.0,
      _currentWidth = initialSide,
      _currentHeight = initialSide {
    _freeRects.add(ui.Rect.fromLTWH(0, 0, initialSide, initialSide));
  }

  @override
  ({ui.Offset offset, bool rotated})? pack(
    double w,
    double h, {
    bool allowRotation = true,
  }) {
    // Best short-side fit — minimizes leftover space on the shorter axis
    int bestIdx = -1;
    double bestShort = double.infinity;
    bool rotated = false;

    for (int i = 0; i < _freeRects.length; i++) {
      final r = _freeRects[i];

      // Original orientation
      if (r.width >= w - 0.0001 && r.height >= h - 0.0001) {
        final leftover = math.min(r.width - w, r.height - h);
        if (leftover < bestShort) {
          bestShort = leftover;
          bestIdx = i;
          rotated = false;
        }
      }

      // Rotated
      if (allowRotation && r.width >= h - 0.0001 && r.height >= w - 0.0001) {
        final leftover = math.min(r.width - h, r.height - w);
        if (leftover < bestShort) {
          bestShort = leftover;
          bestIdx = i;
          rotated = true;
        }
      }
    }

    if (bestIdx == -1) return null;

    final rect = _freeRects.removeAt(bestIdx);
    final useW = rotated ? h : w;
    final useH = rotated ? w : h;
    _split(rect, useW, useH);
    return (offset: ui.Offset(rect.left, rect.top), rotated: rotated);
  }

  @override
  void growToFit(double w, double h, {bool allowRotation = true}) {
    // Ensure width can fit the sprite (or its rotated form)
    final double neededWidth = allowRotation ? math.min(w, h) : w;
    while (_currentWidth < neededWidth && _currentWidth < 4096) {
      _currentWidth *= 2;
    }

    // Grow height only when necessary — no fixed minimums.
    // This avoids wasting space on large rows when sprites are small.
    final double neededHeight = h;
    // Add a new row of the exact height we need.
    _freeRects.add(
      ui.Rect.fromLTWH(0, _currentHeight, _currentWidth, neededHeight),
    );
    _currentHeight += neededHeight;
  }

  void _split(ui.Rect rect, double w, double h) {
    final freeW = rect.width - w;
    final freeH = rect.height - h;

    // Shortest-axis split: split along the shorter leftover
    if (freeW < freeH) {
      // Horizontal split — leftover above/below
      if (freeW > 0.0001) {
        _freeRects.add(ui.Rect.fromLTWH(rect.left + w, rect.top, freeW, h));
      }
      if (freeH > 0.0001) {
        _freeRects.add(
          ui.Rect.fromLTWH(rect.left, rect.top + h, rect.width, freeH),
        );
      }
    } else {
      // Vertical split — leftover left/right
      if (freeH > 0.0001) {
        _freeRects.add(ui.Rect.fromLTWH(rect.left, rect.top + h, w, freeH));
      }
      if (freeW > 0.0001) {
        _freeRects.add(
          ui.Rect.fromLTWH(rect.left + w, rect.top, freeW, rect.height),
        );
      }
    }
  }

  double get currentWidth => _currentWidth;
  double get currentHeight => _currentHeight;

  /// Merges adjacent free rects to create larger contiguous spaces.
  void mergeFreeRects() {
    final merged = <ui.Rect>[];
    final used = List<bool>.filled(_freeRects.length, false);

    for (int i = 0; i < _freeRects.length; i++) {
      if (used[i]) continue;
      var current = _freeRects[i];
      used[i] = true;

      // Try to merge with other free rects
      bool mergedAny;
      do {
        mergedAny = false;
        for (int j = i + 1; j < _freeRects.length; j++) {
          if (used[j]) continue;
          final other = _freeRects[j];
          final merged_ = _tryMerge(current, other);
          if (merged_ != null) {
            current = merged_;
            used[j] = true;
            mergedAny = true;
          }
        }
      } while (mergedAny);

      merged.add(current);
    }

    _freeRects.clear();
    _freeRects.addAll(merged);
  }

  static ui.Rect? _tryMerge(ui.Rect a, ui.Rect b) {
    // Same left/right, vertically adjacent
    if ((a.left - b.left).abs() < 0.0001 &&
        (a.width - b.width).abs() < 0.0001) {
      if ((a.bottom - b.top).abs() < 0.0001) {
        return ui.Rect.fromLTWH(a.left, a.top, a.width, a.height + b.height);
      }
      if ((a.top - b.bottom).abs() < 0.0001) {
        return ui.Rect.fromLTWH(a.left, b.top, a.width, a.height + b.height);
      }
    }
    // Same top/bottom, horizontally adjacent
    if ((a.top - b.top).abs() < 0.0001 &&
        (a.height - b.height).abs() < 0.0001) {
      if ((a.right - b.left).abs() < 0.0001) {
        return ui.Rect.fromLTWH(a.left, a.top, a.width + b.width, a.height);
      }
      if ((a.left - b.right).abs() < 0.0001) {
        return ui.Rect.fromLTWH(b.left, a.top, a.width + b.width, a.height);
      }
    }
    return null;
  }
}

// ─── MaxRects (optimal / prebuild) ──────────────────────────────────────────
/// MaxRects bin-packing with Best-Area-Fit heuristic + free rect merging.
/// Slower but denser packing — ideal for pre-build / dev workflows.
class _MaxRectsPacker implements _AtlasPacker {
  final List<ui.Rect> _freeRects = [];
  double _currentWidth;
  double _currentHeight;

  _MaxRectsPacker(double initialSide)
    : _currentWidth = initialSide,
      _currentHeight = initialSide {
    _freeRects.add(ui.Rect.fromLTWH(0, 0, initialSide, initialSide));
  }

  @override
  ({ui.Offset offset, bool rotated})? pack(
    double w,
    double h, {
    bool allowRotation = true,
  }) {
    int bestIdx = -1;
    double bestArea = double.infinity;
    double bestShort = double.infinity;
    bool rotated = false;

    for (int i = 0; i < _freeRects.length; i++) {
      final r = _freeRects[i];

      if (r.width >= w - 0.0001 && r.height >= h - 0.0001) {
        final area = r.width * r.height;
        final leftover = math.min(r.width - w, r.height - h);
        if (area < bestArea || (area == bestArea && leftover < bestShort)) {
          bestArea = area;
          bestShort = leftover;
          bestIdx = i;
          rotated = false;
        }
      }

      if (allowRotation && r.width >= h - 0.0001 && r.height >= w - 0.0001) {
        final area = r.width * r.height;
        final leftover = math.min(r.width - h, r.height - w);
        if (area < bestArea || (area == bestArea && leftover < bestShort)) {
          bestArea = area;
          bestShort = leftover;
          bestIdx = i;
          rotated = true;
        }
      }
    }

    if (bestIdx == -1) return null;

    final rect = _freeRects.removeAt(bestIdx);
    final useW = rotated ? h : w;
    final useH = rotated ? w : h;
    _placeRect(rect, useW, useH);
    return (offset: ui.Offset(rect.left, rect.top), rotated: rotated);
  }

  @override
  void growToFit(double w, double h, {bool allowRotation = true}) {
    // Ensure width can fit the sprite (or its rotated form)
    final double neededWidth = allowRotation ? math.min(w, h) : w;
    while (_currentWidth < neededWidth && _currentWidth < 4096) {
      _currentWidth *= 2;
    }

    // Add a new row of the exact height we need.
    _freeRects.add(ui.Rect.fromLTWH(0, _currentHeight, _currentWidth, h));
    _currentHeight += h;
  }

  void _placeRect(ui.Rect rect, double w, double h) {
    // Split all free rects that overlap with the placed rect
    final newFree = <ui.Rect>[];
    for (int i = 0; i < _freeRects.length; i++) {
      final fr = _freeRects[i];
      if (_intersect(fr, rect)) {
        // Split this free rect into up to 4 new rects around the placed rect
        // Left
        if (fr.left < rect.left) {
          newFree.add(
            ui.Rect.fromLTWH(fr.left, fr.top, rect.left - fr.left, fr.height),
          );
        }
        // Right
        if (fr.right > rect.right) {
          newFree.add(
            ui.Rect.fromLTWH(
              rect.right,
              fr.top,
              fr.right - rect.right,
              fr.height,
            ),
          );
        }
        // Top
        if (fr.top < rect.top) {
          newFree.add(
            ui.Rect.fromLTWH(
              math.max(fr.left, rect.left),
              fr.top,
              math.min(fr.right, rect.right) - math.max(fr.left, rect.left),
              rect.top - fr.top,
            ),
          );
        }
        // Bottom
        if (fr.bottom > rect.bottom) {
          newFree.add(
            ui.Rect.fromLTWH(
              math.max(fr.left, rect.left),
              rect.bottom,
              math.min(fr.right, rect.right) - math.max(fr.left, rect.left),
              fr.bottom - rect.bottom,
            ),
          );
        }
      } else {
        newFree.add(fr);
      }
    }
    _freeRects.clear();
    _freeRects.addAll(
      newFree.where((r) => r.width > 0.001 && r.height > 0.001),
    );
    mergeFreeRects();
  }

  bool _intersect(ui.Rect a, ui.Rect b) {
    return a.left < b.right &&
        a.right > b.left &&
        a.top < b.bottom &&
        a.bottom > b.top;
  }

  void mergeFreeRects() {
    final merged = <ui.Rect>[];
    final used = List<bool>.filled(_freeRects.length, false);

    for (int i = 0; i < _freeRects.length; i++) {
      if (used[i]) continue;
      var current = _freeRects[i];
      used[i] = true;

      bool mergedAny;
      do {
        mergedAny = false;
        for (int j = i + 1; j < _freeRects.length; j++) {
          if (used[j]) continue;
          final other = _freeRects[j];
          final merged_ = _GuillotinePacker._tryMerge(current, other);
          if (merged_ != null) {
            current = merged_;
            used[j] = true;
            mergedAny = true;
          }
        }
      } while (mergedAny);

      merged.add(current);
    }

    _freeRects.clear();
    _freeRects.addAll(merged);
  }

  double get currentWidth => _currentWidth;
  double get currentHeight => _currentHeight;
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
    bool trim = true,
    AtlasPackMode packMode = AtlasPackMode.fast,
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

    // 2. Group by visual identity (Image + Rect + Filter + Decorator + rotation)
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
              : (animationLengths[name] == 1 ? -1 : (localIndices[name] ?? 0));
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
      } else if (request is SpriteBakeRequest) {
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
          name,
          request.filter,
          request.decorator,
          itemIndex,
          1,
          bakeKey,
          originalName: originalName,
          sourceRegion: sr,
        );

        groupedTasks.putIfAbsent(bakeKey, () => []).add(pending);
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
      // For spritesheets and GDX atlases: compute pixel-level hash
      final sw = key.src.width.toInt();
      final sh = key.src.height.toInt();
      final sx = key.src.left.toInt();
      final sy = key.src.top.toInt();

      final info = keyToInfo[key]!;
      final ew = (info.effectiveWidth ?? sw).toInt();
      final eh = (info.effectiveHeight ?? sh).toInt();
      final ox = info.offsetX.toInt();
      final oy = info.offsetY.toInt();
      final ow = info.originalWidth.toInt();
      final oh = info.originalHeight.toInt();
      final rot = info.rotate ? 1 : 0;
      final metaSig = '${ew}_${eh}_${ox}_${oy}_${ow}_${oh}_${rot}_${sw}_${sh}';

      // Pixel-level hash
      int pixelHash = 0;
      final byteData = await key.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        for (int y = 0; y < sh; y++) {
          for (int x = 0; x < sw; x++) {
            final idx = ((sy + y) * key.image.width + (sx + x)) * 4;
            final r = buffer[idx];
            final g = buffer[idx + 1];
            final b = buffer[idx + 2];
            final a = buffer[idx + 3];
            pixelHash = (pixelHash * 31 + r) ^ (g * 37) ^ (b * 41) ^ (a * 43);
          }
        }
      }
      return '${metaSig}_ph${pixelHash}_img${key.image.hashCode}';
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

    _AtlasPacker packer;
    if (packMode == AtlasPackMode.optimal) {
      packer = _MaxRectsPacker(initialSide);
    } else {
      packer = _GuillotinePacker(initialSide);
    }

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
        if (packer is _GuillotinePacker) packer.mergeFreeRects();
        if (packer is _MaxRectsPacker) packer.mergeFreeRects();
        result = packer.pack(w, h, allowRotation: allowRotation);
        growAttempts++;
      }

      if (result == null) {
        // ignore: avoid_print
        print(
          '[CompositeAtlas] WARNING: Failed to pack "${key.src.width.toInt()}x${key.src.height.toInt()}" '
          '(tried ${growAttempts} grows, atlas exceeded)',
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
      '[CompositeAtlas] Final size: ${texWidth}x${texHeight} '
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

  /// Rounds up to the nearest power-of-two, minimum 64.
  /// Sequence: 64, 128, 256, 512, 1024, 2048, 4096
  static int _nextPow2(int value) {
    if (value <= 64) return 64;
    int pot = 64;
    while (pot < value) pot <<= 1;
    return pot;
  }
}
