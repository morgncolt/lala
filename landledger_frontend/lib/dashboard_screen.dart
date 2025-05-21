import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:landledger_frontend/map_screen.dart';
import 'package:landledger_frontend/my_properties_screen.dart';
import 'package:landledger_frontend/login_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String? regionKey;
  final String? geojsonPath;
  final int initialTabIndex;

  const DashboardScreen({
    super.key,
    this.regionKey,
    this.geojsonPath,
    this.initialTabIndex = 0,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  String? _detectedRegionKey;
  String? _geojsonPath;

  final List<String> _menuItems = [
    "Home",
    "Map View",
    "My Properties",
    "Add Listing",
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
    _selectedIndex = widget.initialTabIndex;
    _detectedRegionKey = widget.regionKey?.toLowerCase();
    _geojsonPath = widget.geojsonPath;
    detectRegionIfNeeded();
  }

  Future<void> detectRegionIfNeeded() async {
    if (_detectedRegionKey != null && _geojsonPath != null) return;

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

  void logoutUser(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    switch (_selectedIndex) {
      case 0:
        content = Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, size: 48, color: Colors.blue),
                    const SizedBox(height: 16),
                    Text(
                      'Hi ${FirebaseAuth.instance.currentUser?.displayName ?? "there"}!',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text('Select your region to get started.'),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      value: _detectedRegionKey,
                      hint: const Text("Choose your region"),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: _regionToGeojson.keys.map((String region) {
                        return DropdownMenuItem<String>(
                          value: region.toLowerCase(),
                          child: Text(region),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _detectedRegionKey = newValue;
                            _geojsonPath = _regionToGeojson.entries
                                .firstWhere((e) => e.key.toLowerCase() == newValue)
                                .value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: (_detectedRegionKey != null && _geojsonPath != null)
                          ? () => setState(() => _selectedIndex = 1)
                          : null,
                      icon: const Icon(Icons.map),
                      label: const Text("Enter Land Map"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _detectedRegionKey == null
                          ? "You can select a region manually above."
                          : "Region selected: $_detectedRegionKey",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        break;
      case 1:
        content = (_geojsonPath != null && _detectedRegionKey != null)
            ? MapScreen(regionKey: _detectedRegionKey!, geojsonPath: _geojsonPath!)
            : const Center(child: CircularProgressIndicator());
        break;
      case 2:
        content = (_geojsonPath != null && _detectedRegionKey != null)
            ? MyPropertiesScreen(regionKey: _detectedRegionKey!, geojsonPath: _geojsonPath!)
            : const Center(child: CircularProgressIndicator());
        break;
      case 3:
        content = const Center(child: Text("Add Listing Page (Coming Soon)"));
        break;
      case 4:
        content = const Center(child: Text("Settings Page (Coming Soon)"));
        break;
      default:
        content = const Center(child: Text("Page not found"));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("LandLedger Africa"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => logoutUser(context),
          ),
        ],
      ),
      body: Row(
        children: [
          Column(
            children: [
              Expanded(
                child: NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.map_outlined),
                      selectedIcon: Icon(Icons.map),
                      label: Text('Map View'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.list_alt_outlined),
                      selectedIcon: Icon(Icons.list_alt),
                      label: Text('My Properties'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.add_circle_outline),
                      selectedIcon: Icon(Icons.add_circle),
                      label: Text('Add Listing'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                ),
              ),
              const Divider(thickness: 1),
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: IconButton(
                  icon: const Icon(Icons.logout, color: Colors.red),
                  tooltip: 'Logout',
                  onPressed: () => logoutUser(context),
                ),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}