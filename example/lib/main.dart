import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/sprite.dart';
import 'package:flame_texturepacker/flame_texturepacker.dart';
import 'package:flutter/material.dart';
import 'package:composite_atlas/composite_atlas.dart';
import 'dart:ui' as ui;

void main() {
  runApp(const MaterialApp(home: AtlasViewerApp()));
}

class AtlasSet {
  final String name;
  final String atlasPath;
  final String imagePath;
  final String simpleAtlasPath;
  final bool allowRotation;
  final bool forceSquare;

  AtlasSet({
    required this.name,
    required this.atlasPath,
    required this.imagePath,
    required this.simpleAtlasPath,
    required this.allowRotation,
    this.forceSquare = false,
  });
}

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
];

class AtlasViewerApp extends StatefulWidget {
  const AtlasViewerApp({super.key});

  @override
  State<AtlasViewerApp> createState() => _AtlasViewerAppState();
}

class _AtlasViewerAppState extends State<AtlasViewerApp> {
  bool _showRaw = false;
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
            icon: Icon(_showRaw ? Icons.compare : Icons.grid_view),
            onPressed: () => setState(() => _showRaw = !_showRaw),
            tooltip: _showRaw ? 'Show Comparison' : 'Show Raw Atlas',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _showRaw
          ? RawAtlasView(key: ValueKey('raw_$_setIndex'), set: _set)
          : ComparisonView(
              key: ValueKey('comp_$_setIndex'),
              set: _set,
              onToggleRaw: () => setState(() => _showRaw = true),
            ),
    );
  }
}

class ComparisonView extends StatefulWidget {
  final AtlasSet set;
  final VoidCallback onToggleRaw;
  const ComparisonView({
    super.key,
    required this.set,
    required this.onToggleRaw,
  });

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
              onPressed: widget.onToggleRaw,
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

class RawAtlasView extends StatefulWidget {
  final AtlasSet set;
  const RawAtlasView({super.key, required this.set});

  @override
  State<RawAtlasView> createState() => _RawAtlasViewState();
}

class _RawAtlasViewState extends State<RawAtlasView> {
  late RawAtlasGame _game;

  @override
  void initState() {
    super.initState();
    _game = RawAtlasGame(widget.set);
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
    originalAtlas = await TexturePackerAtlas.load(set.atlasPath);
    referenceAtlas = await TexturePackerAtlas.load(set.simpleAtlasPath);

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
      referenceTicker!.getSprite() as TexturePackerSprite,
    );
    _renderMeta(
      canvas,
      size.x / 2,
      size.y / 2 + 180,
      originalTicker!.getSprite() as TexturePackerSprite,
    );
    _renderMeta(
      canvas,
      size.x * 5 / 6,
      size.y / 2 + 180,
      bakedTicker!.getSprite() as TexturePackerSprite,
      compareWith: referenceTicker!.getSprite() as TexturePackerSprite,
    );
  }

  void _renderMeta(
    Canvas canvas,
    double x,
    double y,
    TexturePackerSprite s, {
    TexturePackerSprite? compareWith,
  }) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final r = s.region;
    final cr = compareWith?.region;

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
    final atlas = await TexturePackerAtlas.load(set.atlasPath);
    // Use rotation for Experiment 1 (Rotated-Packed) but not for Experiment 0 (Aligned)
    final bool useRotation = set.name.contains('Rotated-Packed');

    bakedAtlas = await CompositeAtlas.bake(
      [AtlasBakeRequest(atlas)],
      maxAtlasWidth: 128.0,
      allowRotation: useRotation,
      forceSquare: set.forceSquare,
    );
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
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (final sprite in bakedAtlas!.sprites) {
      final r = sprite.region;
      canvas.drawRect(
        ui.Rect.fromLTWH(
          r.left.toDouble(),
          r.top.toDouble(),
          r.width.toDouble(),
          r.height.toDouble(),
        ),
        p,
      );
    }

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Paint()
        ..color = Colors.greenAccent.withOpacity(0.1)
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
