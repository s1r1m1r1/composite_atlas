import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';

/// Defines the anchor point for positioning an effect relative to a marker.
///
/// Each value corresponds to a fractional position within both the marker's
/// packed content and the effect's original frame:
///
/// ```
///  topLeft      topCenter      topRight
///  centerLeft     center      centerRight
///  bottomLeft  bottomCenter   bottomRight
/// ```
///
/// The effect is positioned so that the chosen anchor fraction on the
/// marker's packed content aligns with the same fraction on the effect's
/// original frame.
enum MarkerAnchor {
  /// Top-left corner: effect's top-left at marker's packed top-left.
  topLeft(0.0, 0.0),

  /// Top-center: effect's top-center at marker's packed top-center.
  topCenter(0.5, 0.0),

  /// Top-right: effect's top-right at marker's packed top-right.
  topRight(1.0, 0.0),

  /// Center-left: effect's center-left at marker's packed center-left.
  centerLeft(0.0, 0.5),

  /// Center: effect's center at marker's packed center.
  center(0.5, 0.5),

  /// Center-right: effect's center-right at marker's packed center-right.
  centerRight(1.0, 0.5),

  /// Bottom-left: effect's bottom-left at marker's packed bottom-left.
  bottomLeft(0.0, 1.0),

  /// Bottom-center: effect's bottom-center at marker's packed bottom-center.
  bottomCenter(0.5, 1.0),

  /// Bottom-right: effect's bottom-right at marker's packed bottom-right.
  bottomRight(1.0, 1.0);

  /// The horizontal fraction (0.0 = left, 0.5 = center, 1.0 = right).
  final double fractionX;

  /// The vertical fraction (0.0 = top, 0.5 = center, 1.0 = bottom).
  final double fractionY;

  const MarkerAnchor(this.fractionX, this.fractionY);
}

/// Represents a marker (anchor/attach-point) sprite within an atlas.
///
/// Markers are special sprites that encode positional metadata in their
/// [Region.offsetX], [Region.offsetY] fields. They act as reference points
/// for positioning effects, particles, or other visual elements relative
/// to a character or object sprite.
///
/// ## Naming convention
/// Sprites are recognized as markers by their name suffix:
/// - `_point` — a single positional anchor (e.g. `warservant_atk_point`)
/// - `_marker` — a general-purpose marker
/// - `_anchor` — an attachment point
///
/// ## Offset encoding
/// The marker's `offsetX/offsetY` encode the position within the
/// `originalWidth × originalHeight` reference frame. For example,
/// `offsets:93,32,256,256` means the marker is at (93, 32) in a
/// 256×256 source frame.
///
/// The marker's packed `width × height` defines the visual calibration
/// sprite size (e.g. a crosshair). This is only used for debug rendering;
/// at runtime only the offset position matters.
class AtlasMarker {
  /// The full sprite name as it appears in the atlas (e.g. `warservant_atk_point`).
  final String name;

  /// The marker's position within the reference frame, as raw GDX offsets.
  /// NOTE: GDX offsetY is from the BOTTOM (Y-up). Use [flameOffset] for
  /// Flame Y-down coordinates.
  final Vector2 position;

  /// The reference frame size, extracted from [Region.originalWidth]
  /// and [Region.originalHeight] (e.g. 256×256).
  final Vector2 referenceSize;

  /// The packed (trimmed) size of the marker's visual sprite.
  /// Only meaningful for debug/calibration rendering.
  final Vector2 packedSize;

  /// The underlying [TexturePackerSprite] for this marker.
  /// Can be rendered for calibration purposes.
  final TexturePackerSprite sprite;

  const AtlasMarker({
    required this.name,
    required this.position,
    required this.referenceSize,
    required this.packedSize,
    required this.sprite,
  });

  /// Creates an [AtlasMarker] from a [TexturePackerSprite] if its name
  /// matches the marker naming convention.
  static AtlasMarker? fromSprite(TexturePackerSprite sprite) {
    if (!isMarkerName(sprite.region.name)) return null;
    final r = sprite.region;
    return AtlasMarker(
      name: r.name,
      position: Vector2(r.offsetX, r.offsetY),
      referenceSize: Vector2(r.originalWidth, r.originalHeight),
      packedSize: Vector2(r.width, r.height),
      sprite: sprite,
    );
  }

  /// Returns true if [name] matches the marker naming convention.
  static bool isMarkerName(String name) =>
      name.endsWith('_point') ||
      name.endsWith('_marker') ||
      name.endsWith('_anchor');

