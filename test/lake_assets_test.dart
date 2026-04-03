import 'package:flutter_test/flutter_test.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:composite_atlas/composite_atlas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Lake Assets Integration (hex_lake)', () {
    const atlasPath = 'test/assets/hex_lake.atlas';

    test('Bakes hex_lake.atlas and retrieves animation sequences', () async {
      // 1. Load the real atlas from the filesystem
      final baseAtlas = await TexturePackerAtlas.load(
        atlasPath,
        fromStorage: true,
      );

      // 2. Bake into a CompositeAtlas
      final composite = await CompositeAtlas.bake([
        AtlasBakeRequest(baseAtlas),
      ]);

      // 3. Verify sequence identification (findSpritesByName)
      // The atlas contains: hex_lake_bottom_left_anim_1 through _5
      final animName = 'hex_lake_bottom_left_anim';
      final frames = composite.findSpritesByName(animName);

      expect(
        frames.length,
        equals(5),
        reason: 'Should find 5 frames for $animName',
      );

      // 4. Verify sorting (natural order _1 to _5)
      for (var i = 0; i < frames.length; i++) {
        final sprite = frames[i];
        final expectedName = '${animName}_${i + 1}';
        // Note: index is -1 in the source atlas names (they are separate regions),
        // but TexturePackerAtlas handles finding them by base name.
        expect(
          sprite.region.name,
          contains(expectedName),
          reason: 'Frame $i should be $expectedName',
        );
      }
    });

    test('Whitelist correctly filters lake assets', () async {
      final baseAtlas = await TexturePackerAtlas.load(
        atlasPath,
        fromStorage: true,
      );

      // Only include "top" lake tiles
      final composite = await CompositeAtlas.bake([
        AtlasBakeRequest(baseAtlas, whiteList: ['hex_lake_top']),
      ]);

      final allKeys = composite.allSpriteNames;

      // Should contain top pieces
      expect(allKeys.any((k) => k.contains('top_left')), isTrue);
      expect(allKeys.any((k) => k.contains('top_right')), isTrue);

      // Should NOT contain bottom pieces
      expect(allKeys.any((k) => k.contains('bottom_left')), isFalse);
      expect(allKeys.any((k) => k.contains('bottom_right')), isFalse);
    });

    test('Metadata is preserved for lake sprites (Fast Path)', () async {
      final baseAtlas = await TexturePackerAtlas.load(
        atlasPath,
        fromStorage: true,
      );

      final composite = await CompositeAtlas.bake([
        AtlasBakeRequest(baseAtlas),
      ]);

      // hex_lake_top_left_anim_1: offsets: 7, 97, 111, 128
      final sprite = composite.findSpriteByName('hex_lake_top_left_anim_1');
      expect(sprite, isNotNull);
      final tpSprite = sprite!;

      expect(tpSprite.region.offsetX, equals(7.0));
      expect(tpSprite.region.offsetY, equals(97.0));
      expect(tpSprite.region.originalWidth, equals(111.0));
      expect(tpSprite.region.originalHeight, equals(128.0));
    });

    test('Full recursive comparison of all lake sprites', () async {
      final baseAtlas = await TexturePackerAtlas.load(
        atlasPath,
        fromStorage: true,
      );

      final composite = await CompositeAtlas.bake([
        AtlasBakeRequest(baseAtlas),
      ]);

      // Loop through every sprite in the original atlas
      for (final original in baseAtlas.sprites) {
        final spriteName = original.region.name;
        final index = original.region.index;

        // Construct the expected lookup name (CompositeAtlas uses name#index for indexing)
        final lookupName = index != -1 ? '${spriteName}#$index' : spriteName;

        final bakedSprite = composite.findSpriteByName(lookupName);
        expect(
          bakedSprite,
          isNotNull,
          reason: 'Sprite $lookupName not found in baked atlas',
        );

        final tpBaked = bakedSprite!;

        // Comprehensive metadata comparison
        expect(
          tpBaked.region.offsetX,
          equals(original.region.offsetX),
          reason: 'offsetX mismatch for $lookupName',
        );
        expect(
          tpBaked.region.offsetY,
          equals(original.region.offsetY),
          reason: 'offsetY mismatch for $lookupName',
        );
        expect(
          tpBaked.region.originalWidth,
          equals(original.region.originalWidth),
          reason: 'originalWidth mismatch for $lookupName',
        );
        expect(
          tpBaked.region.originalHeight,
          equals(original.region.originalHeight),
          reason: 'originalHeight mismatch for $lookupName',
        );

        // Also verify trimmed source rect sizes match
        expect(
          tpBaked.src.width,
          equals(original.src.width),
          reason: 'srcWidth mismatch for $lookupName',
        );
        expect(
          tpBaked.src.height,
          equals(original.src.height),
          reason: 'srcHeight mismatch for $lookupName',
        );
      }
    });

    test('Full recursive comparison of all SpriteAnimations', () async {
      final baseAtlas = await TexturePackerAtlas.load(
        atlasPath,
        fromStorage: true,
      );

      final composite = await CompositeAtlas.bake([
        AtlasBakeRequest(baseAtlas),
      ]);

      // Identify all unique base names by stripping trailing indices
      final baseNames = baseAtlas.sprites
          .map((s) => s.region.name.replaceFirst(RegExp(r'(_?\d+)$'), ''))
          .toSet();

      for (final name in baseNames) {
        // Compare SpriteAnimations
        final originalAnim = baseAtlas.getAnimation(name);
        final bakedAnim = composite.getAnimation(name);

        expect(bakedAnim.frames.length, equals(originalAnim.frames.length),
            reason: 'Frame count mismatch for animation: $name');

        for (var i = 0; i < originalAnim.frames.length; i++) {
          final originalSprite = originalAnim.frames[i].sprite as TexturePackerSprite;
          final bakedSprite = bakedAnim.frames[i].sprite as TexturePackerSprite;

          expect(bakedSprite.region.name, equals(originalSprite.region.name),
              reason: 'Frame $i name mismatch for animation: $name');

          // Verify metadata preservation within the animation context
          expect(bakedSprite.region.offsetX, equals(originalSprite.region.offsetX),
              reason: 'Frame $i offsetX mismatch for animation: $name');
          expect(bakedSprite.region.offsetY, equals(originalSprite.region.offsetY),
              reason: 'Frame $i offsetY mismatch for animation: $name');
          expect(bakedSprite.region.originalWidth, equals(originalSprite.region.originalWidth),
              reason: 'Frame $i originalWidth mismatch for animation: $name');
          expect(bakedSprite.region.originalHeight, equals(originalSprite.region.originalHeight),
              reason: 'Frame $i originalHeight mismatch for animation: $name');
        }
      }
    });
  });
}
