import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';

class MapStyleOption {
  final String label;
  final String lyrsCode;

  MapStyleOption(this.label, this.lyrsCode);
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<Polygon> polygons = [];
  bool offlineTilesAvailable = false;

  int selectedStyleIndex = 0;

  final List<MapStyleOption> mapStyles = [
    MapStyleOption('Street', 'm'),
    MapStyleOption('Satellite', 's'),
    MapStyleOption('Terrain', 'p'),
  ];

  @override
  void initState() {
    super.initState();
    checkOfflineTiles().then((_) => loadGeoJson());
  }

  Future<void> checkOfflineTiles() async {
    if (kIsWeb || Platform.isWindows || Platform.isMacOS) {
      offlineTilesAvailable = false;
      return;
    }

    try {
      await rootBundle.load('assets/maps/tiles.mbtiles');
      offlineTilesAvailable = true;
    } catch (_) {
      offlineTilesAvailable = false;
    }

    setState(() {});
  }

  Future<void> loadGeoJson() async {
    try {
      final String geoJsonStr = await rootBundle.loadString('assets/data/regions.geojson');
      final Map<String, dynamic> geoData = json.decode(geoJsonStr);

      final List<Polygon> newPolygons = [];
      for (var feature in geoData['features']) {
        final coords = feature['geometry']['coordinates'][0]
            .map<LatLng>((c) => LatLng(c[1], c[0]))
            .toList();
        newPolygons.add(
          Polygon(
            points: coords,
            borderColor: Colors.green,
            color: Colors.green.withOpacity(0.3),
            borderStrokeWidth: 2.0,
          ),
        );
      }

      setState(() {
        polygons = newPolygons;
      });
    } catch (e) {
      debugPrint("Failed to load GeoJSON: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return Scaffold(
      appBar: AppBar(title: const Text("Land Ledger Viewer")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: ToggleButtons(
              isSelected: List.generate(mapStyles.length, (i) => i == selectedStyleIndex),
              onPressed: (int index) {
                setState(() {
                  selectedStyleIndex = index;
                });
              },
              children: mapStyles
                  .map((style) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(style.label),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                center: LatLng(5.0, 10.0),
                zoom: 12.0,
              ),
              children: [
                if (kIsWeb)
                  TileLayer(
                    urlTemplate:
                        "https://mt1.google.com/vt/lyrs=${mapStyles[selectedStyleIndex].lyrsCode}&x={x}&y={y}&z={z}",
                    userAgentPackageName: 'com.example.landledger_frontend',
                  )
                else if (isMobile && offlineTilesAvailable)
                  MbtilesTileLayer(
                    mbtilesFilename: 'assets/maps/tiles.mbtiles',
                    tileProvider: AssetTileProvider(),
                  )
                else
                  TileLayer(
                    urlTemplate:
                        "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                    subdomains: ['a', 'b', 'c'],
                  ),
                PolygonLayer(polygons: polygons),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
