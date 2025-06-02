import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  final String? currentRegionKey;
  final void Function(String regionKey, String geojsonPath) onRegionSelected;

  const HomeScreen({
    super.key,
    this.currentRegionKey,
    required this.onRegionSelected,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late List<Map<String, String>> regions;
  String? selectedRegionKey;

  @override
  void initState() {
    super.initState();

    regions = [
      {
        "key": "cameroon",
        "label": "Cameroon",
        "path": "assets/data/cameroon.geojson",
      },
      {
        "key": "cameroon_bamenda_ubc",
        "label": "Cameroon (Bamenda UBC)",
        "path": "assets/data/cameroon_bamenda_ubc.geojson",
      },
      {
        "key": "ghana",
        "label": "Ghana",
        "path": "assets/data/ghana.geojson",
      },
      {
        "key": "kenya",
        "label": "Kenya",
        "path": "assets/data/kenya.geojson",
      },
      {
        "key": "nigeria_abj",
        "label": "Nigeria (Abuja)",
        "path": "assets/data/nigeria_abj.geojson",
      },
      {
        "key": "nigeria_lagos",
        "label": "Nigeria (Lagos)",
        "path": "assets/data/nigeria_lagos.geojson",
      },
    ];

    // Set default to current region if provided
    selectedRegionKey = widget.currentRegionKey?.toLowerCase() ?? regions.first['key'];
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Select Region to View Land Map",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DropdownButton<String>(
              value: selectedRegionKey,
              hint: const Text("Choose a region"),
              items: regions.map((region) {
                return DropdownMenuItem(
                  value: region['key'],
                  child: Text(region['label'] ?? ''),
                );
              }).toList(),
              onChanged: (value) {
                final selected = regions.firstWhere((r) => r['key'] == value);
                setState(() => selectedRegionKey = value);
                widget.onRegionSelected(selected['key']!, selected['path']!);
              },
            ),
          ],
        ),
      ),
    );
  }
}