  /// The marker's position in Flame Y-down coordinates.
  /// Converts GDX offsetY (from bottom) to Flame Y (from top):
  /// `flameY = originalHeight - offsetY - packedHeight`
  Vector2 get flameOffset =>
      Vector2(position.x, referenceSize.y - position.y - packedSize.y);

  /// Converts any [TexturePackerSprite]'s GDX offset to Flame Y-down.
  /// GDX offsetY is from the bottom; Flame Y is from the top.
  static Vector2 flameSpriteOffset(TexturePackerSprite sprite) {
    final r = sprite.region;
    return Vector2(r.offsetX, r.originalHeight - r.offsetY - r.height);
  }

  /// Returns the marker name with the suffix removed (the "base" name).
  /// E.g. `warservant_atk_point` → `warservant_atk`.
  String get baseName {
    if (name.endsWith('_point')) return name.substring(0, name.length - 6);
    if (name.endsWith('_marker')) return name.substring(0, name.length - 7);
    if (name.endsWith('_anchor')) return name.substring(0, name.length - 7);
    return name;
  }

  @override
  String toString() =>
      'AtlasMarker($name: pos=(${position.x}, ${position.y}) '
      'in ${referenceSize.x}×${referenceSize.y}, '
      'packed=${packedSize.x}×${packedSize.y})';
}

/// Extension on [TexturePackerAtlas] to provide marker lookup.
extension AtlasMarkerExtension on TexturePackerAtlas {
  /// Finds all markers in this atlas by naming convention.
  List<AtlasMarker> getMarkers() {
    final markers = <AtlasMarker>[];
    for (final sprite in sprites) {
      final marker = AtlasMarker.fromSprite(sprite);
      if (marker != null) markers.add(marker);
    }
    return markers;
  }

  /// Finds a single marker by exact [name].
  AtlasMarker? findMarker(String name) {
    for (final sprite in sprites) {
      if (sprite.region.name == name) {
        return AtlasMarker.fromSprite(sprite);
      }
    }
    return null;
  }

  /// Finds a marker by base name (without the suffix).
  /// E.g. `warservant_atk` would match `warservant_atk_point`.
  AtlasMarker? findMarkerByBase(String baseName) {
    for (final sprite in sprites) {
      if (AtlasMarker.isMarkerName(sprite.region.name)) {
        final marker = AtlasMarker.fromSprite(sprite)!;
        if (marker.baseName == baseName) return marker;
      }
    }
    return null;
  }

  /// Computes the effect component position for a given marker and effect
  /// sprite, using the specified [anchor] alignment.
  ///
  /// Uses [AtlasMarker.flameOffset] and [flameSpriteOffset] to convert
  /// GDX Y-up offsets to Flame Y-down coordinates.
  ///
  /// The effect is positioned so that the chosen [anchor] fraction on the
  /// marker's packed content aligns with the same fraction on the effect's
  /// original frame.
  ///
  /// Returns the COMPONENT position (not the packed pixel position).
  /// [TexturePackerSprite.render()] will handle the internal offset
  /// when rendering within the component bounds.
  ///
  /// [marker] — the anchor point marker.
  /// [effectSprite] — the effect sprite to position.
  /// [anchor] — which anchor point to use (default: [MarkerAnchor.topLeft]).
  /// [alignCenter] — **Deprecated**: use [anchor] instead.
  ///   If true, equivalent to [MarkerAnchor.center].
  Vector2 computeEffectPosition(
    AtlasMarker marker,
    TexturePackerSprite effectSprite, {
    MarkerAnchor anchor = MarkerAnchor.topLeft,
    @Deprecated('Use anchor parameter instead') bool alignCenter = false,
  }) {
    // Resolve deprecated parameter
    final effectiveAnchor = alignCenter ? MarkerAnchor.center : anchor;

    final effectOriginalSize = Vector2(
      effectSprite.region.originalWidth,
      effectSprite.region.originalHeight,
    );
    final markerFlamePos = marker.flameOffset;

    // Anchor point on the marker's packed content
    final markerAnchorPoint = Vector2(
      markerFlamePos.x + marker.packedSize.x * effectiveAnchor.fractionX,
      markerFlamePos.y + marker.packedSize.y * effectiveAnchor.fractionY,
    );

    // Corresponding anchor point on the effect's original frame
    final effectAnchorPoint = Vector2(
      effectOriginalSize.x * effectiveAnchor.fractionX,
      effectOriginalSize.y * effectiveAnchor.fractionY,
    );

    // Position the effect so both anchor points coincide
    return Vector2(
      markerAnchorPoint.x - effectAnchorPoint.x,
      markerAnchorPoint.y - effectAnchorPoint.y,
    );
  }
}
