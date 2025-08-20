// lib/country_region_interact.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

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
      fill: Color(0x331E88E5), // ~20% alpha blue
      strokeWidth: 2,
    ),
    this.selectedStyle = const RegionStyle(
      stroke: Color(0xFF1565C0),
      fill: Color(0x801565C0), // ~50% alpha blue
      strokeWidth: 4,
    ),
    this.onRegionSelected,
  });

  // Styles
  final RegionStyle normalStyle;
  final RegionStyle selectedStyle;

  // Optional callback when a region is selected.
  final void Function(String regionId)? onRegionSelected;

  // Attach your GoogleMap controller.
  gmap.GoogleMapController? mapController;

  // Public notifiers.
  final ValueNotifier<Set<gmap.Polygon>> polygonsNotifier =
      ValueNotifier<Set<gmap.Polygon>>({});
  final ValueNotifier<String?> selectedRegionId = ValueNotifier<String?>(null);

  // Internal stores.
  final Map<String, List<Map<String, dynamic>>> _regionParts = {};
  final Map<String, List<gmap.LatLng>> _regionExteriorForBounds = {};
  final Map<String, Map<String, dynamic>> _regionProps = {};

  // NEW: toggle region shading so properties remain visible.
  bool _shadingEnabled = true;
  void setShading(bool enabled) {
    _shadingEnabled = enabled;
    _rebuildPolygons();
  }

  // Public helpers
  List<String> get regionIds => _regionParts.keys.toList(growable: false);
  Map<String, dynamic>? getProps(String id) => _regionProps[id];
  gmap.LatLngBounds? getBounds(String id) {
    final pts = _regionExteriorForBounds[id];
    if (pts == null || pts.isEmpty) return null;
    return _boundsFrom(pts);
  }

  // NEW: expose raw exterior rings for containment tests in your UI
  List<List<gmap.LatLng>> regionExteriors(String id) {
    final parts = _regionParts[id];
    if (parts == null) return const [];
    return parts
        .map((p) => (p['exterior'] as List<gmap.LatLng>))
        .toList(growable: false);
  }

  gmap.LatLng getCentroid(String id) {
    final pts = _regionExteriorForBounds[id] ?? const <gmap.LatLng>[];
    if (pts.isEmpty) return const gmap.LatLng(0, 0);
    double x = 0, y = 0, z = 0;
    for (final p in pts) {
      final lat = p.latitude * (math.pi / 180.0);
      final lng = p.longitude * (math.pi / 180.0);
      x += math.cos(lat) * math.cos(lng);
      y += math.cos(lat) * math.sin(lng);
      z += math.sin(lat);
    }
    final total = pts.length.toDouble();
    x /= total; y /= total; z /= total;
    final hyp = math.sqrt(x * x + y * y);
    return gmap.LatLng(
      math.atan2(z, hyp) * 180 / math.pi,
      math.atan2(y, x) * 180 / math.pi,
    );
  }

  void attachMapController(gmap.GoogleMapController controller) {
    mapController = controller;
  }

  String _chooseRegionId(Map<String, dynamic> props) {
    const candidates = ['name', 'NAME_1', 'ADM1_EN', 'adm1_name', 'NAME'];
    for (final k in candidates) {
      final v = props[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    final fallback = props.entries.firstWhere(
      (e) => e.value is String && (e.value as String).trim().isNotEmpty,
      orElse: () => const MapEntry('id', 'Unknown'),
    );
    return fallback.value as String;
  }

  Future<void> loadAdm1FromAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final fc = jsonDecode(raw) as Map<String, dynamic>;

    _regionParts.clear();
    _regionExteriorForBounds.clear();
    _regionProps.clear();

    final features = (fc['features'] as List?) ?? const [];
    for (final f in features) {
      final feat = f as Map<String, dynamic>;
      final props = (feat['properties'] as Map<String, dynamic>? ) ?? const {};
      final regionId = _chooseRegionId(props);
      _regionProps[regionId] = props;

      final geom = (feat['geometry'] as Map<String, dynamic>?);
      if (geom == null) continue;
      final type = geom['type'] as String?; if (type == null) continue;

      Iterable polys;
      if (type == 'MultiPolygon') {
        polys = (geom['coordinates'] as List);
      } else if (type == 'Polygon') {
        polys = [(geom['coordinates'] as List)];
      } else {
        continue;
      }

      final regionParts = <Map<String, dynamic>>[];
      final exteriorForBounds = <gmap.LatLng>[];

      for (final poly in polys) {
        final rings = (poly as List);
        if (rings.isEmpty) continue;

        final ext = (rings.first as List).map<gmap.LatLng>((c) =>
          gmap.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())
        ).toList();

        final holes = <List<gmap.LatLng>>[];
        for (int h = 1; h < rings.length; h++) {
          final hole = (rings[h] as List).map<gmap.LatLng>((c) =>
            gmap.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())
          ).toList();
          if (hole.isNotEmpty) holes.add(hole);
        }

        if (ext.isNotEmpty) {
          regionParts.add({"exterior": ext, "holes": holes});
          exteriorForBounds.addAll(ext);
        }
      }

      if (regionParts.isNotEmpty) {
        _regionParts[regionId] = regionParts;
        _regionExteriorForBounds[regionId] = exteriorForBounds;
      }
    }

    _rebuildPolygons();
  }

  Future<void> selectRegion(String regionId) async {
    if (!_regionParts.containsKey(regionId)) return;
    selectedRegionId.value = regionId;
    _rebuildPolygons();
    await focusRegion(regionId);
    onRegionSelected?.call(regionId);
  }

  void _rebuildPolygons() {
    final selected = selectedRegionId.value;
    final set = <gmap.Polygon>{};

    _regionParts.forEach((regionId, parts) {
      final isSelected = (selected == regionId);
      final style = isSelected ? selectedStyle : normalStyle;
      final Color fillForThis =
          (isSelected && !_shadingEnabled) ? style.fill.withAlpha(0) : style.fill;

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
            fillColor: fillForThis,
            consumeTapEvents: true,
            onTap: () => selectRegion(regionId),
          ),
        );
      }
    });

    polygonsNotifier.value = set;
  }

  gmap.LatLngBounds _boundsFrom(List<gmap.LatLng> pts) {
    double minLat = pts.first.latitude,
           minLng = pts.first.longitude,
           maxLat = pts.first.latitude,
           maxLng = pts.first.longitude;
    for (int i = 1; i < pts.length; i++) {
      final p = pts[i];
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return gmap.LatLngBounds(
      southwest: gmap.LatLng(minLat, minLng),
      northeast: gmap.LatLng(maxLat, maxLng),
    );
  }

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

  void dispose() {
    polygonsNotifier.dispose();
    selectedRegionId.dispose();
  }
}
