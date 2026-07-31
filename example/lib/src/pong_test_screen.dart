import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:flame_texturepacker/src/model/region.dart';
import 'package:composite_atlas/composite_atlas.dart';
import 'package:flutter/material.dart';

/// Screen to test the pong animation — an object moving from one
/// corner to another in strict order, making offset shifts easy to see.
///
/// Supports three view modes:
/// 1. **Original PNGs** — individual frames loaded directly
/// 2. **GDX Atlas** — pre-packed by TexturePacker desktop tool
/// 3. **Baked Atlas** — baked at runtime by composite_atlas
///
/// Includes a detailed offset comparison table to diagnose Y-axis inversion.
class PongTestScreen extends StatefulWidget {
  const PongTestScreen({super.key});

  @override
  State<PongTestScreen> createState() => _PongTestScreenState();
}

enum _ViewMode { original, gdxAtlas, bakedAtlas }

class _PongTestScreenState extends State<PongTestScreen> {
  List<Sprite> _originalSprites = [];
  TexturePackerAtlas? _gdxAtlas;
  CompositeAtlas? _bakedAtlas;
  int _currentFrame = 0;
  _ViewMode _viewMode = _ViewMode.original;
  bool _baking = false;
  String _bakeStatus = '';
  bool _showComparison = false;

  static const _frameCount = 30;

  @override
  void initState() {
    super.initState();
    _loadOriginalSprites();
    _loadGdxAtlas();
  }

  Future<void> _loadOriginalSprites() async {
    final sprites = <Sprite>[];
    for (int i = 1; i <= _frameCount; i++) {
      final name = 'warservant_export_pong_${i.toString().padLeft(2, '0')}';
      try {
        final sprite = await Sprite.load('/pong/$name.png');
        sprites.add(sprite);
      } catch (_) {
        // Frame not found, skip
      }
    }

    setState(() {
      _originalSprites = sprites;
      _currentFrame = 0;
    });
  }

  Future<void> _loadGdxAtlas() async {
    try {
      final atlas = await TexturePackerAtlas.load(
        'assets/images/gdx_original_pong.atlas',
        useOriginalSize: true,
      );
      setState(() {
        _gdxAtlas = atlas;
      });
    } catch (e) {
      debugPrint('Failed to load GDX atlas: $e');
    }
  }

  Future<void> _bakeAtlas() async {
    setState(() {
      _baking = true;
      _bakeStatus = 'Baking atlas...';
    });

    try {
      final requests = <SpriteBakeRequest>[];
      for (int i = 0; i < _originalSprites.length; i++) {
        requests.add(
          SpriteBakeRequest(
            _originalSprites[i],
            name: 'pong_$i',
            keyPrefix: 'baked_',
          ),
        );
      }

      final bakedAtlas = await CompositeAtlas.bake(
        requests,
        maxAtlasWidth: 2046.0,
        allowRotation: false,
        forceSquare: false,
        trim: true,
      );

      setState(() {
        _bakedAtlas = bakedAtlas;
        _baking = false;
        _bakeStatus =
            'Baked: ${bakedAtlas.image.width}x${bakedAtlas.image.height}';
      });
    } catch (e) {
      setState(() {
        _baking = false;
        _bakeStatus = 'Bake failed: $e';
      });
    }
  }

  void _nextFrame() {
    if (_originalSprites.isEmpty) return;
    setState(() {
      _currentFrame = (_currentFrame + 1) % _originalSprites.length;
    });
  }

  void _prevFrame() {
    if (_originalSprites.isEmpty) return;
    setState(() {
      _currentFrame =
          (_currentFrame - 1 + _originalSprites.length) %
          _originalSprites.length;
    });
  }

