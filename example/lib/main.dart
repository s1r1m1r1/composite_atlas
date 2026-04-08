import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/sprite.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:flutter/material.dart';
import 'package:composite_atlas/composite_atlas.dart';
import 'dart:ui' as ui;

void main() {
  runApp(const MaterialApp(home: HomeScreen()));
}

//region Models
class AtlasSet {
  final String name;
  final String? atlasPath;
  final String imagePath;
  final String? simpleAtlasPath;
  final bool allowRotation;
  final bool forceSquare;
  final bool isSpritesheet;
  final int? frameWidth;
  final int? frameHeight;
  final int? frameCount;

  /// For spritesheets: explicit frame regions (GDX-style)
  final List<SpritesheetFrame>? frames;

  AtlasSet({
    required this.name,
    this.atlasPath,
    required this.imagePath,
    this.simpleAtlasPath,
    required this.allowRotation,
    this.forceSquare = false,
    this.isSpritesheet = false,
    this.frameWidth,
    this.frameHeight,
    this.frameCount,
    this.frames,
  });
}

/// Describes a single frame in a spritesheet.
class SpritesheetFrame {
  final String name;
  final double x;
  final double y;
  final double width;
  final double height;

  const SpritesheetFrame({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class AppPage {
  final String title;
  final IconData icon;
  final Widget Function(BuildContext context) builder;

  const AppPage({
    required this.title,
    required this.icon,
    required this.builder,
  });
}
//endregion

//region Data
final List<AtlasSet> atlasSets = [
  AtlasSet(
    name: 'Aligned (from Rotated Source)',
    atlasPath: 'assets/images/rotated_boy_debug.atlas',
    imagePath: 'assets/images/rotated_boy_debug.png',
    simpleAtlasPath: 'assets/images/simple_boy_debug.atlas',
    allowRotation: false,
  ),
  AtlasSet(
    name: 'Rotated-Packed (from Simple Source)',
    atlasPath: 'assets/images/simple_boy_debug.atlas',
    imagePath: 'assets/images/simple_boy_debug.png',
    simpleAtlasPath: 'assets/images/simple_boy_debug.atlas',
    allowRotation: true,
    forceSquare: true,
  ),
  AtlasSet(
    name: 'Spritesheet (Auto-Sliced)',
    imagePath: 'animations/boy-32x64-idle-walk.png',
    allowRotation: true,
    isSpritesheet: true,
    frameWidth: 32,
    frameHeight: 64,
    frameCount: 10,
    frames: List.generate(
      10,
      (i) => SpritesheetFrame(
        name: 'boy_$i',
        x: i * 32.0,
        y: 0,
        width: 32,
        height: 64,
      ),
    ),
  ),
];

final List<AppPage> appPages = [
  AppPage(
    title: 'Atlas Comparison',
    icon: Icons.compare_arrows,
    builder: (_) => const AtlasComparisonScreen(),
  ),
  AppPage(
    title: 'Raw Atlas Viewer',
    icon: Icons.grid_view,
    builder: (_) => const RawAtlasViewerScreen(),
  ),
  AppPage(
    title: 'Settings',
    icon: Icons.settings,
    builder: (_) => const SettingsScreen(),
  ),
];
//endregion

//region Home Screen
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('Composite Atlas Demo'),
        backgroundColor: Colors.black,
      ),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: appPages
            .map(
              (page) => Card(
                color: Colors.grey[900],
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: page.builder),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(page.icon, size: 64, color: Colors.blueAccent),
                      const SizedBox(height: 12),
                      Text(
                        page.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
//endregion

//region Atlas Comparison Screen
class AtlasComparisonScreen extends StatefulWidget {
  const AtlasComparisonScreen({super.key});

  @override
  State<AtlasComparisonScreen> createState() => _AtlasComparisonScreenState();
}

class _AtlasComparisonScreenState extends State<AtlasComparisonScreen> {
  int _setIndex = 1;

  AtlasSet get _set => atlasSets[_setIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text(_set.name),
        backgroundColor: Colors.black,
        actions: [
          DropdownButton<int>(
            value: _setIndex,
            dropdownColor: Colors.black,
            style: const TextStyle(color: Colors.white),
            items: [
              for (int i = 0; i < atlasSets.length; i++)
                DropdownMenuItem(value: i, child: Text('Exp $i')),
            ],
            onChanged: (v) => setState(() => _setIndex = v!),
          ),
          IconButton(
            icon: const Icon(Icons.grid_view),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RawAtlasViewPage(atlasSet: _set),
              ),
            ),
            tooltip: 'View Baked Atlas',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ComparisonView(key: ValueKey('comp_$_setIndex'), set: _set),
    );
  }
}
//endregion

//region Raw Atlas Viewer Screen
class RawAtlasViewerScreen extends StatefulWidget {
  const RawAtlasViewerScreen({super.key});

  @override
  State<RawAtlasViewerScreen> createState() => _RawAtlasViewerScreenState();
}

class _RawAtlasViewerScreenState extends State<RawAtlasViewerScreen> {
  int _setIndex = 1;

  AtlasSet get _set => atlasSets[_setIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('Raw Atlas Viewer'),
        backgroundColor: Colors.black,
        actions: [
          DropdownButton<int>(
            value: _setIndex,
            dropdownColor: Colors.black,
            style: const TextStyle(color: Colors.white),
            items: [
              for (int i = 0; i < atlasSets.length; i++)
                DropdownMenuItem(value: i, child: Text('Exp $i')),
            ],
            onChanged: (v) => setState(() => _setIndex = v!),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RawAtlasViewPage(key: ValueKey('raw_$_setIndex'), atlasSet: _set),
    );
  }
}
//endregion

//region Settings Screen
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _maxAtlasWidth = 128.0;
  bool _allowRotation = true;
  bool _forceSquare = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Atlas Configuration',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Max Atlas Width: ${_maxAtlasWidth.toInt()}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Slider(
                    value: _maxAtlasWidth,
                    min: 64,
                    max: 512,
                    divisions: 14,
                    label: _maxAtlasWidth.toInt().toString(),
                    activeColor: Colors.blueAccent,
                    onChanged: (v) => setState(() => _maxAtlasWidth = v),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text(
                      'Allow Rotation',
                      style: TextStyle(color: Colors.white),
                    ),
                    value: _allowRotation,
                    activeColor: Colors.blueAccent,
                    onChanged: (v) => setState(() => _allowRotation = v),
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Force Square',
                      style: TextStyle(color: Colors.white),
                    ),
                    value: _forceSquare,
                    activeColor: Colors.blueAccent,
                    onChanged: (v) => setState(() => _forceSquare = v),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
//endregion

//region Shared Widgets
class ComparisonView extends StatefulWidget {
  final AtlasSet set;
  const ComparisonView({super.key, required this.set});

  @override
  State<ComparisonView> createState() => _ComparisonViewState();
}

class _ComparisonViewState extends State<ComparisonView> {
  late ComparisonGame _game;

  @override
  void initState() {
    super.initState();
    _game = ComparisonGame(widget.set);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: GameWidget(game: _game)),
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RawAtlasViewPage(atlasSet: widget.set),
                ),
              ),
              icon: const Icon(Icons.grid_view),
              label: const Text('VIEW BAKED ATLAS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.withOpacity(0.9),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                elevation: 8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RawAtlasViewPage extends StatefulWidget {
  final AtlasSet atlasSet;
  const RawAtlasViewPage({super.key, required this.atlasSet});

  @override
  State<RawAtlasViewPage> createState() => _RawAtlasViewPageState();
}

class _RawAtlasViewPageState extends State<RawAtlasViewPage> {
  late RawAtlasGame _game;

  @override
  void initState() {
    super.initState();
    _game = RawAtlasGame(widget.atlasSet);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(200),
      minScale: 0.1,
      maxScale: 10.0,
      child: FutureBuilder(
        future: _game.onLoad(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              width: 500,
              height: 500,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return SizedBox(
            width: _game.bakedAtlas?.image.width.toDouble() ?? 500,
            height: _game.bakedAtlas?.image.height.toDouble() ?? 500,
            child: GameWidget(game: _game),
          );
        },
      ),
    );
  }
}
//endregion

class ComparisonGame extends Game {
  final AtlasSet set;
  ComparisonGame(this.set);

