import 'dart:ui' as ui;

import 'package:flame/sprite.dart';
import 'package:flame/components.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:flutter/material.dart';

/// Simple screen to test war_servant atlas animations without a full character.
///
/// Lets you step through frames manually to inspect offset consistency
/// and diagnose visual issues like jittering.
class WarServantTestScreen extends StatefulWidget {
  const WarServantTestScreen({super.key});

  @override
  State<WarServantTestScreen> createState() => _WarServantTestScreenState();
}

class _WarServantTestScreenState extends State<WarServantTestScreen> {
  TexturePackerAtlas? _atlas;
  List<TexturePackerSprite> _currentSprites = [];
  String _selectedAnim = 'warservant_export_aim';
  int _currentFrame = 0;

  static const _animNames = [
    'warservant_export_aim',
    'warservant_export_wait',
    'warservant_export_run',
    'warservant_export_atk',
    'warservant_export_reload',
    'warservant_export_ready',
  ];

  @override
  void initState() {
    super.initState();
    _loadAtlas();
  }

  Future<void> _loadAtlas() async {
    final atlas = await TexturePackerAtlas.load(
      'assets/images/war_servant.atlas',
      useOriginalSize: true,
    );

    setState(() {
      _atlas = atlas;
      _currentSprites = atlas.findSpritesByName(_selectedAnim).cast();
      _currentFrame = 0;
    });
  }

  void _nextFrame() {
    if (_currentSprites.isEmpty) return;
    setState(() {
      _currentFrame = (_currentFrame + 1) % _currentSprites.length;
    });
  }

  void _prevFrame() {
    if (_currentSprites.isEmpty) return;
    setState(() {
      _currentFrame =
          (_currentFrame - 1 + _currentSprites.length) % _currentSprites.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('War Servant Animation Tester'),
        backgroundColor: Colors.black,
      ),
      body: _atlas == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Animation selector
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: DropdownButton<String>(
                      value: _selectedAnim,
                      dropdownColor: Colors.black,
                      style: const TextStyle(color: Colors.white),
                      items: _animNames.map((name) {
                        return DropdownMenuItem(
                          value: name,
                          child: Text(
                            name.replaceAll('warservant_export_', ''),
                            style: const TextStyle(color: Colors.white),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedAnim = value!;
                          _currentSprites = _atlas!
                              .findSpritesByName(value)
                              .cast();
                          _currentFrame = 0;
                        });
                      },
                    ),
                  ),
                  // Animation display
                  Center(
                    child: _currentSprites.isEmpty
                        ? const Text(
                            'No frames found',
                            style: TextStyle(color: Colors.white),
                          )
                        : SizedBox.square(
                            dimension: 400,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    border: BoxBorder.all(
                                      color: Colors.green,
                                      width: 2.0,
                                    ),
                                  ),
                                ),
                                CustomPaint(
                                  painter: _SpritePainter(
                                    sprite: _currentSprites[_currentFrame],
                                  ),
                                  child: const SizedBox(
                                    width: 400,
                                    height: 400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  // Frame controls
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.skip_previous,
                            color: Colors.white,
                          ),
                          onPressed: _prevFrame,
                          tooltip: 'Previous frame',
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Frame ${_currentFrame + 1}/${_currentSprites.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.skip_next,
                            color: Colors.white,
                          ),
                          onPressed: _nextFrame,
                          tooltip: 'Next frame',
                        ),
                      ],
                    ),
                  ),
                  // Current frame info
                  _FrameInfo(sprite: _currentSprites[_currentFrame]),
                  // All frames offset summary
                  if (_currentSprites.length >= 2)
                    _OffsetSummary(sprites: _currentSprites),
                ],
              ),
            ),
    );
  }
}

/// Paints a single sprite centered on the canvas at ~80% scale,
/// with a red border showing the actual rendered bounds including offset.
/// The border is centered on the sprite's visual center so the offset
/// shift is visible relative to the center point.
class _SpritePainter extends CustomPainter {
  final TexturePackerSprite sprite;

  _SpritePainter({required this.sprite});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = ui.FilterQuality.none;

    // Scale factor: render sprite at ~80% of available width
    final spriteSize = sprite.srcSize;
    final scale = (size.width / spriteSize.x * 0.8).clamp(0.3, 3.0);

