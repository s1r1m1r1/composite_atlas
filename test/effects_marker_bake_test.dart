import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:composite_atlas/composite_atlas.dart';

// ignore_for_file: implementation_imports
import 'package:flame_texturepacker/src/model/page.dart';
import 'package:flame_texturepacker/src/model/region.dart';

/// Demonstrates atlas baking with markers and computing virtual coordinates
/// for effect sprites (gun_flash) relative to a marker (warservant_atk_point).
///
/// Uses synthetic sprites that replicate the real effects.atlas metadata:
///   gun_flash1: bounds:46,5,9,9    offsets:3,4,15,21
///   gun_flash2: bounds:33,4,11,10  offsets:2,2,15,21
///   gun_flash3: bounds:16,6,15,8   offsets:0,1,15,21
///   gun_flash4: bounds:57,8,5,6    offsets:5,0,15,21
///   gun_flash5: bounds:16,3,3,1    offsets:6,3,15,21
///   warservant_atk_point: bounds:1,1,13,13 offsets:93,32,256,256

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Shared source image (simulates the effects.png atlas texture)
  late ui.Image sourceImage;

  // Sprites replicating effects.atlas metadata
  late TexturePackerSprite flash1;
  late TexturePackerSprite flash2;
  late TexturePackerSprite flash3;
  late TexturePackerSprite flash4;
  late TexturePackerSprite flash5;
  late TexturePackerSprite atkPoint;

  setUpAll(() async {
    // 64×16 matches the effects.png "size:64,16" from effects.atlas
    sourceImage = await _createTestImage(64, 16);

    flash1 = _makeSprite(
      image: sourceImage,
      name: 'gun_flash',
      index: 1,
      left: 46,
      top: 5,
      width: 9,
      height: 9,
      offsetX: 3,
      offsetY: 4,
      originalWidth: 15,
      originalHeight: 21,
    );
    flash2 = _makeSprite(
      image: sourceImage,
      name: 'gun_flash',
      index: 2,
      left: 33,
      top: 4,
      width: 11,
      height: 10,
      offsetX: 2,
      offsetY: 2,
      originalWidth: 15,
      originalHeight: 21,
    );
    flash3 = _makeSprite(
      image: sourceImage,
      name: 'gun_flash',
      index: 3,
      left: 16,
      top: 6,
      width: 15,
      height: 8,
      offsetX: 0,
      offsetY: 1,
      originalWidth: 15,
      originalHeight: 21,
    );
    flash4 = _makeSprite(
      image: sourceImage,
      name: 'gun_flash',
      index: 4,
      left: 57,
      top: 8,
      width: 5,
      height: 6,
      offsetX: 5,
      offsetY: 0,
      originalWidth: 15,
      originalHeight: 21,
    );
    flash5 = _makeSprite(
      image: sourceImage,
      name: 'gun_flash',
      index: 5,
      left: 16,
      top: 3,
      width: 3,
      height: 1,
      offsetX: 6,
      offsetY: 3,
      originalWidth: 15,
      originalHeight: 21,
    );
    atkPoint = _makeSprite(
      image: sourceImage,
      name: 'warservant_atk_point',
      index: -1,
      left: 1,
      top: 1,
      width: 13,
      height: 13,
      offsetX: 93,
      offsetY: 32,
      originalWidth: 256,
      originalHeight: 256,
    );
  });

  group('Approach A: AtlasBakeRequest (re-bake from atlas — recommended)', () {
    late CompositeAtlas bakedAtlas;

    setUpAll(() async {
      // Build a TexturePackerAtlas from the synthetic sprites,
      // then re-bake into a CompositeAtlas. This is the recommended
      // approach because all GDX metadata (offsets, original sizes)
      // is preserved automatically.
      final sourceAtlas = TexturePackerAtlas([
        flash1,
        flash2,
        flash3,
        flash4,
        flash5,
        atkPoint,
      ]);

      bakedAtlas = await CompositeAtlas.bake([AtlasBakeRequest(sourceAtlas)]);
    });

    test('baked atlas contains all 5 gun_flash frames', () {
      final flashSprites = bakedAtlas.findSpritesByName('gun_flash');
      expect(flashSprites.length, 5);
    });

    test('baked atlas contains warservant_atk_point marker', () {
      final marker = bakedAtlas.findMarker('warservant_atk_point');
      expect(marker, isNotNull);
      expect(marker!.name, 'warservant_atk_point');
    });

    test('marker position preserves GDX offsets (93, 32)', () {
      final marker = bakedAtlas.findMarker('warservant_atk_point')!;

      // offsets:93,32,256,256 → position = (93, 32)
      expect(marker.position.x, 93.0);
      expect(marker.position.y, 32.0);
      expect(marker.referenceSize.x, 256.0);
      expect(marker.referenceSize.y, 256.0);
      expect(marker.packedSize.x, 13.0);
      expect(marker.packedSize.y, 13.0);
    });

    test('flameOffset converts GDX Y-up → Flame Y-down', () {
      final marker = bakedAtlas.findMarker('warservant_atk_point')!;

      // GDX: offsets:93,32 means X=93, Y=32 from the BOTTOM (Y-up)
      // Flame Y-down: y = originalHeight - offsetY - packedHeight
      //   = 256 - 32 - 13 = 211
      expect(marker.flameOffset.x, 93.0);
      expect(marker.flameOffset.y, 211.0);
    });

    test('computeEffectPosition topLeft: gun_flash at marker', () {
      final marker = bakedAtlas.findMarker('warservant_atk_point')!;
      final flashSprite =
          bakedAtlas.findSpritesByName('gun_flash').first
              as TexturePackerSprite;

      final pos = bakedAtlas.computeEffectPosition(marker, flashSprite);

      // topLeft: effect original frame top-left at marker flame position
      // marker.flameOffset = (93, 211)
      expect(pos.x, 93.0);
      expect(pos.y, 211.0);
    });

    test('computeEffectPosition center: gun_flash centered on marker', () {
      final marker = bakedAtlas.findMarker('warservant_atk_point')!;
      final flashSprite =
          bakedAtlas.findSpritesByName('gun_flash').first
              as TexturePackerSprite;

      final pos = bakedAtlas.computeEffectPosition(
        marker,
        flashSprite,
        alignCenter: true,
      );

      // marker packed center = flameOffset + packedSize/2
      //   = (93 + 6.5, 211 + 6.5) = (99.5, 217.5)
      // effect originalSize = (15, 21), half = (7.5, 10.5)
      // pos = (99.5 - 7.5, 217.5 - 10.5) = (92.0, 207.0)
      expect(pos.x, 92.0);
      expect(pos.y, 207.0);
    });

    test('virtual coords are identical across all 5 gun_flash frames', () {
      final marker = bakedAtlas.findMarker('warservant_atk_point')!;
      final flashFrames = bakedAtlas.findSpritesByName('gun_flash');

      // All frames share originalSize (15×21), so the computed
      // component position is the same regardless of packed size.
      final positions = flashFrames
          .map(
            (s) => bakedAtlas.computeEffectPosition(
              marker,
              s as TexturePackerSprite,
            ),
          )
          .toList();

      for (int i = 1; i < positions.length; i++) {
        expect(
          positions[i].x,
          positions[0].x,
          reason: 'Frame $i X should match frame 0',
        );
        expect(
          positions[i].y,
          positions[0].y,
          reason: 'Frame $i Y should match frame 0',
        );
      }
    });

    test('baseName strips _point suffix', () {
      final marker = bakedAtlas.findMarker('warservant_atk_point')!;
      expect(marker.baseName, 'warservant_atk');
    });

    test('findMarkerByBase works', () {
      final marker = bakedAtlas.findMarkerByBase('warservant_atk');
      expect(marker, isNotNull);
      expect(marker!.name, 'warservant_atk_point');
    });

    test('getMarkers returns only marker sprites', () {
      final markers = bakedAtlas.getMarkers();
      expect(markers.length, 1);
      expect(markers.first.name, 'warservant_atk_point');
    });

    test('flashSprite offsets are preserved after bake', () {
      // Verify that per-frame offsets survived the bake
      final flashFrames = bakedAtlas.findSpritesByName('gun_flash');

      // Frame 1: offsets:3,4,15,21
      final f1 = flashFrames[0] as TexturePackerSprite;
      expect(f1.region.offsetX, 3.0);
      expect(f1.region.offsetY, 4.0);
      expect(f1.region.originalWidth, 15.0);
      expect(f1.region.originalHeight, 21.0);

      // Frame 2: offsets:2,2,15,21
      final f2 = flashFrames[1] as TexturePackerSprite;
      expect(f2.region.offsetX, 2.0);
      expect(f2.region.offsetY, 2.0);
    });

    test('generateGDXAtlasContent includes marker data', () {
      final gdx = bakedAtlas.generateGDXAtlasContent('effects.png');

      expect(gdx, contains('warservant_atk_point'));
      expect(gdx, contains('offsets:93,32,256,256'));
      expect(gdx, contains('gun_flash'));
    });

    tearDownAll(() {
      bakedAtlas.dispose();
    });
  });

  group('Approach B: ImageBakeRequest (from raw PNGs)', () {
    test('individual frames + marker without atlas metadata', () async {
      // When you don't have a pre-existing .atlas file, you can bake
      // from individual images. The marker is auto-detected by name
      // suffix, but offset metadata is computed from image dimensions,
      // NOT from war servant reference frame.
      final markerImg = await _createTestImage(13, 13);
      final flashImgs = <ui.Image>[];
      for (int i = 0; i < 5; i++) {
        flashImgs.add(await _createTestImage(15, 21));
      }

      final requests = <BakeRequest>[
        for (int i = 0; i < flashImgs.length; i++)
          ImageBakeRequest(flashImgs[i], name: 'gun_flash'),
        // The marker _point suffix triggers auto-detection by AtlasMarker,
        // but the position is computed from image size, NOT (93, 32).
        // This is fine for visual debug, but NOT for coordinate resolution.
        ImageBakeRequest(markerImg, name: 'warservant_atk_point'),
      ];

      final baked = await CompositeAtlas.bake(requests);

      final marker = baked.findMarker('warservant_atk_point');
      expect(marker, isNotNull);

      // Position is auto-computed: offsetX = (256-13)/2 = 121.5
      // This is WRONG for muzzle positioning — it's a centered default.
      // Use AtlasBakeRequest from .atlas for accurate marker positions.
      print('Individual bake marker position: ${marker!.position}');
      print(
        'NOTE: Position is auto-computed from image dimensions. '
        'Use AtlasBakeRequest for accurate war servant muzzle coordinates.',
      );

      baked.dispose();
      for (final img in flashImgs) {
        img.dispose();
      }
      markerImg.dispose();
    });
  });

  group('Coordinate resolution summary', () {
    test('full gun_flash placement walkthrough', () async {
      // Step 1: Build the atlas (same as Approach A)
      final sourceAtlas = TexturePackerAtlas([
        flash1,
        flash2,
        flash3,
        flash4,
        flash5,
        atkPoint,
      ]);
      final atlas = await CompositeAtlas.bake([AtlasBakeRequest(sourceAtlas)]);

      // Step 2: Find the marker
      final marker = atlas.findMarker('warservant_atk_point');
      assert(marker != null, 'Marker not found!');

      // Step 3: Get gun_flash animation sprites
      final flashSprites = atlas.findSpritesByName('gun_flash');

      // Step 4: For each frame, compute the virtual position
      // where the effect component should be placed, relative to
      // the reference frame origin (e.g. character position).
      print('\n═══ GUN_FLASH COORDINATE RESOLUTION ═══');
      print('Marker: ${marker!.name}');
      print('  GDX offsets: ${marker.position} in ${marker.referenceSize}');
      print('  Flame Y-down: ${marker.flameOffset}');
      print('');

      for (int i = 0; i < flashSprites.length; i++) {
        final s = flashSprites[i] as TexturePackerSprite;
        final r = s.region;

        final posTL = atlas.computeEffectPosition(marker, s);
        final posC = atlas.computeEffectPosition(marker, s, alignCenter: true);

        print('Frame ${i + 1} (${r.name}):');
        print(
          '  packed: ${r.width}×${r.height}  offset: (${r.offsetX}, ${r.offsetY})',
        );
        print('  → topLeft position: $posTL');
        print('  → center position:  $posC');
      }

      print('');
      print('RESULT: Place gun_flash SpriteComponent at (93, 211)');
      print(
        '  in Flame Y-down coords, relative to the 256×256 reference frame.',
      );
      print('  Use EffectAnchor.topLeft or computePosition() for scaling.');
      print('══════════════════════════════════════════\n');

      atlas.dispose();
    });
  });
}

// ─── Helpers ───────────────────────────────────────────────────────────

TexturePackerSprite _makeSprite({
  required ui.Image image,
  required String name,
  required int index,
  required double left,
  required double top,
  required double width,
  required double height,
  required double offsetX,
  required double offsetY,
  required double originalWidth,
  required double originalHeight,
}) {
  final page = Page()
    ..texture = image
    ..width = image.width
    ..height = image.height;

  return TexturePackerSprite(
    Region(
      page: page,
      name: name,
      left: left,
      top: top,
      width: width,
      height: height,
      offsetX: offsetX,
      offsetY: offsetY,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
      index: index,
    ),
  );
}

Future<ui.Image> _createTestImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF00FF00), ui.BlendMode.src);
  return recorder.endRecording().toImage(width, height);
}
