import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:meta/meta.dart';

// ─── Common packer interface ───────────────────────────────────────────────
@internal
abstract class AtlasPacker {
  ({ui.Offset offset, bool rotated})? pack(
    double w,
    double h, {
    bool allowRotation,
  });

  void growToFit(double w, double h, {bool allowRotation});

  abstract double _currentWidth;
  double get currentWidth => _currentWidth;
  abstract double _currentHeight;
  double get currentHeight => _currentHeight;
}

// ─── Fast Guillotine (runtime) ──────────────────────────────────────────────
/// Guillotine bin-packing with Shortest-Axis-First split heuristic.
/// O(n log n) speed, good for runtime atlas baking.
@internal
class GuillotinePacker implements AtlasPacker {
  final double maxWidth;
  final List<ui.Rect> _freeRects = [];
  @override
  double _currentWidth;
  @override
  double _currentHeight;

  GuillotinePacker(double initialSide)
    : maxWidth = 4096.0,
      _currentWidth = initialSide,
      _currentHeight = initialSide {
    _freeRects.add(ui.Rect.fromLTWH(0, 0, initialSide, initialSide));
  }

  @override
  ({ui.Offset offset, bool rotated})? pack(
    double w,
    double h, {
    bool allowRotation = true,
  }) {
    // Best short-side fit — minimizes leftover space on the shorter axis
    int bestIdx = -1;
    double bestShort = double.infinity;
    bool rotated = false;

    for (int i = 0; i < _freeRects.length; i++) {
      final r = _freeRects[i];

      // Original orientation
      if (r.width >= w - 0.0001 && r.height >= h - 0.0001) {
        final leftover = math.min(r.width - w, r.height - h);
        if (leftover < bestShort) {
          bestShort = leftover;
          bestIdx = i;
          rotated = false;
        }
      }

      // Rotated
      if (allowRotation && r.width >= h - 0.0001 && r.height >= w - 0.0001) {
        final leftover = math.min(r.width - h, r.height - w);
        if (leftover < bestShort) {
          bestShort = leftover;
          bestIdx = i;
          rotated = true;
        }
      }
    }

    if (bestIdx == -1) return null;

    final rect = _freeRects.removeAt(bestIdx);
    final useW = rotated ? h : w;
    final useH = rotated ? w : h;
    _split(rect, useW, useH);
    return (offset: ui.Offset(rect.left, rect.top), rotated: rotated);
  }

  @override
  void growToFit(double w, double h, {bool allowRotation = true}) {
    // Ensure width can fit the sprite (or its rotated form)
    final double neededWidth = allowRotation ? math.min(w, h) : w;
    while (_currentWidth < neededWidth && _currentWidth < 4096) {
      _currentWidth *= 2;
    }

    // Grow height only when necessary — no fixed minimums.
    final double neededHeight = h;
    _freeRects.add(
      ui.Rect.fromLTWH(0, _currentHeight, _currentWidth, neededHeight),
    );
    _currentHeight += neededHeight;
  }

  void _split(ui.Rect rect, double w, double h) {
    final freeW = rect.width - w;
    final freeH = rect.height - h;

    if (freeW < freeH) {
      if (freeW > 0.0001) {
        _freeRects.add(ui.Rect.fromLTWH(rect.left + w, rect.top, freeW, h));
      }
      if (freeH > 0.0001) {
        _freeRects.add(
          ui.Rect.fromLTWH(rect.left, rect.top + h, rect.width, freeH),
        );
      }
    } else {
      if (freeH > 0.0001) {
        _freeRects.add(ui.Rect.fromLTWH(rect.left, rect.top + h, w, freeH));
      }
      if (freeW > 0.0001) {
        _freeRects.add(
          ui.Rect.fromLTWH(rect.left + w, rect.top, freeW, rect.height),
        );
      }
    }
  }

  @override
  double get currentWidth => _currentWidth;
  @override
  double get currentHeight => _currentHeight;

  void mergeFreeRects() {
    final merged = <ui.Rect>[];
    final used = List<bool>.filled(_freeRects.length, false);

    for (int i = 0; i < _freeRects.length; i++) {
      if (used[i]) continue;
      var current = _freeRects[i];
      used[i] = true;

      bool mergedAny;
      do {
        mergedAny = false;
        for (int j = i + 1; j < _freeRects.length; j++) {
          if (used[j]) continue;
          final other = _freeRects[j];
          final merged_ = tryMerge(current, other);
          if (merged_ != null) {
            current = merged_;
            used[j] = true;
            mergedAny = true;
          }
        }
      } while (mergedAny);

      merged.add(current);
    }

    _freeRects.clear();
    _freeRects.addAll(merged);
  }

  static ui.Rect? tryMerge(ui.Rect a, ui.Rect b) {
    if ((a.left - b.left).abs() < 0.0001 &&
        (a.width - b.width).abs() < 0.0001) {
      if ((a.bottom - b.top).abs() < 0.0001) {
        return ui.Rect.fromLTWH(a.left, a.top, a.width, a.height + b.height);
      }
      if ((a.top - b.bottom).abs() < 0.0001) {
        return ui.Rect.fromLTWH(a.left, b.top, a.width, a.height + b.height);
      }
    }
    if ((a.top - b.top).abs() < 0.0001 &&
        (a.height - b.height).abs() < 0.0001) {
      if ((a.right - b.left).abs() < 0.0001) {
        return ui.Rect.fromLTWH(a.left, a.top, a.width + b.width, a.height);
      }
      if ((a.left - b.right).abs() < 0.0001) {
        return ui.Rect.fromLTWH(b.left, a.top, a.width + b.width, a.height);
      }
    }
    return null;
  }
}

