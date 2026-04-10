import 'dart:async';
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/rendering.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:composite_atlas/composite_atlas.dart';

class ShaderOutlineDecorator extends Decorator
    implements AtlasDecorator, BakePadding {
  final ui.FragmentShader shader;
  final double thickness;
  final ui.Color color;
  final bool outlineOnly;
  AtlasContext? _context;

  ShaderOutlineDecorator(
    this.shader, {
    this.thickness = 2.0,
    this.color = const ui.Color(0xFF00FF00),
    this.outlineOnly = false,
  });

  @override
  void updateAtlasContext(AtlasContext context) {
    _context = context;
  }

  @override
  EdgeInsets get padding => EdgeInsets.all(thickness);

  @override
  void applyChain(void Function(ui.Canvas) draw, ui.Canvas canvas) {
    if (_context == null) {
      draw(canvas);
      return;
    }

    try {
      // 0: sampler2D uTexture (handled by setImageSampler)
      // 1: float uThickness
      shader.setFloat(0, thickness);
      // 2-5: vec4 uColor [r, g, b, a]
      shader.setFloat(1, color.red / 255.0);
      shader.setFloat(2, color.green / 255.0);
      shader.setFloat(3, color.blue / 255.0);
      shader.setFloat(4, color.alpha / 255.0);
      // 6-9: vec4 uSrcRect [left, top, width, height]
      shader.setFloat(5, _context!.srcRect.left);
      shader.setFloat(6, _context!.srcRect.top);
      shader.setFloat(7, _context!.srcRect.width);
      shader.setFloat(8, _context!.srcRect.height);
      // 10-11: vec2 uAtlasSize
      shader.setFloat(9, _context!.atlasSize.width);
      shader.setFloat(10, _context!.atlasSize.height);
      // 12: float uRotate
      shader.setFloat(11, _context!.rotated ? 1.0 : 0.0);
      // 13-16: vec4 uPadding [top, left, right, bottom]
      shader.setFloat(12, _context!.padding.top);
      shader.setFloat(13, _context!.padding.left);
      shader.setFloat(14, _context!.padding.right);
      shader.setFloat(15, _context!.padding.bottom);
      // 17: float uOutlineOnly
      shader.setFloat(16, outlineOnly ? 1.0 : 0.0);

      shader.setImageSampler(0, _context!.atlasImage);
    } catch (e) {
      debugPrint('[ShaderOutlineDecorator] Error: $e');
      draw(canvas);
      return;
    }

    final paint = ui.Paint()..shader = shader;
    final drawSize = ui.Size(
      _context!.localSize.width + _context!.padding.horizontal,
      _context!.localSize.height + _context!.padding.vertical,
    );
    canvas.drawRect(ui.Offset.zero & drawSize, paint);
  }
}

class SpritesheetBakeScreen extends StatefulWidget {
  const SpritesheetBakeScreen({super.key});

  @override
  State<SpritesheetBakeScreen> createState() => _SpritesheetBakeScreenState();
}

class _SpritesheetBakeScreenState extends State<SpritesheetBakeScreen> {
  bool _allowRotation = true;
  bool _trim = true;
  bool _useDecorator = true;
  ui.FragmentProgram? _program;
  SpritesheetBakeGame? _game;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await ui.FragmentProgram.fromAsset(
      'assets/shaders/outline.frag',
    );
    if (mounted) {
      setState(() {
        _program = program;
        _rebuildGame();
      });
    }
  }

  void _rebuildGame() {
    if (_program == null) return;
    _game = SpritesheetBakeGame(
      allowRotation: _allowRotation,
      trim: _trim,
      decorator: _useDecorator
          ? ShaderOutlineDecorator(_program!.fragmentShader(), thickness: 3.0)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('Spritesheet Bake Test'),
        backgroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.black,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildToggle('Rotate', _allowRotation, (v) {
                  setState(() {
                    _allowRotation = v;
                    _rebuildGame();
                  });
                }),
                _buildToggle('Trim', _trim, (v) {
                  setState(() {
                    _trim = v;
                    _rebuildGame();
                  });
                }),
                _buildToggle('Outline', _useDecorator, (v) {
                  setState(() {
                    _useDecorator = v;
                    _rebuildGame();
                  });
                }),
              ],
            ),
          ),
          Expanded(
            child: _game == null
                ? const Center(child: CircularProgressIndicator())
                : GameWidget(game: _game!),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blueAccent,
          ),
        ],
      ),
    );
  }
}

class SpritesheetBakeGame extends FlameGame {
  final bool allowRotation;
  final bool trim;
  final Decorator? decorator;

  SpritesheetBakeGame({
    required this.allowRotation,
    required this.trim,
    this.decorator,
  });

  CompositeAtlas? bakedAtlas;
  SpriteAnimationTicker? ticker;

  @override
  Future<void> onLoad() async {
    final image = await images.load('animations/boy-32x64-idle-walk.png');

    bakedAtlas = await CompositeAtlas.bake(
      [
        SpritesheetBakeRequest(
          image,
          name: 'boy',
          frameWidth: 32,
          frameHeight: 64,
          frameCount: 10,
          decorator: decorator,
        ),
      ],
      allowRotation: allowRotation,
      trim: trim,
      maxAtlasWidth: 256,
    );

    final anim = bakedAtlas!.getAnimation('boy', stepTime: 0.15);
    ticker = anim.createTicker();

    camera.viewfinder.anchor = Anchor.center;
  }

  @override
  void update(double dt) {
    super.update(dt);
    ticker?.update(dt);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (bakedAtlas == null) return;

    final paint = Paint()..filterQuality = ui.FilterQuality.none;

    // Draw the whole atlas for debugging
    canvas.save();
    canvas.translate(10, 150);
    canvas.drawImage(bakedAtlas!.image, ui.Offset.zero, paint);

    // Draw borders
    final borderPaint = Paint()
      ..color = Colors.red
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final sprite in bakedAtlas!.sprites) {
      final r = sprite.region;
      final w = r.rotate ? r.height : r.width;
      final h = r.rotate ? r.width : r.height;
      canvas.drawRect(ui.Rect.fromLTWH(r.left, r.top, w, h), borderPaint);
    }
    canvas.restore();

    // Draw the big animation
    if (ticker != null) {
      canvas.save();
      canvas.translate(size.x / 2, size.y / 2);
      canvas.scale(4.0);
      ticker!.getSprite().render(
        canvas,
        anchor: Anchor.center,
        overridePaint: paint,
      );
      canvas.restore();
    }

    final tp = TextPaint(
      style: const TextStyle(color: Colors.white, fontSize: 14),
    );
    tp.render(
      canvas,
      'Baked Atlas Size: ${bakedAtlas!.image.width}x${bakedAtlas!.image.height}',
      Vector2(10, 120),
    );
  }
}