    final r = sprite.region;
    final w = r.rotate ? r.height : r.width;
    final h = r.rotate ? r.width : r.height;

    // Use Flame-convention offset (Y-down from top-left of original bounding box).
    // sprite.offset converts GDX offsetY (from bottom) to Flame Y-down.
    final flameOffset = sprite.offset;

    // The sprite is rendered at canvas center with Anchor.center.
    // The packed sprite's top-left is at:
    //   screenCenter - originalSize/2 + flameOffset
    final packedTopLeftX =
        size.width / 2 - r.originalWidth * scale / 2 + flameOffset.x * scale;
    final packedTopLeftY =
        size.height / 2 - r.originalHeight * scale / 2 + flameOffset.y * scale;

    // Visual center of the packed sprite
    final visualCenterX = packedTopLeftX + w * scale / 2;
    final visualCenterY = packedTopLeftY + h * scale / 2;

    // The border is centered on the visual center, with scaled dimensions
    final borderX = visualCenterX - w * scale / 2;
    final borderY = visualCenterY - h * scale / 2;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    sprite.render(canvas, anchor: Anchor.center, overridePaint: paint);
    canvas.restore();

    // Draw sprite bounds centered on the visual center (including offset)
    final p = Paint()
      ..color = const Color.fromARGB(255, 255, 0, 0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRect(
      // ui.Rect.fromLTWH(borderX, borderY, w * scale, h * scale),
      ui.Rect.fromCenter(
        center: Offset(borderX, borderY),
        width: w * scale,
        height: h * scale,
      ),
      p,
    );

    // Draw a small cross at the visual center for reference
    final centerPaint = Paint()
      ..color = const Color.fromARGB(255, 0, 255, 0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
      ui.Offset(visualCenterX - 5, visualCenterY),
      ui.Offset(visualCenterX + 5, visualCenterY),
      centerPaint,
    );
    canvas.drawLine(
      ui.Offset(visualCenterX, visualCenterY - 5),
      ui.Offset(visualCenterX, visualCenterY + 5),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpritePainter oldDelegate) => true;
}

/// Displays metadata for the current frame.
class _FrameInfo extends StatelessWidget {
  final TexturePackerSprite sprite;

  const _FrameInfo({required this.sprite});

  @override
  Widget build(BuildContext context) {
    final r = sprite.region;
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Frame:',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          Text(
            'Name: ${r.name}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Index: ${r.index}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Bounds: ${r.left},${r.top},${r.width},${r.height}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Offset: ${r.offsetX}, ${r.offsetY}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Original Size: ${r.originalWidth}x${r.originalHeight}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Packed Size: ${r.width}x${r.height}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          if (r.rotate)
            const Text(
              'Rotated: true',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

/// Displays offset variance summary across all frames of the animation.
class _OffsetSummary extends StatelessWidget {
  final List<TexturePackerSprite> sprites;

  const _OffsetSummary({required this.sprites});

  @override
  Widget build(BuildContext context) {
    final offsets = sprites
        .map((s) => (s.region.offsetX, s.region.offsetY))
        .toList();
    final minX = offsets.map((o) => o.$1).reduce((a, b) => a < b ? a : b);
    final maxX = offsets.map((o) => o.$1).reduce((a, b) => a > b ? a : b);
    final minY = offsets.map((o) => o.$2).reduce((a, b) => a < b ? a : b);
    final maxY = offsets.map((o) => o.$2).reduce((a, b) => a > b ? a : b);

    final hasVariation = (maxX - minX) > 0 || (maxY - minY) > 0;

    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Offset Variance (all frames):',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          Text(
            'Offset X range: $minX - $maxX (delta: ${maxX - minX})',
            style: TextStyle(
              color: hasVariation ? Colors.red : Colors.greenAccent,
              fontSize: 12,
            ),
          ),
          Text(
            'Offset Y range: $minY - $maxY (delta: ${maxY - minY})',
            style: TextStyle(
              color: hasVariation ? Colors.red : Colors.greenAccent,
              fontSize: 12,
            ),
          ),
          if (hasVariation)
            const Text(
              '⚠ Offset variation detected — this causes frame-to-frame jitter!',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
