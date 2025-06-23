import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'region_model.dart';

class RegionUtils {
  /// Load GeoJSON data for a region
  static Future<String> loadGeoJson(Region region) async {
    return await rootBundle.loadString(region.geoJsonPath);
  }

  /// Get appropriate zoom level based on region size
  static double getAutoZoomLevel(Region region) {
    // Implement logic to determine zoom level based on region bounds
    // This is a simplified version - you might want to calculate from actual GeoJSON
    if (region.id.contains('africa')) return 3;
    if (region.parentId == null) return 6; // Country level
    return 11; // City level
  }

  /// Get bounds for a region (would need proper implementation)
  static LatLngBounds? getBounds(Region region) {
    // You would typically calculate this from the GeoJSON
    return null;
  }
}