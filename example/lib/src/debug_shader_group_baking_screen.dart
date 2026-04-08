import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/input.dart';
import 'package:flame/rendering.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
// import 'package:flame_visual_fx/flame_visual_fx.dart';
import 'package:flutter/material.dart';
import 'package:composite_atlas/composite_atlas.dart';
import 'debug_shader_baking_screen.dart'; // Reuse ViewMode and GrayscaleDecorator if possible, or redefine.

/// A decorator that applies an outline shader during baking.
class OutlineDecorator extends Decorator
    implements AtlasDecorator, BakePadding {
  final ui.FragmentShader shader;
  final double thickness;
  final ui.Color color;
  AtlasContext? _context;

  OutlineDecorator(
    this.shader, {
    this.thickness = 2.0,
    this.color = Colors.white,
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
      // 0: float uThickness
      shader.setFloat(0, thickness);
      // 1-4: vec4 uColor
      shader.setFloat(1, color.red / 255.0);
      shader.setFloat(2, color.green / 255.0);
      shader.setFloat(3, color.blue / 255.0);
      shader.setFloat(4, color.alpha / 255.0);
      // 5-8: vec4 uSrcRect [left, top, width, height]
      shader.setFloat(5, _context!.srcRect.left);
      shader.setFloat(6, _context!.srcRect.top);
      shader.setFloat(7, _context!.srcRect.width);
      shader.setFloat(8, _context!.srcRect.height);
      // 9-10: vec2 uAtlasSize [width, height]
      shader.setFloat(9, _context!.atlasSize.width);
      shader.setFloat(10, _context!.atlasSize.height);
      // 11: float uRotate
      shader.setFloat(11, _context!.rotated ? 1.0 : 0.0);
      // 12-15: vec4 uPadding [top, left, right, bottom]
      shader.setFloat(12, _context!.padding.top);
      shader.setFloat(13, _context!.padding.left);
      shader.setFloat(14, _context!.padding.right);
      shader.setFloat(15, _context!.padding.bottom);
      // 16: float uOutlineOnly
      shader.setFloat(
        16,
        1.0,
      ); // Only draw the outline over the previous content

      // Set sampler: index 0 corresponds to uTexture
      shader.setImageSampler(0, _context!.atlasImage);
    } catch (e) {
      debugPrint('[OutlineDecorator] Failed to set uniforms: $e');
      draw(canvas);
      return;
    }

    // Call draw() to render previous effects in the chain
    draw(canvas);

    final paint = ui.Paint()..shader = shader;
    canvas.drawRect(ui.Offset.zero & _context!.localSize, paint);
  }
}

/// A decorator that applies a glitch shader during baking.
class GlitchDecorator extends Decorator implements AtlasDecorator, BakePadding {
  final ui.FragmentShader shader;
  final double seed;
  final double intensity;
  AtlasContext? _context;

  GlitchDecorator(this.shader, {this.seed = 0.0, this.intensity = 0.5});

  @override
  void updateAtlasContext(AtlasContext context) {
    _context = context;
  }

  @override
  EdgeInsets get padding => EdgeInsets.symmetric(horizontal: intensity * 10.0);

  @override
  void applyChain(void Function(ui.Canvas) draw, ui.Canvas canvas) {
    if (_context == null) {
      draw(canvas);
      return;
    }

    try {
      // 0: float uSeed
      shader.setFloat(0, seed);
      // 1: float uIntensity
      shader.setFloat(1, intensity);
      // 2-5: vec4 uSrcRect
      shader.setFloat(2, _context!.srcRect.left);
      shader.setFloat(3, _context!.srcRect.top);
      shader.setFloat(4, _context!.srcRect.width);
      shader.setFloat(5, _context!.srcRect.height);
      // 6-7: vec2 uAtlasSize
      shader.setFloat(6, _context!.atlasSize.width);
      shader.setFloat(7, _context!.atlasSize.height);
      // 8: float uRotate
      shader.setFloat(8, _context!.rotated ? 1.0 : 0.0);

      shader.setImageSampler(0, _context!.atlasImage);
    } catch (e) {
      debugPrint('[GlitchDecorator] Failed to set uniforms: $e');
      draw(canvas);
      return;
    }

    // Call draw() first
    draw(canvas);

    final paint = ui.Paint()..shader = shader;
    canvas.drawRect(ui.Offset.zero & _context!.localSize, paint);
  }
}

