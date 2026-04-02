import 'dart:async';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/rendering.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'atlas_decorator.dart';

/// A internal record of a request to bake a sprite with specific settings.
class PendingBake {
  final Sprite sprite;
  final String prefix;
  final String name;
  final ui.ColorFilter? filter;
  final Decorator? decorator;
  final int? itemIndex;
  final int? itemCount;
  final RegionFilterKey bakeKey;

  PendingBake(
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

class RegionFilterKey {
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

  RegionFilterKey(
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
      (other is RegionFilterKey &&
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

class SpriteBakeInfo {
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
  final RegionFilterKey bakeKey;

  SpriteBakeInfo({
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

  /// Analyzes a sprite to compute its non-transparent bounding box for trimming.
  static Future<SpriteBakeInfo> analyze({
    required RegionFilterKey key,
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

      return SpriteBakeInfo(
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
      return SpriteBakeInfo(
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
