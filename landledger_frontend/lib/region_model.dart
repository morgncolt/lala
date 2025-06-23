import 'package:latlong2/latlong.dart';

class Region {
  final String id;
  final String name;
  final String geoJsonPath;
  final String? mapTilePath;
  final LatLng center;
  final double zoomLevel;
  final String? parentId;

  const Region({
    required this.id,
    required this.name,
    required this.geoJsonPath,
    this.mapTilePath,
    required this.center,
    this.zoomLevel = 10,
    this.parentId,
  });

  @override
  String toString() => name;
}