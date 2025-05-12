import 'package:flutter/material.dart';
import 'my_properties_screen.dart';
import 'map_screen.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

class DashboardScreen extends StatefulWidget {
  final String? regionKey;
  final String? geojsonPath;

  const DashboardScreen({super.key, this.regionKey, this.geojsonPath});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  String? _detectedRegionKey;
  String? _geojsonPath;

  final List<String> _menuItems = [
    "My Properties",
    "Add Listing",
    "Map View",
    "Settings"
  ];

  final Map<String, String> _regionToGeojson = {
    "Cameroon": "assets/data/cameroon.geojson",
    "Ghana": "assets/data/ghana.geojson",
    "Nigeria - Abuja": "assets/data/nigeria_abj.geojson",
    "Nigeria - Lagos": "assets/data/nigeria_lagos.geojson",
    "Kenya": "assets/data/kenya.geojson",
  };

  @override
  void initState() {
    super.initState();
    detectRegion();
  }

  Future<void> detectRegion() async {
    try {
      final geoData = await rootBundle.loadString('assets/data/regions.geojson');
      final regions = json.decode(geoData);

      if (regions['features'].isNotEmpty) {
        final defaultRegion = regions['features'][0]['properties']['name'];
        final defaultGeojson = _regionToGeojson[defaultRegion] ?? "assets/data/cameroon.geojson";

        setState(() {
          _detectedRegionKey = defaultRegion.toLowerCase();
          _geojsonPath = defaultGeojson;
        });
      }
    } catch (e) {
      setState(() {
        _detectedRegionKey = "cameroon";
        _geojsonPath = "assets/data/cameroon.geojson";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    switch (_selectedIndex) {
      case 0:
        content = (_geojsonPath != null && _detectedRegionKey != null)
            ? MyPropertiesScreen(
                regionKey: _detectedRegionKey!,
                geojsonPath: _geojsonPath!,
              )
            : const Center(child: CircularProgressIndicator());
        break;
      case 1:
        content = const Center(child: Text("Add Listing Page (Coming Soon)"));
        break;
      case 2:
        content = (_geojsonPath != null && _detectedRegionKey != null)
            ? MapScreen(
                regionKey: _detectedRegionKey!,
                geojsonPath: _geojsonPath!,
              )
            : const Center(child: CircularProgressIndicator());
        break;
      case 3:
        content = const Center(child: Text("Settings Page (Coming Soon)"));
        break;
      default:
        content = const Center(child: Text("Page not found"));
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: _menuItems
                .map((label) => NavigationRailDestination(
                      icon: const Icon(Icons.circle),
                      selectedIcon: const Icon(Icons.circle_outlined),
                      label: Text(label),
                    ))
                .toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}
