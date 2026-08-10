# composite_atlas

A runtime-composed texture atlas library for Flutter/Flame games. Merges multiple texture sources into a single atlas to **minimize draw calls**, **reduce memory**, and enable **runtime texture manipulation**.

## Purpose

### Runtime Use Cases
- **Per-level atlas baking** — compose a dedicated atlas before loading a game level, containing only the sprites needed for that level
- **Composite characters** — dynamically combine character parts (body, armor, weapon) into a single texture at runtime
- **Runtime shader effects** — bake color-shifted, filtered, or decorated variants of sprites without pre-generating assets
- **Draw call reduction** — batch sprites from multiple source atlases into one mega-atlas for fewer GPU state changes

### Development / Pre-build Use Cases
- **Asset preparation** — pre-bake atlases during development to reduce final game bundle size
- **Smaller storage** — eliminate redundant transparent pixels across hundreds of individual sprite files
- **Format conversion** — re-pack GDX TexturePacker atlases with different settings (rotation, padding, dedup)

## Features

### Multiple Source Types

| Request Type | Purpose |
|---|---|
| `AtlasBakeRequest` | Bake an entire `TexturePackerAtlas` (optionally filtered by whitelist) |
| `SpriteBakeRequest` | Bake a single `Sprite` with an explicit name |
| `ImageBakeRequest` | Bake a raw `ui.Image` as a named entry |

### GDX TexturePacker Compatibility

Reads atlases created by **libGDX TexturePacker** and preserves all metadata:
- `offsetX`, `offsetY` — sprite positioning within original frame
- `originalWidth`, `originalHeight` — pre-trim dimensions
- `rotate` — 90° CCW rotation flag
- `index` — animation frame ordering

Sprites baked from GDX atlases maintain **identical offsets and dimensions** as the source, ensuring pixel-perfect visual equivalence.

### Alpha Trimming

Scans the alpha channel of each sprite to find the tight non-transparent bounding box. Eliminates wasted transparent space, producing a more compact atlas. Automatically disabled for GDX sources (already optimally trimmed).

### Frame Deduplication

Detects sprites with **identical pixel content** and reuses a single packed slot for all duplicates — exactly like GDX TexturePacker. Uses pixel-level hashing to catch duplicates even when source positions differ:

```
[CompositeAtlas] Dedup: 3 duplicate(s) will reuse master slots
[CompositeAtlas] After dedup: 6 master slots (from 9)
```

### Packing Algorithm

The library uses a highly optimized **Guillotine** bin-packing algorithm with the **Shortest-Axis-First (SAF)** split heuristic. When combined with height-descending sorting, it achieves near-optimal density (>95% fill rate) while maintaining high performance (bakes 1000+ sprites in <5ms).

### Power-of-Two Output

Atlas dimensions are always rounded up to the nearest power of two (64, 128, 256, 512, 1024, 2048), compatible with GPU texture requirements.

### Sprite Animation Support

Indexed sprites (GDX `index:` field) are automatically detected and assembled into `SpriteAnimation` objects via `getAnimation()`.

### Decorators & Filters

- `ui.ColorFilter` — apply color transformations (hue shift, tint, etc.)
- `AtlasDecorator` — custom shaders with access to the full source atlas texture coordinates
- `BakePadding` — add outlines, shadows, glows with automatic canvas expansion

## Supported Formats

- **PNG8888** — 32-bit RGBA with full alpha (8 bits per channel)

## Quick Start

```dart
import 'package:composite_atlas/composite_atlas.dart';

// Bake multiple atlases into one
final atlas = await CompositeAtlas.bake([
  AtlasBakeRequest(gdxAtlas),
  AtlasBakeRequest(gdxAtlas2, whiteList: ['ui_']),
  SpriteBakeRequest(mySprite, name: 'hero'),
  ImageBakeRequest(icon, name: 'icon'),
], maxAtlasWidth: 1024.0, allowRotation: true);

// Use with Flame like a regular TexturePackerAtlas
final sprite = atlas.findSpriteByName('hero');
final anim = atlas.getAnimation('boy', stepTime: 0.1);

// Export (example app)
final byteData = await atlas.image.toByteData(format: ImageByteFormat.png);
```

## Example App

The `example/` directory includes a demo application with:
- **Atlas Comparison** — 3-way side-by-side sprite comparison (original vs GDX vs baked)
- **Raw Atlas Viewer** — inspect the baked atlas texture with zoom/pan
- **Export** — save baked atlas as PNG + GDX-compatible `.atlas` metadata file

Run it with:
```bash
cd example && flutter run -d macos
```

## Roadmap

Upcoming features and improvements:

- [ ] **Isolate-based Baking** — Offload alpha scanning and bin-packing calculations to a background isolate to keep UI animations (loading screens) perfectly smooth.
- [ ] **Multi-page Atlas Support** — Support for generating multiple output textures when sprites exceed the maximum atlas size.
- [ ] **BakePadding & Effects** — Native support for adding outlines, shadows, and glows during the baking process with automatic frame expansion.
- [ ] **Web Support Optimization** — Efficient pixel handling for Flutter Web targets.
