import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:composite_atlas/composite_atlas.dart';
import 'package:flutter/material.dart';

/// Calibration screen for atlas markers using Flame engine.
///
/// Uses a consistent reference frame origin for ALL positioning.
/// Marker and effect sprites are rendered via [SpriteComponent] which
/// handles [TexturePackerSprite] offset math internally.
class MarkerCalibrationScreen extends StatefulWidget {
  const MarkerCalibrationScreen({super.key});

  @override
  State<MarkerCalibrationScreen> createState() =>
      _MarkerCalibrationScreenState();
}

class _MarkerCalibrationScreenState extends State<MarkerCalibrationScreen> {
  TexturePackerAtlas? _atlas;
  AtlasMarker? _marker;
  List<TexturePackerSprite> _effectFrames = [];
  int _currentFrame = 0;
  bool _alignCenter = false;
  _MarkerCalibrationGame? _game;

  @override
  void initState() {
    super.initState();
    _loadAtlas();
  }

  Future<void> _loadAtlas() async {
    final atlas = await TexturePackerAtlas.load(
      'assets/images/effects.atlas',
      useOriginalSize: true,
    );

    final markers = atlas.getMarkers();
    final flashFrames = atlas.findSpritesByName('gun_flash');
    final debugFrame = atlas.findSpriteByName('warservant_atk_point');

    setState(() {
      _atlas = atlas;
      _marker = markers.isNotEmpty ? markers.first : null;
      _effectFrames = flashFrames.cast<TexturePackerSprite>();
    });

    if (_marker != null && flashFrames.isNotEmpty && debugFrame != null) {
      final game = _MarkerCalibrationGame(
        marker: _marker!,
        markerSprite: debugFrame,
        effectFrames: flashFrames.cast<TexturePackerSprite>(),
        alignCenter: _alignCenter,
      );
      setState(() => _game = game);
    }
  }

  void _nextFrame() {
    if (_effectFrames.isEmpty) return;
    setState(() {
      _currentFrame = (_currentFrame + 1) % _effectFrames.length;
    });
    _game?.setEffectFrame(_currentFrame);
  }

  void _prevFrame() {
    if (_effectFrames.isEmpty) return;
    setState(() {
      _currentFrame =
          (_currentFrame - 1 + _effectFrames.length) % _effectFrames.length;
    });
    _game?.setEffectFrame(_currentFrame);
  }

  void _setAlignCenter(bool v) {
    setState(() => _alignCenter = v);
    _game?.setAlignCenter(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('Marker Calibration'),
        backgroundColor: Colors.black,
      ),
      body: _atlas == null || _marker == null || _game == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            )
          : Column(
              children: [
                const SizedBox(height: 8),

                // Align mode toggle
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Anchor:',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('topLeft'),
                        selected: !_alignCenter,
                        selectedColor: Colors.blueAccent,
                        onSelected: (v) => _setAlignCenter(false),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('center'),
                        selected: _alignCenter,
                        selectedColor: Colors.blueAccent,
                        onSelected: (v) => _setAlignCenter(true),
                      ),
                    ],
                  ),
                ),

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
                      child: GameWidget(game: _game!),
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
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Frame ${_currentFrame + 1}/${_effectFrames.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        onPressed: _nextFrame,
                      ),
                    ],
                  ),
                ),

                // Info panels
                _MarkerInfo(marker: _marker!),
                if (_effectFrames.isNotEmpty)
                  _EffectFrameInfo(
                    sprite: _effectFrames[_currentFrame],
                    marker: _marker!,
                    alignCenter: _alignCenter,
                  ),
                _AllMarkersInfo(atlas: _atlas!),

                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

/// Flame game that renders marker + effect sprites.
///
/// ALL positioning uses a single [_refOrigin] to ensure consistency.
/// The marker SpriteComponent is sized to [marker.referenceSize] and
/// placed at [_refOrigin]. Flame's [TexturePackerSprite.render()]
/// internally positions the packed pixels at the correct offset.
/// The effect sprite is placed at a computed offset from [_refOrigin]
/// using the same formula as [GunFlashBundle.computePosition].
class _MarkerCalibrationGame extends FlameGame with PanDetector {
  final AtlasMarker marker;
  final TexturePackerSprite markerSprite;
  final List<TexturePackerSprite> effectFrames;
  bool alignCenter;

