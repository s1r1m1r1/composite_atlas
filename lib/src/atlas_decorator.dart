import 'dart:ui' as ui;

/// Context provided to [AtlasDecorator]s during the baking process.
/// This allows shaders to sample from the original atlas using correctly
/// mapping global texture coordinates.
class AtlasContext {
  final ui.Image atlasImage;
  final ui.Rect srcRect;
  final ui.Size atlasSize;
  final ui.Size localSize;
  final int? itemIndex;
  final int? itemCount;

  AtlasContext({
    required this.atlasImage,
    required this.srcRect,
    required this.atlasSize,
    required this.localSize,
    this.itemIndex,
    this.itemCount,
  });
}

/// An interface for [Decorator]s that require access to the source atlas context.
/// This is particularly useful for fragment shaders that need to sample from
/// an atlas.
abstract class AtlasDecorator {
  void updateAtlasContext(AtlasContext context);
}