  TexturePackerAtlas? originalAtlas;
  TexturePackerAtlas? referenceAtlas;
  CompositeAtlas? bakedAtlas;
  SpriteAnimationTicker? originalTicker;
  SpriteAnimationTicker? referenceTicker;
  SpriteAnimationTicker? bakedTicker;
  bool _loggedDifferences = false;

  @override
  Future<void> onLoad() async {
    if (set.isSpritesheet) {
      // For spritesheets, we slice the image into frames with explicit GDX regions
      final image = await images.load(set.imagePath);

      final List<SpriteBakeRequest> bakeRequests;
      if (set.frames != null) {
        // Use explicit frame regions (GDX-style)
        bakeRequests = set.frames!
            .map(
              (frame) => SpriteBakeRequest(
                Sprite(
                  image,
                  srcPosition: Vector2(frame.x, frame.y),
                  srcSize: Vector2(frame.width, frame.height),
                ),
                name: frame.name,
                keyPrefix: 'baked_',
                sourceRegion: SpriteSourceRegion(
                  x: frame.x,
                  y: frame.y,
                  width: frame.width,
                  height: frame.height,
                  originalWidth: frame.width,
                  originalHeight: frame.height,
                ),
              ),
            )
            .toList();
      } else {
        // Fallback: generate frames from grid
        bakeRequests = List.generate(
          set.frameCount!,
          (i) => SpriteBakeRequest(
            Sprite(
              image,
              srcPosition: Vector2(i * set.frameWidth!.toDouble(), 0),
              srcSize: Vector2(
                set.frameWidth!.toDouble(),
                set.frameHeight!.toDouble(),
              ),
            ),
            name: 'boy_$i',
            keyPrefix: 'baked_',
            sourceRegion: SpriteSourceRegion(
              x: i * set.frameWidth!.toDouble(),
              y: 0,
              width: set.frameWidth!.toDouble(),
              height: set.frameHeight!.toDouble(),
              originalWidth: set.frameWidth!.toDouble(),
              originalHeight: set.frameHeight!.toDouble(),
            ),
          ),
        );
      }

      bakedAtlas = await CompositeAtlas.bake(
        bakeRequests,
        maxAtlasWidth: 128.0,
        allowRotation: set.allowRotation,
        forceSquare: set.forceSquare,
        trim: true, // Now safe: explicit regions with proper offset computation
      );

      final List<Sprite> frames = bakeRequests
          .map(
            (r) => Sprite(
              image,
              srcPosition: Vector2(
                set.frames != null
                    ? set.frames![bakeRequests.indexOf(r)].x
                    : r.sourceRegion?.x ?? 0,
                0,
              ),
              srcSize: Vector2(
                set.frames != null
                    ? set.frames![bakeRequests.indexOf(r)].width
                    : r.sourceRegion?.width ?? set.frameWidth!.toDouble(),
                set.frameHeight!.toDouble(),
              ),
            ),
          )
          .toList();

      final originalAnim = SpriteAnimation.spriteList(frames, stepTime: 0.2);
      final bakedAnim = bakedAtlas!.getAnimation('baked_boy', stepTime: 0.2);

      originalTicker = originalAnim.createTicker();
      bakedTicker = bakedAnim.createTicker();
      referenceTicker = originalAnim
          .createTicker(); // Reference is the original spritesheet
      return;
    }

    originalAtlas = await TexturePackerAtlas.load(set.atlasPath!);
    referenceAtlas = await TexturePackerAtlas.load(set.simpleAtlasPath!);

    bakedAtlas = await CompositeAtlas.bake(
      [AtlasBakeRequest(referenceAtlas!, keyPrefix: 'baked_')],
      maxAtlasWidth: 128.0,
      allowRotation: set.allowRotation,
      forceSquare: set.forceSquare,
    );

    final List<Sprite> originalSprites = originalAtlas!
        .findSpritesByName('boy')
        .cast<Sprite>()
        .toList();

    final originalAnim = SpriteAnimation.spriteList(
      originalSprites,
      stepTime: 0.2,
    );

    final bakedAnim = bakedAtlas!.getAnimation('baked_boy', stepTime: 0.2);

    originalTicker = originalAnim.createTicker();
    bakedTicker = bakedAnim.createTicker();

    final List<Sprite> referenceSprites = referenceAtlas!
        .findSpritesByName('boy')
        .cast<Sprite>()
        .toList();
    final referenceAnim = SpriteAnimation.spriteList(
      referenceSprites,
      stepTime: 0.2,
    );
    referenceTicker = referenceAnim.createTicker();
  }

