//region Settings Screen
import 'package:flutter/material.dart';

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
