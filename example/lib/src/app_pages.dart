import 'package:example/main.dart';
import 'package:flutter/material.dart';

import 'atlas_comparison_screen.dart';
import 'debug_shader_baking_screen.dart';
import 'raw_atlas_viewer_screen.dart';
import 'settings_screen.dart';

final List<AppPage> appPages = [
  AppPage(
    title: 'Atlas Comparison',
    icon: Icons.compare_arrows,
    builder: (_) => const AtlasComparisonScreen(),
  ),
  AppPage(
    title: 'Shader Baking Debug',
    icon: Icons.brush,
    builder: (_) => const DebugShaderBakingScreen(),
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
