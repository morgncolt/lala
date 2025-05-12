import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'map_screen.dart';
import 'dashboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedRegion;
  bool _locationTried = false;

  final Map<String, String> _regionToGeojson = {
    "Cameroon":             "assets/data/cameroon.geojson",
    "Ghana":                "assets/data/ghana.geojson",
    "Nigeria - Abuja":      "assets/data/nigeria_abj.geojson",
    "Nigeria - Lagos":      "assets/data/nigeria_lagos.geojson",
    "Kenya":                "assets/data/kenya.geojson",
  };

  @override
  void initState() {
    super.initState();
    _determineRegionFromLocation();
  }

  Future<void> _determineRegionFromLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        final regionsData = await rootBundle.loadString('assets/data/regions.geojson');
        final regions = json.decode(regionsData);

        for (var feature in regions['features']) {
          final name = feature['properties']['name'];
          final coords = feature['geometry']['coordinates'][0];
          final polygon = coords.map<Offset>((c) => Offset(c[0].toDouble(), c[1].toDouble())).toList();

          if (_pointInPolygon(Offset(position.longitude, position.latitude), polygon)) {
            setState(() {
              _selectedRegion = name;
              _locationTried = true;
            });
            return;
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ Error determining location: $e");
    }

    setState(() => _locationTried = true);
  }

  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    int i, j = polygon.length - 1;
    bool oddNodes = false;

    for (i = 0; i < polygon.length; i++) {
      if ((polygon[i].dy < point.dy && polygon[j].dy >= point.dy ||
          polygon[j].dy < point.dy && polygon[i].dy >= point.dy) &&
          (polygon[i].dx <= point.dx || polygon[j].dx <= point.dx)) {
        if (polygon[i].dx + (point.dy - polygon[i].dy) / (polygon[j].dy - polygon[i].dy) *
            (polygon[j].dx - polygon[i].dx) < point.dx) {
          oddNodes = !oddNodes;
        }
      }
      j = i;
    }

    return oddNodes;
  }

  void _enterMap() {
    final geojsonPath = _regionToGeojson[_selectedRegion!];
    if (geojsonPath != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            regionKey: _selectedRegion!,
            geojsonPath: geojsonPath,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xF9FBF7),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('LandLedger Dashboard', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            Text('Welcome, ${_selectedRegion ?? (_locationTried ? "please select region" : "detecting...")}'),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: _selectedRegion,
              hint: const Text("Select Region"),
              items: _regionToGeojson.keys.map((String region) {
                return DropdownMenuItem<String>(
                  value: region,
                  child: Text(region),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedRegion = newValue!;
                });
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _selectedRegion != null ? _enterMap : null,
              icon: const Icon(Icons.map),
              label: const Text("Enter Map"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
