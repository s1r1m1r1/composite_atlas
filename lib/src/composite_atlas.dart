import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'bake_request.dart';
import 'composite_atlas_impl.dart';

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