  @override
  void update(double dt) {
    originalTicker?.update(dt);
    bakedTicker?.update(dt);
    referenceTicker?.update(dt);
  }

  @override
  void render(Canvas canvas) {
    if (originalTicker == null ||
        bakedTicker == null ||
        referenceTicker == null)
      return;

    final paint = Paint()..filterQuality = ui.FilterQuality.none;
    const scale = 4.0;

    // Draw background
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..color = const Color(0xFF1A1A1A),
    );

    // 3-way layout
    // Left: Reference (Simple)
    canvas.save();
    canvas.translate(size.x / 6, size.y / 2);
    canvas.scale(scale);
    referenceTicker!.getSprite().render(
      canvas,
      anchor: Anchor.center,
      overridePaint: paint,
    );
    canvas.restore();

    // Middle: Original (Rotated Source)
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(scale);
    originalTicker!.getSprite().render(
      canvas,
      anchor: Anchor.center,
      overridePaint: paint,
    );
    canvas.restore();

    // Right: Baked (Composite Result)
    canvas.save();
    canvas.translate(size.x * 5 / 6, size.y / 2);
    canvas.scale(scale);
    bakedTicker!.getSprite().render(
      canvas,
      anchor: Anchor.center,
      overridePaint: paint,
    );
    canvas.restore();

    // Labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(
      String text,
      double x,
      double y, {
      Color color = Colors.white,
    }) {
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, y));
    }

    drawLabel(
      'SIMPLE (Reference)',
      size.x / 6,
      size.y / 2 + 150,
      color: Colors.blueAccent,
    );
    drawLabel(
      'SOURCE',
      size.x / 2,
      size.y / 2 + 150,
      color: Colors.orangeAccent,
    );
    drawLabel(
      'BAKED (Result)',
      size.x * 5 / 6,
      size.y / 2 + 150,
      color: Colors.greenAccent,
    );

    // Metadata diffs
    _renderMeta(
      canvas,
      size.x / 6,
      size.y / 2 + 180,
      referenceTicker!.getSprite(),
    );
    _renderMeta(
      canvas,
      size.x / 2,
      size.y / 2 + 180,
      originalTicker!.getSprite(),
    );
    _renderMeta(
      canvas,
      size.x * 5 / 6,
      size.y / 2 + 180,
      bakedTicker!.getSprite(),
      compareWith: referenceTicker!.getSprite(),
    );
  }

  void _renderMeta(
    Canvas canvas,
    double x,
    double y,
    Sprite s, {
    Sprite? compareWith,
  }) {
    if (s is! TexturePackerSprite) {
      final tp = TextPainter(textDirection: TextDirection.ltr);
      tp.text = TextSpan(
        text: 'Raw Sprite (${s.srcSize.x.toInt()}x${s.srcSize.y.toInt()})',
        style: const TextStyle(color: Colors.grey, fontSize: 11),
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y));
      return;
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    final r = s.region;
    final cr = compareWith is TexturePackerSprite ? compareWith.region : null;

    bool isDiff(double a, double b) => a != b;

    final List<(String, dynamic, bool)> rows = [
      (
        'Size',
        '${r.width.toInt()}x${r.height.toInt()}',
        cr != null &&
            (isDiff(r.width, cr.width) || isDiff(r.height, cr.height)),
      ),
      (
        'Offset',
        '${r.offsetX.toInt()}, ${r.offsetY.toInt()}',
        cr != null &&
            (isDiff(r.offsetX, cr.offsetX) || isDiff(r.offsetY, cr.offsetY)),
      ),
      ('Rot', '${r.rotate}', cr != null && r.rotate != cr.rotate),
    ];

    // Логирование различий в размерах спрайтов
    if (!_loggedDifferences &&
        cr != null &&
        (isDiff(r.width, cr.width) || isDiff(r.height, cr.height))) {
      print(
        'Различие в размерах спрайта: ${r.width.toInt()}x${r.height.toInt()} vs ${cr.width.toInt()}x${cr.height.toInt()}',
      );
      _loggedDifferences = true;
    }

    double curY = y;
    for (final row in rows) {
      tp.text = TextSpan(
        children: [
          TextSpan(
            text: '${row.$1}: ',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
          TextSpan(
            text: '${row.$2}',
            style: TextStyle(
              color: row.$3 ? Colors.red : Colors.greenAccent,
              fontSize: 11,
            ),
          ),
        ],
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, curY));
      curY += 16;
    }
  }
}

