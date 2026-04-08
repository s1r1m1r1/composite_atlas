//region Raw Atlas Viewer Screen
import 'package:example/main.dart';
import 'package:flutter/material.dart';

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