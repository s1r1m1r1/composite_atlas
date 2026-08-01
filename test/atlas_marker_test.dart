import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:composite_atlas/composite_atlas.dart';

// ignore_for_file: implementation_imports
import 'package:flame_texturepacker/src/model/page.dart';
import 'package:flame_texturepacker/src/model/region.dart';

/// Creates a minimal TexturePackerSprite for testing marker math.
TexturePackerSprite _makeSprite({
  required double offsetX,
  required double offsetY,
  required double originalWidth,
  required double originalHeight,
  required double width,
  required double height,
  String name = 'test',
}) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final dummyImage = recorder.endRecording().toImageSync(1, 1);

  final page = Page()
    ..texture = dummyImage
    ..width = 1
    ..height = 1;

  return TexturePackerSprite(
    Region(
      page: page,
      name: name,
      left: 0,
      top: 0,
      width: width,
      height: height,
      offsetX: offsetX,
      offsetY: offsetY,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
    ),
  );
}

void main() {
  group('AtlasMarker', () {
    group('isMarkerName', () {
      test('detects _point suffix', () {
        expect(AtlasMarker.isMarkerName('warservant_atk_point'), isTrue);
      });

      test('detects _marker suffix', () {
        expect(AtlasMarker.isMarkerName('muzzle_marker'), isTrue);
      });

      test('detects _anchor suffix', () {
        expect(AtlasMarker.isMarkerName('hand_anchor'), isTrue);
      });

      test('rejects regular sprite names', () {
        expect(AtlasMarker.isMarkerName('gun_flash1'), isFalse);
        expect(AtlasMarker.isMarkerName('warservant_export_atk'), isFalse);
      });
    });

    group('flameOffset (GDX Y-up → Flame Y-down conversion)', () {
      test('converts marker: offsetY=32 from bottom → Y=211 from top', () {
        // offsets:93,32,256,256 packed:13x13
        // flameY = 256 - 32 - 13 = 211
        final marker = AtlasMarker(
          name: 'warservant_atk_point',
          position: Vector2(93, 32),
          referenceSize: Vector2(256, 256),
          packedSize: Vector2(13, 13),
          sprite: _makeSprite(
            offsetX: 93,
            offsetY: 32,
            originalWidth: 256,
            originalHeight: 256,
            width: 13,
            height: 13,
            name: 'warservant_atk_point',
          ),
        );

        expect(marker.flameOffset.x, 93.0);
        expect(marker.flameOffset.y, 211.0);
      });

      test('flameSpriteOffset converts effect offset correctly', () {
        // gun_flash1: offsets:3,4,15,21 packed:9x9
        // flameY = 21 - 4 - 9 = 8
        final sprite = _makeSprite(
          offsetX: 3,
          offsetY: 4,
          originalWidth: 15,
          originalHeight: 21,
          width: 9,
          height: 9,
        );
        final flame = AtlasMarker.flameSpriteOffset(sprite);

        expect(flame.x, 3.0);
        expect(flame.y, 8.0);
      });

      test('flameSpriteOffset with zero offset', () {
        final sprite = _makeSprite(
          offsetX: 0,
          offsetY: 0,
          originalWidth: 100,
          originalHeight: 100,
          width: 100,
          height: 100,
        );
        final flame = AtlasMarker.flameSpriteOffset(sprite);

        expect(flame.x, 0.0);
        expect(flame.y, 0.0);
      });
    });

    group('computeEffectPosition (via extension)', () {
      late AtlasMarker marker;
      late TexturePackerAtlas atlas;

      setUp(() {
        final markerSprite = _makeSprite(
          offsetX: 93,
          offsetY: 32,
          originalWidth: 256,
          originalHeight: 256,
          width: 13,
          height: 13,
          name: 'warservant_atk_point',
        );
        marker = AtlasMarker.fromSprite(markerSprite)!;

        // Create a minimal atlas with marker + effect sprites
        final effectSprite = _makeSprite(
          offsetX: 3,
          offsetY: 4,
          originalWidth: 15,
          originalHeight: 21,
          width: 9,
          height: 9,
          name: 'gun_flash1',
        );
        atlas = TexturePackerAtlas([markerSprite, effectSprite]);
      });

      test('topLeft: effect original frame at marker flame position', () {
        final effectSprite = _makeSprite(
          offsetX: 3,
          offsetY: 4,
          originalWidth: 15,
          originalHeight: 21,
          width: 9,
          height: 9,
        );

        final pos = atlas.computeEffectPosition(marker, effectSprite);

        // marker.flameOffset = (93, 211)
        expect(pos.x, 93.0);
        expect(pos.y, 211.0);
      });

      test('center: effect frame center at marker packed center', () {
        final effectSprite = _makeSprite(
          offsetX: 3,
          offsetY: 4,
          originalWidth: 15,
          originalHeight: 21,
          width: 9,
          height: 9,
        );

        final pos = atlas.computeEffectPosition(
          marker,
          effectSprite,
          alignCenter: true,
        );

        // marker packed center = (93+6.5, 211+6.5) = (99.5, 217.5)
        // effect originalSize/2 = (7.5, 10.5)
        // pos = (99.5-7.5, 217.5-10.5) = (92, 207)
        expect(pos.x, 92.0);
        expect(pos.y, 207.0);
      });

      test('position is consistent across frames with different offsets', () {
        final frame1 = _makeSprite(
          offsetX: 3,
          offsetY: 4,
          originalWidth: 15,
          originalHeight: 21,
          width: 9,
          height: 9,
        );
        final frame2 = _makeSprite(
          offsetX: 2,
          offsetY: 2,
          originalWidth: 15,
          originalHeight: 21,
          width: 11,
          height: 10,
        );

        final pos1 = atlas.computeEffectPosition(marker, frame1);
        final pos2 = atlas.computeEffectPosition(marker, frame2);

        // Same originalSize → same position regardless of internal offset
        expect(pos1.x, pos2.x);
        expect(pos1.y, pos2.y);
      });
    });

    group('baseName', () {
      test('strips _point suffix', () {
        final marker = AtlasMarker(
          name: 'warservant_atk_point',
          position: Vector2(93, 32),
          referenceSize: Vector2(256, 256),
          packedSize: Vector2(13, 13),
          sprite: _makeSprite(
            offsetX: 0,
            offsetY: 0,
            originalWidth: 1,
            originalHeight: 1,
            width: 1,
            height: 1,
          ),
        );
        expect(marker.baseName, 'warservant_atk');
      });

      test('strips _marker suffix', () {
        final marker = AtlasMarker(
          name: 'muzzle_marker',
          position: Vector2(0, 0),
          referenceSize: Vector2(100, 100),
          packedSize: Vector2(10, 10),
          sprite: _makeSprite(
            offsetX: 0,
            offsetY: 0,
            originalWidth: 1,
            originalHeight: 1,
            width: 1,
            height: 1,
          ),
        );
        expect(marker.baseName, 'muzzle');
      });

      test('returns full name when no suffix', () {
        final marker = AtlasMarker(
          name: 'some_sprite',
          position: Vector2(0, 0),
          referenceSize: Vector2(100, 100),
          packedSize: Vector2(10, 10),
          sprite: _makeSprite(
            offsetX: 0,
            offsetY: 0,
            originalWidth: 1,
            originalHeight: 1,
            width: 1,
            height: 1,
          ),
        );
        expect(marker.baseName, 'some_sprite');
      });
    });

    group('fromSprite', () {
      test('returns null for non-marker names', () {
        final sprite = _makeSprite(
          offsetX: 0,
          offsetY: 0,
          originalWidth: 10,
          originalHeight: 10,
          width: 10,
          height: 10,
          name: 'gun_flash1',
        );
        expect(AtlasMarker.fromSprite(sprite), isNull);
      });

      test('creates marker from valid sprite', () {
        final sprite = _makeSprite(
          offsetX: 50,
          offsetY: 30,
          originalWidth: 200,
          originalHeight: 200,
          width: 20,
          height: 20,
          name: 'test_point',
        );
        final marker = AtlasMarker.fromSprite(sprite);

        expect(marker, isNotNull);
        expect(marker!.name, 'test_point');
        expect(marker.position.x, 50.0);
        expect(marker.position.y, 30.0);
        expect(marker.packedSize.x, 20.0);
        expect(marker.packedSize.y, 20.0);
      });
    });
  });
}