  late SpriteComponent _markerComponent;
  late SpriteComponent _effectComponent;
  late PositionComponent _crosshairComponent;
  late TextComponent _modeLabel;

  static const double _zoom = 3.0;

  /// Single consistent origin for the reference frame.
  /// Marker component, border, crosshair, and effect all use this.
  static final Vector2 _refOrigin = Vector2(50, 50);

  int _currentFrame = 0;

  _MarkerCalibrationGame({
    required this.marker,
    required this.markerSprite,
    required this.effectFrames,
    required this.alignCenter,
  });

  @override
  void onPanUpdate(DragUpdateInfo info) {
    // Move camera in opposite direction of drag (natural scroll behavior)
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
        size: marker.referenceSize,
        paint: Paint()
          ..color = Colors.yellow
          ..style = PaintingStyle.stroke,
      ),
    );

    // ── Grid lines (64px) ──
    for (int i = 64; i < marker.referenceSize.x.toInt(); i += 64) {
      world.add(
        RectangleComponent(
          position: _refOrigin + Vector2(i.toDouble(), 0),
          size: Vector2(1, marker.referenceSize.y),
          paint: Paint()
            ..color = Colors.white12
            ..style = PaintingStyle.stroke,
        ),
      );
      world.add(
        RectangleComponent(
          position: _refOrigin + Vector2(0, i.toDouble()),
          size: Vector2(marker.referenceSize.x, 1),
          paint: Paint()
            ..color = Colors.white12
            ..style = PaintingStyle.stroke,
        ),
      );
    }

    // ── Marker sprite ──
    // The SpriteComponent is at _refOrigin (top-left of reference frame).
    // TexturePackerSprite.render() handles the internal offset automatically,
    // placing packed pixels at the correct position within the frame.
    // markerFlamePos is the Flame Y-down position of the packed content.
    final markerFlamePos = _refOrigin + marker.flameOffset;
    _markerComponent =
        SpriteComponent(
          sprite: markerSprite,
          position: _refOrigin,
          size: marker.referenceSize,
        )..add(
          RectangleComponent(
            size: marker.referenceSize,
            paint: Paint()..color = Colors.green.withAlpha(60),
          ),
        );
    world.add(_markerComponent);

    // ── Marker crosshair at Flame-correct packed center ──
    final mcx = markerFlamePos.x + marker.packedSize.x / 2;
    final mcy = markerFlamePos.y + marker.packedSize.y / 2;
    _crosshairComponent = PositionComponent(position: Vector2(mcx, mcy));
    _crosshairComponent.add(
      _CrossLine(from: Vector2(-4, 0), to: Vector2(4, 0), color: Colors.red),
    );
    _crosshairComponent.add(
      _CrossLine(from: Vector2(0, -4), to: Vector2(0, 4), color: Colors.red),
    );
    world.add(_crosshairComponent);

    // ── Marker packed bounds outline (at Flame-correct position) ──
    world.add(
      RectangleComponent(
        position: markerFlamePos.clone(),
        size: marker.packedSize.clone(),
        paint: Paint()
          ..color = Colors.red.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke,
      ),
    );

    // ── Effect sprite ──
    // Sized to the effect's own originalSize (e.g. 15×21).
    // Positioned at markerFlamePos — the full original frame's top-left
    // is at the marker position. TexturePackerSprite.render() handles
    // the internal offset (whitespace) when rendering packed pixels.
    _effectComponent = SpriteComponent(
      sprite: effectFrames.first,
      position: markerFlamePos.clone(),
      size: effectFrames.first.originalSize,
    );
    world.add(_effectComponent);

    // ── Mode label ──
    _modeLabel = TextComponent(
      text: 'Mode: ${alignCenter ? "center" : "topLeft"}',
      position: Vector2(4, 4),
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.white70, fontSize: 2),
      ),
    );
    world.add(_modeLabel);

    _updateEffectPosition();
  }

  void setEffectFrame(int index) {
    _currentFrame = index;
    if (effectFrames.isNotEmpty && index < effectFrames.length) {
      _effectComponent.sprite = effectFrames[index];
      _updateEffectPosition();
    }
  }

  void setAlignCenter(bool value) {
    alignCenter = value;
    _modeLabel.text = 'Mode: ${alignCenter ? "center" : "topLeft"}';
    _updateEffectPosition();
  }

  /// Positions the effect sprite relative to the marker.
  ///
  /// Uses [AtlasMarker.computeEffectPosition] which accounts for the
  /// effect sprite's internal offset (whitespace in the original frame).
  /// The component position is for the full original frame —
  /// [TexturePackerSprite.render()] handles the internal offset when
  /// rendering packed pixels within the component bounds.
  void _updateEffectPosition() {
    if (effectFrames.isEmpty) return;

    final effectSprite = effectFrames[_currentFrame];
    final effectOriginalSize = effectSprite.originalSize;
    final markerFlamePos = marker.flameOffset;

    if (alignCenter) {
      // Center of marker packed content
      final markerCenter = markerFlamePos + marker.packedSize * 0.5;
      // Place effect original frame center at marker packed center
      _effectComponent.position =
          _refOrigin +
          Vector2(
            markerCenter.x - effectOriginalSize.x * 0.5,
            markerCenter.y - effectOriginalSize.y * 0.5,
          );
    } else {
      // topLeft: place effect original frame top-left at marker packed top-left
      _effectComponent.position = _refOrigin + markerFlamePos.clone();
    }

    _effectComponent.size = effectOriginalSize;
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

class _MarkerInfo extends StatelessWidget {
  final AtlasMarker marker;
  const _MarkerInfo({required this.marker});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Marker:',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Name: ${marker.name}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Position (offset): (${marker.position.x}, ${marker.position.y})',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Reference: ${marker.referenceSize.x}×${marker.referenceSize.y}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Packed: ${marker.packedSize.x}×${marker.packedSize.y}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EffectFrameInfo extends StatelessWidget {
  final TexturePackerSprite sprite;
  final AtlasMarker marker;
  final bool alignCenter;

  const _EffectFrameInfo({
    required this.sprite,
    required this.marker,
    required this.alignCenter,
  });

  @override
  Widget build(BuildContext context) {
    final r = sprite.region;
    final effectOriginalSize = Vector2(r.originalWidth, r.originalHeight);
    final markerFlamePos = marker.flameOffset;

    double computedX, computedY;
    if (alignCenter) {
      final markerCenter = markerFlamePos + marker.packedSize * 0.5;
      computedX = markerCenter.x - effectOriginalSize.x * 0.5;
      computedY = markerCenter.y - effectOriginalSize.y * 0.5;
    } else {
      // topLeft: effect original frame top-left at marker packed top-left
      computedX = markerFlamePos.x;
      computedY = markerFlamePos.y;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Effect Frame:',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Name: ${r.name} (index: ${r.index})',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Offset (padding): ${r.offsetX}, ${r.offsetY}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Original: ${r.originalWidth}×${r.originalHeight}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Packed: ${r.width}×${r.height}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Computed pos (${alignCenter ? "center" : "topLeft"}): '
            '(${computedX.toStringAsFixed(1)}, ${computedY.toStringAsFixed(1)})',
            style: const TextStyle(
              color: Colors.yellow,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllMarkersInfo extends StatelessWidget {
  final TexturePackerAtlas atlas;
  const _AllMarkersInfo({required this.atlas});

  @override
  Widget build(BuildContext context) {
    final markers = atlas.getMarkers();
    if (markers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'No markers found in atlas.',
          style: TextStyle(color: Colors.orange),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'All Markers in Atlas:',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          ...markers.map(
            (m) => Text(
              '  ${m.name} → (${m.position.x}, ${m.position.y}) '
              'in ${m.referenceSize.x}×${m.referenceSize.y}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