/// A decorator that groups multiple decorators into a single bake pass.
class GroupDecorator extends Decorator implements AtlasDecorator, BakePadding {
  final List<Decorator> decorators;
  GroupDecorator(this.decorators);

  @override
  void updateAtlasContext(AtlasContext context) {
    for (final d in decorators) {
      if (d is AtlasDecorator) {
        (d as AtlasDecorator).updateAtlasContext(context);
      }
    }
  }

  @override
  EdgeInsets get padding {
    var p = EdgeInsets.zero;
    for (final d in decorators) {
      if (d is BakePadding) {
        final dp = (d as BakePadding).padding;
        p = EdgeInsets.fromLTRB(
          p.left + dp.left,
          p.top + dp.top,
          p.right + dp.right,
          p.bottom + dp.bottom,
        );
      }
    }
    return p;
  }

  @override
  void applyChain(void Function(ui.Canvas) draw, ui.Canvas canvas) {
    void process(int index, void Function(ui.Canvas) next) {
      if (index < 0) {
        next(canvas);
        return;
      }
      // Apply decorators in sequence (from last to first in the list to maintain expected layering)
      decorators[index].applyChain((c) => process(index - 1, next), canvas);
    }

    process(decorators.length - 1, draw);
  }
}

class DebugShaderGroupBakingScreen extends StatefulWidget {
  const DebugShaderGroupBakingScreen({super.key});

  @override
  State<DebugShaderGroupBakingScreen> createState() =>
      _DebugShaderGroupBakingScreenState();
}

class _DebugShaderGroupBakingScreenState
    extends State<DebugShaderGroupBakingScreen> {
  ui.FragmentProgram? _grayscaleProgram;
  ui.FragmentProgram? _outlineProgram;
  ui.FragmentProgram? _glitchProgram;
  DebugShaderGroupGame? _game;
  bool _exporting = false;
  ViewMode _viewMode = ViewMode.comparison;

  @override
  void initState() {
    super.initState();
    _loadShaders();
  }

  Future<void> _loadShaders() async {
    _grayscaleProgram = await ui.FragmentProgram.fromAsset(
      'assets/shaders/grayscale.frag',
    );
    _outlineProgram = await ui.FragmentProgram.fromAsset(
      'assets/shaders/outline.frag',
    );
    _glitchProgram = await ui.FragmentProgram.fromAsset(
      'assets/shaders/glitch.frag',
    );

    if (mounted) {
      setState(() {
        _game = DebugShaderGroupGame(
          grayscaleShader: _grayscaleProgram!.fragmentShader(),
          outlineShader: _outlineProgram!.fragmentShader(),
          glitchShader: _glitchProgram!.fragmentShader(),
        );
      });
    }
  }

  Future<void> _exportAtlas() async {
    if (_game?.bakedAtlas == null) return;
    setState(() => _exporting = true);

    try {
      final exportsDir = 'composite_atlas_export';
      await Directory(exportsDir).create(recursive: true);

      final atlas = _game!.bakedAtlas!;

      // Save PNG
      final byteData = await atlas.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final bytes = byteData!.buffer.asUint8List();
      await File('$exportsDir/baked_group_atlas.png').writeAsBytes(bytes);

      // Save .atlas
      final sb = StringBuffer();
      sb.writeln('baked_group_atlas.png');
      sb.writeln('size:${atlas.image.width},${atlas.image.height}');
      sb.writeln('format:RGBA8888');
      sb.writeln('filter:Nearest,Nearest');
      sb.writeln('repeat:none');

      for (final sprite in atlas.sprites) {
        final r = sprite.region;
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

      await File(
        '$exportsDir/baked_group_atlas.atlas',
      ).writeAsString(sb.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $exportsDir'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => Process.run('open', [exportsDir]),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_game == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('Group Shader Baking'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _exporting ? null : _exportAtlas,
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
                  label: Text('Orig'),
                  icon: Icon(Icons.image),
                ),
                ButtonSegment(
                  value: ViewMode.baked,
                  label: Text('Baked'),
                  icon: Icon(Icons.auto_awesome),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (set) {
                setState(() => _viewMode = set.first);
                _game!.updateViewMode(_viewMode);
              },
            ),
          ),
        ],
      ),
      body: GameWidget(game: _game!),
    );
  }
}

