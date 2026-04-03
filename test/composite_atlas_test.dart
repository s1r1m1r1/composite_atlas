import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:flame/rendering.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
// Internal imports for manual setup
import 'package:flame_texturepacker/src/model/page.dart';
import 'package:flame_texturepacker/src/model/region.dart';

import 'package:composite_atlas/composite_atlas.dart';
import 'package:composite_atlas/src/composite_atlas_impl.dart';
import 'package:composite_atlas/src/internal_models.dart';
import 'package:composite_atlas/src/atlas_decorator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RegionFilterKey', () {
    test('Equality and HashCode', () async {
      final image = await createTestImage(width: 10, height: 10);
      final src = const ui.Rect.fromLTWH(0, 0, 10, 10);

      final key1 = RegionFilterKey(image, src, null, null, 0, 1, 0, 0, 10, 10);

      final key1Copy = RegionFilterKey(
        image,
        src,
        null,
        null,
        0,
        1,
        0,
        0,
        10,
        10,
      );

      final keyWithDifferentIndex = RegionFilterKey(
        image,
        src,
        null,
        null,
        1,
        1,
        0,
        0,
        10,
        10,
      );

      // Verify basic equality
      expect(key1, equals(key1Copy));
      expect(key1.hashCode, equals(key1Copy.hashCode));

      // Optimization: Without a decorator, indices should NOT affect equality
      // (to allow grouping of identical frames)
      expect(key1, equals(keyWithDifferentIndex));

      final keyWithDecorator1 = RegionFilterKey(
        image,
        src,
        null,
        MockDecorator(),
        0,
        1,
        0,
        0,
        10,
        10,
      );
      final keyWithDecorator2 = RegionFilterKey(
        image,
        src,
        null,
        MockDecorator(),
        1,
        1,
        0,
        0,
        10,
        10,
      );

      // With a decorator, indices MUST affect equality
      expect(keyWithDecorator1, isNot(equals(keyWithDecorator2)));
    });
  });

  group('CompositeAtlas.fromAtlas', () {
    test('Wraps standard atlas correctly', () async {
      final image = await createTestImage();
      final sprite = createTPSprite(image, 'test_sprite', 0);
      final atlas = TexturePackerAtlas([sprite]);

      final composite = CompositeAtlas.fromAtlas(atlas);
      expect(composite.image, equals(image));
      expect(composite.findSpriteByName('test_sprite#0'), isNotNull);
    });
  });

  group('CompositeAtlas.bake', () {
    test('ImageBakeRequest', () async {
      final image = await createTestImage(width: 32, height: 32);
      final atlas = await CompositeAtlas.bake([
        ImageBakeRequest(image, name: 'raw_image'),
      ]);

      expect(
        atlas.allSpriteNames,
        contains('raw_image'),
      );
      expect(atlas.findSpriteByName('raw_image'), isNotNull);
    });

    test('SpriteBakeRequest with prefix', () async {
      final image = await createTestImage(width: 16, height: 16);
      final sprite = Sprite(image);

      final atlas = await CompositeAtlas.bake([
        SpriteBakeRequest(sprite, name: 'my_sprite', keyPrefix: 'ui_'),
      ]);

      expect(
        atlas.allSpriteNames,
        contains('ui_my_sprite'),
      );
      final found = atlas.findSpriteByName('ui_my_sprite');
      expect(found, isNotNull);
    });

    test('AtlasBakeRequest with whitelist', () async {
      final image = await createTestImage();
      final s1 = createTPSprite(image, 'keep_me', 0);
      final s2 = createTPSprite(image, 'drop_me', 0);
      final baseAtlas = TexturePackerAtlas([s1, s2]);

      final atlas = await CompositeAtlas.bake([
        AtlasBakeRequest(baseAtlas, whiteList: ['keep_']),
      ]);

      expect(
        atlas.allSpriteNames,
        contains('keep_me#0'),
      );
      expect(atlas.allSpriteNames, isNot(contains('drop_me#0')));
    });

    test('AtlasBakeRequest with multiple whitelist patterns', () async {
      final image = await createTestImage();
      final s1 = createTPSprite(image, 'apple', 0);
      final s2 = createTPSprite(image, 'banana', 0);
      final s3 = createTPSprite(image, 'cherry', 0);
      final baseAtlas = TexturePackerAtlas([s1, s2, s3]);

      final atlas = await CompositeAtlas.bake([
        AtlasBakeRequest(baseAtlas, whiteList: ['app', 'cherr']),
      ]);

      final keys = atlas.allSpriteNames;
      expect(keys, contains('apple#0'));
      expect(keys, contains('cherry#0'));
      expect(keys, isNot(contains('banana#0')));
    });

    test('Fast Path Metadata Preservation (e.g. hex_lake)', () async {
      final image = await createTestImage(width: 1024, height: 64);

      // Mirroring hex_lake_top_left_anim_1 from hex_lake.atlas
      // bounds: 461, 8, 45, 26
      // offsets: 7, 97, 111, 128
      final lakeTopLeft = createDetailedTPSprite(
        image: image,
        name: 'hex_lake_top_left_anim',
        index: 1,
        offsetX: 7,
        offsetY: 97,
        originalWidth: 111,
        originalHeight: 128,
        srcLeft: 461,
        srcTop: 8,
        srcWidth: 45,
        srcHeight: 26,
      );

      final baseAtlas = TexturePackerAtlas([lakeTopLeft]);

      // Bake it (Fast Path - no decorator)
      final baked = await CompositeAtlas.bake([AtlasBakeRequest(baseAtlas)]);

      final found = baked.findSpriteByName('hex_lake_top_left_anim#1');
      expect(found, isA<TexturePackerSprite>());
      final tpFound = found as TexturePackerSprite;

      // Assert precise metadata preservation
      expect(tpFound.region.offsetX, equals(7));
      expect(tpFound.region.offsetY, equals(97));
      expect(tpFound.region.originalWidth, equals(111));
      expect(tpFound.region.originalHeight, equals(128));

      // Source size should match trimmed size (45x26)
      expect(tpFound.src.width, equals(45));
      expect(tpFound.src.height, equals(26));
    });

    test('Grouping logic - identical bakes use same region', () async {
      final image = await createTestImage();
      final s1 = Sprite(image);

      // Two requests for the same image/sprite with no decorators should be grouped
      final atlas = await CompositeAtlas.bake([
        SpriteBakeRequest(s1, name: 'copy1'),
        SpriteBakeRequest(s1, name: 'copy2'),
      ]);

      final sprite1 = atlas.findSpriteByName('copy1') as TexturePackerSprite;
      final sprite2 = atlas.findSpriteByName('copy2') as TexturePackerSprite;

      // They should point to exactly the same rectangle in the baked atlas
      expect(sprite1.region.left, equals(sprite2.region.left));
      expect(sprite1.region.top, equals(sprite2.region.top));
    });

    test('Decorator invocation and context', () async {
      final image = await createTestImage();
      final sprite = Sprite(image);
      final decorator = MockDecorator();

      await CompositeAtlas.bake([
        SpriteBakeRequest(sprite, name: 'test', decorator: decorator),
      ]);

      expect(decorator.wasCalled, isTrue);
      expect(decorator.context, isNotNull);
      expect(decorator.context?.itemIndex, equals(0));
    });
  });

  group('Sprite Lookup', () {
    test('findSpritesByName handles indexed sequences', () async {
      final image = await createTestImage();

      final realAtlas = await CompositeAtlas.bake([
        SpriteBakeRequest(Sprite(image), name: 'anim_0'),
        SpriteBakeRequest(Sprite(image), name: 'anim_1'),
      ]);

      final frames = realAtlas.findSpritesByName('anim');
      expect(frames.length, equals(2));
    });

    test('findSpritesByName sorting', () async {
      final image = await createTestImage();
      final realAtlas = await CompositeAtlas.bake([
        SpriteBakeRequest(Sprite(image), name: 'step_10'),
        SpriteBakeRequest(Sprite(image), name: 'step_2'),
      ]);

      final frames = realAtlas.findSpritesByName('step');
      expect(frames.length, equals(2));
      // step_2 should come before step_10 if sorting works
      expect(frames[0].region.name, contains('2'));
      expect(frames[1].region.name, contains('10'));
    });
  });
}

