import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:composite_atlas/composite_atlas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Calibration test for all 9 [MarkerAnchor] directions.
///
/// Each direction has a pair of 32×32 images:
/// - `{dir}_test.png`  — reference: shows expected visual result
/// - `{dir}_sprite.png` — effect sprite to be anchored
///
/// A small 4×4 marker point is placed at the center of a 96×96 frame.
/// The 32×32 sprite is positioned using [MarkerAnchor] fractions via the
/// same formula as [AtlasMarkerExtension.computeEffectPosition].
///
/// Because marker.packedSize (4×4) ≠ effect.originalSize (32×32),
/// each anchor direction produces a visually distinct offset:
///
/// ```
/// effectPos = markerFlamePos + packedSize*fraction - effectSize*fraction
///           = markerFlamePos + (packedSize - effectSize) * fraction
/// ```
class MarkerAnchorTestScreen extends StatefulWidget {
  const MarkerAnchorTestScreen({super.key});

  @override
  State<MarkerAnchorTestScreen> createState() => _MarkerAnchorTestScreenState();
}

class _MarkerAnchorTestScreenState extends State<MarkerAnchorTestScreen> {
  static const _directions = [
    'top_left',
    'top_center',
    'top_right',
    'center_left',
    'center',
    'center_right',
    'bottom_left',
    'bottom_center',
    'bottom_right',
  ];

  static const _anchors = {
    'top_left': MarkerAnchor.topLeft,
    'top_center': MarkerAnchor.topCenter,
    'top_right': MarkerAnchor.topRight,
    'center_left': MarkerAnchor.centerLeft,
    'center': MarkerAnchor.center,
    'center_right': MarkerAnchor.centerRight,
    'bottom_left': MarkerAnchor.bottomLeft,
    'bottom_center': MarkerAnchor.bottomCenter,
    'bottom_right': MarkerAnchor.bottomRight,
  };

  int _currentIndex = 0;
  _AnchorTestGame? _game;
  Map<String, ui.Image> _loadedImages = {};
  bool _loading = true;
  bool _showTestOverlay = true;

  @override
  void initState() {
    super.initState();
    _loadAllImages();
  }

  Future<void> _loadAllImages() async {
    final images = <String, ui.Image>{};
    for (final dir in _directions) {
      for (final suffix in ['test', 'sprite']) {
        final key = '${dir}_$suffix';
        final assetPath = 'assets/images/marker_test/export/$key.png';
        try {
          final ByteData data = await rootBundle.load(assetPath);
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          final frame = await codec.getNextFrame();
          images[key] = frame.image;
        } catch (e) {
          debugPrint('Failed to load $assetPath: $e');
        }
      }
    }
    setState(() {
      _loadedImages = images;
      _loading = false;
    });
    _rebuildGame();
  }

  void _rebuildGame() {
    if (_loadedImages.isEmpty) return;
    final dir = _directions[_currentIndex];
    final anchor = _anchors[dir]!;
    final testImage = _loadedImages['${dir}_test'];
    final spriteImage = _loadedImages['${dir}_sprite'];

    if (testImage == null || spriteImage == null) return;

    final game = _AnchorTestGame(
      testImage: testImage,
      spriteImage: spriteImage,
      direction: dir,
      anchor: anchor,
      showTestOverlay: _showTestOverlay,
    );
    setState(() => _game = game);
  }

  void _next() {
    setState(() {
      _currentIndex = (_currentIndex + 1) % _directions.length;
    });
    _rebuildGame();
  }

  void _prev() {
    setState(() {
      _currentIndex =
          (_currentIndex - 1 + _directions.length) % _directions.length;
    });
    _rebuildGame();
  }

  void _toggleTestOverlay() {
    setState(() => _showTestOverlay = !_showTestOverlay);
    _rebuildGame();
  }

  @override
  Widget build(BuildContext context) {
    final dir = _directions[_currentIndex];
    final anchor = _anchors[dir]!;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('Marker Anchor Test'),
        backgroundColor: Colors.black,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            )
          : Column(
              children: [
                const SizedBox(height: 8),

                // Direction info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Direction: $dir',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Anchor: ${anchor.name} '
                          '(${anchor.fractionX}, ${anchor.fractionY})',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // Direction counter + controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${_currentIndex + 1} / ${_directions.length}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: _toggleTestOverlay,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _showTestOverlay
                                ? Colors.orangeAccent.withValues(alpha: 0.3)
                                : Colors.grey[800],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _showTestOverlay
                                ? 'Test overlay: ON'
                                : 'Test overlay: OFF',
                            style: TextStyle(
                              color: _showTestOverlay
                                  ? Colors.orangeAccent
                                  : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Legend
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _legendDot(Colors.yellow, 'Frame'),
                      const SizedBox(width: 12),
                      _legendDot(Colors.red, 'Marker (4×4)'),
                      const SizedBox(width: 12),
                      _legendDot(Colors.cyanAccent, 'Sprite bounds'),
                      const SizedBox(width: 12),
                      _legendDot(Colors.greenAccent, 'Anchor point'),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Flame game canvas
                Expanded(
                  child: Center(
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.5),
                        ),
                      ),
                      child: _game != null
                          ? GameWidget(game: _game!)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),

                // Navigation buttons
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(
                          Icons.skip_previous,
                          color: Colors.white,
                        ),
                        onPressed: _prev,
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        onPressed: _next,
                      ),
                    ],
                  ),
                ),

                // Image preview row
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ImagePreview(
                        label: 'Reference ($dir _test)',
                        image: _loadedImages['${dir}_test'],
                      ),
                      const SizedBox(width: 24),
                      _ImagePreview(
                        label: 'Sprite ($dir _sprite)',
                        image: _loadedImages['${dir}_sprite'],
                      ),
                    ],
                  ),
                ),

                // Anchor grid overview
                _AnchorGrid(
                  directions: _directions,
                  anchors: _anchors,
                  currentIndex: _currentIndex,
                  onSelect: (i) {
                    setState(() => _currentIndex = i);
                    _rebuildGame();
                  },
                ),

                const SizedBox(height: 12),
              ],
            ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }
}