  /// Gets the GDX atlas sprite for the current frame.
  TexturePackerSprite? _currentGdxSprite() {
    if (_gdxAtlas == null) return null;
    // GDX atlas names: warservant_export_pong with index 1..30
    // The current frame is 0-based, GDX index is 1-based
    final gdxIndex = _currentFrame + 1;
    final sprites = _gdxAtlas!
        .findSpritesByName('warservant_export_pong')
        .cast<TexturePackerSprite>();
    try {
      return sprites.firstWhere((s) => s.region.index == gdxIndex);
    } catch (_) {
      return sprites.isNotEmpty
          ? sprites[_currentFrame % sprites.length]
          : null;
    }
  }

  /// Gets the baked atlas sprite for the current frame.
  TexturePackerSprite? _currentBakedSprite() {
    if (_bakedAtlas == null) return null;
    final name = 'baked_pong_$_currentFrame';
    final sprites = _bakedAtlas!.findSpritesByName(name);
    return sprites.isNotEmpty ? sprites.first as TexturePackerSprite : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('Pong Animation Tester'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(
              _showComparison ? Icons.visibility : Icons.table_chart,
              color: Colors.amber,
            ),
            onPressed: () => setState(() => _showComparison = !_showComparison),
            tooltip: _showComparison ? 'Hide comparison' : 'Show comparison',
          ),
        ],
      ),
      body: _originalSprites.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Bake button
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _baking ? null : _bakeAtlas,
                          icon: _baking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white,
                                ),
                          label: Text(
                            _baking ? 'Baking...' : 'Bake Atlas',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_bakeStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Text(
                        _bakeStatus,
                        style: TextStyle(
                          color: _bakeStatus.startsWith('Bake failed')
                              ? Colors.red
                              : Colors.greenAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  // View mode selector
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ViewModeButton(
                          label: 'Original PNG',
                          icon: Icons.image,
                          selected: _viewMode == _ViewMode.original,
                          color: Colors.blue,
                          onPressed: () =>
                              setState(() => _viewMode = _ViewMode.original),
                        ),
                        const SizedBox(width: 8),
                        _ViewModeButton(
                          label: 'GDX Atlas',
                          icon: Icons.texture,
                          selected: _viewMode == _ViewMode.gdxAtlas,
                          color: Colors.orange,
                          enabled: _gdxAtlas != null,
                          onPressed: () =>
                              setState(() => _viewMode = _ViewMode.gdxAtlas),
                        ),
                        const SizedBox(width: 8),
                        _ViewModeButton(
                          label: 'Baked Atlas',
                          icon: Icons.auto_awesome,
                          selected: _viewMode == _ViewMode.bakedAtlas,
                          color: Colors.green,
                          enabled: _bakedAtlas != null,
                          onPressed: () =>
                              setState(() => _viewMode = _ViewMode.bakedAtlas),
                        ),
                      ],
                    ),
                  ),
                  // Animation display
                  Center(
                    child: SizedBox(
                      width: 400,
                      height: 400,
                      child: _buildSpriteView(),
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
                            'Frame ${_currentFrame + 1}/${_originalSprites.length}',
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
                  // Frame info
                  _FrameInfo(
                    originalSprite: _originalSprites[_currentFrame],
                    gdxSprite: _currentGdxSprite(),
                    bakedSprite: _currentBakedSprite(),
                    viewMode: _viewMode,
                  ),
                  // Comparison table
                  if (_showComparison)
                    _OffsetComparisonTable(
                      originalSprites: _originalSprites,
                      gdxAtlas: _gdxAtlas,
                      bakedAtlas: _bakedAtlas,
                      currentFrame: _currentFrame,
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSpriteView() {
    switch (_viewMode) {
      case _ViewMode.original:
        return _SpriteComponentView(
          sprite: _originalSprites[_currentFrame],
          label: 'Original PNG',
          labelColor: Colors.blue,
        );
      case _ViewMode.gdxAtlas:
        final gdxSprite = _currentGdxSprite();
        if (gdxSprite == null) {
          return const Center(
            child: Text(
              'GDX atlas not loaded',
              style: TextStyle(color: Colors.red),
            ),
          );
        }
        return _SpriteComponentView(
          sprite: gdxSprite,
          label: 'GDX TexturePacker',
          labelColor: Colors.orange,
        );
      case _ViewMode.bakedAtlas:
        final bakedSprite = _currentBakedSprite();
        if (bakedSprite == null) {
          return const Center(
            child: Text(
              'Bake the atlas first',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return _SpriteComponentView(
          sprite: bakedSprite,
          label: 'composite_atlas baked',
          labelColor: Colors.green,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// View mode button
// ---------------------------------------------------------------------------

class _ViewModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final Color color;
  final VoidCallback onPressed;

  const _ViewModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 16, color: selected ? Colors.white : color),
      label: Text(
        label,
        style: TextStyle(
          color: enabled
              ? (selected ? Colors.white : color)
              : Colors.grey.shade600,
          fontSize: 11,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: selected
            ? color.withValues(alpha: 0.7)
            : Colors.black26,
        side: BorderSide(color: enabled ? color : Colors.grey.shade800),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sprite rendering with Flame GameWidget
// ---------------------------------------------------------------------------

class _SpriteComponentView extends StatelessWidget {
  final Sprite sprite;
  final String label;
  final Color labelColor;

  const _SpriteComponentView({
    required this.sprite,
    required this.label,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return GameWidget(
      game: _SpriteRenderGame(sprite: sprite),
      overlayBuilderMap: {
        'border': (context, game) => _SpriteBorderOverlay(
          sprite: sprite,
          label: label,
          labelColor: labelColor,
        ),
      },
      initialActiveOverlays: const ['border'],
    );
  }
}

class _SpriteRenderGame extends FlameGame {
  final Sprite sprite;

  _SpriteRenderGame({required this.sprite});

  @override
  Future<void> onLoad() async {
    final component = SpriteComponent(
      sprite: sprite,
      size: sprite.srcSize,
      scale: Vector2.all(0.8),
    );
    world.add(component);
  }
}

// ---------------------------------------------------------------------------
// Border overlay
// ---------------------------------------------------------------------------

class _SpriteBorderOverlay extends StatelessWidget {
  final Sprite sprite;
  final String label;
  final Color labelColor;

  const _SpriteBorderOverlay({
    required this.sprite,
    required this.label,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BorderPainter(
        sprite: sprite,
        label: label,
        labelColor: labelColor,
      ),
      child: const SizedBox(width: 400, height: 400),
    );
  }
}

/// Paints a red border around the sprite's visual bounds and a green cross
/// at the visual center (accounting for offset).
///
/// The offset is read from the sprite's `offset` getter which returns the
/// Flame-convention offset (Y-down from top-left of original bounding box).
class _BorderPainter extends CustomPainter {
  final Sprite sprite;
  final String label;
  final Color labelColor;

  _BorderPainter({
    required this.sprite,
    required this.label,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final spriteSize = sprite.srcSize;
    final scale = (size.width / spriteSize.x * 0.8).clamp(0.3, 3.0);

    // Get Flame-convention offset (Y-down from top-left)
    Vector2 flameOffset = Vector2.zero();
    double packedW = spriteSize.x;
    double packedH = spriteSize.y;
    if (sprite is TexturePackerSprite) {
      final tp = sprite as TexturePackerSprite;
      flameOffset = tp.offset; // Already Flame convention after fix
      packedW = tp.region.width;
      packedH = tp.region.height;
    }

    // The SpriteComponent uses Anchor.topLeft at position (0,0) in the game.
    // The FlameGame camera centers the viewport, so (0,0) is at screen center.
    // The packed sprite's top-left is at screenCenter + flameOffset * scale.
    final screenCenterX = size.width / 2;
    final screenCenterY = size.height / 2;

    // Packed sprite top-left in screen coords
    final topLeftX = screenCenterX + flameOffset.x * scale;
    final topLeftY = screenCenterY + flameOffset.y * scale;

    // Draw red border around packed sprite bounds
    final borderPaint = Paint()
      ..color = const Color.fromARGB(255, 255, 0, 0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(
      ui.Rect.fromLTWH(topLeftX, topLeftY, packedW * scale, packedH * scale),
      borderPaint,
    );

    // Draw green cross at center of packed sprite
    final centerX = topLeftX + packedW * scale / 2;
    final centerY = topLeftY + packedH * scale / 2;
    final centerPaint = Paint()
      ..color = const Color.fromARGB(255, 0, 255, 0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
      ui.Offset(centerX - 5, centerY),
      ui.Offset(centerX + 5, centerY),
      centerPaint,
    );
    canvas.drawLine(
      ui.Offset(centerX, centerY - 5),
      ui.Offset(centerX, centerY + 5),
      centerPaint,
    );

    // Draw label
    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: label,
            style: TextStyle(color: labelColor, fontSize: 11),
          ),
          if (sprite is TexturePackerSprite) ...[
            const TextSpan(
              text: '\nRegion offset:',
              style: TextStyle(color: Colors.grey, fontSize: 9),
            ),
            TextSpan(
              text:
                  ' (${(sprite as TexturePackerSprite).region.offsetX.toStringAsFixed(1)}, '
                  '${(sprite as TexturePackerSprite).region.offsetY.toStringAsFixed(1)})',
              style: const TextStyle(color: Colors.orange, fontSize: 9),
            ),
            const TextSpan(
              text: '\nFlame offset:',
              style: TextStyle(color: Colors.grey, fontSize: 9),
            ),
            TextSpan(
              text:
                  ' (${flameOffset.x.toStringAsFixed(1)}, '
                  '${flameOffset.y.toStringAsFixed(1)})',
              style: const TextStyle(color: Colors.green, fontSize: 9),
            ),
          ],
        ],
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: 200);
    textPainter.paint(canvas, const ui.Offset(8, 8));
  }

  @override
  bool shouldRepaint(covariant _BorderPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Frame info panel
// ---------------------------------------------------------------------------

class _FrameInfo extends StatelessWidget {
  final Sprite originalSprite;
  final TexturePackerSprite? gdxSprite;
  final TexturePackerSprite? bakedSprite;
  final _ViewMode viewMode;

  const _FrameInfo({
    required this.originalSprite,
    this.gdxSprite,
    this.bakedSprite,
    required this.viewMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current view info
          if (viewMode == _ViewMode.original) ...[
            _infoRow('View:', 'Original PNG', Colors.blue),
            _infoRow(
              'Size:',
              '${originalSprite.srcSize.x.toInt()}x${originalSprite.srcSize.y.toInt()}',
              Colors.grey,
            ),
          ],
          if (viewMode == _ViewMode.gdxAtlas && gdxSprite != null) ...[
            _infoRow('View:', 'GDX TexturePacker Atlas', Colors.orange),
            _regionInfo(gdxSprite!.region, 'GDX'),
          ],
          if (viewMode == _ViewMode.bakedAtlas && bakedSprite != null) ...[
            _infoRow('View:', 'composite_atlas Baked', Colors.green),
            _regionInfo(bakedSprite!.region, 'Baked'),
          ],
          const Divider(color: Colors.white24, height: 12),
          // GDX vs Baked comparison
          if (gdxSprite != null && bakedSprite != null) ...[
            const Text(
              'Offset Comparison:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                _tableHeader(['', 'GDX Atlas', 'Baked Atlas', 'Match']),
                _tableRow(
                  'offsetX',
                  gdxSprite!.region.offsetX.toStringAsFixed(1),
                  bakedSprite!.region.offsetX.toStringAsFixed(1),
                  gdxSprite!.region.offsetX == bakedSprite!.region.offsetX,
                ),
                _tableRow(
                  'offsetY',
                  gdxSprite!.region.offsetY.toStringAsFixed(1),
                  bakedSprite!.region.offsetY.toStringAsFixed(1),
                  gdxSprite!.region.offsetY == bakedSprite!.region.offsetY,
                ),
                _tableRow(
                  'width',
                  gdxSprite!.region.width.toStringAsFixed(1),
                  bakedSprite!.region.width.toStringAsFixed(1),
                  gdxSprite!.region.width == bakedSprite!.region.width,
                ),
                _tableRow(
                  'height',
                  gdxSprite!.region.height.toStringAsFixed(1),
                  bakedSprite!.region.height.toStringAsFixed(1),
                  gdxSprite!.region.height == bakedSprite!.region.height,
                ),
                _tableRow(
                  'origW',
                  gdxSprite!.region.originalWidth.toStringAsFixed(1),
                  bakedSprite!.region.originalWidth.toStringAsFixed(1),
                  gdxSprite!.region.originalWidth ==
                      bakedSprite!.region.originalWidth,
                ),
                _tableRow(
                  'origH',
                  gdxSprite!.region.originalHeight.toStringAsFixed(1),
                  bakedSprite!.region.originalHeight.toStringAsFixed(1),
                  gdxSprite!.region.originalHeight ==
                      bakedSprite!.region.originalHeight,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(color: valueColor, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _regionInfo(Region r, String tag) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow(
          'Bounds:',
          '${r.left.toInt()},${r.top.toInt()},'
              '${r.width.toInt()}x${r.height.toInt()}',
          Colors.grey,
        ),
        _infoRow(
          'offsets:',
          '${r.offsetX.toInt()},${r.offsetY.toInt()},'
              '${r.originalWidth.toInt()}x${r.originalHeight.toInt()}',
          Colors.orange,
        ),
        _infoRow(
          'Flame offset:',
          '(${OffsetMath.gdxToFlameOffsetY(r.offsetY, r.originalHeight, r.height).toStringAsFixed(1)})',
          Colors.green,
        ),
        if (r.rotate)
          const Text(
            'Rotated: true',
            style: TextStyle(color: Colors.orange, fontSize: 11),
          ),
      ],
    );
  }

  TableRow _tableHeader(List<String> cells) {
    return TableRow(
      children: cells
          .map(
            (c) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                c,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  TableRow _tableRow(String label, String gdx, String baked, bool match) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            gdx,
            style: const TextStyle(color: Colors.orange, fontSize: 10),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            baked,
            style: const TextStyle(color: Colors.green, fontSize: 10),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            match ? '✓' : '✗',
            style: TextStyle(
              color: match ? Colors.greenAccent : Colors.red,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Offset comparison table (all frames)
// ---------------------------------------------------------------------------

class _OffsetComparisonTable extends StatelessWidget {
  final List<Sprite> originalSprites;
  final TexturePackerAtlas? gdxAtlas;
  final CompositeAtlas? bakedAtlas;
  final int currentFrame;

  const _OffsetComparisonTable({
    required this.originalSprites,
    this.gdxAtlas,
    this.bakedAtlas,
    required this.currentFrame,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      color: Colors.black38,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Offset Comparison — All Frames',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'GDX offsets are from-bottom (Y-up). Flame offsets are from-top (Y-down).',
            style: TextStyle(color: Colors.grey, fontSize: 10),
          ),
          const Text(
            'Flame_Y = originalHeight - packedHeight - GDX_Y',
            style: TextStyle(color: Colors.amber, fontSize: 10),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final rows = <TableRow>[];

    // Header
    rows.add(
      TableRow(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white24)),
        ),
        children: [
          _cell('#', Colors.white, bold: true),
          _cell('GDX OX', Colors.orange, bold: true),
          _cell('GDX OY', Colors.orange, bold: true),
          _cell('GDX W', Colors.orange, bold: true),
          _cell('GDX H', Colors.orange, bold: true),
          _cell('Baked OX', Colors.green, bold: true),
          _cell('Baked OY', Colors.green, bold: true),
          _cell('Baked W', Colors.green, bold: true),
          _cell('Baked H', Colors.green, bold: true),
          _cell('OX?', Colors.white, bold: true),
          _cell('OY?', Colors.white, bold: true),
        ],
      ),
    );

    for (int i = 0; i < originalSprites.length; i++) {
      final isCurrent = i == currentFrame;

      // GDX sprite (1-indexed)
      TexturePackerSprite? gdxSpr;
      if (gdxAtlas != null) {
        final gdxIdx = i + 1;
        final found = gdxAtlas!
            .findSpritesByName('warservant_export_pong')
            .cast<TexturePackerSprite>();
        try {
          gdxSpr = found.firstWhere((s) => s.region.index == gdxIdx);
        } catch (_) {
          gdxSpr = null;
        }
      }

      // Baked sprite
      TexturePackerSprite? bakedSpr;
      if (bakedAtlas != null) {
        final found = bakedAtlas!.findSpritesByName('baked_pong_$i');
        bakedSpr = found.isNotEmpty ? found.first as TexturePackerSprite : null;
      }

      final gdxR = gdxSpr?.region;
      final bakedR = bakedSpr?.region;

      final oxMatch = gdxR != null && bakedR != null
          ? gdxR.offsetX == bakedR.offsetX
          : null;
      final oyMatch = gdxR != null && bakedR != null
          ? gdxR.offsetY == bakedR.offsetY
          : null;

      final bgColor = isCurrent
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.transparent;

      rows.add(
        TableRow(
          decoration: BoxDecoration(color: bgColor),
          children: [
            _cell('${i + 1}', isCurrent ? Colors.white : Colors.white70),
            _cell(
              gdxR != null ? gdxR.offsetX.toStringAsFixed(0) : '-',
              Colors.orange,
            ),
            _cell(
              gdxR != null ? gdxR.offsetY.toStringAsFixed(0) : '-',
              Colors.orange,
            ),
            _cell(
              gdxR != null ? gdxR.width.toStringAsFixed(0) : '-',
              Colors.orange,
            ),
            _cell(
              gdxR != null ? gdxR.height.toStringAsFixed(0) : '-',
              Colors.orange,
            ),
            _cell(
              bakedR != null ? bakedR.offsetX.toStringAsFixed(0) : '-',
              Colors.green,
            ),
            _cell(
              bakedR != null ? bakedR.offsetY.toStringAsFixed(0) : '-',
              Colors.green,
            ),
            _cell(
              bakedR != null ? bakedR.width.toStringAsFixed(0) : '-',
              Colors.green,
            ),
            _cell(
              bakedR != null ? bakedR.height.toStringAsFixed(0) : '-',
              Colors.green,
            ),
            _cell(
              oxMatch == null ? '-' : (oxMatch ? '✓' : '✗'),
              oxMatch == null
                  ? Colors.grey
                  : (oxMatch ? Colors.greenAccent : Colors.red),
            ),
            _cell(
              oyMatch == null ? '-' : (oyMatch ? '✓' : '✗'),
              oyMatch == null
                  ? Colors.grey
                  : (oyMatch ? Colors.greenAccent : Colors.red),
            ),
          ],
        ),
      );
    }

    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      columnWidths: const {0: FixedColumnWidth(28)},
      children: rows,
    );
  }

  Widget _cell(String text, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OffsetMath helper
// ---------------------------------------------------------------------------

/// Helper methods for GDX-to-Flame offset conversion.
///
/// GDX atlas format defines offsetY from the **bottom** of the original
/// image (Y-up coordinate system). Flame uses Y-down (top-left origin).
///
/// Conversion formula:
///   flameOffsetY = originalHeight - packedHeight - gdxOffsetY
class OffsetMath {
  /// Converts a GDX-style offsetY to Flame-compatible offsetY.
  static double gdxToFlameOffsetY(
    double gdxOffsetY,
    double originalHeight,
    double packedHeight,
  ) => originalHeight - packedHeight - gdxOffsetY;

  /// Converts a Flame-compatible offsetY back to GDX-style.
  static double flameToGdxOffsetY(
    double flameOffsetY,
    double originalHeight,
    double packedHeight,
  ) => originalHeight - packedHeight - flameOffsetY;
}