/// Helper to create a dummy ui.Image for testing
Future<ui.Image> createTestImage({int width = 1, int height = 1}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF00FF00), ui.BlendMode.src);
  return recorder.endRecording().toImage(width, height);
}

/// Helper to create a TexturePackerSprite manually
TexturePackerSprite createTPSprite(ui.Image image, String name, int index) {
  final page = Page()
    ..texture = image
    ..width = image.width
    ..height = image.height;

  final region = Region(
    page: page,
    name: name,
    left: 0,
    top: 0,
    width: image.width.toDouble(),
    height: image.height.toDouble(),
    offsetX: 0,
    offsetY: 0,
    originalWidth: image.width.toDouble(),
    originalHeight: image.height.toDouble(),
    degrees: 0,
    rotate: false,
    index: index,
  );

  return TexturePackerSprite(region);
}

/// More detailed helper for metadata testing
TexturePackerSprite createDetailedTPSprite({
  required ui.Image image,
  required String name,
  required int index,
  required double offsetX,
  required double offsetY,
  required double originalWidth,
  required double originalHeight,
  required double srcLeft,
  required double srcTop,
  required double srcWidth,
  required double srcHeight,
}) {
  final page = Page()
    ..texture = image
    ..width = image.width
    ..height = image.height;

  final region = Region(
    page: page,
    name: name,
    left: srcLeft,
    top: srcTop,
    width: srcWidth,
    height: srcHeight,
    offsetX: offsetX,
    offsetY: offsetY,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
    degrees: 0,
    rotate: false,
    index: index,
  );

  return TexturePackerSprite(region);
}

class MockDecorator extends Decorator implements AtlasDecorator {
  bool wasCalled = false;
  AtlasContext? context;

  @override
  void updateAtlasContext(AtlasContext context) {
    this.context = context;
  }

  @override
  void applyChain(void Function(ui.Canvas) next, ui.Canvas canvas) {
    wasCalled = true;
    next(canvas);
  }
}
