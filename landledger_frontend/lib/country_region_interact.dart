// lib/country_region_interact.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:flutter/material.dart';

/// Simple style config for polygons.
class RegionStyle {
  final Color stroke;
  final Color fill;
  final int strokeWidth;

  const RegionStyle({
    required this.stroke,
    required this.fill,
    this.strokeWidth = 2,
  });
}

class CountryRegionController {
  CountryRegionController({
    this.normalStyle = const RegionStyle(
      stroke: Color(0xFF1E88E5),
      fill: Color(0x4D1E88E5), // ~30% alpha
      strokeWidth: 2,
    ),
    this.selectedStyle = const RegionStyle(
      stroke: Colors.white,
      fill: Color(0x80FFFFFF), // ~50% alpha
      strokeWidth: 4,
    ),
    this.onRegionSelected,
  });

  /// Styles
  final RegionStyle normalStyle;
  final RegionStyle selectedStyle;

  /// Optional callback when a region is selected.
  final void Function(String regionId)? onRegionSelected;

  /// Google map controller (attached by your map widget).
  gmap.GoogleMapController? mapController;

  /// Expose polygons with a ValueNotifier so outside widgets can rebuild easily.
  final ValueNotifier<Set<gmap.Polygon>> polygonsNotifier =
      ValueNotifier<Set<gmap.Polygon>>({});

  /// Currently selected region ID (typically the ADM1 'name').
  final ValueNotifier<String?> selectedRegionId = ValueNotifier<String?>(null);

  /// regionId -> list of polygon parts.
  /// Each part contains: exterior ring + holes.
  ///   {
  ///     "exterior": <List<gmap.LatLng>>,
  ///     "holes": <List<List<gmap.LatLng>>>
  ///   }
  final Map<String, List<Map<String, dynamic>>> _regionParts = {};

  /// Convenience: regionId -> all exterior points (merged) for bounds calc.
  final Map<String, List<gmap.LatLng>> _regionExteriorForBounds = {};

  /// Attach the GoogleMap controller once map is created.
  void attachMapController(gmap.GoogleMapController controller) {
    mapController = controller;
  }

  /// Load ADM1 GeoJSON from assets and build polygons.
  /// The file should have a FeatureCollection with geometry of type Polygon or MultiPolygon
  /// and a 'name' property per feature (we use that as regionId).
  Future<void> loadAdm1FromAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final fc = jsonDecode(raw) as Map<String, dynamic>;

    _regionParts.clear();
    _regionExteriorForBounds.clear();

    for (final feat in (fc['features'] as List)) {
      final props = (feat['properties'] as Map<String, dynamic>);
      final String regionId = (props['name'] as String);

      final geom = feat['geometry'] as Map<String, dynamic>;
      final String type = geom['type'] as String;

      Iterable polys;
      if (type == 'MultiPolygon') {
        polys = (geom['coordinates'] as List);
      } else if (type == 'Polygon') {
        polys = [(geom['coordinates'] as List)];
      } else {
        // skip unknown geometry
        continue;
      }

      final regionParts = <Map<String, dynamic>>[];
      final exteriorForBounds = <gmap.LatLng>[];

      for (final poly in polys) {
        // poly is List<LinearRing>; ring[0] = exterior, ring[1..] = holes
        final rings = (poly as List);

        // Exterior
        final ext = (rings.first as List)
            .map<gmap.LatLng>((c) => gmap.LatLng(
                  (c[1] as num).toDouble(),
                  (c[0] as num).toDouble(),
                ))
            .toList();

        // Holes (optional)
        final holes = <List<gmap.LatLng>>[];
        if (rings.length > 1) {
          for (int h = 1; h < rings.length; h++) {
            final hole = (rings[h] as List)
                .map<gmap.LatLng>((c) => gmap.LatLng(
                      (c[1] as num).toDouble(),
                      (c[0] as num).toDouble(),
                    ))
                .toList();
            holes.add(hole);
          }
        }

        regionParts.add({
          "exterior": ext,
          "holes": holes,
        });

        exteriorForBounds.addAll(ext);
      }

      _regionParts[regionId] = regionParts;
      _regionExteriorForBounds[regionId] = exteriorForBounds;
    }

    _rebuildPolygons(); // push to notifier
  }

  /// Programmatically select a region (updates style + centers/zooms).
  Future<void> selectRegion(String regionId) async {
    if (!_regionParts.containsKey(regionId)) return;
    selectedRegionId.value = regionId;
    _rebuildPolygons();
    await focusRegion(regionId);
    onRegionSelected?.call(regionId);
  }

  /// Internal: rebuild polygon set with correct styles.
  void _rebuildPolygons() {
    final selected = selectedRegionId.value;
    final set = <gmap.Polygon>{};

    _regionParts.forEach((regionId, parts) {
      final isSelected = (selected == regionId);
      final style = isSelected ? selectedStyle : normalStyle;

      for (int i = 0; i < parts.length; i++) {
        final exterior = parts[i]["exterior"] as List<gmap.LatLng>;
        final holes = parts[i]["holes"] as List<List<gmap.LatLng>>;
        set.add(
          gmap.Polygon(
            polygonId: gmap.PolygonId('$regionId#$i'),
            points: exterior,
            holes: holes,
            strokeWidth: style.strokeWidth,
            strokeColor: style.stroke,
            fillColor: style.fill,
            consumeTapEvents: true,
            onTap: () => selectRegion(regionId),
          ),
        );
      }
    });

    polygonsNotifier.value = set;
  }

  /// Camera helpers
  gmap.LatLngBounds _boundsFrom(List<gmap.LatLng> pts) {
    double? minLat, minLng, maxLat, maxLng;
    for (final p in pts) {
      minLat = (minLat == null) ? p.latitude : (p.latitude < minLat ? p.latitude : minLat);
      minLng = (minLng == null) ? p.longitude : (p.longitude < minLng ? p.longitude : minLng);
      maxLat = (maxLat == null) ? p.latitude : (p.latitude > maxLat ? p.latitude : maxLat);
      maxLng = (maxLng == null) ? p.longitude : (p.longitude > maxLng ? p.longitude : maxLng);
    }
    return gmap.LatLngBounds(
      southwest: gmap.LatLng(minLat!, minLng!),
      northeast: gmap.LatLng(maxLat!, maxLng!),
    );
  }

  /// Center/zoom to a region’s bounds.
  Future<void> focusRegion(String regionId, {double padding = 48}) async {
    final controller = mapController;
    if (controller == null) return;
    final pts = _regionExteriorForBounds[regionId];
    if (pts == null || pts.isEmpty) return;

    if (pts.length == 1) {
      await controller.animateCamera(
        gmap.CameraUpdate.newLatLngZoom(pts.first, 12),
      );
    } else {
      final b = _boundsFrom(pts);
      await controller.animateCamera(
        gmap.CameraUpdate.newLatLngBounds(b, padding),
      );
    }
  }

  /// Free notifiers when done.
  void dispose() {
    polygonsNotifier.dispose();
    selectedRegionId.dispose();
  }
}
