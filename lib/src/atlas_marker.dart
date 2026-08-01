import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';

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

  /// Computes the effect position for a given marker and effect sprite,
  /// using either topLeft or center alignment.
  ///
  /// Uses [AtlasMarker.flameOffset] and [flameSpriteOffset] to convert
  /// GDX Y-up offsets to Flame Y-down coordinates.
  ///
  /// [marker] — the anchor point marker.
  /// [effectSprite] — the effect sprite to position.
  /// [alignCenter] — if true, centers the effect's packed pixels on the
  ///   marker's packed pixels. If false, uses topLeft alignment.
  Vector2 computeEffectPosition(
    AtlasMarker marker,
    TexturePackerSprite effectSprite, {
    bool alignCenter = false,
  }) {
    final effectFlame = AtlasMarker.flameSpriteOffset(effectSprite);
    final effectPacked = Vector2(
      effectSprite.region.width.toDouble(),
      effectSprite.region.height.toDouble(),
    );

    if (alignCenter) {
      final markerCenter = marker.flameOffset + marker.packedSize * 0.5;
      final effectCenter = effectFlame + effectPacked * 0.5;
      return Vector2(
        markerCenter.x - effectCenter.x,
        markerCenter.y - effectCenter.y,
      );
    } else {
      return Vector2(
        marker.flameOffset.x - effectFlame.x,
        marker.flameOffset.y - effectFlame.y,
      );
    }
  }
}