/// Flame game that renders marker + sprite for anchor calibration.
///
/// Uses a SMALL marker point (4×4) at the center of a 96×96 reference
/// frame. The 32×32 sprite is positioned via the [MarkerAnchor] formula:
///
/// ```
/// markerAnchor = markerFlamePos + packedSize * fraction
/// effectAnchor = effectSize * fraction
/// effectPos    = markerAnchor - effectAnchor
///              = markerFlamePos + (packedSize - effectSize) * fraction
/// ```
///
/// With packedSize=(4,4) and effectSize=(32,32), each anchor produces
/// a distinct offset from the marker center.
class _AnchorTestGame extends FlameGame with PanDetector {
  final ui.Image testImage;
  final ui.Image spriteImage;
  final String direction;
  final MarkerAnchor anchor;
  final bool showTestOverlay;

  static const double _zoom = 3.0;
  static final Vector2 _refOrigin = Vector2(16, 16);
  static final Vector2 _frameSize = Vector2(96, 96);

  /// Small marker represents a real atlas marker point.
  static final Vector2 _markerPackedSize = Vector2(4, 4);

  /// The effect sprite is 32×32.
  static final Vector2 _effectSize = Vector2(32, 32);

  _AnchorTestGame({
    required this.testImage,
    required this.spriteImage,
    required this.direction,
    required this.anchor,
    required this.showTestOverlay,
  });

