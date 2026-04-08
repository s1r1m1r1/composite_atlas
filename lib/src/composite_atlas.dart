import 'dart:ui' as ui;
import 'package:flame/sprite.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'bake_request.dart';
import 'composite_atlas_impl.dart';

/// Packing algorithm mode for [CompositeAtlas.bake].
///
/// - [fast] — Guillotine bin-packing with shortest-side-first heuristic.
///   O(n log n) speed, ideal for **runtime** atlas baking.
///
/// - [optimal] — MaxRects with best-area-fit + merge heuristics.
///   Slower but produces denser packing, ideal for **pre-build/dev** workflows.
enum AtlasPackMode { fast, optimal }

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

  /// Efficiently creates a [SpriteAnimation] for a given sprite name.
  SpriteAnimation getAnimation(
    String name, {
    double stepTime = 0.1,
    bool loop = true,
    bool useIndexedSpritesOnly = false,
  });

  /// Creates a [ui.ColorFilter] that shifts the hue by the given [radians].
  static ui.ColorFilter hue(double radians) =>
      CompositeAtlasImpl.hueFilter(radians);

  /// Bakes multiple [BakeRequest] instances into a single [CompositeAtlas].
  ///
  /// [packMode] controls the packing algorithm:
  /// - [AtlasPackMode.fast] — Guillotine, O(n log n), good for runtime
  /// - [AtlasPackMode.optimal] — MaxRects with merge, slower but denser
  static Future<CompositeAtlas> bake(
    List<BakeRequest> requests, {
    double maxAtlasWidth = 1024.0,
    bool allowRotation = true,
    bool forceSquare = false,
    bool trim = true,
    AtlasPackMode packMode = AtlasPackMode.fast,
  }) => CompositeAtlasImpl.bake(
    requests,
    maxAtlasWidth: maxAtlasWidth,
    allowRotation: allowRotation,
    forceSquare: forceSquare,
    trim: trim,
    packMode: packMode,
  );

  /// Creates a simple wrapper for a regular [TexturePackerAtlas] without baking.
  static CompositeAtlas fromAtlas(TexturePackerAtlas atlas) =>
      CompositeAtlasImpl.fromAtlas(atlas);
}
