import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:composite_atlas/src/packers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Packer Benchmarks', () {
    test('Standard Growth: Guillotine', () async {
      final counts = [100, 500, 1000];
      
      print('\n' + '=' * 85);
      print('SCENARIO: Standard Growth (Random Distribution, Sorted by Height)');
      print('${"Count".padRight(10)} | ${"Packer".padRight(12)} | ${"Time (ms)".padRight(10)} | ${"Fill %".padRight(10)} | ${"Final Size".padRight(15)}');
      print('-' * 85);

      for (final count in counts) {
        final sizes = _generateRandomSizes(count, seed: 42);
        sizes.sort((a, b) => b.height.compareTo(a.height));
        
        _runBenchmark(count, 'Guillotine', GuillotinePacker(1024.0), sizes);
        print('-' * 85);
      }
      print('=' * 85 + '\n');
    });

    test('Stress Test: Big & Small Mix', () async {
      final sizes = [
        ...List.generate(15, (_) => const ui.Size(256, 256)),
        ...List.generate(1000, (_) => const ui.Size(16, 16)),
      ];
      
      sizes.sort((a, b) => b.height.compareTo(a.height));

      print('\n' + '=' * 85);
      print('SCENARIO: Stress Test (15 Large 256x256 + 1000 Small 16x16, Sorted)');
      print('${"Count".padRight(10)} | ${"Packer".padRight(12)} | ${"Time (ms)".padRight(10)} | ${"Fill %".padRight(10)} | ${"Final Size".padRight(15)}');
      print('-' * 85);

      _runBenchmark(sizes.length, 'Guillotine', GuillotinePacker(1024.0), sizes);
      print('=' * 85 + '\n');
    });
  });
}

List<ui.Size> _generateRandomSizes(int count, {required int seed}) {
  final rng = math.Random(seed);
  return List.generate(count, (_) {
    final isSmall = rng.nextDouble() < 0.7;
    final double w = isSmall ? (rng.nextDouble() * 32 + 8) : (rng.nextDouble() * 128 + 32);
    final double h = isSmall ? (rng.nextDouble() * 32 + 8) : (rng.nextDouble() * 128 + 32);
    return ui.Size(w.roundToDouble(), h.roundToDouble());
  });
}

void _runBenchmark(int count, String name, AtlasPacker packer, List<ui.Size> sizes) {
  final sw = Stopwatch()..start();
  
  double totalSpriteArea = 0;
  for (final size in sizes) {
    totalSpriteArea += size.width * size.height;
    
    var result = packer.pack(size.width, size.height, allowRotation: true);
    int growAttempts = 0;
    while (result == null && growAttempts < 20) {
      // Grow more aggressively in height to avoid fragmentation overload
      packer.growToFit(size.width, 256.0, allowRotation: true);
      
      if (packer is GuillotinePacker) packer.mergeFreeRects();
      
      result = packer.pack(size.width, size.height, allowRotation: true);
      growAttempts++;
    }
  }
  
  sw.stop();
  
  final finalArea = packer.currentWidth * packer.currentHeight;
  final fillRate = (totalSpriteArea / finalArea) * 100;
  
  final countStr = count.toString().padRight(10);
  final nameStr = name.padRight(12);
  final timeStr = sw.elapsedMilliseconds.toString().padRight(10);
  final fillStr = '${fillRate.toStringAsFixed(1)}%'.padRight(10);
  final sizeStr = '${packer.currentWidth.toInt()}x${packer.currentHeight.toInt()}'.padRight(15);
  
  print('$countStr | $nameStr | $timeStr | $fillStr | $sizeStr');
}
