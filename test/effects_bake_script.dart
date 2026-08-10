import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:composite_atlas/composite_atlas.dart';

/// Bake script: re-bakes effects.atlas using CompositeAtlas and recalculates
/// the warservant_atk_point marker position.
///
/// Run: flutter test test/effects_bake_script.dart
/// Output: packages/tokens_assets/assets/images/atlases/effects_baked.*
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Bake effects atlas with marker recalculation', () async {
    final effectsAtlasPath =
        '/Users/today/Desktop/S1RGAME/apps/tokens_app/packages/tokens_assets/assets/images/atlases/effects.atlas';
    final outputDir =
        '/Users/today/Desktop/S1RGAME/apps/tokens_app/packages/tokens_assets/assets/images/atlases';

    // 1. Load the source effects atlas from disk
    final sourceAtlas = await TexturePackerAtlas.load(
      effectsAtlasPath,
      fromStorage: true,
      useOriginalSize: true,
    );

    print('\n═══════════════════════════════════════════════');
    print('SOURCE ATLAS: effects.atlas');
    print('  Sprites: ${sourceAtlas.sprites.length}');
    for (final s in sourceAtlas.sprites) {
      final r = s.region;
      print(
        '  ${r.name} (idx:${r.index}) '
        'bounds:${r.left.toInt()},${r.top.toInt()},'
        '${r.width.toInt()},${r.height.toInt()} '
        'offsets:${r.offsetX.toInt()},${r.offsetY.toInt()},'
        '${r.originalWidth.toInt()},${r.originalHeight.toInt()}',
      );
    }

    // 2. Detect markers BEFORE bake
    final sourceMarkers = sourceAtlas.getMarkers();
    print('\nSource markers:');
    for (final m in sourceMarkers) {
      print(
        '  ${m.name}: pos=(${m.position.x}, ${m.position.y}) '
        'ref=${m.referenceSize.x}×${m.referenceSize.y} '
        'packed=${m.packedSize.x}×${m.packedSize.y}',
      );
      print('  flameOffset=${m.flameOffset}');
    }

    // 3. Re-bake into CompositeAtlas (preserves all GDX metadata)
    print('\nBaking...');
    final bakedAtlas = await CompositeAtlas.bake([
      AtlasBakeRequest(sourceAtlas),
    ]);

    print('\nBAKED ATLAS:');
    print('  Image size: ${bakedAtlas.image.width}×${bakedAtlas.image.height}');
    print('  All sprite names: ${bakedAtlas.allSpriteNames}');

    // 4. Verify markers AFTER bake
    final bakedMarker = bakedAtlas.findMarker('warservant_atk_point');
    if (bakedMarker == null) {
      fail('Marker warservant_atk_point lost during bake!');
    }
    print('\nBaked marker:');
    print(
      '  ${bakedMarker.name}: pos=(${bakedMarker.position.x}, ${bakedMarker.position.y})',
    );
    print(
      '  ref=${bakedMarker.referenceSize.x}×${bakedMarker.referenceSize.y}',
    );
    print('  packed=${bakedMarker.packedSize.x}×${bakedMarker.packedSize.y}');
    print('  flameOffset=${bakedMarker.flameOffset}');

    // 5. Collect gun_flash frames — source names are gun_flash1..gun_flash5
    // (not indexed frames, so findSpritesByName('gun_flash') won't match).
    final allFlashFrames = <TexturePackerSprite>[];
    for (int i = 1; i <= 5; i++) {
      final sprite = bakedAtlas.findSpriteByName('gun_flash$i');
      if (sprite != null) {
        allFlashFrames.add(sprite as TexturePackerSprite);
      }
    }
    print('\ngun_flash via marker (${allFlashFrames.length} frames):');
    for (int i = 0; i < allFlashFrames.length; i++) {
      final s = allFlashFrames[i];
      final r = s.region;
      final posTL = bakedAtlas.computeEffectPosition(bakedMarker, s);
      final posC = bakedAtlas.computeEffectPosition(
        bakedMarker,
        s,
        alignCenter: true,
      );
      print(
        '  ${r.name}: bounds=${r.left.toInt()},${r.top.toInt()},'
        '${r.width.toInt()},${r.height.toInt()} '
        'offsets=${r.offsetX.toInt()},${r.offsetY.toInt()},'
        '${r.originalWidth.toInt()},${r.originalHeight.toInt()}',
      );
      print('    → topLeft: $posTL  center: $posC');
    }

    // 6. Save baked PNG
    final pngData = await bakedAtlas.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (pngData == null) {
      fail('Failed to encode baked atlas as PNG');
    }
    final pngBytes = pngData.buffer.asUint8List();
    final pngFile = File('$outputDir/effects_baked.png');
    await pngFile.writeAsBytes(pngBytes);
    print('\nSaved PNG: ${pngFile.path} (${pngBytes.length} bytes)');

    // 7. Save baked atlas metadata
    final atlasContent = bakedAtlas.generateGDXAtlasContent(
      'effects_baked.png',
    );
    final atlasFile = File('$outputDir/effects_baked.atlas');
    await atlasFile.writeAsString(atlasContent);
    print('Saved atlas: ${atlasFile.path}');

    // 8. Print the generated atlas content
    print('\n═══ GENERATED effects_baked.atlas ═══');
    print(atlasContent);
    print('═══════════════════════════════════════════════\n');

    // Verify marker metadata survived
    expect(bakedMarker.position.x, 93.0, reason: 'Marker offsetX should be 93');
    expect(bakedMarker.position.y, 32.0, reason: 'Marker offsetY should be 32');
    expect(
      bakedMarker.referenceSize.x,
      256.0,
      reason: 'Marker origW should be 256',
    );
    expect(
      bakedMarker.referenceSize.y,
      256.0,
      reason: 'Marker origH should be 256',
    );
    expect(
      bakedMarker.packedSize.x,
      13.0,
      reason: 'Marker packedW should be 13',
    );
    expect(
      bakedMarker.packedSize.y,
      13.0,
      reason: 'Marker packedH should be 13',
    );
    expect(allFlashFrames.length, 5, reason: 'Should have 5 gun_flash frames');

    // Verify gun_flash coordinates via marker
    // computeEffectPosition uses marker.flameOffset = (93, 211)
    // and the flash sprite's originalSize (15×21).
    // For topLeft alignment: pos = marker.flameOffset = (93, 211)
    final firstFlashPos = bakedAtlas.computeEffectPosition(
      bakedMarker,
      allFlashFrames.first,
    );
    expect(firstFlashPos.x, 93.0, reason: 'gun_flash topLeft X should be 93');
    expect(firstFlashPos.y, 211.0, reason: 'gun_flash topLeft Y should be 211');

    bakedAtlas.dispose();
  });
}
