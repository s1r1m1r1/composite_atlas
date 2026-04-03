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
    // lake_0 and lake_1 should be grouped to 'lake#0' and 'lake#1'
    expect(impl.spriteMap.keys, contains('lake#0'));
    expect(impl.spriteMap.keys, contains('lake#1'));
    
    // lake_left_0 and lake_left_1 should NOT be renamed to 'lake#2' etc.
    // They should keep their original identity!
    expect(impl.spriteMap.keys, contains('lake_left_0'));
    expect(impl.spriteMap.keys, contains('lake_left_1'));
  });
}

Future<ui.Image> createTestImage({int width = 1, int height = 1}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF00FF00), ui.BlendMode.src);
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
