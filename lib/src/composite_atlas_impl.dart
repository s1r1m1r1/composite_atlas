import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
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
}

/// Represents a request to bake assets into a [CompositeAtlas].
abstract class BakeRequest {
  final ui.ColorFilter? filter;
  final String? keyPrefix;

  BakeRequest({this.filter, this.keyPrefix});
}

/// Request to bake an entire [TexturePackerAtlas] (optionally filtered by whitelist).
class AtlasBakeRequest extends BakeRequest {
  final TexturePackerAtlas atlas;
  final List<String>? whiteList;

  AtlasBakeRequest(this.atlas, {super.filter, super.keyPrefix, this.whiteList});
}

/// Request to bake a standalone [Sprite] as a specific entry in the atlas.
class SpriteBakeRequest extends BakeRequest {
  final Sprite sprite;
  final String name;

  SpriteBakeRequest(
    this.sprite, {
    required this.name,
    super.filter,
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

  /// Bakes multiple [BakeRequest] instances into a single [CompositeAtlas].
  static Future<CompositeAtlas> bake(List<BakeRequest> requests) async {
    if (requests.isEmpty) {
      throw ArgumentError('At least one bake request must be provided.');
    }

    // 1. Collect and analyze all sprites
    final List<Future<_SpriteBakeInfo>> analyzerFutures = [];
    for (final request in requests) {
      final prefix = request.keyPrefix ?? '';

      if (request is AtlasBakeRequest) {
        for (final sprite in request.atlas.sprites) {
          final region = sprite.region;
          if (request.whiteList != null) {
            if (!request.whiteList!.any((w) => region.name.startsWith(w))) {
              continue;
            }
          }
          // Atlas regions are usually pre-trimmed, just use them.
          analyzerFutures.add(
            Future.value(
              _SpriteBakeInfo(
                originalSprite: sprite,
                filter: request.filter,
                prefix: prefix,
                nameInAtlas: region.name,
                trimmedSrc: sprite.src,
                offsetX: region.offsetX,
                offsetY: region.offsetY,
                originalWidth: region.originalWidth,
                originalHeight: region.originalHeight,
              ),
            ),
          );
        }
      } else if (request is SpriteBakeRequest) {
        analyzerFutures.add(
          _SpriteBakeInfo.analyze(
            sprite: request.sprite,
            filter: request.filter,
            prefix: prefix,
            name: request.name,
          ),
        );
      } else if (request is ImageBakeRequest) {
        analyzerFutures.add(
          _SpriteBakeInfo.analyze(
            sprite: Sprite(request.image),
            filter: request.filter,
            prefix: prefix,
            name: request.name,
          ),
        );
      }
    }

    final spritesToBake = await Future.wait(analyzerFutures);
    if (spritesToBake.isEmpty) {
      throw StateError('No sprites found matching the bake requests.');
    }

    // 2. Identify unique Region+Filter combinations to draw
    final uniqueSourceRegions = <_RegionFilterKey>{};
    for (final info in spritesToBake) {
      uniqueSourceRegions.add(
        _RegionFilterKey(
          info.originalSprite.image,
          info.trimmedSrc,
          info.filter,
        ),
      );
    }

    // 3. Layout (Shelf Packing)
    final sortedUniqueRegions = uniqueSourceRegions.toList()
      ..sort((a, b) => b.height.compareTo(a.height));

    const double maxAtlasWidth = 1024.0;
    const double padding = 2.0;
    double currentX = 0;
    double currentY = 0;
    double currentRowHeight = 0;
    double maxWidth = 0;

    final Map<_RegionFilterKey, ui.Offset> drawingPositions = {};

    for (final key in sortedUniqueRegions) {
      if (currentX + key.width + padding > maxAtlasWidth && currentX > 0) {
        currentX = 0;
        currentY += currentRowHeight + padding;
        currentRowHeight = 0;
      }

      drawingPositions[key] = ui.Offset(currentX, currentY);
      maxWidth = math.max(maxWidth, currentX + key.width);
      currentRowHeight = math.max(currentRowHeight, key.height);
      currentX += key.width + padding;
    }

    final totalHeight = currentY + currentRowHeight;

    // 4. Draw
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    for (final key in sortedUniqueRegions) {
      final pos = drawingPositions[key]!;
      final paint = ui.Paint()
        ..filterQuality = ui.FilterQuality.none
        ..colorFilter = key.filter;

      canvas.drawImageRect(
        key.image,
        key.src,
        ui.Rect.fromLTWH(pos.dx, pos.dy, key.width, key.height),
        paint,
      );
    }

    final megaImage = await recorder.endRecording().toImage(
      maxWidth.toInt(),
      totalHeight.toInt(),
    );

    // 5. Build Map
    final spriteMap = <String, Sprite>{};
    final megaPage = Page()
      ..texture = megaImage
      ..width = megaImage.width
      ..height = megaImage.height;

    for (final info in spritesToBake) {
      final key = _RegionFilterKey(
        info.originalSprite.image,
        info.trimmedSrc,
        info.filter,
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
  final String prefix;
  final String nameInAtlas;
  final ui.Rect trimmedSrc;
  final double offsetX;
  final double offsetY;
  final double originalWidth;
  final double originalHeight;

  _SpriteBakeInfo({
    required this.originalSprite,
    required this.filter,
    required this.prefix,
    required this.nameInAtlas,
    required this.trimmedSrc,
    required this.offsetX,
    required this.offsetY,
    required this.originalWidth,
    required this.originalHeight,
  });

  /// Analyzes a sprite to compute its non-transparent bounding box for trimming.
  static Future<_SpriteBakeInfo> analyze({
    required Sprite sprite,
    required ui.ColorFilter? filter,
    required String prefix,
    required String name,
  }) async {
    final image = sprite.image;
    final src = sprite.src;

    // Default values (no trimming)
    ui.Rect trimmedSrc = src;
    double offsetX = 0;
    double offsetY = 0;

    try {
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();

        int minX = src.right.toInt();
        int maxX = src.left.toInt();
        int minY = src.bottom.toInt();
        int maxY = src.top.toInt();
        bool found = false;

        // Correct bounds check relative to src
        final startX = src.left.toInt();
        final startY = src.top.toInt();
        final width = src.width.toInt();
        final height = src.height.toInt();

        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            // Index in rawRgba buffer
            final index = ((startY + y) * image.width + (startX + x)) * 4 + 3;
            if (buffer[index] > 5) {
              // Threshold for "nearly transparent"
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
              found = true;
            }
          }
        }

        if (found) {
          trimmedSrc = ui.Rect.fromLTWH(
            startX + minX.toDouble(),
            startY + minY.toDouble(),
            (maxX - minX + 1).toDouble(),
            (maxY - minY + 1).toDouble(),
          );
          offsetX = minX.toDouble();
          offsetY = minY.toDouble();
        }
      }
    } catch (e) {
      // Fallback to untrimmed if anything fails
    }

    return _SpriteBakeInfo(
      originalSprite: sprite,
      filter: filter,
      prefix: prefix,
      nameInAtlas: name,
      trimmedSrc: trimmedSrc,
      offsetX: offsetX,
      offsetY: offsetY,
      originalWidth: src.width,
      originalHeight: src.height,
    );
  }
}

class _RegionFilterKey {
  final ui.Image image;
  final ui.Rect src;
  final ui.ColorFilter? filter;

  _RegionFilterKey(this.image, this.src, this.filter);

  double get width => src.width;
  double get height => src.height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _RegionFilterKey &&
          image == other.image &&
          src == other.src &&
          filter == other.filter);

  @override
  int get hashCode => Object.hash(image, src, filter);
}
