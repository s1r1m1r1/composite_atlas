import 'dart:async';
import 'dart:ui' as ui;
import 'package:flame/cache.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/rendering.dart';
import 'package:flame/sprite.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:composite_atlas/composite_atlas.dart';

class AtlasRotationBakeScreen extends StatefulWidget {
  const AtlasRotationBakeScreen({super.key});

  @override
  State<AtlasRotationBakeScreen> createState() =>
      _AtlasRotationBakeScreenState();
}

class _AtlasRotationBakeScreenState extends State<AtlasRotationBakeScreen> {
  bool _allowRotation = false;
  bool _trim = true;
  bool _outline = true;

  CompositeAtlas? _bakedAtlas;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('Atlas Rotation Bake Test'),
        backgroundColor: Colors.black,
        actions: [
          _Toggle(
            label: 'Rotate',
            value: _allowRotation,
            onChanged: (v) => setState(() => _allowRotation = v),
          ),
          _Toggle(
            label: 'Trim',
            value: _trim,
            onChanged: (v) => setState(() => _trim = v),
          ),
          _Toggle(
            label: 'Outline',
            value: _outline,
            onChanged: (v) => setState(() => _outline = v),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: GameWidget(
              game: AtlasRotationBakeGame(
                allowRotation: _allowRotation,
                trim: _trim,
                outline: _outline,
                onAtlasBaked: (atlas) {
                  setState(() => _bakedAtlas = atlas);
                },
              ),
            ),
          ),
          if (_bakedAtlas != null)
            Container(
              width: 300,
              decoration: const BoxDecoration(
                color: Colors.black87,
                border: Border(left: BorderSide(color: Colors.white24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text(
                      'BAKED SPRITES INFO',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white24, height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _bakedAtlas!.sprites.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white10),
                      itemBuilder: (context, index) {
                        final sprite =
                            _bakedAtlas!.sprites.elementAt(index)
                                as TexturePackerSprite;
                        final r = sprite.region;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _InfoRow('Index', '${r.index}'),
                            _InfoRow(
                              'Bounds',
                              '${r.left.toInt()}, ${r.top.toInt()}, ${r.width.toInt()}x${r.height.toInt()}',
                            ),
                            _InfoRow(
                              'Offsets',
                              '${r.offsetX.toInt()}, ${r.offsetY.toInt()} [${r.originalWidth.toInt()}x${r.originalHeight.toInt()}]',
                            ),
                            _InfoRow('Rotate', '${r.rotate}'),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
            activeColor: Colors.greenAccent,
            // scale: 0.8,
          ),
        ],
      ),
    );
  }
}

class AtlasRotationBakeGame extends FlameGame {
  final bool allowRotation;
  final bool trim;
  final bool outline;
  final ValueChanged<CompositeAtlas>? onAtlasBaked;

  AtlasRotationBakeGame({
    required this.allowRotation,
    required this.trim,
    required this.outline,
    this.onAtlasBaked,
  });

  CompositeAtlas? bakedAtlas;
  SpriteAnimationTicker? ticker;
  final Vector2 pteroSize = Vector2(48, 32);

  @override
  Future<void> onLoad() async {
    // 1. Load the original rotated atlas
    final atlas = await TexturePackerAtlas.load('ptero_rotated.atlas');

    // 2. Prepare decorator
    Decorator? decorator;
    if (outline) {
      decorator = await PureOutlineDecorator(
        color: const Color(0xFF00FF00),
        thickness: 2.0,
      );
    }

    // 3. Bake!
    bakedAtlas = await CompositeAtlas.bake(
      [AtlasBakeRequest(atlas, keyPrefix: 'baked_', decorator: decorator)],
      allowRotation: allowRotation,
      trim: trim,
    );

    onAtlasBaked?.call(bakedAtlas!);

    // 4. Create animation from baked atlas
    // Note: ptero_anim has 4 frames.
    // In the original atlas they are ptero_anim#0 to ptero_anim#3.
    // Some frames (like #1 and #3) are rotated in the source atlas.
    final List<Sprite> frames = [];
    for (int i = 0; i < 4; i++) {
      final sprite = bakedAtlas!.findSpriteByName('baked_ptero_anim#$i');
      if (sprite != null) {
        frames.add(sprite);
      }
    }

    if (frames.isNotEmpty) {
      final anim = SpriteAnimation.spriteList(frames, stepTime: 0.15);
      ticker = anim.createTicker();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    ticker?.update(dt);
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    if (bakedAtlas == null) return;

    final paint = Paint()..filterQuality = ui.FilterQuality.none;

    // Draw the whole atlas for debugging (scale it down a bit)
    canvas.save();
    canvas.translate(10, 150);
    canvas.scale(2.0);
    canvas.drawImage(bakedAtlas!.image, ui.Offset.zero, paint);

    // Draw borders around sprites in the baked atlas
    final borderPaint = Paint()
      ..color = Colors.red
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (final sprite in bakedAtlas!.sprites) {
      canvas.drawRect(sprite.src, borderPaint);
    }
    canvas.restore();

    // Draw the animation to verify alignment
    if (ticker != null) {
      canvas.save();
      canvas.translate(size.x / 2, size.y / 2);
      canvas.scale(4.0);
      ticker!.getSprite().render(
        canvas,
        anchor: Anchor.center,
        overridePaint: paint,
      );

      // Draw a crosshair to verify anchor points
      final crossPaint = Paint()
        ..color = Colors.white54
        ..strokeWidth = 0.5;
      canvas.drawLine(
        const ui.Offset(-10, 0),
        const ui.Offset(10, 0),
        crossPaint,
      );
      canvas.drawLine(
        const ui.Offset(0, -10),
        const ui.Offset(0, 10),
        crossPaint,
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

    tp.render(
      canvas,
      'Sprites in Atlas: ${bakedAtlas!.sprites.length}',
      Vector2(10, 140),
    );
  }
}

/// Helper to reuse the PureOutlineDecorator logic from flame_visual_fx
/// If not available in the workspace, we would implement a simple color-rect decorator
class PureOutlineDecorator extends Decorator implements BakePadding {
  PureOutlineDecorator({
    this.color = const ui.Color.fromARGB(255, 253, 6, 138),
    this.thickness = 1.0,
    this.isActive = true,
  });

  ui.Color color;
  double thickness;
  bool isActive;

  @override
  EdgeInsets get padding =>
      isActive ? EdgeInsets.all(thickness) : EdgeInsets.zero;

  @override
  void apply(void Function(ui.Canvas) draw, ui.Canvas canvas) {
    if (!isActive) {
      draw(canvas);
      return;
    }

    // Capture content
    final recorder = ui.PictureRecorder();
    final tempCanvas = ui.Canvas(recorder);
    draw(tempCanvas);
    final picture = recorder.endRecording();

    try {
      final outlinePaint = ui.Paint()
        ..colorFilter = ui.ColorFilter.mode(color, ui.BlendMode.srcIn);

      canvas.saveLayer(null, outlinePaint);

      // 4-direction outline
      final List<ui.Offset> offsets = [
        ui.Offset(0, -thickness),
        ui.Offset(0, thickness),
        ui.Offset(-thickness, 0),
        ui.Offset(thickness, 0),
      ];

      for (final offset in offsets) {
        canvas.save();
        canvas.translate(offset.dx, offset.dy);
        canvas.drawPicture(picture);
        canvas.restore();
      }

      canvas.restore();
      canvas.drawPicture(picture);
    } finally {
      picture.dispose();
    }
  }
}
