import 'dart:ui' as ui;
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'bake_request.dart';
import 'composite_atlas_impl.dart';

/// A runtime-composed texture atlas that merges multiple [BakeRequest]
/// sources into a single [ui.Image] to minimize draw calls.
/// 
/// It extends [TexturePackerAtlas] to be fully compatible with the Flame engine.
abstract class CompositeAtlas extends TexturePackerAtlas {
  /// Internal constructor to pass through sprites to [TexturePackerAtlas].
  CompositeAtlas(super.sprites);

  /// Provides direct access to the underlying image (from the first sprite).
  ui.Image get image;

  /// Returns all sprite names present in the atlas.
  List<String> get allSpriteNames;

  /// Disposes the underlying image for baked atlases.
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
