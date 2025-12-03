import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'region_model.dart';

class RegionsRepository {
  static final Map<String, Region> _regions = {
    // Africa (optional, keep if you have this file)
    'africa': Region(
      id: 'africa',
      name: 'Africa',
      // If you have this, leave it. Otherwise remove this entry or add the file.
      geoJsonPath: 'assets/data/africa.geojson',
      center: LatLng(8.7832, 34.5085),
      zoomLevel: 3,
    ),

    // Cameroon
    'cameroon': Region(
      id: 'cameroon',
      name: 'Cameroon',
      geoJsonPath: 'assets/data/cameroon.geojson', // <— fixed
      mapTilePath: 'assets/maps/cameroon.mbtiles',
      center: LatLng(7.3697, 12.3547),
      zoomLevel: 6,
    ),

    // Ghana
    'ghana': Region(
      id: 'ghana',
      name: 'Ghana',
      geoJsonPath: 'assets/data/ghana.geojson', // <— fixed
      mapTilePath: 'assets/maps/ghana.mbtiles',
      center: LatLng(7.9465, -1.0232),
      zoomLevel: 7,
    ),

    // Kenya
    'kenya': Region(
      id: 'kenya',
      name: 'Kenya',
      geoJsonPath: 'assets/data/kenya.geojson', // <— fixed
      mapTilePath: 'assets/maps/kenya.mbtiles',
      center: LatLng(-0.0236, 37.9062),
      zoomLevel: 6,
    ),

    // Nigeria (country level)
    'nigeria': Region(
      id: 'nigeria',
      name: 'Nigeria',
      // Use the file you actually have. If you only have `nigeria.geojson`, use that:
      geoJsonPath: 'assets/data/nigeria.geojson', // <— replace full.geojson
      mapTilePath: 'assets/maps/nigeria.mbtiles',
      center: LatLng(9.0820, 8.6753),
      zoomLevel: 6,
    ),
  };

  /// Top-level regions (no parent)
  static List<Region> getCountries() =>
      _regions.values.where((r) => r.parentId == null).toList();

  /// All regions
  static List<Region> getAll() => _regions.values.toList();

  /// Lookup by id (case-insensitive)
  static Region? getById(String id) => _regions[id.toLowerCase()];

  /// Sub-regions of a parent
  static List<Region> getSubRegions(String parentId) =>
      _regions.values.where((r) => r.parentId == parentId.toLowerCase()).toList();

  /// Search by name
  static List<Region> search(String query) =>
      _regions.values.where((r) => r.name.toLowerCase().contains(query.toLowerCase())).toList();
}
