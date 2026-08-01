import 'package:flutter/material.dart';

import '../main.dart';

import 'atlas_comparison_screen.dart';
import 'debug_shader_baking_screen.dart';
import 'debug_shader_group_baking_screen.dart';
import 'raw_atlas_viewer_screen.dart';
import 'settings_screen.dart';
import 'spritesheet_bake_screen.dart';
import 'atlas_rotation_bake_screen.dart';
import 'war_servant_test_screen.dart';
import 'pong_test_screen.dart';
import 'marker_calibration_screen.dart';

final List<AppPage> appPages = [
  AppPage(
    title: 'Atlas Comparison',
    icon: Icons.compare_arrows,
    builder: (_) => const AtlasComparisonScreen(),
  ),
  AppPage(
    title: 'Spritesheet Bake Test',
    icon: Icons.animation,
    builder: (_) => const SpritesheetBakeScreen(),
  ),
  AppPage(
    title: 'Atlas Rotation Bake',
    icon: Icons.rotate_right,
    builder: (_) => const AtlasRotationBakeScreen(),
  ),
  AppPage(
    title: 'Shader Baking Debug',
    icon: Icons.brush,
    builder: (_) => const DebugShaderBakingScreen(),
  ),
  AppPage(
    title: 'Shader Group Baking',
    icon: Icons.layers,
    builder: (_) => const DebugShaderGroupBakingScreen(),
  ),
  AppPage(
    title: 'Raw Atlas Viewer',
    icon: Icons.grid_view,
    builder: (_) => const RawAtlasViewerScreen(),
  ),
  AppPage(
    title: 'War Servant Test',
    icon: Icons.play_arrow,
    builder: (_) => const WarServantTestScreen(),
  ),
  AppPage(
    title: 'Marker Calibration',
    icon: Icons.adjust,
    builder: (_) => MarkerCalibrationScreen(),
  ),
  AppPage(
    title: 'Pong Test',
    icon: Icons.sports_esports,
    builder: (_) => const PongTestScreen(),
  ),
  AppPage(
    title: 'Settings',
    icon: Icons.settings,
    builder: (_) => const SettingsScreen(),
  ),
];