class DebugShaderGroupGame extends FlameGame with ScrollDetector, PanDetector {
  final ui.FragmentShader grayscaleShader;
  final ui.FragmentShader outlineShader;
  final ui.FragmentShader glitchShader;

  DebugShaderGroupGame({
    required this.grayscaleShader,
    required this.outlineShader,
    required this.glitchShader,
  });

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
    final atlas = await TexturePackerAtlas.load(
      'assets/images/electro_bot.atlas',
    );
    originalAtlas = CompositeAtlas.fromAtlas(atlas);

    // Bake multiple variations
    bakedAtlas = await CompositeAtlas.bake(
      [
        // 2. Outline version (Red)
        AtlasBakeRequest(
          atlas,
          keyPrefix: 'outline_',
          decorator: GroupDecorator([
            GrayscaleDecorator(grayscaleShader, intensity: 1.0),
            OutlineDecorator(
              outlineShader,
              thickness: 2.0,
              color: Colors.redAccent,
            ),
            GlitchDecorator(glitchShader, seed: 123.45, intensity: 0.3),
          ]),
        ),

        // 3. Glitch version
      ],
      maxAtlasWidth: 1024,
      trim: true,
    );

    world0 = World();
    camera0 = CameraComponent.withFixedResolution(
      width: 800,
      height: 600,
      world: world0,
    );
    camera0.viewfinder.anchor = Anchor.topLeft;
    add(world0);
    add(camera0);

    _refreshDisplay();
  }

  void updateViewMode(ViewMode mode) {
    viewMode = mode;
    _refreshDisplay();
  }

  void _refreshDisplay() {
    world0.removeAll(world0.children);

    if (originalAtlas == null || bakedAtlas == null) return;

    final spriteNames = originalAtlas!.sprites
        .map((s) => s.region.name)
        .toSet()
        .toList();

    // We'll show 2 variants: Orig and Combined (Group)
    final variants = ['', 'outline_'];

    for (int i = 0; i < spriteNames.length; i++) {
      final baseName = spriteNames[i];
      final row = i;

      for (int j = 0; j < variants.length; j++) {
        final prefix = variants[j];
        final fullName = '$prefix$baseName';
        final atlas = (prefix == '') ? originalAtlas! : bakedAtlas!;

        final sprites = atlas.findSpritesByName(fullName);
        if (sprites.isEmpty) continue;

        // Just show the first index (frame 0) of each animation for brevity
        final sprite = sprites.first;

        final comp = SpriteComponent(
          sprite: sprite,
          position: Vector2(
            j * columnWidth + padding,
            row * rowHeight + padding,
          ),
          anchor: Anchor.center,
        );

        // Add a background to see transparency
        world0.add(
          RectangleComponent(
            position: comp.position.clone(),
            size: Vector2(rowHeight - 10, rowHeight - 10),
            anchor: Anchor.center,
            paint: Paint()..color = Colors.white.withOpacity(0.05),
          ),
        );
        world0.add(comp);
      }
    }
  }

  @override
  void onScroll(info) {
    camera0.viewfinder.position += Vector2(0, info.scrollDelta.global.y);
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    camera0.viewfinder.position -= info.delta.global;
  }
}
