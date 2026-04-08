import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/input.dart';
import 'package:flame/rendering.dart';
// ignore: implementation_imports
import 'package:flame/src/rendering/decorator.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:composite_atlas/composite_atlas.dart';

/// A decorator that applies a grayscale shader during baking.
class GrayscaleDecorator extends Decorator implements AtlasDecorator {
  final ui.FragmentShader shader;
  final double intensity;
  AtlasContext? _context;

  GrayscaleDecorator(this.shader, {this.intensity = 0.1});

  @override
  void updateAtlasContext(AtlasContext context) {
    _context = context;
  }

  @override
  void applyChain(void Function(ui.Canvas) draw, ui.Canvas canvas) {
    if (_context == null) {
      draw(canvas);
      return;
    }

    try {
      // Set uniforms
      // 0: float uIntensity
      shader.setFloat(0, intensity);
      // 1-4: vec4 uSrcRect [left, top, width, height]
      shader.setFloat(1, _context!.srcRect.left);
      shader.setFloat(2, _context!.srcRect.top);
      shader.setFloat(3, _context!.srcRect.width);
      shader.setFloat(4, _context!.srcRect.height);
      // 5-6: vec2 uAtlasSize [width, height]
      shader.setFloat(5, _context!.atlasSize.width);
      shader.setFloat(6, _context!.atlasSize.height);
      // 7: float uRotate
      shader.setFloat(7, _context!.rotated ? 1.0 : 0.0);

      // Set sampler: index 0 corresponds to uTexture
      shader.setImageSampler(0, _context!.atlasImage);
    } catch (e) {
      debugPrint('[GrayscaleDecorator] Failed to set uniforms: $e');
      // Continue drawing without the shader to avoid crashing the bake process
      draw(canvas);
      return;
    }

    final paint = ui.Paint()..shader = shader;

    // Use drawRect with the shader to completely fill the target area.
    // The shader handles the atlas sampling and rotation mapping.
    canvas.drawRect(ui.Offset.zero & _context!.localSize, paint);
  }
}

class DebugShaderBakingScreen extends StatefulWidget {
  const DebugShaderBakingScreen({super.key});

  @override
  State<DebugShaderBakingScreen> createState() =>
      _DebugShaderBakingScreenState();
}

enum ViewMode { comparison, original, baked }