class RawAtlasGame extends Game {
  final AtlasSet set;
  RawAtlasGame(this.set);

  CompositeAtlas? bakedAtlas;

  @override
  Future<void> onLoad() async {
    if (set.isSpritesheet) {
      final image = await images.load(set.imagePath);

      final List<SpriteBakeRequest> requests;
      if (set.frames != null) {
        requests = set.frames!
            .map(
              (frame) => SpriteBakeRequest(
                Sprite(
                  image,
                  srcPosition: Vector2(frame.x, frame.y),
                  srcSize: Vector2(frame.width, frame.height),
                ),
                name: frame.name,
                sourceRegion: SpriteSourceRegion(
                  x: frame.x,
                  y: frame.y,
                  width: frame.width,
                  height: frame.height,
                  originalWidth: frame.width,
                  originalHeight: frame.height,
                ),
              ),
            )
            .toList();
      } else {
        requests = List.generate(
          set.frameCount!,
          (i) => SpriteBakeRequest(
            Sprite(
              image,
              srcPosition: Vector2(i * set.frameWidth!.toDouble(), 0),
              srcSize: Vector2(
                set.frameWidth!.toDouble(),
                set.frameHeight!.toDouble(),
              ),
            ),
            name: 'frame_$i',
            sourceRegion: SpriteSourceRegion(
              x: i * set.frameWidth!.toDouble(),
              y: 0,
              width: set.frameWidth!.toDouble(),
              height: set.frameHeight!.toDouble(),
              originalWidth: set.frameWidth!.toDouble(),
              originalHeight: set.frameHeight!.toDouble(),
            ),
          ),
        );
      }

      bakedAtlas = await CompositeAtlas.bake(
        requests,
        maxAtlasWidth: 128.0,
        allowRotation: set.allowRotation,
        forceSquare: set.forceSquare,
        trim: true,
      );
    } else {
      final atlas = await TexturePackerAtlas.load(set.atlasPath!);
      // Use rotation for Experiment 1 (Rotated-Packed) but not for Experiment 0 (Aligned)
      final bool useRotation = set.name.contains('Rotated-Packed');

      bakedAtlas = await CompositeAtlas.bake(
        [AtlasBakeRequest(atlas)],
        maxAtlasWidth: 128.0,
        allowRotation: useRotation,
        forceSquare: set.forceSquare,
      );
    }
    debugPrint(
      '[Raw View] Baked Atlas: ${bakedAtlas?.image.width}x${bakedAtlas?.image.height}',
    );
  }

  @override
  void update(double dt) {}

  @override
  void render(Canvas canvas) {
    if (bakedAtlas == null) return;
    final image = bakedAtlas!.image;

    canvas.save();
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = ui.FilterQuality.none,
    );

    // Draw borders for each sprite
    final p = Paint()
      ..color = const Color.fromARGB(255, 255, 0, 0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final sprite in bakedAtlas!.sprites) {
      final r = sprite.region;
      final w = r.rotate ? r.height : r.width;
      final h = r.rotate ? r.width : r.height;
      canvas.drawRect(
        ui.Rect.fromLTWH(
          r.left.toDouble(),
          r.top.toDouble(),
          w.toDouble(),
          h.toDouble(),
        ),
        p,
      );
    }

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Paint()
        ..color = Colors.greenAccent.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();

    final tp = TextPainter(
      text: TextSpan(
        text:
            'Baked Atlas View: ${image.width.toInt()}x${image.height.toInt()}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(20, image.height + 20));
  }
}
