import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'region_model.dart';

class RegionsRepository {
  static final Map<String, Region> _regions = {
    // Africa Regions
    'africa': Region(
      id: 'africa',
      name: 'Africa',
      geoJsonPath: 'assets/data/regions/africa.geojson',
      center: LatLng(8.7832, 34.5085),
      zoomLevel: 3,
    ),

    // Cameroon
    'cameroon': Region(
      id: 'cameroon',
      name: 'Cameroon',
      geoJsonPath: 'assets/data/regions/cameroon.geojson',
      mapTilePath: 'assets/maps/cameroon.mbtiles',
      center: LatLng(7.3697, 12.3547),
      zoomLevel: 6,
    ),

    // Ghana
    'ghana': Region(
      id: 'ghana',
      name: 'Ghana',
      geoJsonPath: 'assets/data/regions/ghana.geojson',
      mapTilePath: 'assets/maps/ghana.mbtiles',
      center: LatLng(7.9465, -1.0232),
      zoomLevel: 7,
    ),

    // Kenya
    'kenya': Region(
      id: 'kenya',
      name: 'Kenya',
      geoJsonPath: 'assets/data/regions/kenya.geojson',
      mapTilePath: 'assets/maps/kenya.mbtiles',
      center: LatLng(-0.0236, 37.9062),
      zoomLevel: 6,
    ),

    // Nigeria (Country Level)
    'nigeria': Region(
      id: 'nigeria',
      name: 'Nigeria',
      geoJsonPath: 'assets/data/regions/nigeria/full.geojson',
      mapTilePath: 'assets/maps/nigeria.mbtiles',
      center: LatLng(9.0820, 8.6753),
      zoomLevel: 6,
    ),

    // Nigeria - Abuja (Capital Territory)
    'nigeria-abuja': Region(
      id: 'nigeria-abuja',
      name: 'Abuja, Nigeria',
      geoJsonPath: 'assets/data/regions/nigeria/abuja.geojson',
      mapTilePath: 'assets/maps/nigeria/abuja.mbtiles',
      center: LatLng(9.0579, 7.4951),
      zoomLevel: 12,
      parentId: 'nigeria',
    ),

    // Nigeria - Lagos State
    'nigeria-lagos': Region(
      id: 'nigeria-lagos',
      name: 'Lagos, Nigeria',
      geoJsonPath: 'assets/data/regions/nigeria/lagos.geojson',
      mapTilePath: 'assets/maps/nigeria/lagos.mbtiles',
      center: LatLng(6.5244, 3.3792),
      zoomLevel: 11,
      parentId: 'nigeria',
    ),

    // Add more regions here following the same pattern
  };

  /// Get all top-level regions (excluding sub-regions)
  static List<Region> getCountries() {
    return _regions.values.where((region) => region.parentId == null).toList();
  }

  /// Get all regions including sub-regions
  static List<Region> getAll() => _regions.values.toList();

  /// Get a region by its ID
  static Region? getById(String id) => _regions[id.toLowerCase()];

  /// Get sub-regions for a parent region
  static List<Region> getSubRegions(String parentId) {
    return _regions.values
        .where((region) => region.parentId == parentId.toLowerCase())
        .toList();
  }

  /// Search regions by name
  static List<Region> search(String query) {
    return _regions.values
        .where((region) => region.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }
}