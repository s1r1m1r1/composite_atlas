import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
// Direct imports for internal models since they are not exported by the main library
import 'package:flame_texturepacker/src/model/page.dart';
import 'package:flame_texturepacker/src/model/region.dart';

import 'package:composite_atlas/composite_atlas.dart';
import 'package:composite_atlas/src/composite_atlas_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Reproduction: Aliased visuals with different offsets', () async {
    final image = await createTestImage(width: 100, height: 100);

    // Create two sprites pointing to SAME area but with DIFFERENT offsets (aliases)
    final s1 = createTPSprite(
      image,
      'hex_grass',
      -1,
      src: const ui.Rect.fromLTWH(0, 0, 10, 10),
      offset: const ui.Offset(0, 0),
    );
    final s2 = createTPSprite(
      image,
      'hex_bottom_dirt',
      -1,
      src: const ui.Rect.fromLTWH(0, 0, 10, 10),
      offset: const ui.Offset(0, 15),
    );

    final baseAtlas = TexturePackerAtlas([s1, s2]);

    final atlas = await CompositeAtlas.bake([
      AtlasBakeRequest(baseAtlas, whiteList: ['hex_grass', 'hex_bottom_dirt']),
    ]);

    final spriteGrass =
        atlas.findSpriteByName('hex_grass') as TexturePackerSprite;
    final spriteDirt =
        atlas.findSpriteByName('hex_bottom_dirt') as TexturePackerSprite;

    // They MUST correctly preserve their original offsets
    expect(
      spriteGrass.region.offsetY,
      equals(0),
      reason: 'hex_grass should have 0 offset',
    );
    expect(
      spriteDirt.region.offsetY,
      equals(15),
      reason: 'hex_bottom_dirt should have 15 offset',
    );
  });

  test('Reproduction: Prefix matching and animation grouping', () async {
    final image = await createTestImage(width: 10, height: 10);

    // Create two sprites that look like animation frames
    final s1 = createTPSprite(image, 'hex_grass', 0);
    final s2 = createTPSprite(image, 'hex_grass', 1);

    final baseAtlas = TexturePackerAtlas([s1, s2]);

    final atlas = await CompositeAtlas.bake([
      AtlasBakeRequest(baseAtlas, whiteList: ['hex_grass']),
    ]);

    final impl = atlas as CompositeAtlasImpl;

    expect(impl.spriteMap.keys, contains('hex_grass#0'));
    expect(impl.spriteMap.keys, contains('hex_grass#1'));
  });

  test(
    'Reproduction: Prefix matching with underscores (no index field)',
    () async {
      final image = await createTestImage(width: 10, height: 10);

      final s1 = createTPSprite(image, 'hex_grass_0', -1);
      final s2 = createTPSprite(image, 'hex_grass_1', -1);

      final baseAtlas = TexturePackerAtlas([s1, s2]);

      final atlas = await CompositeAtlas.bake([
        AtlasBakeRequest(baseAtlas, whiteList: ['hex_grass']),
      ]);

      final impl = atlas as CompositeAtlasImpl;

      expect(impl.spriteMap.keys, contains('hex_grass#0'));
      expect(impl.spriteMap.keys, contains('hex_grass#1'));
    },
  );

  test('Reproduction: findSpritesByName with prefixes', () async {
    final image = await createTestImage(width: 10, height: 10);
    final s1 = createTPSprite(image, 'lake_0', -1);
    final s2 = createTPSprite(image, 'lake_1', -1);

    final baseAtlas = TexturePackerAtlas([s1, s2]);

    final atlas = await CompositeAtlas.bake([
      AtlasBakeRequest(baseAtlas, whiteList: ['lake'], keyPrefix: 'env_'),
    ]);

    // Keys are now 'env_lake#0' and 'env_lake#1'
    expect(
      (atlas as CompositeAtlasImpl).spriteMap.keys,
      contains('env_lake#0'),
    );

    // findSpritesByName('lake') MUST find them even with the 'env_' prefix
    final sprites = atlas.findSpritesByName('lake');
    expect(
      sprites,
      isNotEmpty,
      reason: 'Should find sprites even with env_ prefix',
    );
    expect(sprites.length, equals(2));

    // Also check singular lookup
    final single = atlas.findSpriteByName('lake#0');
    expect(single, isNotNull, reason: 'Should find specific frame by suffix');

    final byBase = atlas.findSpriteByName('lake');
    expect(byBase, isNotNull, reason: 'Should find by base name (matching env_lake#0)');
  });

  test('Reproduction: broad whitelist doesn\'t steal sub-sequences', () async {
    final image = await createTestImage(width: 10, height: 10);
    // These should belong to 'lake' sequence
    final s1 = createTPSprite(image, 'lake_0', -1);
    final s2 = createTPSprite(image, 'lake_1', -1);
    // These should NOT belong to 'lake' sequence even if whitelisted as 'lake'
    final s3 = createTPSprite(image, 'lake_left_0', -1);
    final s4 = createTPSprite(image, 'lake_left_1', -1);
    
    final baseAtlas = TexturePackerAtlas([s1, s2, s3, s4]);

    final atlas = await CompositeAtlas.bake([
      AtlasBakeRequest(
        baseAtlas,
        whiteList: ['lake'],
      ),
    ]);

    final impl = atlas as CompositeAtlasImpl;
    // lake_left_0 and lake_left_1 should NOT be renamed to 'lake#2' etc.
    // They should keep their original identity!
    expect(impl.spriteMap.keys, contains('lake_left_0'));
    expect(impl.spriteMap.keys, contains('lake_left_1'));
  });

  test('Reproduction: Rotation correctly updates atlas size and rendering', () async {
    // Create a horizontal sprite (50x10)
    final image = await createTestImage(width: 50, height: 10);
    final sprite = Sprite(image);

    // Force rotation by setting maxAtlasWidth narrower than the visual width (e.g., 20)
    final atlas = await CompositeAtlas.bake(
      [SpriteBakeRequest(sprite, name: 'hrz')],
      maxAtlasWidth: 20,
      allowRotation: true,
    );

    final bakedSprite = atlas.findSpriteByName('hrz') as TexturePackerSprite;
    
    // 1. Verify rotation was indeed applied by the packer
    expect(bakedSprite.region.rotate, isTrue, reason: 'Should have rotated 50x10 to fit in 20 width');

    // 2. Verify atlas image dimensions
    // Rotated 50x10 becomes 10x50 on the sheet.
    // If the calculation was bugged, it would have used 50 for width.
    expect(atlas.image.width, lessThan(30), reason: 'Atlas width should be small (around 10) for rotated horizontal sprite');
    expect(atlas.image.height, greaterThan(40), reason: 'Atlas height should be large (around 50) for rotated horizontal sprite');

    // 3. Verify visual size is PRESERVED (50x10)
    expect(bakedSprite.originalSize.x, equals(50));
    expect(bakedSprite.originalSize.y, equals(10));
  });

  test('Reproduction: Trimming raw sprites removes whitespace and preserves offsets', () async {
    // Create a 50x50 image with a 10x10 red block at (20, 20)
    final image = await createTestImageWithRect(
      width: 50,
      height: 50,
      rect: const ui.Rect.fromLTWH(20, 20, 10, 10),
      color: const ui.Color(0xFFFF0000),
    );
    final sprite = Sprite(image);

    final atlas = await CompositeAtlas.bake(
      [SpriteBakeRequest(sprite, name: 'trimmed')],
      trim: true,
      maxAtlasWidth: 100, // Large enough
    );

    final bakedSprite = atlas.findSpriteByName('trimmed') as TexturePackerSprite;
    
    // 1. Verify atlas image is small (around 10x10)
    // We expect it to be 10x10 (the red block) plus padding
    expect(atlas.image.width, lessThan(20), reason: 'Atlas width should be small after trimming');
    expect(atlas.image.height, lessThan(20), reason: 'Atlas height should be small after trimming');

    // 2. Verify offsets are correct
    // The 10x10 block was at (20, 20) in the 50x50 frame.
    expect(bakedSprite.region.offsetX, closeTo(20, 1), reason: 'Offset X should be ~20');
    expect(bakedSprite.region.offsetY, closeTo(20, 1), reason: 'Offset Y should be ~20');

    // 3. Verify original size is preserved
    expect(bakedSprite.originalSize.x, equals(50));
    expect(bakedSprite.originalSize.y, equals(50));
  });
}

