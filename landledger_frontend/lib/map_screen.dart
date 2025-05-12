import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

class MapScreen extends StatefulWidget {
  final String regionKey;
  final String geojsonPath;
  final List<LatLng>? highlightPolygon;

  const MapScreen({
    Key? key,
    required this.regionKey,
    required this.geojsonPath,
    this.highlightPolygon,
  }) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<Polygon> polygons = [];
  List<Map<String, dynamic>> polygonProperties = [];
  List<List<LatLng>> polygonPointsList = [];
  bool isDrawing = false;
  List<LatLng> currentPolygonPoints = [];
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    loadGeoJson();
  }

  Future<void> loadGeoJson() async {
    try {
      final geoJsonStr = await rootBundle.loadString(widget.geojsonPath);
      final geoData = json.decode(geoJsonStr);

      final List<Polygon> loadedPolygons = [];
      final List<Map<String, dynamic>> properties = [];
      LatLngBounds? bounds;

      for (var feature in geoData['features']) {
        final coords = feature['geometry']['coordinates'][0];
        final latLngList = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();

        for (var point in latLngList) {
          bounds ??= LatLngBounds(point, point);
          bounds.extend(point);
        }

        loadedPolygons.add(
          Polygon(
            points: latLngList,
            borderColor: Colors.green,
            color: Colors.green.withOpacity(0.3),
            borderStrokeWidth: 2,
            isFilled: true,
          ),
        );

        polygonPointsList.add(latLngList);
        properties.add(feature['properties']);
      }

      setState(() {
        polygons = loadedPolygons;
        polygonProperties = properties;
      });

      if (widget.highlightPolygon != null) {
        final highlightBounds = LatLngBounds(widget.highlightPolygon!.first, widget.highlightPolygon!.first);
        for (var point in widget.highlightPolygon!) {
          highlightBounds.extend(point);
        }
        _mapController.fitBounds(
          highlightBounds,
          options: const FitBoundsOptions(padding: EdgeInsets.all(40)),
        );
      } else if (bounds != null) {
        _mapController.fitBounds(
          bounds,
          options: const FitBoundsOptions(padding: EdgeInsets.all(40)),
        );
      }
    } catch (e) {
      debugPrint("Failed to load GeoJSON: $e");
    }
  }

  void _handlePolygonTap(Map<String, dynamic> properties) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Property Info"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Title: ${properties['title_number'] ?? 'N/A'}"),
            Text("Owner: ${properties['owner'] ?? 'Unknown'}"),
            Text("Description: ${properties['description'] ?? ''}"),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Map: ${widget.regionKey.toUpperCase()}"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          center: LatLng(0, 0),
          zoom: 10,
          onTap: (tapPosition, point) {
            if (isDrawing) {
              setState(() => currentPolygonPoints.add(point));
            } else {
              for (int i = 0; i < polygonPointsList.length; i++) {
                final polygon = polygonPointsList[i];
                if (_pointInPolygon(point, polygon)) {
                  _handlePolygonTap(polygonProperties[i]);
                  break;
                }
              }
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            subdomains: ['a', 'b', 'c'],
          ),
          if (currentPolygonPoints.length >= 2)
            PolygonLayer(
              polygons: [
                Polygon(
                  points: currentPolygonPoints,
                  borderColor: Colors.orange,
                  color: Colors.orange.withOpacity(0.4),
                  borderStrokeWidth: 2.0,
                )
              ],
            ),
          PolygonLayer(polygons: polygons),
          if (widget.highlightPolygon != null)
            PolygonLayer(
              polygons: [
                Polygon(
                  points: widget.highlightPolygon!,
                  borderColor: Colors.red,
                  color: Colors.red.withOpacity(0.4),
                  borderStrokeWidth: 3,
                )
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: Icon(isDrawing ? Icons.save : Icons.edit),
        label: Text(isDrawing ? "Save Region" : "Add Region"),
        onPressed: () {
          setState(() {
            isDrawing = !isDrawing;
            if (!isDrawing) currentPolygonPoints.clear();
          });
        },
      ),
    );
  }

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    int i, j = polygon.length - 1;
    bool oddNodes = false;

    for (i = 0; i < polygon.length; i++) {
      if ((polygon[i].latitude < point.latitude && polygon[j].latitude >= point.latitude ||
              polygon[j].latitude < point.latitude && polygon[i].latitude >= point.latitude) &&
          (polygon[i].longitude <= point.longitude || polygon[j].longitude <= point.longitude)) {
        if (polygon[i].longitude + (point.latitude - polygon[i].latitude) /
                (polygon[j].latitude - polygon[i].latitude) *
                (polygon[j].longitude - polygon[i].longitude) <
            point.longitude) {
          oddNodes = !oddNodes;
        }
      }
      j = i;
    }

    return oddNodes;
  }
}
