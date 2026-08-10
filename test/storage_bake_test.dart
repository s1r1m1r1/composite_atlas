import 'package:flutter_test/flutter_test.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:composite_atlas/composite_atlas.dart';

void main() {
  // Required for loading images and using Canvas in tests
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CompositeAtlas Storage Integration', () {
    const electroAtlasPath = 'example/assets/images/electro_bot.atlas';
    const pteroAtlasPath = 'example/assets/images/ptero_rotated.atlas';

    test('Baking electro_bot.atlas from storage', () async {
      // 1. Load from storage
      final baseAtlas = await TexturePackerAtlas.load(
        electroAtlasPath,
        fromStorage: true,
      );

      // 2. Bake into a CompositeAtlas
      final composite = await CompositeAtlas.bake([
        AtlasBakeRequest(baseAtlas),
      ]);

      // 3. Verify sprites are found
      // Using # index notation as CompositeAtlas converts animation frames to indexed names
      final sprite = composite.findSpriteByName('character_atk.left#3');
      expect(sprite, isNotNull, reason: 'Should find character_atk.left#3');

      final sequence = composite.findSpritesByName('character_atk.left');
      expect(sequence, isNotEmpty);
      expect(sequence.length, greaterThan(1));
    });

    test('Rotation support: ptero_rotated.atlas', () async {
      // ptero_rotated.atlas has rotation:true for indices 2 and 3
      final baseAtlas = await TexturePackerAtlas.load(
        pteroAtlasPath,
        fromStorage: true,
      );

      final composite = await CompositeAtlas.bake([
        AtlasBakeRequest(baseAtlas),
      ]);

      // Sprite index 2 is rotated in original atlas
      final rotatedSprite = composite.findSpriteByName('ptero_anim#2');
      expect(rotatedSprite, isNotNull);

      // In CompositeAtlas, when we bake, we usually "un-rotate" the source content
      // into the new atlas for simpler rendering, OR keep the rotation.
      // Let's verify what the current implementation does.

      // If the baking process is correct, the resulting sprite should have correct dimensions.
      // Original ptero_anim index 2: bounds: 2,2, 16,32; offsets: 16,0, 48,32; rotate: true
      // Visual size should be 16x32 (or 32x16 if rotated).

      expect(
        rotatedSprite!.srcSize.x,
        equals(48.0),
        reason: 'Original width should be 48',
      );
      expect(
        rotatedSprite.srcSize.y,
        equals(32.0),
        reason: 'Original height should be 32',
      );
    });

    test('Preserves metadata (offsets) during storage baking', () async {
      final baseAtlas = await TexturePackerAtlas.load(
        electroAtlasPath,
        fromStorage: true,
      );

      final composite = await CompositeAtlas.bake([
        AtlasBakeRequest(baseAtlas),
      ]);

      // character_atk.left index 3: offsets: 4,54, 111,128; bounds: 41,94, 62,33
      final sprite = composite.findSpriteByName('character_atk.left#3');
      expect(sprite, isA<TexturePackerSprite>());
      final tpSprite = sprite as TexturePackerSprite;

      expect(tpSprite.region.offsetX, equals(4.0));
      expect(tpSprite.region.offsetY, equals(54.0));
      expect(tpSprite.region.originalWidth, equals(111.0));
      expect(tpSprite.region.originalHeight, equals(128.0));
    });

    test('Multi-atlas baking from storage with prefixes', () async {
      final atlas1 = await TexturePackerAtlas.load(
        electroAtlasPath,
        fromStorage: true,
      );
      final atlas2 = await TexturePackerAtlas.load(
        pteroAtlasPath,
        fromStorage: true,
      );

      final composite = await CompositeAtlas.bake([
        AtlasBakeRequest(atlas1, keyPrefix: 'bot_'),
        AtlasBakeRequest(atlas2, keyPrefix: 'dino_'),
      ]);

      // Check prefixes
      expect(composite.findSpriteByName('bot_character_atk.left#1'), isNotNull);
      expect(composite.findSpriteByName('dino_ptero_anim#0'), isNotNull);

      // Check all keys
      final allNames = composite.allSpriteNames;
      expect(allNames.any((n) => n.startsWith('bot_')), isTrue);
      expect(allNames.any((n) => n.startsWith('dino_')), isTrue);
    });
  });
}
