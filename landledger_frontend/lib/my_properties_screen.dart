import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import 'map_screen.dart';

class MyPropertiesScreen extends StatefulWidget {
  final String regionKey;
  final String geojsonPath;

  const MyPropertiesScreen({
    super.key,
    required this.regionKey,
    required this.geojsonPath,
  });

  @override
  State<MyPropertiesScreen> createState() => _MyPropertiesScreenState();
}


class _MyPropertiesScreenState extends State<MyPropertiesScreen> {
  final List<String> geojsonPaths = [
    'assets/data/cameroon.geojson',
    'assets/data/ghana.geojson',
    'assets/data/nigeria_abj.geojson',
    'assets/data/nigeria_lagos.geojson',
    'assets/data/kenya.geojson',
  ];

  List<Map<String, dynamic>> properties = [];
  List<List<LatLng>> polygons = [];
  List<String> regionKeys = [];

  @override
  void initState() {
    super.initState();
    loadAllProperties();
  }

  Future<void> loadAllProperties() async {
    for (String path in geojsonPaths) {
      try {
        final jsonStr = await rootBundle.loadString(path);
        final jsonData = json.decode(jsonStr);
        final String region = path.split('/').last.split('.').first;

        for (var feature in jsonData['features']) {
          final coords = feature['geometry']['coordinates'][0];
          final points = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();

          setState(() {
            properties.add({
              ...feature['properties'],
              'region': region,
              'geojsonPath': path,
            });
            polygons.add(points);
            regionKeys.add(region);
          });
        }
      } catch (e) {
        debugPrint("Error loading properties from $path: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (properties.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: properties.length,
      itemBuilder: (context, index) {
        final prop = properties[index];
        final poly = polygons[index];
        return Card(
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 10),
          child: ListTile(
            title: Text("Title: ${prop['title_number'] ?? 'N/A'}"),
            subtitle: Text("Region: ${prop['region'] ?? 'N/A'}\nOwner: ${prop['owner'] ?? 'Unknown'}\nDescription: ${prop['description'] ?? ''}"),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MapScreen(
                    regionKey: prop['region'],
                    geojsonPath: prop['geojsonPath'],
                    highlightPolygon: poly,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