class _DebugShaderBakingScreenState extends State<DebugShaderBakingScreen> {
  ui.FragmentProgram? _program;
  ViewMode _viewMode = ViewMode.comparison;
  DebugShaderBakingGame? _game;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'assets/shaders/grayscale.frag',
      );
      if (mounted) {
        setState(() {
          _program = program;
          _game = DebugShaderBakingGame(shader: _program!.fragmentShader());
        });
      }
    } catch (e) {
      debugPrint('Error loading shader: $e');
    }
  }

  Future<void> _exportAtlas() async {
    if (_game == null || _game!.bakedAtlas == null) return;
    final atlas = _game!.bakedAtlas!;
    final image = atlas.image;
    setState(() => _exporting = true);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      // Save to the current working directory of the app
      final exportsDir = 'composite_atlas_export';
      await Directory(exportsDir).create(recursive: true);

      final pngFile = File('$exportsDir/baked_shader_atlas.png');
      await pngFile.writeAsBytes(bytes);

      final sb = StringBuffer();
      sb.writeln('baked_shader_atlas.png');
      sb.writeln('size:${image.width},${image.height}');
      sb.writeln('format:RGBA8888');
      sb.writeln('filter:Nearest,Nearest');
      sb.writeln('repeat:none');

      final Set<ui.Rect> exportedRects = {};
      for (final sprite in atlas.sprites) {
        final r = sprite.region;
        // Check for duplicates: if we already exported a region with this name, index, and rect, skip it.
        // We use the 'left, top, width, height' as a unique signature for the rect.
        final rectKey = ui.Rect.fromLTWH(r.left, r.top, r.width, r.height);

        // Note: We might want slightly different naming logic if we want to deduplicate by name+index+pixels.
        // But the LibGDX format allows multiple names pointing to same pixels.
        // However, we want to avoid writing the EXACT SAME region entry twice.

        sb.writeln(r.name);
        sb.writeln('  index:${r.index}');
        sb.writeln('  rotate:${r.rotate}');
        sb.writeln('  xy:${r.left.toInt()},${r.top.toInt()}');
        sb.writeln('  size:${r.width.toInt()},${r.height.toInt()}');
        sb.writeln(
          '  orig:${r.originalWidth.toInt()},${r.originalHeight.toInt()}',
        );
        sb.writeln('  offset:${r.offsetX.toInt()},${r.offsetY.toInt()}');
      }

      final atlasFile = File('$exportsDir/baked_shader_atlas.atlas');
      await atlasFile.writeAsString(sb.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved:\n$exportsDir'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () => Process.run('open', [exportsDir]),
            ),
          ),
        );
      }
    } catch (e, stack) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e\n$stack'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_program == null || _game == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('Shader Baking Debug'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _exporting ? null : _exportAtlas,
            tooltip: 'Export Baked Shader Atlas',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: SegmentedButton<ViewMode>(
              segments: const [
                ButtonSegment(
                  value: ViewMode.comparison,
                  label: Text('Compare'),
                  icon: Icon(Icons.compare),
                ),
                ButtonSegment(
                  value: ViewMode.original,
                  label: Text('Original'),
                  icon: Icon(Icons.image),
                ),
                ButtonSegment(
                  value: ViewMode.baked,
                  label: Text('Baked'),
                  icon: Icon(Icons.brush),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (set) {
                setState(() => _viewMode = set.first);
                _game!.updateViewMode(_viewMode);
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: Colors.grey[900],
                foregroundColor: Colors.white,
                selectedBackgroundColor: Colors.blueAccent,
                selectedForegroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: GameWidget(game: _game!),
    );
  }
}

class DebugShaderBakingGame extends FlameGame with ScrollDetector, PanDetector {
  final ui.FragmentShader shader;
  DebugShaderBakingGame({required this.shader});

  CompositeAtlas? originalAtlas;
  CompositeAtlas? bakedAtlas;
  ViewMode viewMode = ViewMode.comparison;

  final columnWidth = 120.0;
  final rowHeight = 120.0;
  final padding = 40.0;

  late final World world0;
  late final CameraComponent camera0;

  @override
  Future<void> onLoad() async {
    // 1. Load the original electro_bot atlas
    final atlas = await TexturePackerAtlas.load(
      'assets/images/electro_bot.atlas',
    );
    originalAtlas = CompositeAtlas.fromAtlas(atlas);

    // 2. Bake it with a shader decorator
    bakedAtlas = await CompositeAtlas.bake(
      [
        AtlasBakeRequest(
          atlas,
          keyPrefix: 'gray_',
          decorator: GrayscaleDecorator(shader, intensity: 1.0),
        ),
      ],
      maxAtlasWidth: 512,
      trim: true,
    );

    // 3. Set up the display
    world0 = World();
    camera0 = CameraComponent.withFixedResolution(
      width: 800,
      height: 600,
      world: world0,
    );
    camera0.viewfinder.anchor = Anchor.topLeft;
    add(world0);
    add(camera0);

    // Refresh display
    _refreshDisplay();
  }

  void updateViewMode(ViewMode mode) {
    viewMode = mode;
    _refreshDisplay();
  }

  @override
  Color backgroundColor() => const Color(0xFF1A1A1A);

  void _refreshDisplay() {
    world0.removeAll(world0.children);
    // Reset camera when switching modes to avoid showing empty space
    camera0.viewfinder.position = Vector2.zero();

    if (originalAtlas == null || bakedAtlas == null) return;

    final spriteNames = originalAtlas!.allSpriteNames..sort();

    double curY = padding;

    for (int i = 0; i < spriteNames.length; i++) {
      final name = spriteNames[i];
      final originalSprite = originalAtlas!.findSpriteByName(name);
      final bakedSprite = bakedAtlas!.findSpriteByName('gray_$name');

      if (viewMode == ViewMode.comparison) {
        _addSpriteWithLabel(
          name,
          originalSprite,
          Vector2(padding, curY),
          'Original',
        );
        _addSpriteWithLabel(
          'gray_$name',
          bakedSprite,
          Vector2(padding + columnWidth + 100, curY),
          'Baked',
        );
      } else if (viewMode == ViewMode.original) {
        final col = i % 5;
        final row = i ~/ 5;
        _addSpriteWithLabel(
          name,
          originalSprite,
          Vector2(
            padding + col * (columnWidth + 20),
            padding + row * (rowHeight + 40),
          ),
          '',
        );
      } else if (viewMode == ViewMode.baked) {
        final col = i % 5;
        final row = i ~/ 5;
        _addSpriteWithLabel(
          'gray_$name',
          bakedSprite,
          Vector2(
            padding + col * (columnWidth + 20),
            padding + row * (rowHeight + 40),
          ),
          '',
        );
      }

      if (viewMode == ViewMode.comparison) {
        curY += rowHeight + 20;
      }
    }
  }

  void _addSpriteWithLabel(
    String name,
    Sprite? sprite,
    Vector2 position,
    String label,
  ) {
    if (sprite == null) return;

    // Checkerboard background
    world0.add(
      RectangleComponent(
        position: position,
        size: Vector2(columnWidth, rowHeight),
        paint: ui.Paint()..color = Colors.grey[800]!,
      ),
    );

    // Sprite
    world0.add(
      SpriteComponent(
        sprite: sprite,
        position: position + Vector2(columnWidth / 2, rowHeight / 2),
        size: Vector2(columnWidth * 0.8, rowHeight * 0.8),
        anchor: Anchor.center,
      ),
    );

    // Labels
    if (label.isNotEmpty) {
      world0.add(
        TextComponent(
          text: label,
          position: position + Vector2(0, -20),
          textRenderer: TextPaint(
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      );
    }

    world0.add(
      TextComponent(
        text: name,
        position: position + Vector2(0, rowHeight + 5),
        textRenderer: TextPaint(
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
    );
  }

  // Handle panning/scrolling
  @override
  void onScroll(PointerScrollInfo event) {
    camera0.viewfinder.position += event.scrollDelta.global;
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    camera0.viewfinder.position -= info.delta.global;
  }
}
