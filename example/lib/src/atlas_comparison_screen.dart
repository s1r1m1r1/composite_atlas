//region Atlas Comparison Screen
import 'package:example/main.dart';
import 'package:flutter/material.dart';

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