Future<ui.Image> createTestImage({int width = 1, int height = 1}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF00FF00), ui.BlendMode.src);
  return recorder.endRecording().toImage(width, height);
}

Future<ui.Image> createTestImageWithRect({
  required int width,
  required int height,
  required ui.Rect rect,
  required ui.Color color,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(rect, ui.Paint()..color = color);
  return recorder.endRecording().toImage(width, height);
}

TexturePackerSprite createTPSprite(
  ui.Image image,
  String name,
  int index, {
  ui.Rect? src,
  ui.Offset? offset,
}) {
  final page = Page()
    ..texture = image
    ..width = image.width
    ..height = image.height;

  final region = Region(
    page: page,
    name: name,
    left: src?.left ?? 0,
    top: src?.top ?? 0,
    width: src?.width ?? image.width.toDouble(),
    height: src?.height ?? image.height.toDouble(),
    offsetX: offset?.dx ?? 0,
    offsetY: offset?.dy ?? 0,
    originalWidth: (src?.width ?? image.width.toDouble()) + (offset?.dx ?? 0),
    originalHeight:
        (src?.height ?? image.height.toDouble()) + (offset?.dy ?? 0),
    degrees: 0,
    rotate: false,
    index: index,
  );

  return TexturePackerSprite(region);
}
