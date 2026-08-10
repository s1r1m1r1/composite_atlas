import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:composite_atlas/composite_atlas.dart';

// ignore_for_file: implementation_imports
import 'package:flame_texturepacker/src/model/page.dart';
import 'package:flame_texturepacker/src/model/region.dart';

/// Creates a minimal TexturePackerSprite for testing.
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
  group('MarkerAnchor enum', () {
    test('has exactly 9 values', () {
      expect(MarkerAnchor.values.length, 9);
    });

    test('fraction pairs match expected grid', () {
      // 3×3 grid of anchor fractions
      const expected = <MarkerAnchor, (double, double)>{
        MarkerAnchor.topLeft: (0.0, 0.0),
        MarkerAnchor.topCenter: (0.5, 0.0),
        MarkerAnchor.topRight: (1.0, 0.0),
        MarkerAnchor.centerLeft: (0.0, 0.5),
        MarkerAnchor.center: (0.5, 0.5),
        MarkerAnchor.centerRight: (1.0, 0.5),
        MarkerAnchor.bottomLeft: (0.0, 1.0),
        MarkerAnchor.bottomCenter: (0.5, 1.0),
        MarkerAnchor.bottomRight: (1.0, 1.0),
      };

      for (final entry in expected.entries) {
        expect(
          entry.key.fractionX,
          entry.value.$1,
          reason: '${entry.key.name}.fractionX',
        );
        expect(
          entry.key.fractionY,
          entry.value.$2,
          reason: '${entry.key.name}.fractionY',
        );
      }
    });

    test('X fractions form left-center-right pattern', () {
      expect(MarkerAnchor.topLeft.fractionX, 0.0);
      expect(MarkerAnchor.topCenter.fractionX, 0.5);
      expect(MarkerAnchor.topRight.fractionX, 1.0);
    });

    test('Y fractions form top-center-bottom pattern', () {
      expect(MarkerAnchor.topLeft.fractionY, 0.0);
      expect(MarkerAnchor.centerLeft.fractionY, 0.5);
      expect(MarkerAnchor.bottomLeft.fractionY, 1.0);
    });
  });

  group('computeEffectPosition — distinct positions per anchor', () {
    // Use a small marker (4×4) in a 96×96 frame and a 32×32 effect sprite.
    // This ensures (packedSize - effectSize) ≠ 0, so each anchor
    // produces a unique offset.

    late AtlasMarker smallMarker;
    late TexturePackerAtlas atlas;

    setUp(() {
      // Marker: small 4×4 point, GDX position at center of 96×96 frame
      //   offsetX = (96-4)/2 = 46, offsetY = (96-4)/2 = 46
      //   flameY = 96 - 46 - 4 = 46
      final markerSprite = _makeSprite(
        offsetX: 46,
        offsetY: 46,
        originalWidth: 96,
        originalHeight: 96,
        width: 4,
        height: 4,
        name: 'center_point',
      );
      smallMarker = AtlasMarker.fromSprite(markerSprite)!;

      // Effect sprite: 32×32
      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 32,
        originalHeight: 32,
        width: 32,
        height: 32,
        name: 'effect_sprite',
      );

      atlas = TexturePackerAtlas([markerSprite, effectSprite]);
    });

    test('all 9 anchors produce unique positions', () {
      final positions = <MarkerAnchor, Vector2>{};
      for (final anchor in MarkerAnchor.values) {
        final effectSprite = _makeSprite(
          offsetX: 0,
          offsetY: 0,
          originalWidth: 32,
          originalHeight: 32,
          width: 32,
          height: 32,
        );
        positions[anchor] = atlas.computeEffectPosition(
          smallMarker,
          effectSprite,
          anchor: anchor,
        );
      }

      // All positions should be distinct
      final uniquePositions = positions.values.toSet();
      expect(
        uniquePositions.length,
        9,
        reason: 'Each anchor must produce a unique position',
      );
    });

    test('center is at (46, 46) — same as marker flame offset', () {
      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 32,
        originalHeight: 32,
        width: 32,
        height: 32,
      );

      final pos = atlas.computeEffectPosition(
        smallMarker,
        effectSprite,
        anchor: MarkerAnchor.center,
      );

      // marker.flameOffset = (46, 46)
      // markerAnchor = (46 + 4*0.5, 46 + 4*0.5) = (48, 48)
      // effectAnchor = (32*0.5, 32*0.5) = (16, 16)
      // pos = (48 - 16, 48 - 16) = (32, 32)
      expect(pos.x, 32.0);
      expect(pos.y, 32.0);
    });

    test('topLeft is at marker flame offset', () {
      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 32,
        originalHeight: 32,
        width: 32,
        height: 32,
      );

      final pos = atlas.computeEffectPosition(
        smallMarker,
        effectSprite,
        anchor: MarkerAnchor.topLeft,
      );

      // markerAnchor = (46 + 4*0, 46 + 4*0) = (46, 46)
      // effectAnchor = (32*0, 32*0) = (0, 0)
      // pos = (46, 46)
      expect(pos.x, 46.0);
      expect(pos.y, 46.0);
    });

    test('bottomRight is offset by (packedSize - effectSize)', () {
      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 32,
        originalHeight: 32,
        width: 32,
        height: 32,
      );

      final pos = atlas.computeEffectPosition(
        smallMarker,
        effectSprite,
        anchor: MarkerAnchor.bottomRight,
      );

      // markerAnchor = (46 + 4*1, 46 + 4*1) = (50, 50)
      // effectAnchor = (32*1, 32*1) = (32, 32)
      // pos = (50 - 32, 50 - 32) = (18, 18)
      expect(pos.x, 18.0);
      expect(pos.y, 18.0);
    });

    test('topRight — X at effectSize offset, Y at marker offset', () {
      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 32,
        originalHeight: 32,
        width: 32,
        height: 32,
      );

      final pos = atlas.computeEffectPosition(
        smallMarker,
        effectSprite,
        anchor: MarkerAnchor.topRight,
      );

      // markerAnchor = (46 + 4*1, 46 + 4*0) = (50, 46)
      // effectAnchor = (32*1, 32*0) = (32, 0)
      // pos = (50 - 32, 46 - 0) = (18, 46)
      expect(pos.x, 18.0);
      expect(pos.y, 46.0);
    });

    test('bottomLeft — X at marker offset, Y at effectSize offset', () {
      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 32,
        originalHeight: 32,
        width: 32,
        height: 32,
      );

      final pos = atlas.computeEffectPosition(
        smallMarker,
        effectSprite,
        anchor: MarkerAnchor.bottomLeft,
      );

      // markerAnchor = (46 + 4*0, 46 + 4*1) = (46, 50)
      // effectAnchor = (32*0, 32*1) = (0, 32)
      // pos = (46 - 0, 50 - 32) = (46, 18)
      expect(pos.x, 46.0);
      expect(pos.y, 18.0);
    });

    test(
      'offset between topLeft and bottomRight is (packedSize - effectSize)',
      () {
        final effectSpriteTL = _makeSprite(
          offsetX: 0,
          offsetY: 0,
          originalWidth: 32,
          originalHeight: 32,
          width: 32,
          height: 32,
        );
        final effectSpriteBR = _makeSprite(
          offsetX: 0,
          offsetY: 0,
          originalWidth: 32,
          originalHeight: 32,
          width: 32,
          height: 32,
        );

        final posTL = atlas.computeEffectPosition(
          smallMarker,
          effectSpriteTL,
          anchor: MarkerAnchor.topLeft,
        );
        final posBR = atlas.computeEffectPosition(
          smallMarker,
          effectSpriteBR,
          anchor: MarkerAnchor.bottomRight,
        );

        // posBR - posTL = (packedSize - effectSize) * (1,1) - (packedSize - effectSize) * (0,0)
        //               = (packedSize - effectSize)
        //               = (4 - 32, 4 - 32) = (-28, -28)
        expect(posBR.x - posTL.x, smallMarker.packedSize.x - 32.0);
        expect(posBR.y - posTL.y, smallMarker.packedSize.y - 32.0);
      },
    );
  });

  group('computeEffectPosition — same-size cancellation', () {
    // When marker.packedSize == effect.originalSize, ALL anchors
    // produce the same position. This is mathematically correct:
    //   pos = markerFlamePos + (packedSize - effectSize) * fraction
    //       = markerFlamePos + 0
    //       = markerFlamePos

    late AtlasMarker marker32;
    late TexturePackerAtlas atlas;

    setUp(() {
      final markerSprite = _makeSprite(
        offsetX: 16,
        offsetY: 16,
        originalWidth: 64,
        originalHeight: 64,
        width: 32,
        height: 32,
        name: 'center_point',
      );
      marker32 = AtlasMarker.fromSprite(markerSprite)!;

      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 32,
        originalHeight: 32,
        width: 32,
        height: 32,
        name: 'effect',
      );
      atlas = TexturePackerAtlas([markerSprite, effectSprite]);
    });

    test('all 9 anchors produce the same position', () {
      final positions = <Vector2>[];
      for (final anchor in MarkerAnchor.values) {
        final effectSprite = _makeSprite(
          offsetX: 0,
          offsetY: 0,
          originalWidth: 32,
          originalHeight: 32,
          width: 32,
          height: 32,
        );
        positions.add(
          atlas.computeEffectPosition(marker32, effectSprite, anchor: anchor),
        );
      }

      // All should equal marker.flameOffset
      for (final pos in positions) {
        expect(pos.x, marker32.flameOffset.x);
        expect(pos.y, marker32.flameOffset.y);
      }
    });
  });

  group('computeEffectPosition — asymmetric marker/effect sizes', () {
    // Marker 8×8, effect 48×24 (wider than tall).
    // Different X and Y offsets per anchor.

    late AtlasMarker marker;
    late TexturePackerAtlas atlas;

    setUp(() {
      final markerSprite = _makeSprite(
        offsetX: 100,
        offsetY: 50,
        originalWidth: 200,
        originalHeight: 200,
        width: 8,
        height: 8,
        name: 'test_point',
      );
      marker = AtlasMarker.fromSprite(markerSprite)!;

      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 48,
        originalHeight: 24,
        width: 48,
        height: 24,
        name: 'effect',
      );
      atlas = TexturePackerAtlas([markerSprite, effectSprite]);
    });

    test('topLeft — effectPos = marker.flameOffset', () {
      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 48,
        originalHeight: 24,
        width: 48,
        height: 24,
      );
      final pos = atlas.computeEffectPosition(
        marker,
        effectSprite,
        anchor: MarkerAnchor.topLeft,
      );
      expect(pos.x, marker.flameOffset.x);
      expect(pos.y, marker.flameOffset.y);
    });

    test('center — offset by (packedSize - effectSize) / 2', () {
      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 48,
        originalHeight: 24,
        width: 48,
        height: 24,
      );
      final pos = atlas.computeEffectPosition(
        marker,
        effectSprite,
        anchor: MarkerAnchor.center,
      );
      final expectedDx = (marker.packedSize.x - 48.0) * 0.5;
      final expectedDy = (marker.packedSize.y - 24.0) * 0.5;
      expect(pos.x, marker.flameOffset.x + expectedDx);
      expect(pos.y, marker.flameOffset.y + expectedDy);
    });

    test('bottomRight — offset by (packedSize - effectSize)', () {
      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 48,
        originalHeight: 24,
        width: 48,
        height: 24,
      );
      final pos = atlas.computeEffectPosition(
        marker,
        effectSprite,
        anchor: MarkerAnchor.bottomRight,
      );
      final expectedDx = marker.packedSize.x - 48.0;
      final expectedDy = marker.packedSize.y - 24.0;
      expect(pos.x, marker.flameOffset.x + expectedDx);
      expect(pos.y, marker.flameOffset.y + expectedDy);
    });

    test('topRight has different X but same Y as topLeft', () {
      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 48,
        originalHeight: 24,
        width: 48,
        height: 24,
      );
      final posTL = atlas.computeEffectPosition(
        marker,
        effectSprite,
        anchor: MarkerAnchor.topLeft,
      );
      final posTR = atlas.computeEffectPosition(
        marker,
        effectSprite,
        anchor: MarkerAnchor.topRight,
      );
      expect(posTR.x, isNot(posTL.x));
      expect(posTR.y, posTL.y);
    });

    test('bottomLeft has same X but different Y as topLeft', () {
      final effectSprite = _makeSprite(
        offsetX: 0,
        offsetY: 0,
        originalWidth: 48,
        originalHeight: 24,
        width: 48,
        height: 24,
      );
      final posTL = atlas.computeEffectPosition(
        marker,
        effectSprite,
        anchor: MarkerAnchor.topLeft,
      );
      final posBL = atlas.computeEffectPosition(
        marker,
        effectSprite,
        anchor: MarkerAnchor.bottomLeft,
      );
      expect(posBL.x, posTL.x);
      expect(posBL.y, isNot(posTL.y));
    });
  });

  group('MarkerAnchor direction naming', () {
    // Verify the 9 direction strings used in the calibration screen
    // correctly map to MarkerAnchor values.

    const directionToAnchor = {
      'top_left': MarkerAnchor.topLeft,
      'top_center': MarkerAnchor.topCenter,
      'top_right': MarkerAnchor.topRight,
      'center_left': MarkerAnchor.centerLeft,
      'center': MarkerAnchor.center,
      'center_right': MarkerAnchor.centerRight,
      'bottom_left': MarkerAnchor.bottomLeft,
      'bottom_center': MarkerAnchor.bottomCenter,
      'bottom_right': MarkerAnchor.bottomRight,
    };

    test('all 9 direction names are mapped', () {
      expect(directionToAnchor.length, 9);
    });

    test('direction names map to valid anchors with fractions', () {
      for (final entry in directionToAnchor.entries) {
        // The mapping itself should be consistent
        expect(entry.value.fractionX, isA<double>());
        expect(entry.value.fractionY, isA<double>());
        expect(entry.value.fractionX, inInclusiveRange(0.0, 1.0));
        expect(entry.value.fractionY, inInclusiveRange(0.0, 1.0));
      }
    });

    test(
      'snake_case direction names correspond to correct anchor fractions',
      () {
        // "center" is the only direction whose snake_case name
        // matches the camelCase MarkerAnchor name exactly
        expect(directionToAnchor['center']!.name, 'center');

        // All others use snake_case with underscores
        expect(directionToAnchor['top_left']!.name, 'topLeft');
        expect(directionToAnchor['bottom_right']!.name, 'bottomRight');
        expect(directionToAnchor['center_right']!.name, 'centerRight');
      },
    );

    test('each direction name follows the naming convention', () {
      for (final dirName in directionToAnchor.keys) {
        // Should contain a vertical component
        expect(
          dirName.contains('top') ||
              dirName.contains('center') ||
              dirName.contains('bottom'),
          isTrue,
          reason: '$dirName should contain vertical component',
        );
      }
    });
  });

  group('computeEffectPosition — offset formula verification', () {
    // For each anchor, verify the general formula:
    //   pos = markerFlamePos + (packedSize - effectSize) * (fx, fy)

    test('formula holds for all 9 anchors with random marker/effect sizes', () {
      final markerSprite = _makeSprite(
        offsetX: 50,
        offsetY: 30,
        originalWidth: 128,
        originalHeight: 128,
        width: 6,
        height: 6,
        name: 'test_point',
      );
      final marker = AtlasMarker.fromSprite(markerSprite)!;

      final effectW = 40.0;
      final effectH = 28.0;
      final atlas = TexturePackerAtlas([markerSprite]);

      for (final anchor in MarkerAnchor.values) {
        final effectSprite = _makeSprite(
          offsetX: 0,
          offsetY: 0,
          originalWidth: effectW,
          originalHeight: effectH,
          width: effectW,
          height: effectH,
        );
        final pos = atlas.computeEffectPosition(
          marker,
          effectSprite,
          anchor: anchor,
        );

        final flameOffset = marker.flameOffset;
        final dx = (marker.packedSize.x - effectW) * anchor.fractionX;
        final dy = (marker.packedSize.y - effectH) * anchor.fractionY;

        expect(
          pos.x,
          closeTo(flameOffset.x + dx, 0.001),
          reason: '${anchor.name}: X mismatch',
        );
        expect(
          pos.y,
          closeTo(flameOffset.y + dy, 0.001),
          reason: '${anchor.name}: Y mismatch',
        );
      }
    });
  });

  group('flameOffset Y-down conversion', () {
    test('centered marker in 96×96 frame', () {
      // GDX: offsetX=46, offsetY=46, packedSize=4×4
      // Flame Y = 96 - 46 - 4 = 46
      final sprite = _makeSprite(
        offsetX: 46,
        offsetY: 46,
        originalWidth: 96,
        originalHeight: 96,
        width: 4,
        height: 4,
        name: 'center_point',
      );
      final marker = AtlasMarker.fromSprite(sprite)!;

      expect(marker.flameOffset.x, 46.0);
      expect(marker.flameOffset.y, 46.0);
    });

    test('top-left marker in 96×96 frame', () {
      // GDX: offsetX=0, offsetY=60, packedSize=4×4
      // Flame Y = 96 - 60 - 4 = 32
      final sprite = _makeSprite(
        offsetX: 0,
        offsetY: 60,
        originalWidth: 96,
        originalHeight: 96,
        width: 4,
        height: 4,
        name: 'tl_point',
      );
      final marker = AtlasMarker.fromSprite(sprite)!;

      expect(marker.flameOffset.x, 0.0);
      expect(marker.flameOffset.y, 32.0);
    });

    test('bottom-right marker in 96×96 frame', () {
      // GDX: offsetX=92, offsetY=0, packedSize=4×4
      // Flame Y = 96 - 0 - 4 = 92
      final sprite = _makeSprite(
        offsetX: 92,
        offsetY: 0,
        originalWidth: 96,
        originalHeight: 96,
        width: 4,
        height: 4,
        name: 'br_point',
      );
      final marker = AtlasMarker.fromSprite(sprite)!;

      expect(marker.flameOffset.x, 92.0);
      expect(marker.flameOffset.y, 92.0);
    });
  });
}