  @override
  void onPanUpdate(DragUpdateInfo info) {
    camera.viewfinder.position -= info.delta.global / camera.viewfinder.zoom;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();

    camera = CameraComponent.withFixedResolution(width: 400, height: 400);
    camera.viewfinder.zoom = _zoom;
    camera.viewfinder.anchor = Anchor.topLeft;

    final world = World();
    add(world);
    camera.world = world;

    // ── Reference frame border ──
    world.add(
      RectangleComponent(
        position: _refOrigin,
        size: _frameSize,
        paint: Paint()
          ..color = Colors.yellow
          ..style = PaintingStyle.stroke,
      ),
    );

    // ── Grid lines (8px) ──
    for (int i = 8; i < _frameSize.x.toInt(); i += 8) {
      world.add(
        RectangleComponent(
          position: _refOrigin + Vector2(i.toDouble(), 0),
          size: Vector2(0.25, _frameSize.y),
          paint: Paint()
            ..color = Colors.white10
            ..style = PaintingStyle.stroke,
        ),
      );
      world.add(
        RectangleComponent(
          position: _refOrigin + Vector2(0, i.toDouble()),
          size: Vector2(_frameSize.x, 0.25),
          paint: Paint()
            ..color = Colors.white10
            ..style = PaintingStyle.stroke,
        ),
      );
    }

    // ── Major grid lines (32px) ──
    for (int i = 32; i < _frameSize.x.toInt(); i += 32) {
      world.add(
        RectangleComponent(
          position: _refOrigin + Vector2(i.toDouble(), 0),
          size: Vector2(0.5, _frameSize.y),
          paint: Paint()
            ..color = Colors.white24
            ..style = PaintingStyle.stroke,
        ),
      );
      world.add(
        RectangleComponent(
          position: _refOrigin + Vector2(0, i.toDouble()),
          size: Vector2(_frameSize.x, 0.5),
          paint: Paint()
            ..color = Colors.white24
            ..style = PaintingStyle.stroke,
        ),
      );
    }

    // ── Virtual marker at center of frame ──
    // GDX: offsetX = (96-4)/2 = 46, offsetY = (96-4)/2 = 46
    // Flame: flameY = 96 - 46 - 4 = 46
    final markerGdxOffset = Vector2(
      (_frameSize.x - _markerPackedSize.x) / 2,
      (_frameSize.y - _markerPackedSize.y) / 2,
    );
    final markerFlameY = _frameSize.y - markerGdxOffset.y - _markerPackedSize.y;
    final markerFlamePos = Vector2(markerGdxOffset.x, markerFlameY);

    // ── Marker point (small red square 4×4) ──
    world.add(
      RectangleComponent(
        position: _refOrigin + markerFlamePos,
        size: _markerPackedSize.clone(),
        paint: Paint()..color = Colors.red.withValues(alpha: 0.8),
      ),
    );

    // ── Compute effect position using anchor formula ──
    // Same formula as computeEffectPosition:
    //   markerAnchor = markerFlamePos + packedSize * fraction
    //   effectAnchor = effectSize * fraction
    //   effectPos = markerAnchor - effectAnchor
    final markerAnchorPoint = Vector2(
      markerFlamePos.x + _markerPackedSize.x * anchor.fractionX,
      markerFlamePos.y + _markerPackedSize.y * anchor.fractionY,
    );
    final effectAnchorPoint = Vector2(
      _effectSize.x * anchor.fractionX,
      _effectSize.y * anchor.fractionY,
    );
    final effectPos = Vector2(
      markerAnchorPoint.x - effectAnchorPoint.x,
      markerAnchorPoint.y - effectAnchorPoint.y,
    );

    // ── Test reference overlay (optional, shows expected result) ──
    if (showTestOverlay) {
      world.add(
        SpriteComponent(
          sprite: Sprite(testImage),
          position: _refOrigin + effectPos,
          size: _effectSize,
          paint: Paint()..color = Colors.white.withValues(alpha: 0.35),
        ),
      );
    }

    // ── Effect sprite ──
    world.add(
      SpriteComponent(
        sprite: Sprite(spriteImage),
        position: _refOrigin + effectPos,
        size: _effectSize,
        paint: Paint()..color = Colors.white.withValues(alpha: 0.9),
      ),
    );

    // ── Effect bounds outline (cyan) ──
    world.add(
      RectangleComponent(
        position: _refOrigin + effectPos,
        size: _effectSize.clone(),
        paint: Paint()
          ..color = Colors.pinkAccent.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke,
      ),
    );

    // ── Anchor point crosshair (green) ──
    final anchorWorldPos = _refOrigin + markerAnchorPoint;
    final crosshair = PositionComponent(position: anchorWorldPos);
    crosshair.add(
      _CrossLine(
        from: Vector2(-2, 0),
        to: Vector2(2, 0),
        color: Colors.greenAccent,
      ),
    );
    crosshair.add(
      _CrossLine(
        from: Vector2(0, -2),
        to: Vector2(0, 2),
        color: Colors.greenAccent,
      ),
    );
    world.add(crosshair);

    // ── Offset info label ──
    final offsetX = (effectPos.x - markerFlamePos.x).toStringAsFixed(1);
    final offsetY = (effectPos.y - markerFlamePos.y).toStringAsFixed(1);
    world.add(
      TextComponent(
        text: '$direction\n${anchor.name}\noffset: ($offsetX, $offsetY)',
        position: Vector2(2, 2),
        textRenderer: TextPaint(
          style: const TextStyle(color: Colors.white70, fontSize: 2),
        ),
      ),
    );
  }
}

class _CrossLine extends Component {
  final Vector2 from;
  final Vector2 to;
  final Color color;

  _CrossLine({required this.from, required this.to, required this.color});

  @override
  void render(Canvas canvas) {
    canvas.drawLine(
      Offset(from.x, from.y),
      Offset(to.x, to.y),
      Paint()..color = color,
    );
  }
}

/// Preview of a loaded image.
class _ImagePreview extends StatelessWidget {
  final String label;
  final ui.Image? image;

  const _ImagePreview({required this.label, this.image});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            color: Colors.black26,
          ),
          child: image != null
              ? RawImage(image: image, fit: BoxFit.contain)
              : const Center(
                  child: Text(
                    'N/A',
                    style: TextStyle(color: Colors.red, fontSize: 10),
                  ),
                ),
        ),
      ],
    );
  }
}

/// 3×3 grid showing all anchor directions, highlighting the current one.
class _AnchorGrid extends StatelessWidget {
  final List<String> directions;
  final Map<String, MarkerAnchor> anchors;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _AnchorGrid({
    required this.directions,
    required this.anchors,
    required this.currentIndex,
    required this.onSelect,
  });

  // Grid layout order (row-major, matching visual 3×3):
  //  0: topLeft     1: topCenter    2: topRight
  //  3: centerLeft  4: center       5: centerRight
  //  6: bottomLeft  7: bottomCenter 8: bottomRight
  static const _gridOrder = [
    'top_left',
    'top_center',
    'top_right',
    'center_left',
    'center',
    'center_right',
    'bottom_left',
    'bottom_center',
    'bottom_right',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Anchor Grid (tap to select):',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          ...List.generate(3, (row) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (col) {
                final gridIdx = row * 3 + col;
                final dirName = _gridOrder[gridIdx];
                final dirIdx = directions.indexOf(dirName);
                final isSelected = dirIdx == currentIndex;

                return Padding(
                  padding: const EdgeInsets.all(2),
                  child: GestureDetector(
                    onTap: () => onSelect(dirIdx),
                    child: Container(
                      width: 80,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blueAccent
                            : Colors.grey[800],
                        borderRadius: BorderRadius.circular(4),
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 1.5)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        dirName,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white54,
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }
}