// ─── MaxRects (optimal / prebuild) ──────────────────────────────────────────
/// MaxRects bin-packing with Best-Area-Fit heuristic + free rect merging.
/// Slower but denser packing — ideal for pre-build / dev workflows.
@internal
class MaxRectsPacker implements AtlasPacker {
  final List<ui.Rect> _freeRects = [];
  @override
  double _currentWidth;
  @override
  double _currentHeight;

  MaxRectsPacker(double initialSide)
    : _currentWidth = initialSide,
      _currentHeight = initialSide {
    _freeRects.add(ui.Rect.fromLTWH(0, 0, initialSide, initialSide));
  }

  @override
  ({ui.Offset offset, bool rotated})? pack(
    double w,
    double h, {
    bool allowRotation = true,
  }) {
    int bestIdx = -1;
    double bestArea = double.infinity;
    double bestShort = double.infinity;
    bool rotated = false;

    for (int i = 0; i < _freeRects.length; i++) {
      final r = _freeRects[i];

      if (r.width >= w - 0.0001 && r.height >= h - 0.0001) {
        final area = r.width * r.height;
        final leftover = math.min(r.width - w, r.height - h);
        if (area < bestArea || (area == bestArea && leftover < bestShort)) {
          bestArea = area;
          bestShort = leftover;
          bestIdx = i;
          rotated = false;
        }
      }

      if (allowRotation && r.width >= h - 0.0001 && r.height >= w - 0.0001) {
        final area = r.width * r.height;
        final leftover = math.min(r.width - h, r.height - w);
        if (area < bestArea || (area == bestArea && leftover < bestShort)) {
          bestArea = area;
          bestShort = leftover;
          bestIdx = i;
          rotated = true;
        }
      }
    }

    if (bestIdx == -1) return null;

    final rect = _freeRects.removeAt(bestIdx);
    final useW = rotated ? h : w;
    final useH = rotated ? w : h;
    _placeRect(rect, useW, useH);
    return (offset: ui.Offset(rect.left, rect.top), rotated: rotated);
  }

  @override
  void growToFit(double w, double h, {bool allowRotation = true}) {
    final double neededWidth = allowRotation ? math.min(w, h) : w;
    while (_currentWidth < neededWidth && _currentWidth < 4096) {
      _currentWidth *= 2;
    }

    _freeRects.add(ui.Rect.fromLTWH(0, _currentHeight, _currentWidth, h));
    _currentHeight += h;
  }

  void _placeRect(ui.Rect rect, double w, double h) {
    final newFree = <ui.Rect>[];
    for (int i = 0; i < _freeRects.length; i++) {
      final fr = _freeRects[i];
      if (_intersect(fr, rect)) {
        if (fr.left < rect.left) {
          newFree.add(
            ui.Rect.fromLTWH(fr.left, fr.top, rect.left - fr.left, fr.height),
          );
        }
        if (fr.right > rect.right) {
          newFree.add(
            ui.Rect.fromLTWH(
              rect.right,
              fr.top,
              fr.right - rect.right,
              fr.height,
            ),
          );
        }
        if (fr.top < rect.top) {
          newFree.add(
            ui.Rect.fromLTWH(
              math.max(fr.left, rect.left),
              fr.top,
              math.min(fr.right, rect.right) - math.max(fr.left, rect.left),
              rect.top - fr.top,
            ),
          );
        }
        if (fr.bottom > rect.bottom) {
          newFree.add(
            ui.Rect.fromLTWH(
              math.max(fr.left, rect.left),
              rect.bottom,
              math.min(fr.right, rect.right) - math.max(fr.left, rect.left),
              fr.bottom - rect.bottom,
            ),
          );
        }
      } else {
        newFree.add(fr);
      }
    }
    _freeRects.clear();
    _freeRects.addAll(
      newFree.where((r) => r.width > 0.001 && r.height > 0.001),
    );
    mergeFreeRects();
  }

  bool _intersect(ui.Rect a, ui.Rect b) {
    return a.left < b.right &&
        a.right > b.left &&
        a.top < b.bottom &&
        a.bottom > b.top;
  }

  void mergeFreeRects() {
    final merged = <ui.Rect>[];
    final used = List<bool>.filled(_freeRects.length, false);

    for (int i = 0; i < _freeRects.length; i++) {
      if (used[i]) continue;
      var current = _freeRects[i];
      used[i] = true;

      bool mergedAny;
      do {
        mergedAny = false;
        for (int j = i + 1; j < _freeRects.length; j++) {
          if (used[j]) continue;
          final other = _freeRects[j];
          final merged_ = GuillotinePacker.tryMerge(current, other);
          if (merged_ != null) {
            current = merged_;
            used[j] = true;
            mergedAny = true;
          }
        }
      } while (mergedAny);

      merged.add(current);
    }

    _freeRects.clear();
    _freeRects.addAll(merged);
  }

  @override
  double get currentWidth => _currentWidth;
  @override
  double get currentHeight => _currentHeight;
}
