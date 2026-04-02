import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/rendering.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';

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
