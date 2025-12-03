// map_screen.dart
// Region-focused zoom, per-state highlight toggle, robust property-in-region matching,
// Firestore save/load for polygons, and owner-highlight rendering (blue vs. grey).

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'city_model.dart';
import 'country_region_interact.dart';
import 'region_model.dart';
import 'regions_repository.dart';
import 'widgets/consent.dart';
import 'widgets/address_input_widget.dart';
import 'models/property_address.dart';
import 'services/identity_service.dart';

class MapScreen extends StatefulWidget {
  final String regionId; // country id (e.g., "cameroon")
  final String? geojsonPath; // any country's GeoJSON asset path
  final bool startDrawing;
  final List<ll.LatLng>? highlightPolygon;
  final bool centerOnRegion;
  final void Function()? onBackToHome;
  final bool openedFromTab;
  final VoidCallback? onOpenMyProperties;
  final void Function(String regionId, String geojsonPath)? onRegionSelected;
  final bool showBackArrow;
  final void Function(Map<String, dynamic>)? onBlockchainUpdate;

  /// show all polygons but render "owner" polygons in blue
  final bool showAllWithOwnerHighlight;

  /// who counts as "owner" for blue styling; defaults to current user
  final String? highlightOwnerUid;

  const MapScreen({
    super.key,
    required this.regionId,
    required this.geojsonPath,
    this.startDrawing = false,
    this.highlightPolygon,
    this.centerOnRegion = true,
    this.onBackToHome,
    this.openedFromTab = false,
    this.onOpenMyProperties,
    this.onRegionSelected,
    this.showBackArrow = false,
    this.onBlockchainUpdate,
    this.showAllWithOwnerHighlight = true,
    this.highlightOwnerUid,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final user = FirebaseAuth.instance.currentUser;
  final mapController = MapController();
  final TextEditingController descriptionController = TextEditingController();
  PropertyAddress? _propertyAddress; // Structured address from AddressInputWidget
  final ImagePicker _imagePicker = ImagePicker();
  List<XFile> _selectedImages = [];

  final bool _useGoogle = true;

  String canonicalizeRegionId(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

  // -- Google map controller/zoom
  gmap.GoogleMapController? _gController;
  double _currentZoom = 16;

  bool isDrawing = false;
  bool showSatellite = false;
  bool show3D = false;

  bool _isSaving = false;

  // Cached polygon sets to avoid recreation
  Set<gmap.Polygon> _cachedPolygons = {};
  int _lastPolygonHash = 0;

  // Drawn/loaded polygons
  List<ll.LatLng> currentPolygonPoints = [];
  List<List<ll.LatLng>> boundaryPolygons = []; // country outline(s) — only used in FlutterMap path
  List<List<ll.LatLng>> userPolygons = [];
  List<List<ll.LatLng>> otherPolygons = [];
  List<DocumentSnapshot> userPolygonDocs = [];
  List<DocumentSnapshot> otherPolygonDocs = [];
  List<ll.LatLng>? selectedPolygon;

  Region? currentRegion;
  DocumentSnapshot? _selectedPolygonDoc;
  bool _showPolygonInfo = false;
  ll.LatLng? _currentCenter;

  // Country bounds/center for initial fit (Google + FlutterMap)
  gmap.LatLngBounds? _regionBoundsGoogle;
  LatLngBounds? _regionBoundsFlutter;
  ll.LatLng? _regionCenterComputed;

  // Helpers to convert
  gmap.LatLng _g(ll.LatLng p) => gmap.LatLng(p.latitude, p.longitude);
  List<gmap.LatLng> _gList(List<ll.LatLng> pts) => pts.map(_g).toList();

  // Quantize to 6 decimals to avoid noisy diffs & dedupe issues
  double _q6(double v) => double.parse(v.toStringAsFixed(6));

  // --- US ADM1 helpers ---
  static const _US_REGION_ID = 'united_states'; // must match your HomeScreen id
  static const Set<String> _US_TERRITORIES_AND_DC = {
    // Exclude to keep strictly “50 states”
    'Puerto Rico',
    'Guam',
    'American Samoa',
    'Northern Mariana Islands',
    'United States Virgin Islands',
    'U.S. Virgin Islands',
    'District of Columbia', // remove D.C. if you want strictly 50
  };

  // Mainland U.S. (CONUS) bounding box + center
  static const gmap.LatLng _kConusSW = gmap.LatLng(24.396308, -124.848974);
  static const gmap.LatLng _kConusNE = gmap.LatLng(49.384358,  -66.885444);
  static const ll.LatLng   _kConusCenter = ll.LatLng(39.8283, -98.5795);

  // If your GeoJSON has STATEFP codes, skip by code (more robust)
  static const Set<String> _US_STATEFP_TERRITORIES = {'60','66','69','72','78'};

  // === Hashtag helpers (fix "##" everywhere) ===
  String _stripLeadingHashes(String s) =>
      s.trim().replaceFirst(RegExp(r'^#+'), '');
  String _ensureSingleHash(String s) => '#${_stripLeadingHashes(s)}';
  String _aliasKeyFrom(String s) => _stripLeadingHashes(s).toUpperCase();

  /// Build formatted address display from Firestore data
  Widget _buildAddressDisplay(Map<String, dynamic> data) {
    // Try to get structured address first
    final addressData = data['address'];
    PropertyAddress? address;

    if (addressData is Map<String, dynamic>) {
      try {
        address = PropertyAddress.fromJson(addressData);
      } catch (e) {
        debugPrint('Error parsing address: $e');
      }
    }

    // Fallback to addressString if structured address isn't available
    final addressString = data['addressString'] as String?;

    // If no address data at all, show nothing
    if (address == null && (addressString == null || addressString.isEmpty)) {
      return const SizedBox.shrink();
    }

    // Use structured address if available, otherwise use string
    final displayText = address?.toDisplayString() ?? addressString ?? 'No address';

    // If structured address exists and has details, show expandable detailed view
    if (address != null && address.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Colors.blue),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  displayText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          // Show structured details in a compact format
          if (address.houseNumber != null || address.streetName != null ||
              address.postalCode != null || address.additionalInfo != null)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (address.houseNumber != null || address.streetName != null)
                    Text(
                      [
                        if (address.houseNumber != null) 'House: ${address.houseNumber}',
                        if (address.streetName != null) 'Street: ${address.streetName}',
                      ].join(' • '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                    ),
                  if (address.postalCode != null)
                    Text(
                      'Postal Code: ${address.postalCode}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                    ),
                  if (address.additionalInfo != null && address.additionalInfo!.isNotEmpty)
                    Text(
                      'Note: ${address.additionalInfo}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    }

    // Simple display for string-only address
    return Row(
      children: [
        const Icon(Icons.location_on, size: 16, color: Colors.blue),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            displayText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  List<ll.LatLng> _quantizeRing(List<ll.LatLng> pts) =>
      pts.map((p) => ll.LatLng(_q6(p.latitude), _q6(p.longitude))).toList();

  /// Simplify polygon using Douglas-Peucker algorithm for smoother boundaries
  /// Reduces point count while preserving shape
  List<gmap.LatLng> _simplifyPolygon(List<gmap.LatLng> points, {required double tolerance}) {
    if (points.length <= 2) return points;

    // Douglas-Peucker algorithm
    double perpendicularDistance(gmap.LatLng point, gmap.LatLng lineStart, gmap.LatLng lineEnd) {
      final dx = lineEnd.longitude - lineStart.longitude;
      final dy = lineEnd.latitude - lineStart.latitude;

      // Magnitude of the line segment
      final mag = dx * dx + dy * dy;
      if (mag == 0) {
        // lineStart and lineEnd are the same point
        final pdx = point.longitude - lineStart.longitude;
        final pdy = point.latitude - lineStart.latitude;
        return (pdx * pdx + pdy * pdy);
      }

      // Calculate perpendicular distance
      final u = ((point.longitude - lineStart.longitude) * dx +
                 (point.latitude - lineStart.latitude) * dy) / mag;

      final gmap.LatLng closest;
      if (u < 0) {
        closest = lineStart;
      } else if (u > 1) {
        closest = lineEnd;
      } else {
        closest = gmap.LatLng(
          lineStart.latitude + u * dy,
          lineStart.longitude + u * dx,
        );
      }

      final pdx = point.longitude - closest.longitude;
      final pdy = point.latitude - closest.latitude;
      return (pdx * pdx + pdy * pdy);
    }

    List<gmap.LatLng> douglasPeucker(List<gmap.LatLng> points, double epsilon) {
      if (points.length <= 2) return points;

      // Find the point with maximum distance
      double maxDist = 0;
      int maxIndex = 0;
      final start = points.first;
      final end = points.last;

      for (int i = 1; i < points.length - 1; i++) {
        final dist = perpendicularDistance(points[i], start, end);
        if (dist > maxDist) {
          maxDist = dist;
          maxIndex = i;
        }
      }

      // If max distance is greater than epsilon, recursively simplify
      if (maxDist > epsilon * epsilon) {
        final left = douglasPeucker(points.sublist(0, maxIndex + 1), epsilon);
        final right = douglasPeucker(points.sublist(maxIndex), epsilon);

        // Combine results (remove duplicate middle point)
        return [...left.sublist(0, left.length - 1), ...right];
      } else {
        // Points can be approximated by a line
        return [start, end];
      }
    }

    return douglasPeucker(points, tolerance);
  }

  List<ll.LatLng> _ensureClosed(List<ll.LatLng> pts) {
    if (pts.isEmpty) return pts;
    final q = _quantizeRing(pts);
    final first = q.first;
    final last = q.last;
    if (first.latitude == last.latitude && first.longitude == last.longitude) {
      return q;
    }
    return [...q, first];
  }

  Map<String, double> _bboxOf(List<ll.LatLng> ring) {
    double minLat = 90, minLng = 180, maxLat = -90, maxLng = -180;
    for (final p in ring) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return {
      "minLat": _q6(minLat),
      "minLng": _q6(minLng),
      "maxLat": _q6(maxLat),
      "maxLng": _q6(maxLng),
    };
  }

  // Find the ADM1 that contains the given point (by centroid).
  // Prefers an explicit _lastTappedRegion if valid; falls back to computation.
  String? _pickAdm1ForPoint(ll.LatLng centroid) {
    if (_lastTappedRegion != null) {
      final rings = _regionRingsLL(_lastTappedRegion!);
      for (final r in rings) {
        if (pointInPolygon(centroid, r)) return _lastTappedRegion;
      }
    }
    for (final entry in _admRingsByBase.entries) {
      final base = entry.key;
      final rings = entry.value;
      for (int i = 0; i < rings.length; i++) {
        final ring = rings[i];
        if (pointInPolygon(centroid, ring)) {
          return i == 0 ? base : "$base #$i";
        }
      }
    }
    return null;
  }

  Future<void> _goToAlias(String raw) async {
    final key = _aliasKeyFrom(raw); // normalize for compare
    List<ll.LatLng>? poly;
    DocumentSnapshot? doc;

    bool matchDoc(DocumentSnapshot d) {
      final m = (d.data() ?? {}) as Map<String, dynamic>;
      final k =
          (m['aliasKey'] ?? _aliasKeyFrom(m['alias'] ?? '')).toString().toUpperCase();
      return k == key;
    }

    final iUser = userPolygonDocs.indexWhere(matchDoc);
    if (iUser >= 0) {
      poly = userPolygons[iUser];
      doc = userPolygonDocs[iUser];
    }
    if (poly == null) {
      final iOther = otherPolygonDocs.indexWhere(matchDoc);
      if (iOther >= 0) {
        poly = otherPolygons[iOther];
        doc = otherPolygonDocs[iOther];
      }
    }

    if (poly != null && poly.length >= 3) {
      setState(() {
        selectedPolygon = poly!;
        _selectedPolygonDoc = doc;
        _showPolygonInfo = true;
      });
      if (_gController != null) {
        final b = _boundsFromLl(poly);
        await _gController!.animateCamera(
          gmap.CameraUpdate.newLatLngBounds(b, 150),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No polygon found for ${_ensureSingleHash(raw)}')),
      );
    }
  }

  // Split raw ADM1 id into base (no " #N")
  String _admBaseOf(String admId) => _prettyAdmId(admId);

  // Same logic you used in landledger_screen.dart
  String get _apiBase {
    // Use localhost for all platforms (ADB reverse port forwarding handles Android connectivity)
    return 'http://localhost:4000';
  }

  // --- helper: compare polygons to avoid double-drawing highlight & user copy ---
  bool _samePolygon(List<ll.LatLng> a, List<ll.LatLng> b, {double eps = 1e-6}) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if ((a[i].latitude - b[i].latitude).abs() > eps ||
          (a[i].longitude - b[i].longitude).abs() > eps) {
        return false;
      }
    }
    return true;
  }

  gmap.LatLngBounds _boundsFromLl(List<ll.LatLng> pts) {
    assert(pts.isNotEmpty);
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return gmap.LatLngBounds(
      southwest: gmap.LatLng(minLat, minLng),
      northeast: gmap.LatLng(maxLat, maxLng),
    );
  }

  Future<void> _fitToPolygonIfAny() async {
    if (_gController == null) return;
    final poly = widget.highlightPolygon;
    if (poly == null || poly.isEmpty) return;

    if (poly.length == 1) {
      await _gController!.animateCamera(
        gmap.CameraUpdate.newLatLngZoom(
          gmap.LatLng(poly.first.latitude, poly.first.longitude),
          16,
        ),
      );
      return;
    }

    final bounds = _boundsFromLl(poly);
    await _gController!.animateCamera(
      gmap.CameraUpdate.newLatLngBounds(bounds, 150.0),
    );
  }

  /// Back-compat migration (not automatically called).
  Future<void> migrateOldRegionsDocs(String uid) async {
    final old = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('regions')
        .get();

    for (final d in old.docs) {
      final data = d.data();
      final ridRaw =
          (data['region'] ?? data['regionId'] ?? widget.regionId).toString();
      final regionId = canonicalizeRegionId(ridRaw);
      final propId = (data['title_number'] ?? d.id).toString();

      final userDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('regions')
          .doc(regionId)
          .collection('properties')
          .doc(propId);

      final publicDoc = FirebaseFirestore.instance
          .collection('regions')
          .doc(regionId)
          .collection('properties')
          .doc(propId);

      await userDoc.set({
        ...data,
        'id': propId,
        'regionId': regionId,
        'ownerUid': uid,
        'migratedFromFlat': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await publicDoc.set({
        ...data,
        'id': propId,
        'regionId': regionId,
        'ownerUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  gmap.LatLngBounds _toGoogleBounds(List<ll.LatLng> pts) {
    double minLat = 90, minLng = 180, maxLat = -90, maxLng = -180;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return gmap.LatLngBounds(
      southwest: gmap.LatLng(minLat, minLng),
      northeast: gmap.LatLng(maxLat, maxLng),
    );
  }

  // Simple arithmetic centroid (used in a few places)
  ll.LatLng _centroid(List<ll.LatLng> pts) {
    if (pts.isEmpty) return const ll.LatLng(0, 0);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return ll.LatLng(lat / pts.length, lng / pts.length);
  }

  // Area (polygon) centroid, robust for region tests
  ll.LatLng _areaCentroid(List<ll.LatLng> pts) {
    if (pts.isEmpty) return const ll.LatLng(0, 0);
    double signedArea = 0;
    double cx = 0; // longitude
    double cy = 0; // latitude
    for (int i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      final x0 = pts[i].longitude;
      final y0 = pts[i].latitude;
      final x1 = pts[j].longitude;
      final y1 = pts[j].latitude;
      final a = x0 * y1 - x1 * y0;
      signedArea += a;
      cx += (x0 + x1) * a;
      cy += (y0 + y1) * a;
    }
    if (signedArea.abs() < 1e-12) return _centroid(pts);
    signedArea *= 0.5;
    cx /= (6 * signedArea);
    cy /= (6 * signedArea);
    return ll.LatLng(cy, cx);
  }

  String generateAliasFromCity(String city) {
    final cleaned = city.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
    if (cleaned.length <= 4) {
      final code = _randomCode();
      return '#${cleaned.isEmpty ? "P" : cleaned[0].toUpperCase()}${cleaned.length > 1 ? cleaned.substring(1) : ""}$code';
    }
    const vowels = 'aeiouy';
    final buffer = StringBuffer();
    bool lastWasVowel = false;
    for (int i = 0; i < cleaned.length; i++) {
      final char = cleaned[i];
      final isVowel = vowels.contains(char);
      if (isVowel && !lastWasVowel && i > 0) {
        buffer.write(cleaned[i - 1]);
      }
      lastWasVowel = isVowel;
    }
    final short = buffer.isNotEmpty
        ? buffer.toString().toUpperCase()
        : cleaned.substring(0, 2).toUpperCase();
    return '#$short${_randomCode()}';
  }

  String _randomCode() {
    final rand = DateTime.now().microsecondsSinceEpoch;
    final digits = (1000 + rand % 9000).toString();
    return digits;
  }

  String get _mapboxStyleId {
    if (showSatellite) return 'mapbox/satellite-streets-v12';
    if (show3D) return 'morgancolt/clxyz3dstyle';
    return 'mapbox/outdoors-v12';
  }

  // Global show/hide + per-region hide using base IDs
  final bool _regionFillVisible = true;
  final Set<String> _hiddenAdmRegions = <String>{};

  // Cache of ADM rings grouped by base name (e.g., "Littoral")
  final Map<String, List<List<ll.LatLng>>> _admRingsByBase = {};

  // Pretty display + "base" key helper: remove trailing " #N"
  String _prettyAdmId(String raw) => raw.replaceFirst(RegExp(r'\s*#\d+$'), '');

  List<List<ll.LatLng>> _regionRingsLL(String regionIdRaw) {
    final base = _prettyAdmId(regionIdRaw);
    final cached = _admRingsByBase[base];
    if (cached != null && cached.isNotEmpty) return cached;

    final ringsG = _admCtl.regionExteriors(regionIdRaw);
    return ringsG
        .map((ring) => ring
            .map((p) => ll.LatLng(p.latitude, p.longitude))
            .toList(growable: false))
        .toList(growable: false);
  }

  late CountryRegionController _admCtl;
  bool _admCtlInit = false;

  String? _lastTappedRegion;

  // ---------- Pending alias intent (from Home) ----------
  String? _pendingAliasKey;

  Future<void> _consumePendingAliasIfReady() async {
    if (_pendingAliasKey == null) return;
    final hasData = userPolygons.isNotEmpty || otherPolygons.isNotEmpty;
    if (!hasData) return; // wait until polygons are loaded
    final key = _pendingAliasKey!;
    _pendingAliasKey = null; // consume
    await _goToAlias(key);
  }

  @override
  void initState() {
    super.initState();

    if (!_admCtlInit) {
      _admCtl = CountryRegionController(
        onRegionSelected: (id) {
          if (!mounted) return;
          _promptRegionDetails(id);
          if (widget.onRegionSelected != null && widget.geojsonPath != null) {
            widget.onRegionSelected!(id, widget.geojsonPath!);
          }
        },
      );
      _admCtl.setShading(_regionFillVisible);
      final admPath =
          widget.geojsonPath ?? RegionsRepository.getById(widget.regionId)?.geoJsonPath;
      if (admPath != null && admPath.isNotEmpty) {
        _admCtl.loadAdm1FromAsset(admPath);
      }
      _admCtlInit = true;
    }

    // If we’re in the US region, pre-hide DC/territories (just affects fill toggling)
    if (canonicalizeRegionId(widget.regionId) == _US_REGION_ID) {
      _hiddenAdmRegions.addAll(_US_TERRITORIES_AND_DC);
    }

    _initializeRegion();
    if (widget.startDrawing) isDrawing = true;
    _loadUserSavedPolygons();

    // Read alias intent from Home and hold it until polygons load.
    () async {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString('pending_map_alias_key');
      if (key != null && key.isNotEmpty) {
        _pendingAliasKey = key; // already normalized by Home
        await prefs.remove('pending_map_alias_key');
        await prefs.remove('pending_map_alias_raw');
        await _consumePendingAliasIfReady();
      }
    }();
  }

  @override
  void dispose() {
    descriptionController.dispose();
    // PropertyAddress doesn't need disposal (no controller)
    try {
      _admCtl.dispose();
    } catch (_) {}
    _gController?.dispose();
    _moveDebounce?.cancel();
    // Clear cached polygons to free memory
    _cachedPolygons.clear();
    _admRingsByBase.clear();
    super.dispose();
  }

  // ---- ADM1 / Region inference for robust deletes ----
  String? _deriveAdm1BaseFromDoc({
    required Map<String, dynamic> data,
    required DocumentReference ref,
    List<ll.LatLng>? polygon,
  }) {
    final direct = (data['adm1Base'] ?? '').toString();
    if (direct.isNotEmpty) return direct;

    final admId = (data['adm1Id'] ?? '').toString();
    if (admId.isNotEmpty) return _admBaseOf(admId);

    // From path: .../adm1/{ADM1}/properties/{propId}
    final segs = ref.path.split('/');
    for (int i = 0; i < segs.length - 1; i++) {
      if (segs[i] == 'adm1' && i + 1 < segs.length) {
        return _prettyAdmId(segs[i + 1]);
      }
    }

    // Fallback: compute from geometry
    if (polygon != null && polygon.length >= 3) {
      final c = _areaCentroid(polygon);
      final picked = _pickAdm1ForPoint(c);
      if (picked != null) return _admBaseOf(picked);
    }
    return null;
  }

  String _deriveRegionIdFromDoc({
    required Map<String, dynamic> data,
    required DocumentReference ref,
  }) {
    final rid = (data['regionId'] ?? '').toString();
    if (rid.isNotEmpty) return canonicalizeRegionId(rid);

    // From path: users/{uid}/regions/{REGION}/... or regions/{REGION}/...
    final segs = ref.path.split('/');
    for (int i = 0; i < segs.length - 1; i++) {
      if (segs[i] == 'regions' && i + 1 < segs.length) {
        return canonicalizeRegionId(segs[i + 1]);
      }
    }
    // Fallback to current screen
    return canonicalizeRegionId(widget.regionId);
  }

  Future<void> _tryDeleteOnBlockchain(String? parcelId) async {
    if (parcelId == null || parcelId.isEmpty) return;
    try {
      final del = await http.delete(Uri.parse('$_apiBase/api/landledger/delete/$parcelId'));
      if (del.statusCode >= 200 && del.statusCode < 300) {
        debugPrint('✅ Blockchain delete OK for $parcelId');
        return;
      }
      final post =
          await http.post(Uri.parse('$_apiBase/api/landledger/delete/$parcelId'));
      debugPrint('ℹ️ Blockchain delete fallback status ${post.statusCode}: ${post.body}');
    } catch (e) {
      debugPrint('⚠️ Blockchain delete exception: $e');
    }
  }

  Future<void> _deleteDocEverywhere({
    required String uid,
    required String regionId,
    required String propId,
    String? adm1Base,
    required DocumentReference originalRef,
  }) async {
    final fs = FirebaseFirestore.instance;
    final batch = fs.batch();

    // USER / ADM1
    if (adm1Base != null && adm1Base.isNotEmpty) {
      batch.delete(fs
          .collection('users')
          .doc(uid)
          .collection('regions')
          .doc(regionId)
          .collection('adm1')
          .doc(adm1Base)
          .collection('properties')
          .doc(propId));
    }

    // PUBLIC / ADM1
    if (adm1Base != null && adm1Base.isNotEmpty) {
      batch.delete(fs
          .collection('regions')
          .doc(regionId)
          .collection('adm1')
          .doc(adm1Base)
          .collection('properties')
          .doc(propId));
    }

    // USER / ADM0
    batch.delete(fs
        .collection('users')
        .doc(uid)
        .collection('regions')
        .doc(regionId)
        .collection('properties')
        .doc(propId));

    // PUBLIC / ADM0
    batch.delete(fs.collection('regions').doc(regionId).collection('properties').doc(propId));

    // Legacy flat
    batch.delete(fs.collection('users').doc(uid).collection('regions').doc(propId));

    // The exact tapped doc, wherever it lives
    batch.delete(originalRef);

    await batch.commit();
  }

  Future<void> deleteSelectedProperty() async {
    if (_selectedPolygonDoc == null) return;
    final doc = _selectedPolygonDoc!;
    final data = (doc.data() ?? {}) as Map<String, dynamic>;
    final uid = (data['ownerUid'] ?? user?.uid)?.toString();

    if (uid == null || user == null || uid != user!.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can only delete your own property.")),
      );
      return;
    }

    final propId = (data['id'] ?? data['title_number'] ?? doc.id).toString();
    final regionId = _deriveRegionIdFromDoc(data: data, ref: doc.reference);
    final adm1Base = _deriveAdm1BaseFromDoc(
      data: data,
      ref: doc.reference,
      polygon: selectedPolygon,
    );
    final blockchainId =
        (data['blockchainId'] ?? data['id'] ?? data['title_number'] ?? propId)
            .toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete property?"),
        content: Text("This will remove $propId from your account and public indexes."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _deleteDocEverywhere(
        uid: uid,
        regionId: regionId,
        propId: propId,
        adm1Base: adm1Base,
        originalRef: doc.reference,
      );

      // Best-effort blockchain cleanup (non-blocking UI)
      // ignore: unawaited_futures
      _tryDeleteOnBlockchain(blockchainId);

      // Remove from UI lists
      setState(() {
        // Prefer removing from user lists
        final idxUser = userPolygonDocs.indexWhere((d) {
          final dd = (d.data() ?? {}) as Map<String, dynamic>;
          final id = (dd['id'] ?? dd['title_number'] ?? d.id).toString();
          return id == propId;
        });
        if (idxUser >= 0) {
          userPolygonDocs.removeAt(idxUser);
          userPolygons.removeAt(idxUser);
        } else {
          final idxOther = otherPolygonDocs.indexWhere((d) {
            final dd = (d.data() ?? {}) as Map<String, dynamic>;
            final id = (dd['id'] ?? dd['title_number'] ?? d.id).toString();
            return id == propId;
          });
          if (idxOther >= 0) {
            otherPolygonDocs.removeAt(idxOther);
            otherPolygons.removeAt(idxOther);
          }
        }
        _showPolygonInfo = false;
        selectedPolygon = null;
        _selectedPolygonDoc = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Deleted $propId.")),
      );
    } catch (e) {
      debugPrint("❌ Delete failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Delete failed: $e")),
      );
    }
  }

  // 1) Point-in-polygon (ray casting)
  bool pointInPolygon(ll.LatLng point, List<ll.LatLng> polygon) {
    int intersectCount = 0;
    for (int i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      final yi = polygon[i].latitude, yj = polygon[j].latitude;
      final xi = polygon[i].longitude, xj = polygon[j].longitude;
      final py = point.latitude, px = point.longitude;

      final crosses = (yi > py) != (yj > py);
      if (crosses) {
        final x = (xj - xi) * (py - yi) / ((yj - yi) + 0.0) + xi;
        if (px < x) intersectCount++;
      }
    }
    return intersectCount.isOdd;
  }

  // Show options for a polygon point (delete, view coordinates)
  void _showPointOptions(int index) {
    if (!isDrawing || index >= currentPolygonPoints.length) return;

    final point = currentPolygonPoints[index];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == 0 ? 'Start Point' : 'Point ${index + 1}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Latitude: ${point.latitude.toStringAsFixed(6)}'),
            Text('Longitude: ${point.longitude.toStringAsFixed(6)}'),
            const SizedBox(height: 8),
            const Text('You can drag this marker to move it.'),
          ],
        ),
        actions: [
          if (currentPolygonPoints.length > 1)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  currentPolygonPoints.removeAt(index);
                });
                Navigator.pop(context);
              },
              icon: const Icon(Icons.delete, color: Colors.red),
              label: const Text('Delete Point', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Show city selector dialog and zoom to selected city
  Future<void> _showCitySelector() async {
    debugPrint("🏙️ City selector opened for region: ${widget.regionId}");

    // Check if this is an ADM0 (country-level) region
    if (CitiesDatabase.isAdm0Region(widget.regionId)) {
      // Show hierarchical selector: Region → City
      await _showHierarchicalCitySelector();
    } else {
      // Direct city selector for ADM1 regions
      await _showDirectCitySelector();
    }
  }

  // Show hierarchical selector for ADM0 countries (Region → City)
  Future<void> _showHierarchicalCitySelector() async {
    // Step 1: Get all ADM1 regions for this country
    final adm1Regions = CitiesDatabase.getAdm1RegionsForCountry(widget.regionId);

    if (adm1Regions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No regions available for this country')),
      );
      return;
    }

    // Step 2: Show region selector
    final selectedRegionId = await showDialog<String>(
      context: context,
      builder: (context) {
        String searchQuery = '';
        List<MapEntry<String, String>> filteredRegions = adm1Regions.entries.toList();

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              child: Container(
                width: 400,
                constraints: const BoxConstraints(maxHeight: 600),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.map, color: Colors.white),
                          const SizedBox(width: 12),
                          const Text(
                            'Select a Region',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    // Search bar
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search regions...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            searchQuery = value.toLowerCase();
                            filteredRegions = adm1Regions.entries
                                .where((entry) => entry.value.toLowerCase().contains(searchQuery))
                                .toList();
                          });
                        },
                      ),
                    ),

                    // Region count
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${filteredRegions.length} ${filteredRegions.length == 1 ? 'region' : 'regions'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Regions list
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredRegions.length,
                        itemBuilder: (context, index) {
                          final entry = filteredRegions[index];
                          final regionId = entry.key;
                          final regionName = entry.value;
                          final cityCount = CitiesDatabase.getCitiesForRegion(regionId).length;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green.shade100,
                              child: Icon(
                                Icons.map,
                                color: Colors.green.shade700,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              regionName,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              '$cityCount ${cityCount == 1 ? 'city' : 'cities'}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () => Navigator.pop(context, regionId),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // Step 3: If region selected, show cities in that region
    if (selectedRegionId != null) {
      await _showCitiesForRegion(selectedRegionId);
    }
  }

  // Show direct city selector for ADM1 regions or after region selection
  Future<void> _showDirectCitySelector() async {
    await _showCitiesForRegion(widget.regionId);
  }

  // Show cities for a specific region
  Future<void> _showCitiesForRegion(String regionId) async {
    final cities = CitiesDatabase.getCitiesForRegion(regionId);

    if (cities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No cities available for this region')),
      );
      return;
    }

    final selectedCity = await showDialog<City>(
      context: context,
      builder: (context) {
        String searchQuery = '';
        List<City> filteredCities = cities;

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              child: Container(
                width: 400,
                constraints: const BoxConstraints(maxHeight: 600),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_city, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Select a City',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  CitiesDatabase.getRegionDisplayName(regionId),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    // Search bar
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search cities...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            searchQuery = value.toLowerCase();
                            filteredCities = cities
                                .where((city) => city.name.toLowerCase().contains(searchQuery))
                                .toList();
                          });
                        },
                      ),
                    ),

                    // City count
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${filteredCities.length} ${filteredCities.length == 1 ? 'city' : 'cities'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Cities list
                    Flexible(
                      child: filteredCities.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No cities found',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredCities.length,
                              itemBuilder: (context, index) {
                                final city = filteredCities[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue.shade100,
                                    child: Icon(
                                      Icons.location_on,
                                      color: Colors.blue.shade700,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    city.name,
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Text(
                                    '${city.coordinates.latitude.toStringAsFixed(4)}, ${city.coordinates.longitude.toStringAsFixed(4)}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                  onTap: () => Navigator.pop(context, city),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selectedCity != null) {
      await _zoomToCity(selectedCity);
    }
  }

  // Zoom map to a specific city
  Future<void> _zoomToCity(City city) async {
    debugPrint("🏙️ Zooming to city: ${city.name}");

    if (_gController != null) {
      await _gController!.animateCamera(
        gmap.CameraUpdate.newCameraPosition(
          gmap.CameraPosition(
            target: gmap.LatLng(city.coordinates.latitude, city.coordinates.longitude),
            zoom: city.zoomLevel,
          ),
        ),
      );

      // Show confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.location_city, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Centered on ${city.name}'),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      debugPrint("❌ Map controller not available");
    }
  }

  // 2) Unified map tap handler (used by GoogleMap onTap)
  void _handleTap(ll.LatLng point) {
    if (isDrawing) {
      setState(() {
        currentPolygonPoints.add(point);
        _showPolygonInfo = false;
      });
      return;
    }

    // Hit-test user polygons (blue)
    for (int i = 0; i < userPolygons.length; i++) {
      final poly = userPolygons[i];
      if (poly.length >= 3 && pointInPolygon(point, poly)) {
        setState(() {
          selectedPolygon = poly;
          _selectedPolygonDoc = userPolygonDocs[i];
          _showPolygonInfo = true;
        });
        return;
      }
    }
    // Hit-test others (grey)
    for (int i = 0; i < otherPolygons.length; i++) {
      final poly = otherPolygons[i];
      if (poly.length >= 3 && pointInPolygon(point, poly)) {
        setState(() {
          selectedPolygon = poly;
          _selectedPolygonDoc = otherPolygonDocs[i];
          _showPolygonInfo = true;
        });
        return;
      }
    }

    // Nothing hit
    setState(() {
      selectedPolygon = null;
      _selectedPolygonDoc = null;
      _showPolygonInfo = false;
    });
  }

  // 3) flutter_map tap adapter (signature used by your FlutterMap onTap)
  void _handleMapTapFlutter(TapPosition _, ll.LatLng p) => _handleTap(p);

  // 4) Center to user location (used by the FAB)
  Future<void> centerToUserLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;

      // Zoom to level 18 for precise location (was 14)
      if (_useGoogle && _gController != null) {
        await _gController!.animateCamera(
          gmap.CameraUpdate.newLatLngZoom(gmap.LatLng(pos.latitude, pos.longitude), 18),
        );
      } else {
        mapController.move(ll.LatLng(pos.latitude, pos.longitude), 18);
      }
    } catch (e) {
      debugPrint("Location error: $e");
    }
  }

  // 4b) Calculate polygon center from list of points (for address auto-fill)
  ll.LatLng _calculatePolygonCenter(List<ll.LatLng> points) {
    if (points.isEmpty) {
      return ll.LatLng(0, 0);
    }

    double totalLat = 0;
    double totalLng = 0;

    for (var point in points) {
      totalLat += point.latitude;
      totalLng += point.longitude;
    }

    return ll.LatLng(
      totalLat / points.length,
      totalLng / points.length,
    );
  }

  // 5) Region properties bottom sheet (invoked by "Show properties")
  void _showRegionSheet(String idRaw) {
    final displayId = _prettyAdmId(idRaw);
    final rings = _regionRingsLL(idRaw);

    bool touchesRegion(List<ll.LatLng> poly) {
      if (poly.isEmpty) return false;
      final c = _areaCentroid(poly);
      for (final r in rings) {
        if (pointInPolygon(c, r)) return true;
        for (final v in poly) {
          if (pointInPolygon(v, r)) return true;
        }
      }
      return false;
    }

    final myIdx = <int>[];
    for (int i = 0; i < userPolygons.length; i++) {
      if (touchesRegion(userPolygons[i])) myIdx.add(i);
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.45,
          minChildSize: 0.25,
          maxChildSize: 0.9,
          builder: (_, scroll) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayId, style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (myIdx.isEmpty) Text("You have no saved properties in $displayId."),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: myIdx.length,
                      itemBuilder: (_, i) {
                        final idx = myIdx[i];
                        final doc = userPolygonDocs[idx];
                        final data = (doc.data() ?? {}) as Map<String, dynamic>;
                        final title = (data['title_number'] ?? 'Untitled').toString();
                        final poly = userPolygons[idx];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(title),
                            trailing: IconButton(
                              icon: const Icon(Icons.center_focus_strong),
                              tooltip: 'Focus on polygon',
                              onPressed: () async {
                                if (_gController != null && poly.isNotEmpty) {
                                  if (poly.length == 1) {
                                    await _gController!.animateCamera(
                                      gmap.CameraUpdate.newLatLngZoom(
                                        gmap.LatLng(poly.first.latitude, poly.first.longitude),
                                        18,
                                      ),
                                    );
                                  } else {
                                    final b = _boundsFromLl(poly);
                                    await _gController!.animateCamera(
                                      gmap.CameraUpdate.newLatLngBounds(b, 150),
                                    );
                                  }
                                }
                                if (mounted) Navigator.pop(context);
                              },
                            ),
                            onTap: () {
                              setState(() {
                                selectedPolygon = poly;
                                _selectedPolygonDoc = doc;
                                _showPolygonInfo = true;
                              });
                              Navigator.pop(context);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _promptRegionDetails(String regionId) {
    _lastTappedRegion = regionId;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(_prettyAdmId(regionId)),
        action: SnackBarAction(
          label: 'Show properties',
          onPressed: () => _showRegionSheet(regionId),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  bool _didCenterInitial = false;

  /// Compute Google LatLngBounds for a given ADM1 region id using the
  /// full boundary rings from _regionRingsLL.
  gmap.LatLngBounds? _admBoundsFromRegion(String regionId) {
    final rings = _regionRingsLL(regionId);
    if (rings.isEmpty) return null;

    final allPts = <ll.LatLng>[];
    for (final r in rings) {
      allPts.addAll(r);
    }
    if (allPts.isEmpty) return null;

    return _boundsFromLl(allPts);
  }

  /// Used when tapping the shaded ADM1 polygon.
  /// Prefer ADM1 boundary rings; fall back to the rendered polygon if needed.
  Future<void> _focusRegionOnTap(String regionId, List<gmap.LatLng> fallbackPts) async {
    if (_gController == null) return;

    final bounds = _admBoundsFromRegion(regionId);
    if (bounds != null) {
      await _gController!.animateCamera(
        gmap.CameraUpdate.newLatLngBounds(bounds, 48.0),
      );
      return;
    }

    // Fallback: old behavior if for some reason we have no rings
    if (fallbackPts.isEmpty) return;

    double minLat = fallbackPts.first.latitude, maxLat = fallbackPts.first.latitude;
    double minLng = fallbackPts.first.longitude, maxLng = fallbackPts.first.longitude;
    for (final p in fallbackPts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final fbounds = gmap.LatLngBounds(
      southwest: gmap.LatLng(minLat, minLng),
      northeast: gmap.LatLng(maxLat, maxLng),
    );

    await _gController!.animateCamera(
      gmap.CameraUpdate.newLatLngBounds(fbounds, 48.0),
    );
  }

  Future<void> _centerInitialIfReady() async {
    if (!_useGoogle || _gController == null || _didCenterInitial) return;

    final hp = widget.highlightPolygon;
    if (hp != null && hp.length >= 3) {
      final b = _boundsFromLl(hp);
      await _gController!.animateCamera(gmap.CameraUpdate.newLatLngBounds(b, 30)); // Reduced for MORE zoom
      _didCenterInitial = true;
      return;
    }

    if (_regionBoundsGoogle != null) {
      // First fit to bounds with minimal padding
      await _gController!.animateCamera(
        gmap.CameraUpdate.newLatLngBounds(_regionBoundsGoogle!, 1),
      );

      // Then zoom in 2 more clicks for dramatic effect
      await Future.delayed(const Duration(milliseconds: 300));
      final currentZoom = await _gController!.getZoomLevel();
      await _gController!.animateCamera(
        gmap.CameraUpdate.zoomTo(currentZoom + 2),
      );

      _didCenterInitial = true;
      return;
    }

    final c = currentRegion?.center;
    final z = (currentRegion?.zoomLevel ?? 5).toDouble();
    if (c != null) {
      await _gController!
          .moveCamera(gmap.CameraUpdate.newLatLngZoom(gmap.LatLng(c.latitude, c.longitude), z));
      _didCenterInitial = true;
    }
  }

  Future<void> _initializeRegion() async {
    currentRegion = RegionsRepository.getById(widget.regionId);
    await _loadRegionBoundary();
    if (!mounted) return;

    if (!_useGoogle && widget.highlightPolygon != null && widget.highlightPolygon!.isNotEmpty) {
      final fb = LatLngBounds.fromPoints(widget.highlightPolygon!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          mapController.fitBounds(
            fb,
            options: const FitBoundsOptions(padding: EdgeInsets.all(40)),
          );
        }
      });
    } else if (!_useGoogle && widget.centerOnRegion && _regionBoundsFlutter != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          mapController.fitBounds(
            _regionBoundsFlutter!,
            options: const FitBoundsOptions(padding: EdgeInsets.all(1)),
          );

          // Zoom in 2 more levels after a delay
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              mapController.move(
                mapController.camera.center,
                mapController.camera.zoom + 2,
              );
            }
          });
        }
      });
    }
  }

  Future<void> _loadRegionBoundary() async {
    try {
      final path = widget.geojsonPath ?? currentRegion?.geoJsonPath;
      debugPrint("📦 Using geojson path: $path");
      if (path == null || path.isEmpty) {
        debugPrint("❌ No geojson path provided for region ${widget.regionId}");
        return;
      }

      final isUS = path.toLowerCase().contains('united_states.geojson') ||
          canonicalizeRegionId(widget.regionId) == _US_REGION_ID;

      final geojsonStr = await rootBundle.loadString(path);
      final geoData = json.decode(geojsonStr) as Map<String, dynamic>;
      final features = (geoData['features'] as List).cast<Map<String, dynamic>>();

      final parsedPolygons = <List<ll.LatLng>>[]; // only used for FlutterMap path

      bool skipUSFeature(Map<String, dynamic> f) {
        if (!isUS) return false;
        final props = (f['properties'] ?? {}) as Map<String, dynamic>;

        // Handle multiple common field names
        final stateName = (props['shapeName'] ??
                props['NAME'] ??
                props['STATE_NAME'] ??
                props['name'] ??
                props['StName'] ??
                '')
            .toString();

        final stateFp = (props['STATEFP'] ?? '').toString();

        // Prefer robust STATEFP check when available (60,66,69,72,78 are territories)
        if (_US_STATEFP_TERRITORIES.contains(stateFp)) return true;

        // Fallback to name-based filter (keeps it safe for different files)
        return _US_TERRITORIES_AND_DC.contains(stateName) ||
            stateName == 'Commonwealth of the Northern Mariana Islands';
      }

      for (final f in features) {
        if (skipUSFeature(f)) continue;

        final geometry = f['geometry'] as Map<String, dynamic>;
        final type = geometry['type'] as String;
        final coordinates = geometry['coordinates'] as List<dynamic>;

        if (type == 'Polygon') {
          final coords = (coordinates[0] as List).cast<List>();
          if (!_useGoogle) {
            parsedPolygons.add(coords.map<ll.LatLng>((pair) {
              final lng = (pair[0] as num).toDouble();
              final lat = (pair[1] as num).toDouble();
              return ll.LatLng(lat, lng);
            }).toList());
          }
        } else if (type == 'MultiPolygon') {
          for (final poly in coordinates) {
            final outer = (poly as List)[0] as List;
            if (!_useGoogle) {
              parsedPolygons.add(outer.map<ll.LatLng>((pair) {
                final lng = (pair[0] as num).toDouble();
                final lat = (pair[1] as num).toDouble();
                return ll.LatLng(lat, lng);
              }).toList());
            }
          }
        }
      }

      final allPts = <ll.LatLng>[];
      if (!_useGoogle) {
        for (final p in parsedPolygons) {
          allPts.addAll(p);
        }
      } else {
        // When using Google, we don't need the heavy rings here; `_admCtl` drives ADM shapes.
        // Compute bounds from GeoJSON if desired, else rely on CONUS/defaults below.
      }

      ll.LatLng? computedCenter;
      gmap.LatLngBounds? gBounds;
      LatLngBounds? fBounds;

      if (allPts.isNotEmpty) {
        computedCenter = _centroid(allPts);
        gBounds = _toGoogleBounds(allPts);
        fBounds = LatLngBounds.fromPoints(allPts);
      }

      // If this is the U.S., use CONUS bounds for the initial fit
      if (isUS) {
        _regionCenterComputed = _kConusCenter;
        _regionBoundsGoogle = gmap.LatLngBounds(southwest: _kConusSW, northeast: _kConusNE);
        _regionBoundsFlutter = LatLngBounds(
          ll.LatLng(_kConusSW.latitude, _kConusSW.longitude),
          ll.LatLng(_kConusNE.latitude, _kConusNE.longitude),
        );
      } else {
        _regionCenterComputed = computedCenter;
        _regionBoundsGoogle = gBounds;
        _regionBoundsFlutter = fBounds;
      }

      if (!_useGoogle) {
        setState(() {
          boundaryPolygons = parsedPolygons;
        });
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => _centerInitialIfReady());
    } catch (e) {
      debugPrint("❌ Failed to load GeoJSON: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to load boundary data")),
        );
      }
    }
  }

  Future<void> _loadUserSavedPolygons() async {
    if (user == null) return;

    final ownerUid = widget.highlightOwnerUid ?? user!.uid;

    // IMPORTANT: resolve the same region id we saved with
    String regionIdFromGeojsonPath(String? p) {
      if (p == null || p.isEmpty) return canonicalizeRegionId(widget.regionId);
      final m = RegExp(r'([^/\\]+)\.geojson$', caseSensitive: false).firstMatch(p);
      if (m != null && m.groupCount >= 1) {
        return canonicalizeRegionId(m.group(1)!);
      }
      return canonicalizeRegionId(widget.regionId);
    }

    final regIdCanonical = regionIdFromGeojsonPath(widget.geojsonPath);

    debugPrint('🔎 load polys for uid=$ownerUid, region=$regIdCanonical');

    // Local accumulators (de-dupe by id, prefer ADM1 over ADM0)
    final Map<String, DocumentSnapshot> userById = {};
    final Map<String, List<ll.LatLng>> userPoly = {};
    final Map<String, DocumentSnapshot> othersById = {};
    final Map<String, List<ll.LatLng>> othersPoly = {};

    List<ll.LatLng> coordsFromDoc(DocumentSnapshot d) {
      final data = (d.data() ?? {}) as Map<String, dynamic>;
      final coords = (data['coordinates'] as List? ?? const []);
      return coords.map<ll.LatLng>((c) {
        final m = c as Map;
        return ll.LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
      }).toList();
    }

    void insertPreferringADM1({
      required Map<String, DocumentSnapshot> docs,
      required Map<String, List<ll.LatLng>> polys,
      required DocumentSnapshot d,
    }) {
      final data = (d.data() ?? {}) as Map<String, dynamic>;
      final id = (data['id'] ?? d.id).toString();
      if (id.isEmpty) return;

      final isADM1 = (data['admLevel'] ?? '') == 'ADM1';
      if (!docs.containsKey(id)) {
        docs[id] = d;
        polys[id] = coordsFromDoc(d);
        return;
      }
      final prev = (docs[id]!.data() ?? {}) as Map<String, dynamic>;
      final prevIsADM1 = (prev['admLevel'] ?? '') == 'ADM1';
      if (!prevIsADM1 && isADM1) {
        docs[id] = d;
        polys[id] = coordsFromDoc(d);
      }
    }

    try {
      final fs = FirebaseFirestore.instance;

      // ---------- USER (authoritative): ADM1 ----------
      final adm1RootsUser = await fs
          .collection('users')
          .doc(ownerUid)
          .collection('regions')
          .doc(regIdCanonical)
          .collection('adm1')
          .get();

      for (final adm in adm1RootsUser.docs) {
        final props =
            await adm.reference.collection('properties').orderBy('updatedAt', descending: true).get();
        for (final d in props.docs) {
          insertPreferringADM1(docs: userById, polys: userPoly, d: d);
        }
      }

      // ---------- USER: ADM0 aggregate ----------
      final userAdm0Snap = await fs
          .collection('users')
          .doc(ownerUid)
          .collection('regions')
          .doc(regIdCanonical)
          .collection('properties')
          .orderBy('updatedAt', descending: true)
          .get();
      for (final d in userAdm0Snap.docs) {
        insertPreferringADM1(docs: userById, polys: userPoly, d: d);
      }

      // ---------- OTHERS (public): ADM1 ----------
      final adm1RootsPublic =
          await fs.collection('regions').doc(regIdCanonical).collection('adm1').get();

      for (final adm in adm1RootsPublic.docs) {
        final others = await adm.reference
            .collection('properties')
            .where('ownerUid', isNotEqualTo: ownerUid)
            .get();
        for (final d in others.docs) {
          insertPreferringADM1(docs: othersById, polys: othersPoly, d: d);
        }
      }

      // ---------- OTHERS (public): ADM0 aggregate ----------
      final othersAdm0Snap = await fs
          .collection('regions')
          .doc(regIdCanonical)
          .collection('properties')
          .where('ownerUid', isNotEqualTo: ownerUid)
          .get();
      for (final d in othersAdm0Snap.docs) {
        insertPreferringADM1(docs: othersById, polys: othersPoly, d: d);
      }

      // ---- Convert to ordered lists (newest first by updatedAt/timestamp) ----
      int cmpDocs(DocumentSnapshot a, DocumentSnapshot b) {
        final da = (a.data() ?? {}) as Map<String, dynamic>;
        final db = (b.data() ?? {}) as Map<String, dynamic>;
        final atA = da['updatedAt'] ?? da['timestamp'];
        final atB = db['updatedAt'] ?? db['timestamp'];
        final ta =
            (atA is Timestamp) ? atA.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        final tb =
            (atB is Timestamp) ? atB.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      }

      final userDocsOrdered = userById.values.toList()..sort(cmpDocs);
      final othersDocsOrdered = othersById.values.toList()..sort(cmpDocs);

      final newUserPolys = <List<ll.LatLng>>[];
      final newUserDocs = <DocumentSnapshot>[];
      for (final d in userDocsOrdered) {
        final id = ((d.data() ?? {}) as Map<String, dynamic>)['id']?.toString() ?? d.id;
        final pts = userPoly[id] ?? const <ll.LatLng>[];
        if (pts.length >= 3) {
          newUserPolys.add(pts);
          newUserDocs.add(d);
        }
      }

      final newOtherPolys = <List<ll.LatLng>>[];
      final newOtherDocs = <DocumentSnapshot>[];
      for (final d in othersDocsOrdered) {
        final id = ((d.data() ?? {}) as Map<String, dynamic>)['id']?.toString() ?? d.id;
        final pts = othersPoly[id] ?? const <ll.LatLng>[];
        if (pts.length >= 3) {
          newOtherPolys.add(pts);
          newOtherDocs.add(d);
        }
      }

      if (!mounted) return;
      setState(() {
        userPolygons = newUserPolys;
        userPolygonDocs = newUserDocs;
        otherPolygons = newOtherPolys;
        otherPolygonDocs = newOtherDocs;
      });

      debugPrint(
          '👤 userPolygons=${userPolygons.length}, 👥 otherPolygons=${otherPolygons.length} [ADM0+ADM1, de-duped]');
    } catch (e) {
      debugPrint("Failed to load saved polygons (ADM0+ADM1): $e");
    } finally {
      // Try pending alias now that lists are populated.
      await _consumePendingAliasIfReady();
    }
  }

  Future<void> backfillAdm1Parents(String uid, String regionIdRaw) async {
    final fs = FirebaseFirestore.instance;
    final regionId = canonicalizeRegionId(regionIdRaw);
    final q = await fs
        .collectionGroup('properties')
        .where('ownerUid', isEqualTo: uid)
        .where('regionId', isEqualTo: regionId)
        .get();

    final batch = fs.batch();
    for (final d in q.docs) {
      final data = d.data();
      final base = (data['adm1Base'] ?? '').toString();
      final adm1Id = (data['adm1Id'] ?? '').toString();
      if (base.isEmpty) continue;

      batch.set(
        fs.doc('users/$uid/regions/$regionId/adm1/$base'),
        {"base": base, "adm1Id": adm1Id, "regionId": regionId, "updatedAt": FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      batch.set(
        fs.doc('regions/$regionId/adm1/$base'),
        {"base": base, "adm1Id": adm1Id, "regionId": regionId, "updatedAt": FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> savePolygon() async {
    if (!mounted) return;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must be signed in to save.")),
      );
      return;
    }
    if (currentPolygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add at least 3 points before saving.")),
      );
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    // --- resolve regionId from geojson path first (prevents Cameroon/Nigeria mixups)
    String regionIdFromGeojsonPath(String? p) {
      if (p == null || p.isEmpty) return canonicalizeRegionId(widget.regionId);
      final m = RegExp(r'([^/\\]+)\.geojson$', caseSensitive: false).firstMatch(p);
      if (m != null && m.groupCount >= 1) {
        return canonicalizeRegionId(m.group(1)!);
      }
      return canonicalizeRegionId(widget.regionId);
    }

    // ---- Build title + alias (same behavior)
    String llid, alias, aliasKey;
    try {
      final center = _calculateCentroid(currentPolygonPoints);
      final placemarks = await placemarkFromCoordinates(center.latitude, center.longitude)
          .timeout(const Duration(seconds: 3));
      final city = placemarks.isNotEmpty
          ? (placemarks.first.locality ??
              placemarks.first.subAdministrativeArea ??
              'Region')
          : 'Region';
      final shortCity = city.replaceAll(' ', '');
      final uniquePart = const Uuid().v4().substring(0, 6).toUpperCase();
      llid = 'LL-$shortCity-$uniquePart';
      alias = generateAliasFromCity(city);     // already includes '#'
      aliasKey = _aliasKeyFrom(alias);         // hash-free key
    } catch (_) {
      final fallback = DateFormat('yyyyMMdd').format(DateTime.now());
      llid = 'LL-Region-$fallback';
      alias = '#Plot${_randomCode()}';
      aliasKey = _aliasKeyFrom(alias);
    }

    // ---- Confirm dialog (using Dialog instead of AlertDialog to avoid intrinsic width issues)
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: Container(
            width: 400,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9, // Max 90% of screen height
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(
                  "Save Property",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Text("Title ID: $llid"),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: "Description",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                // Structured address input with auto-fill from polygon center
                AddressInputWidget(
                  initialAddress: _propertyAddress,
                  latitude: _calculatePolygonCenter(currentPolygonPoints).latitude,
                  longitude: _calculatePolygonCenter(currentPolygonPoints).longitude,
                  onAddressChanged: (PropertyAddress address) {
                    _propertyAddress = address;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final images = await _imagePicker.pickMultiImage();
                          if (images.isNotEmpty) {
                            setState(() {
                              _selectedImages.addAll(images);
                            });
                          }
                        },
                        icon: const Icon(Icons.add_photo_alternate),
                        label: Text("Add Photos (${_selectedImages.length})"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final image = await _imagePicker.pickImage(source: ImageSource.camera);
                          if (image != null) {
                            setState(() {
                              _selectedImages.add(image);
                            });
                          }
                        },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text("Take Photo"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_selectedImages.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    "Selected Photos (${_selectedImages.length})",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 100,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(8),
                      itemCount: _selectedImages.length,
                      itemBuilder: (context, index) {
                        final image = _selectedImages[index];
                        return Container(
                          width: 80,
                          height: 80,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade400, width: 2),
                          ),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 80,
                                  height: 80,
                                  child: kIsWeb
                                      ? Image.network(
                                          image.path,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.grey.shade200,
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.image, size: 24),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    image.name.length > 10
                                                        ? '${image.name.substring(0, 10)}...'
                                                        : image.name,
                                                    style: const TextStyle(fontSize: 8),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        )
                                      : Image.file(
                                          File(image.path),
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.grey.shade200,
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.image, size: 24),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    image.name.length > 10
                                                        ? '${image.name.substring(0, 10)}...'
                                                        : image.name,
                                                    style: const TextStyle(fontSize: 8),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ),
                              // Remove button
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedImages.removeAt(index);
                                    });
                                  },
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade600,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Cancel"),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Save"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
    if (ok != true) {
      _selectedImages.clear();
      if (mounted) setState(() => _isSaving = false);
      return;
    }

    // ---- Capture inputs BEFORE clearing
    final capturedDescription = descriptionController.text.trim();
    final capturedAddress = _propertyAddress; // Structured address object
    final capturedWallet = await getCurrentUserWallet() ?? '';
    final capturedImages = List<XFile>.from(_selectedImages);

    debugPrint("💾 Starting save operation...");
    debugPrint("💾 Description: $capturedDescription");
    debugPrint("💾 Address: ${capturedAddress?.toDisplayString() ?? 'No address'}");
    debugPrint("💾 Images: ${capturedImages.length}");

    try {
      // 1) Close & quantize ring
      debugPrint("💾 Step 1: Closing and quantizing ring...");
      final closed = _ensureClosed(currentPolygonPoints);
      debugPrint("✅ Step 1 complete: ${closed.length} points");

      // 2) Centroid (and basic checks)
      debugPrint("💾 Step 2: Calculating centroid...");
      final centroid = _calculateCentroid(closed);
      debugPrint("✅ Step 2 complete: centroid at ${centroid.latitude}, ${centroid.longitude}");

      // 3) Detect enclosing ADM1 (base id)
      debugPrint("💾 Step 3: Detecting ADM1 region...");
      final adm1Id = _pickAdm1ForPoint(centroid);
      if (adm1Id == null) {
        debugPrint("❌ No ADM1 region found for centroid");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Draw your polygon inside a state/province boundary.")),
        );
        return;
      }
      final adm1Base = _admBaseOf(adm1Id);
      debugPrint("✅ Step 3 complete: adm1Id=$adm1Id, adm1Base=$adm1Base");

      // 4) Canonical region ids/names — derive from geojson path as source of truth
      debugPrint("💾 Step 4: Getting region IDs...");
      final regionIdCanonical = regionIdFromGeojsonPath(widget.geojsonPath);
      final displayRegionName = currentRegion?.name ?? widget.regionId;
      debugPrint("✅ Step 4 complete: regionId=$regionIdCanonical, name=$displayRegionName");

      // 5) Area & bbox
      debugPrint("💾 Step 5: Calculating area and bbox...");
      final areaSqKm = calculateArea(closed);
      final bbox = _bboxOf(closed);
      debugPrint("✅ Step 5 complete: area=$areaSqKm km²");

      // 5.5) Upload photos to Firebase Storage with timeout
      final List<String> photoUrls = [];
      if (capturedImages.isNotEmpty) {
        debugPrint("📸 Step 5.5: Starting upload of ${capturedImages.length} photos with 30s timeout per photo...");

        for (int i = 0; i < capturedImages.length; i++) {
          try {
            final file = capturedImages[i];
            debugPrint("📸 Uploading photo $i: ${file.name}");

            // Get file extension safely
            String extension = 'jpg';
            if (file.name.contains('.')) {
              extension = file.name.split('.').last.toLowerCase();
            }

            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final storagePath = 'properties/$llid/photo_${timestamp}_$i.$extension';
            final storageRef = FirebaseStorage.instance.ref().child(storagePath);

            debugPrint("📸 Storage path: $storagePath");

            // Add timeout to prevent hanging
            if (kIsWeb) {
              debugPrint("📸 Reading file bytes for web upload...");
              final bytes = await file.readAsBytes().timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw TimeoutException('Reading file took too long'),
              );
              debugPrint("📸 Read ${bytes.length} bytes, starting upload...");
              final uploadTask = await storageRef.putData(bytes).timeout(
                const Duration(seconds: 30),
                onTimeout: () => throw TimeoutException('Upload took too long'),
              );
              final downloadUrl = await uploadTask.ref.getDownloadURL().timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw TimeoutException('Getting download URL took too long'),
              );
              photoUrls.add(downloadUrl);
              debugPrint("✅ Photo $i uploaded successfully");
            } else {
              debugPrint("📸 Starting file upload for mobile...");
              final uploadTask = await storageRef.putFile(File(file.path)).timeout(
                const Duration(seconds: 30),
                onTimeout: () => throw TimeoutException('Upload took too long'),
              );
              final downloadUrl = await uploadTask.ref.getDownloadURL().timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw TimeoutException('Getting download URL took too long'),
              );
              photoUrls.add(downloadUrl);
              debugPrint("✅ Photo $i uploaded successfully");
            }
          } on TimeoutException catch (e) {
            debugPrint("⏱️ Photo $i upload timed out: $e");
            debugPrint("⚠️ Skipping this photo and continuing...");
          } catch (e, stackTrace) {
            debugPrint("❌ Failed to upload photo $i: $e");
            debugPrint("❌ Stack trace: $stackTrace");
            // Continue with other photos even if one fails
          }
        }
        debugPrint("📸 Upload complete. ${photoUrls.length} out of ${capturedImages.length} photos uploaded successfully.");
      } else {
        debugPrint("📸 No photos to upload, skipping step 5.5");
      }

      // 6) Build doc body (normalized fields)
      debugPrint("💾 Step 6: Building document data...");
      final fs = FirebaseFirestore.instance;
      final now = FieldValue.serverTimestamp();
      final propId = llid;
      final baseData = {
        "id": propId,
        "title_number": llid,
        "alias": alias,           // e.g. "#LTN2460"
        "aliasKey": aliasKey,     // e.g. "LTN2460"
        "description": capturedDescription,

        // Structured address data (for blockchain and database)
        "address": capturedAddress?.toJson(),  // Full structured address
        "addressString": capturedAddress?.toDisplayString() ?? '',  // Formatted string for display

        "wallet_address": capturedWallet,
        "ownerUid": user!.uid,

        "regionId": regionIdCanonical,
        "regionName": displayRegionName,
        "adm1Id": adm1Id,
        "adm1Base": adm1Base,

        "coordinates": closed
            .map((p) => {"lat": _q6(p.latitude), "lng": _q6(p.longitude)})
            .toList(),
        "centroid": {"lat": _q6(centroid.latitude), "lng": _q6(centroid.longitude)},
        "bbox": bbox,
        "area_sqkm": areaSqKm,

        "photoUrls": photoUrls,

        "createdAt": now,
        "updatedAt": now,
        "timestamp": now, // legacy UI
      };
      debugPrint("✅ Step 6 complete: baseData has ${baseData.length} fields, ${photoUrls.length} photos");

      // 7) Firestore writes (ensure ADM1 parents exist) + ADM0 copies + legacy flat
      debugPrint("💾 Step 7: Preparing batch write to Firestore...");
      final batch = fs.batch();

      // Ensure country parent exists (helps console navigation)
      final userRegionDoc = fs.doc("users/${user!.uid}/regions/$regionIdCanonical");
      batch.set(
        userRegionDoc,
        {"regionId": regionIdCanonical, "regionName": displayRegionName, "updatedAt": now},
        SetOptions(merge: true),
      );

      final publicRegionDoc = fs.doc("regions/$regionIdCanonical");
      batch.set(
        publicRegionDoc,
        {"regionId": regionIdCanonical, "regionName": displayRegionName, "updatedAt": now},
        SetOptions(merge: true),
      );

      // --- NEW: create ADM1 parent docs (so collection('adm1').get() sees them)
      final userAdm1Parent =
          fs.doc("users/${user!.uid}/regions/$regionIdCanonical/adm1/$adm1Base");
      final publicAdm1Parent =
          fs.doc("regions/$regionIdCanonical/adm1/$adm1Base");
      final parentPayload = {
        "base": adm1Base,
        "adm1Id": adm1Id,
        "regionId": regionIdCanonical,
        "updatedAt": now,
      };
      batch.set(userAdm1Parent, parentPayload, SetOptions(merge: true));
      batch.set(publicAdm1Parent, parentPayload, SetOptions(merge: true));

      // ---- USER / ADM1 (authoritative per-state)
      final userAdm1Doc =
          fs.doc("users/${user!.uid}/regions/$regionIdCanonical/adm1/$adm1Base/properties/$propId");
      batch.set(userAdm1Doc, {...baseData, "admLevel": "ADM1"}, SetOptions(merge: true));

      // ---- PUBLIC / ADM1
      final publicAdm1Doc =
          fs.doc("regions/$regionIdCanonical/adm1/$adm1Base/properties/$propId");
      batch.set(publicAdm1Doc, {...baseData, "admLevel": "ADM1"}, SetOptions(merge: true));

      // ---- USER / ADM0 (country aggregate)
      final userAdm0Doc =
          fs.doc("users/${user!.uid}/regions/$regionIdCanonical/properties/$propId");
      batch.set(userAdm0Doc, {...baseData, "admLevel": "ADM0"}, SetOptions(merge: true));

      // ---- PUBLIC / ADM0
      final publicAdm0Doc =
          fs.doc("regions/$regionIdCanonical/properties/$propId");
      batch.set(publicAdm0Doc, {...baseData, "admLevel": "ADM0"}, SetOptions(merge: true));

      // ---- Legacy flat (keep while migrating readers)
      final legacyFlat = fs.doc("users/${user!.uid}/regions/$propId");
      batch.set(legacyFlat, {...baseData, "migratedFromFlat": true}, SetOptions(merge: true));

      debugPrint("💾 Committing batch write to Firestore...");
      await batch.commit();
      debugPrint("✅ Batch write completed successfully");

      // Re-read authoritative user ADM1 copy & update local UI
      debugPrint("💾 Reading back saved document...");
      final newSnap = await userAdm1Doc.get();
      debugPrint("✅ Document read successfully");
      if (!mounted) return;
      setState(() {
        userPolygons.add(closed);
        userPolygonDocs.add(newSnap);
        selectedPolygon = closed;
        _selectedPolygonDoc = newSnap;
        isDrawing = false;
        currentPolygonPoints = [];
      });

      descriptionController.clear();
      _propertyAddress = null; // Clear structured address
      _selectedImages.clear();

      _admCtl.setShading(_regionFillVisible);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            photoUrls.isNotEmpty
                ? "Property saved with ${photoUrls.length} photo(s)!"
                : "Property saved to state/province & country."
          ),
        ),
      );

      // 8) Fire & forget: blockchain
      // ignore: unawaited_futures
      saveToBlockchainSilent(llid, closed, capturedWallet, capturedDescription, capturedAddress);

      // 9) Refresh lists in background (optional)
      // ignore: unawaited_futures
      _loadUserSavedPolygons();
    } catch (e, stackTrace) {
      debugPrint("❌ Save failed: $e");
      debugPrint("❌ Stack trace: $stackTrace");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save: $e"),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      debugPrint("💾 Save operation completed (success or failure)");
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Build polygon set with caching to avoid recreation
  Set<gmap.Polygon> _buildPolygonSet(Set<gmap.Polygon> admPolys, bool isUS) {
    // Calculate hash of current state
    final currentHash = Object.hash(
      admPolys.length,
      userPolygons.length,
      otherPolygons.length,
      currentPolygonPoints.length,
      isDrawing,
      selectedPolygon,
      widget.highlightPolygon,
      _regionFillVisible,
    );

    // Return cached polygons if nothing changed
    if (currentHash == _lastPolygonHash && _cachedPolygons.isNotEmpty) {
      return _cachedPolygons;
    }

    _lastPolygonHash = currentHash;

    // Build our polygons manually so ADM polygons can be interacted with
    final Set<gmap.Polygon> polys = <gmap.Polygon>{};

    // ---- Rebuild ADM cache (group by base name) ----
    _admRingsByBase.clear();
    for (final p in admPolys) {
      final raw = p.polygonId.value; // e.g., "Littoral #0"
      final base = _prettyAdmId(raw); // "Littoral"
      final ringLL = p.points
          .map((pp) => ll.LatLng(pp.latitude, pp.longitude))
          .toList(growable: false);
      (_admRingsByBase[base] ??= <List<ll.LatLng>>[]).add(ringLL);
    }

        // --- ADM polygons (states/provinces) ---
        if (!isDrawing) {
          final isUS = canonicalizeRegionId(widget.regionId) == _US_REGION_ID ||
              (widget.geojsonPath ?? '').toLowerCase().contains('united_states.geojson');

          for (final p in admPolys) {
            final regionId = p.polygonId.value; // raw id (may have #N)
            final baseId = _prettyAdmId(regionId); // e.g., "Texas" (no " #0")
            if (isUS && _US_TERRITORIES_AND_DC.contains(baseId)) {
              // skip territories + DC
              continue;
            }

            // Simplify polygon using Douglas-Peucker-like algorithm for smoother boundaries
            final rawPts = p.points;
            final pointsCopy = rawPts.length > 1000
                ? _simplifyPolygon(rawPts, tolerance: 0.0001) // Simplify large polygons
                : List<gmap.LatLng>.from(rawPts); // Keep smaller polygons as-is

            final cloneId = gmap.PolygonId('adm_clone_$regionId');
            final hideThis = _hiddenAdmRegions.contains(baseId);

            polys.add(gmap.Polygon(
              polygonId: cloneId,
              points: pointsCopy,
              strokeWidth: (_regionFillVisible && !hideThis) ? 2 : p.strokeWidth,
              strokeColor: (_regionFillVisible && !hideThis)
                  ? Colors.orange.withValues(alpha: 0.8)  // Visible orange border when highlighted
                  : p.strokeColor,
              fillColor: (_regionFillVisible && !hideThis)
                  ? Colors.orange.withValues(alpha: 0.05)  // Very subtle orange tint instead of blue
                  : p.fillColor.withValues(alpha: 0.0),
              zIndex: 500,
              consumeTapEvents: true,
              onTap: isDrawing
                  ? null
                  : () async {
                      // Small delay to let higher-zIndex polygon taps process first
                      await Future.delayed(const Duration(milliseconds: 50));

                      // Don't zoom if a user/other polygon was selected
                      // (prevents zooming out when user taps their own polygon)
                      if (selectedPolygon != null && _showPolygonInfo) {
                        return; // User tapped a property polygon, don't zoom to region
                      }

                      _lastTappedRegion = regionId;
                      await _focusRegionOnTap(regionId, pointsCopy);
                      _promptRegionDetails(regionId);
                      if (widget.onRegionSelected != null && widget.geojsonPath != null) {
                        widget.onRegionSelected!(regionId, widget.geojsonPath!);
                      }
                    },
            ));
          }
        }

        // Drawing polygon
        if (currentPolygonPoints.length >= 3) {
          polys.add(gmap.Polygon(
            polygonId: const gmap.PolygonId('drawing'),
            points: _gList(currentPolygonPoints),
            strokeWidth: 2,
            strokeColor: Colors.blue,
            fillColor: Colors.blue.withValues(alpha: 0.22),
            consumeTapEvents: false,
            zIndex: 1200,
          ));
        }

        // User polygons in BLUE (always render with blue highlight)
        for (int i = 0; i < userPolygons.length; i++) {
          final poly = userPolygons[i];
          if (poly.length < 3) continue;

          // Check if this is the highlighted polygon from external screen
          final isHighlighted = widget.highlightPolygon != null &&
                                _samePolygon(poly, widget.highlightPolygon!);
          final isSelected = identical(selectedPolygon, poly) && _showPolygonInfo;

          polys.add(gmap.Polygon(
            polygonId: gmap.PolygonId('user_$i'),
            points: _gList(poly),
            strokeWidth: (isHighlighted || isSelected) ? 3 : 2,
            strokeColor: Colors.blue,  // Always blue
            fillColor: Colors.blue.withValues(
              alpha: (isHighlighted || isSelected) ? 0.45 : 0.28  // More visible when highlighted/selected
            ),
            consumeTapEvents: !isDrawing,
            onTap: isDrawing
                ? null
                : () {
                    setState(() {
                      selectedPolygon = poly;
                      _selectedPolygonDoc = userPolygonDocs[i];
                      _showPolygonInfo = true; // show card
                    });
                  },
            zIndex: (isHighlighted || isSelected) ? 1100 : 1030,
          ));
        }

        // Others in GREY
        for (int i = 0; i < otherPolygons.length; i++) {
          final poly = otherPolygons[i];
          if (poly.length < 3) continue;
          final isSelected = identical(selectedPolygon, poly) && _showPolygonInfo;
          polys.add(gmap.Polygon(
            polygonId: gmap.PolygonId('other_$i'),
            points: _gList(poly),
            strokeWidth: isSelected ? 3 : 2,
            strokeColor: Colors.grey,  // Always grey
            fillColor: Colors.grey.withValues(
              alpha: isSelected ? 0.45 : 0.20  // More visible when selected
            ),
            consumeTapEvents: !isDrawing,
            onTap: isDrawing
                ? null
                : () {
                    setState(() {
                      selectedPolygon = poly;
                      _selectedPolygonDoc = otherPolygonDocs[i];
                      _showPolygonInfo = true; // show card
                    });
                  },
            zIndex: isSelected ? 1020 : 1010,
          ));
        }

        // Cache and return the polygon set
        _cachedPolygons = polys;
        return polys;
  }

  Widget _buildGoogleMap({required bool isUS}) {
    // For US region, use CONUS center immediately to prevent jarring transition from Nigeria
    ll.LatLng initCenter;
    if (isUS) {
      initCenter = _kConusCenter; // Use CONUS center immediately for US
    } else {
      initCenter = currentRegion?.center ?? _regionCenterComputed ?? const ll.LatLng(9.0, 8.0);
    }

    final double initZoom = (currentRegion?.zoomLevel ?? 5).toDouble();

    final gmap.CameraPosition camPos = gmap.CameraPosition(
      target: gmap.LatLng(initCenter.latitude, initCenter.longitude),
      zoom: initZoom,
    );

    return ValueListenableBuilder<Set<gmap.Polygon>>(
      valueListenable: _admCtl.polygonsNotifier,
      builder: (context, admPolys, _) {
        // Build polygons with caching
        final polys = _buildPolygonSet(admPolys, isUS);

        // Build markers for polygon points when drawing
        final Set<gmap.Marker> markers = {};
        if (isDrawing && currentPolygonPoints.isNotEmpty) {
          for (int i = 0; i < currentPolygonPoints.length; i++) {
            final point = currentPolygonPoints[i];
            markers.add(
              gmap.Marker(
                markerId: gmap.MarkerId('point_$i'),
                position: gmap.LatLng(point.latitude, point.longitude),
                draggable: true,
                onDragEnd: (newPosition) {
                  setState(() {
                    currentPolygonPoints[i] = ll.LatLng(
                      newPosition.latitude,
                      newPosition.longitude,
                    );
                  });
                },
                onTap: () {
                  // Show option to delete this point
                  _showPointOptions(i);
                },
                icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                  i == 0 ? gmap.BitmapDescriptor.hueGreen : gmap.BitmapDescriptor.hueRed,
                ),
                infoWindow: gmap.InfoWindow(
                  title: i == 0 ? 'Start Point' : 'Point ${i + 1}',
                  snippet: '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                ),
              ),
            );
          }
        }

        return gmap.GoogleMap(
          mapType: showSatellite ? gmap.MapType.hybrid : gmap.MapType.normal,
          initialCameraPosition: camPos,
          polygons: polys,
          markers: markers,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (c) async {
            _gController = c;
            // IMPORTANT: do not attach _admCtl to the map controller here to avoid double rendering
            _currentZoom = await c.getZoomLevel();

            await _centerInitialIfReady();

            if (widget.highlightPolygon != null && widget.highlightPolygon!.isNotEmpty) {
              await _fitToPolygonIfAny();
            } else if (widget.centerOnRegion && _regionBoundsGoogle != null) {
              await Future.delayed(const Duration(milliseconds: 50));
              if (mounted) {
                // First fit to bounds with minimal padding
                await _gController!.animateCamera(
                  gmap.CameraUpdate.newLatLngBounds(_regionBoundsGoogle!, 1),
                );

                // Then zoom in 2 more clicks
                await Future.delayed(const Duration(milliseconds: 300));
                final currentZoom = await _gController!.getZoomLevel();
                await _gController!.animateCamera(
                  gmap.CameraUpdate.zoomTo(currentZoom + 2),
                );
              }
            }
          },
          onTap: (gmap.LatLng p) => _handleTap(ll.LatLng(p.latitude, p.longitude)),
          onCameraMove: (pos) {
            _currentZoom = pos.zoom;
            _currentCenter = ll.LatLng(pos.target.latitude, pos.target.longitude);
            // Increased debounce to 200ms and only update if needed
            _moveDebounce?.cancel();
            _moveDebounce = Timer(const Duration(milliseconds: 200), () {
              // Only rebuild if there are UI elements that depend on camera position
              if (mounted && (isDrawing || _showPolygonInfo)) {
                setState(() {});
              }
            });
          },
        );
      },
    );
  }

  double calculateArea(List<ll.LatLng> points) {
    if (points.length < 3) return 0;
    double area = 0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      area += points[i].latitude * points[j].longitude;
      area -= points[j].latitude * points[i].longitude;
    }
    // very rough planar -> km²
    return (area.abs() / 2) * 111 * 111;
  }

  ll.LatLng _calculateCentroid(List<ll.LatLng> points) => _centroid(points);

  void _showBlockchainSuccessCard({
    required String parcelId,
    required String owner,
    String? description,
    DateTime? createdAt,
  }) {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final ts = createdAt != null
            ? DateFormat('MMM d, y • HH:mm').format(createdAt.toLocal())
            : 'Just now';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Color(0xFF1B5E20)),
                  const SizedBox(width: 8),
                  Text(
                    'Saved to LandLedger',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text('Parcel: $parcelId',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          Chip(label: Text('Owner: $owner')),
                          Chip(label: Text('Time: $ts')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if ((description ?? '').isNotEmpty)
                        Text(
                          description!,
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Parcel ID'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: parcelId));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Parcel ID copied')),
                        );
                      }
                    },
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: const Icon(Icons.public),
                    label: const Text('OK'),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> saveToBlockchainSilent(
    String id,
    List<ll.LatLng> points,
    String wallet,
    String description,
    PropertyAddress? address,
  ) async {
    final url = Uri.parse('$_apiBase/api/landledger/polygons');
    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "uid": user?.uid ?? 'unknown',
          "polygon": {
            "parcelId": id,
            "titleNumber": id,
            "owner": wallet,
            "coordinates":
                points.map((p) => {"lat": p.latitude, "lng": p.longitude}).toList(),
            "areaSqKm": calculateArea(points),
            "description": description,
            "address": address?.toJson(),
            "addressString": address?.toDisplayString() ?? '',
          }
        }),
      );

      if (res.statusCode != 200) {
        debugPrint("❌ Blockchain Error: ${res.body}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Blockchain write failed: ${res.statusCode}")),
          );
        }
        return;
      }

      debugPrint("✅ Blockchain saved for $id");

      DateTime? created;
      try {
        final jsonBody = jsonDecode(res.body);
        final createdRaw = jsonBody['createdAt'] ?? jsonBody['timestamp'];
        if (createdRaw is String && createdRaw.isNotEmpty) {
          created = DateTime.tryParse(createdRaw);
        }
      } catch (_) {}

      widget.onBlockchainUpdate?.call({
        "parcelId": id,
        "owner": wallet,
        "description": description,
        "createdAt": created?.toIso8601String(),
      });

      _showBlockchainSuccessCard(
        parcelId: id,
        owner: wallet.isEmpty ? '—' : wallet,
        description: description,
        createdAt: created,
      );
    } catch (e) {
      debugPrint("❌ Blockchain request failed: $e");
      String errorMessage = "Failed to save to blockchain";
      if (e.toString().contains("not found in contract")) {
        errorMessage = "Blockchain contract functions not available. Please contact support.";
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> fetchPolygonFromBlockchain(String id) async {
    final url = Uri.parse('$_apiBase/api/landledger/$id');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final coordinates =
            (jsonBody['polygon'] as List).map((coord) => ll.LatLng(coord[1], coord[0])).toList();
        return {
          "polygon": coordinates,
          "owner": jsonBody['owner'],
          "description": jsonBody['description'],
          "timestamp": jsonBody['createdAt'],
        };
      } else {
        debugPrint("❌ Failed to fetch: ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ Error fetching from blockchain: $e");
      return null;
    }
  }

  Widget buildMapControls() {
    return Stack(
      children: [
        if (_showPolygonInfo && _selectedPolygonDoc != null) buildPolygonInfoCard(),

        // Coordinate info panel at top left when drawing
        if (isDrawing)
          Positioned(
            top: 16,
            left: 16,
            child: Card(
              elevation: 8,
              child: Container(
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxWidth: 250),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.draw, size: 18, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text(
                          'Drawing Mode',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Text(
                      'Points: ${currentPolygonPoints.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (currentPolygonPoints.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last: ${currentPolygonPoints.last.latitude.toStringAsFixed(6)}, ${currentPolygonPoints.last.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                    if (currentPolygonPoints.length >= 3) ...[
                      const SizedBox(height: 8),
                      Builder(builder: (context) {
                        final areaSqM = calculateArea(currentPolygonPoints) * 1e6;
                        final display = areaSqM >= 100000
                            ? "${(areaSqM / 1e6).toStringAsFixed(2)} km²"
                            : "${areaSqM.toStringAsFixed(0)} m²";
                        return Text(
                          'Area: $display',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green),
                        );
                      }),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      '• Tap map to add points\n• Drag markers to adjust\n• Tap markers for options',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),

        Positioned(
          bottom: 100,
          right: 16,
          child: Column(
            children: [
              FloatingActionButton(
                heroTag: "btn-center",
                mini: true,
                onPressed: centerToUserLocation,
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(height: 8),
              // City selector button (only when NOT drawing)
              if (!isDrawing)
                FloatingActionButton(
                  heroTag: "btn-city-selector",
                  mini: true,
                  backgroundColor: Colors.blue.shade700,
                  onPressed: _showCitySelector,
                  child: const Icon(Icons.location_city, size: 20),
                ),
              if (!isDrawing)
                const SizedBox(height: 8),
              // Undo button when drawing
              if (isDrawing && currentPolygonPoints.isNotEmpty)
                FloatingActionButton(
                  heroTag: "btn-undo",
                  mini: true,
                  backgroundColor: Colors.orange,
                  onPressed: () {
                    setState(() {
                      if (currentPolygonPoints.isNotEmpty) {
                        currentPolygonPoints.removeLast();
                      }
                    });
                  },
                  child: const Icon(Icons.undo),
                ),
              if (isDrawing && currentPolygonPoints.isNotEmpty)
                const SizedBox(height: 8),
              // Clear all button when drawing
              if (isDrawing && currentPolygonPoints.length > 1)
                FloatingActionButton(
                  heroTag: "btn-clear",
                  mini: true,
                  backgroundColor: Colors.red.shade700,
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Clear All Points?'),
                        content: Text('Remove all ${currentPolygonPoints.length} points?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('Clear All'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      setState(() {
                        currentPolygonPoints.clear();
                      });
                    }
                  },
                  child: const Icon(Icons.clear_all),
                ),
              if (isDrawing && currentPolygonPoints.length > 1)
                const SizedBox(height: 8),
              // Drawing mode buttons
              if (isDrawing) ...[
                // Cancel drawing button (always visible when drawing)
                FloatingActionButton(
                  heroTag: "btn-cancel-draw",
                  backgroundColor: Colors.grey.shade700,
                  child: const Icon(Icons.close),
                  onPressed: () async {
                    // Ask for confirmation if there are points
                    if (currentPolygonPoints.isNotEmpty) {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Cancel Drawing?'),
                          content: Text(
                            'You have ${currentPolygonPoints.length} point(s). '
                            'All progress will be lost.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Keep Drawing'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              child: const Text('Cancel & Exit'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                    }

                    setState(() {
                      isDrawing = false;
                      currentPolygonPoints = [];
                      selectedPolygon = null;
                      _showPolygonInfo = false;
                    });
                    _admCtl.setShading(_regionFillVisible);
                  },
                ),
                const SizedBox(height: 8),
                // Save button (only when 3+ points)
                if (currentPolygonPoints.length >= 3)
                  Column(
                    children: [
                      Builder(builder: (context) {
                        final areaSqM = calculateArea(currentPolygonPoints) * 1e6;
                        final display = areaSqM >= 100000
                            ? "${(areaSqM / 1e6).toStringAsFixed(2)} km²"
                            : "${areaSqM.toStringAsFixed(0)} m²";
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            display,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        );
                      }),
                      FloatingActionButton(
                        heroTag: "btn-save",
                        backgroundColor: Colors.green,
                        onPressed: _isSaving ? null : savePolygon,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                      ),
                    ],
                  ),
              ] else
                FloatingActionButton(
                  heroTag: "btn-draw-toggle",
                  backgroundColor: const Color.fromARGB(255, 2, 76, 63),
                  child: const Icon(Icons.edit_location_alt),
                  onPressed: () async {
                    final ok = await confirmOnChain(context,
                      title: 'Draw Polygon',
                      summary: 'You are about to draw a polygon for a new parcel. This will lead to a signed transaction.');
                    if (!ok) return;

                    setState(() {
                      isDrawing = true;
                      currentPolygonPoints = [];
                      selectedPolygon = null;
                      _showPolygonInfo = false;
                    });
                    _admCtl.setShading(!isDrawing && _regionFillVisible);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildPolygonInfoCard() {
    if (_selectedPolygonDoc == null) return const SizedBox.shrink();
    final data = (_selectedPolygonDoc!.data() ?? {}) as Map<String, dynamic>;
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: () => setState(() {
          _showPolygonInfo = false;
          selectedPolygon = null;  // Reset selection to revert polygon color
          _selectedPolygonDoc = null;
        }),
        child: Card(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(
                    (data['title_number'] ?? 'No Title').toString(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (data.containsKey('alias'))
                    InkWell(
                      onTap: () => _goToAlias((data['alias'] ?? '').toString()),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _ensureSingleHash((data['alias'] ?? '').toString()),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _showPolygonInfo = false;
                      selectedPolygon = null;  // Reset selection to revert polygon color
                      _selectedPolygonDoc = null;
                    }),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Description: ${data['description'] ?? 'No description'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                // Address display (structured)
                _buildAddressDisplay(data),
                const SizedBox(height: 8),
                // Photo gallery
                if (data['photoUrls'] != null && (data['photoUrls'] as List).isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Photos (${(data['photoUrls'] as List).length}):',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 200,
                        child: PageView.builder(
                          itemCount: (data['photoUrls'] as List).length,
                          itemBuilder: (context, index) {
                            final photoUrl = (data['photoUrls'] as List)[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      photoUrl,
                                      width: double.infinity,
                                      height: 200,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Center(
                                          child: CircularProgressIndicator(
                                            value: loadingProgress.expectedTotalBytes != null
                                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                : null,
                                          ),
                                        );
                                      },
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          color: Colors.grey[300],
                                          child: const Center(
                                            child: Icon(Icons.error_outline, size: 50, color: Colors.red),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  // Photo counter badge
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${index + 1}/${(data['photoUrls'] as List).length}',
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                // Edit Photos button - only for property owner
                const SizedBox(height: 8),
                if (data['ownerUid'] == user?.uid)
                  ElevatedButton.icon(
                    onPressed: () => _editPropertyPhotos(data),
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: Text(
                      data['photoUrls'] != null && (data['photoUrls'] as List).isNotEmpty
                          ? 'Edit Photos (${(data['photoUrls'] as List).length})'
                          : 'Add Photos'
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Only the property owner can edit photos',
                      style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Wallet: ${formatFriendlyWalletSync(data['wallet_address'] ?? '')}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Builder(builder: (context) {
                  final area = (data['area_sqkm'] ?? 0) as num;
                  final areaSqM = area * 1e6;
                  final formatted =
                      areaSqM >= 100000 ? "${(areaSqM / 1e6).toStringAsFixed(2)} km²" : "${areaSqM.toStringAsFixed(0)} m²";
                  return Text("Area: $formatted");
                }),
                const SizedBox(height: 8),
                if (data['timestamp'] is Timestamp)
                  Text(
                    'Created: ${DateFormat('yyyy-MM-dd').format((data['timestamp'] as Timestamp).toDate())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editPropertyPhotos(Map<String, dynamic> propertyData) async {
    debugPrint("📸 Opening photo editor for property: ${propertyData['id']}");

    // ✅ Permission check - only owner can edit photos
    if (propertyData['ownerUid'] != user?.uid) {
      debugPrint("❌ Permission denied: User ${user?.uid} cannot edit photos for property owned by ${propertyData['ownerUid']}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the property owner can edit photos'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Get existing photo URLs
    final existingPhotoUrls = propertyData['photoUrls'] != null
        ? List<String>.from(propertyData['photoUrls'] as List)
        : <String>[];

    // Track which existing photos to keep and which new photos to add
    List<String> photosToKeep = List.from(existingPhotoUrls);
    List<XFile> newPhotosToAdd = [];

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Edit Photos",
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text("Property: ${propertyData['title_number'] ?? 'Unknown'}"),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final images = await _imagePicker.pickMultiImage();
                            if (images.isNotEmpty) {
                              setState(() {
                                newPhotosToAdd.addAll(images);
                              });
                            }
                          },
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text("Add Photos"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final image = await _imagePicker.pickImage(source: ImageSource.camera);
                            if (image != null) {
                              setState(() {
                                newPhotosToAdd.add(image);
                              });
                            }
                          },
                          icon: const Icon(Icons.camera_alt),
                          label: const Text("Take Photo"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Show existing photos
                  if (photosToKeep.isNotEmpty) ...[
                    Text(
                      "Existing Photos (${photosToKeep.length})",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(8),
                        itemCount: photosToKeep.length,
                        itemBuilder: (context, index) {
                          final photoUrl = photosToKeep[index];
                          return Container(
                            width: 80,
                            height: 80,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade400, width: 2),
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    photoUrl,
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey.shade200,
                                        child: const Icon(Icons.image, size: 24),
                                      );
                                    },
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        photosToKeep.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade600,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.3),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Show new photos to add
                  if (newPhotosToAdd.isNotEmpty) ...[
                    Text(
                      "New Photos to Add (${newPhotosToAdd.length})",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.green.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(8),
                        itemCount: newPhotosToAdd.length,
                        itemBuilder: (context, index) {
                          final image = newPhotosToAdd[index];
                          return Container(
                            width: 80,
                            height: 80,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade400, width: 2),
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 80,
                                    height: 80,
                                    child: kIsWeb
                                        ? Image.network(
                                            image.path,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Container(
                                                color: Colors.grey.shade200,
                                                child: const Icon(Icons.image, size: 24),
                                              );
                                            },
                                          )
                                        : Image.file(
                                            File(image.path),
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Container(
                                                color: Colors.grey.shade200,
                                                child: const Icon(Icons.image, size: 24),
                                              );
                                            },
                                          ),
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        newPhotosToAdd.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade600,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.3),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Save Changes"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result != true) {
      debugPrint("📸 Photo edit cancelled");
      return;
    }

    // User confirmed, now upload new photos and update Firestore
    debugPrint("📸 Saving photo changes...");
    debugPrint("📸 Photos to keep: ${photosToKeep.length}");
    debugPrint("📸 New photos to add: ${newPhotosToAdd.length}");

    try {
      // Upload new photos
      final List<String> newPhotoUrls = [];
      if (newPhotosToAdd.isNotEmpty) {
        final propertyId = propertyData['id'] ?? propertyData['title_number'];

        for (int i = 0; i < newPhotosToAdd.length; i++) {
          try {
            final file = newPhotosToAdd[i];
            debugPrint("📸 Uploading new photo $i: ${file.name}");

            String extension = 'jpg';
            if (file.name.contains('.')) {
              extension = file.name.split('.').last.toLowerCase();
            }

            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final storagePath = 'properties/$propertyId/photo_${timestamp}_$i.$extension';
            final storageRef = FirebaseStorage.instance.ref().child(storagePath);

            if (kIsWeb) {
              final bytes = await file.readAsBytes().timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw TimeoutException('Reading file took too long'),
              );
              final uploadTask = await storageRef.putData(bytes).timeout(
                const Duration(seconds: 30),
                onTimeout: () => throw TimeoutException('Upload took too long'),
              );
              final downloadUrl = await uploadTask.ref.getDownloadURL().timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw TimeoutException('Getting download URL took too long'),
              );
              newPhotoUrls.add(downloadUrl);
              debugPrint("✅ New photo $i uploaded successfully");
            } else {
              final uploadTask = await storageRef.putFile(File(file.path)).timeout(
                const Duration(seconds: 30),
                onTimeout: () => throw TimeoutException('Upload took too long'),
              );
              final downloadUrl = await uploadTask.ref.getDownloadURL().timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw TimeoutException('Getting download URL took too long'),
              );
              newPhotoUrls.add(downloadUrl);
              debugPrint("✅ New photo $i uploaded successfully");
            }
          } on TimeoutException catch (e) {
            debugPrint("⏱️ New photo $i upload timed out: $e");
          } catch (e, stackTrace) {
            debugPrint("❌ Failed to upload new photo $i: $e");
            debugPrint("❌ Stack trace: $stackTrace");
          }
        }
      }

      // Combine kept photos + new photos
      final updatedPhotoUrls = [...photosToKeep, ...newPhotoUrls];
      debugPrint("📸 Final photo count: ${updatedPhotoUrls.length}");

      // Update Firestore documents
      final fs = FirebaseFirestore.instance;
      final propertyId = propertyData['id'] ?? propertyData['title_number'];
      final regionId = propertyData['regionId'];
      final adm1Base = propertyData['adm1Base'];

      debugPrint("📸 Updating Firestore documents for property: $propertyId");

      final batch = fs.batch();
      final updateData = {
        'photoUrls': updatedPhotoUrls,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Update all document copies
      if (regionId != null && adm1Base != null) {
        // User ADM1
        final userAdm1Doc = fs.doc("users/${user!.uid}/regions/$regionId/adm1/$adm1Base/properties/$propertyId");
        batch.update(userAdm1Doc, updateData);

        // Public ADM1
        final publicAdm1Doc = fs.doc("regions/$regionId/adm1/$adm1Base/properties/$propertyId");
        batch.update(publicAdm1Doc, updateData);

        // User ADM0
        final userAdm0Doc = fs.doc("users/${user!.uid}/regions/$regionId/properties/$propertyId");
        batch.update(userAdm0Doc, updateData);

        // Public ADM0
        final publicAdm0Doc = fs.doc("regions/$regionId/properties/$propertyId");
        batch.update(publicAdm0Doc, updateData);
      }

      // Legacy flat
      final legacyFlat = fs.doc("users/${user!.uid}/regions/$propertyId");
      batch.update(legacyFlat, updateData);

      await batch.commit();
      debugPrint("✅ Firestore documents updated successfully");

      // Refresh the selected polygon doc to show updated photos
      // Force read from server to avoid stale cache
      if (_selectedPolygonDoc != null) {
        debugPrint("📸 Refreshing document from server...");

        // Add a small delay to ensure Firestore has propagated the changes
        await Future.delayed(const Duration(milliseconds: 500));

        final refreshedDoc = await _selectedPolygonDoc!.reference.get(
          const GetOptions(source: Source.server)
        );

        final refreshedData = refreshedDoc.data() as Map<String, dynamic>?;
        debugPrint("📸 Refreshed doc photo count: ${(refreshedData?['photoUrls'] as List?)?.length ?? 0}");

        if (mounted) {
          setState(() {
            _selectedPolygonDoc = refreshedDoc;

            // Also update the document in userPolygonDocs list
            final docIndex = userPolygonDocs.indexWhere((doc) => doc.id == refreshedDoc.id);
            if (docIndex != -1) {
              debugPrint("📸 Updating userPolygonDocs at index $docIndex");
              userPolygonDocs[docIndex] = refreshedDoc;
            } else {
              debugPrint("📸 Document not found in userPolygonDocs list");
            }
          });
        }
      }

      // Reload all polygons to ensure everything is in sync
      debugPrint("📸 Reloading polygon list in background...");
      // ignore: unawaited_futures
      _loadUserSavedPolygons();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Photos updated! Total: ${updatedPhotoUrls.length}"
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint("❌ Failed to update photos: $e");
      debugPrint("❌ Stack trace: $stackTrace");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update photos: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String> getCityNameFromLatLng(ll.LatLng latLng) async {
    try {
      final placemarks = await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
      if (placemarks.isNotEmpty) {
        return placemarks.first.locality ??
            placemarks.first.subAdministrativeArea ??
            'Unknown City';
      }
    } catch (e) {
      debugPrint("Error during reverse geocoding: $e");
    }
    return 'Unknown City';
  }

  Timer? _moveDebounce;

  @override
  Widget build(BuildContext context) {
    // Define isUS here so it's available to both Google Map and FlutterMap sections
    final isUS = canonicalizeRegionId(widget.regionId) == _US_REGION_ID ||
        (widget.geojsonPath ?? '').toLowerCase().contains('united_states.geojson');

    final topLeftInfo = Positioned(
      top: 16,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration:
            BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20)),
        child: FutureBuilder<String>(
          future: _currentCenter != null ? getCityNameFromLatLng(_currentCenter!) : Future.value('Unknown City'),
          builder: (context, snapshot) {
            final text = (snapshot.connectionState == ConnectionState.waiting)
                ? 'Loading...'
                : (snapshot.hasError || !snapshot.hasData)
                    ? 'Unknown City'
                    : snapshot.data!;
            return Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            );
          },
        ),
      ),
    );

    final bottomLeftInfo = Positioned(
      bottom: 16,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration:
            BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20)),
        child: Text(
          _currentCenter != null
              ? 'Lat: ${_currentCenter!.latitude.toStringAsFixed(5)}, Lng: ${_currentCenter!.longitude.toStringAsFixed(5)}'
              : 'Coords unavailable',
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(currentRegion?.name ?? 'Map View'),
        leading: widget.showBackArrow
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (widget.onBackToHome != null) {
                    widget.onBackToHome!();
                  } else {
                    final navigator = Navigator.of(context);
                    if (navigator.canPop()) {
                      navigator.pop();
                    } else if (widget.openedFromTab && widget.onOpenMyProperties != null) {
                      widget.onOpenMyProperties!();
                    }
                  }
                },
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(showSatellite ? Icons.map : Icons.satellite),
            onPressed: () => setState(() => showSatellite = !showSatellite),
          ),
          IconButton(
            icon: Icon(show3D ? Icons.zoom_out_map : Icons.threed_rotation),
            onPressed: () => setState(() => show3D = !show3D),
          ),
        ],
      ),
      body: Stack(
        children: [
          MouseRegion(
            cursor: isDrawing ? SystemMouseCursors.precise : SystemMouseCursors.basic,
            child: _useGoogle
                ? _buildGoogleMap(isUS: isUS)
                : FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      center: isUS
                          ? _kConusCenter
                          : (currentRegion?.center ?? _regionCenterComputed ?? const ll.LatLng(9.0, 8.0)),
                      zoom: currentRegion?.zoomLevel ?? 5,
                      onTap: _handleMapTapFlutter,
                      onPositionChanged: (MapPosition position, bool hasGesture) {
                        setState(() => _currentCenter = position.center);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            "https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}",
                        additionalOptions: {
                          'accessToken':
                              'pk.eyJ1IjoibW9yZ25jb2x0IiwiYSI6ImNtYng2eHI0ZjB3cjQybW9zNXZhaDJqanYifQ.0qZEU6MBjiTZiUDPs6JyoQ',
                          'id': _mapboxStyleId,
                        },
                        tileSize: 512,
                        zoomOffset: -1,
                        retinaMode: true,
                        maxNativeZoom: 22,
                        maxZoom: 22,
                        tileProvider: CancellableNetworkTileProvider(),
                      ),
                      if (selectedPolygon != null)
                        ColorFiltered(
                          colorFilter:
                              ColorFilter.mode(Colors.black.withOpacity(0.5), BlendMode.darken),
                          child: TileLayer(
                            urlTemplate:
                                "https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}",
                            additionalOptions: {
                              'accessToken':
                                  'pk.eyJ1IjoibW9yZ25jb2x0IiwiYSI6ImNtYng2eHI0ZjB3cjQybW9zNXZhaDJqanYifQ.0qZEU6MBjiTZiUDPs6JyoQ',
                              'id': _mapboxStyleId,
                            },
                            tileSize: 512,
                            zoomOffset: -1,
                            retinaMode: true,
                            maxNativeZoom: 22,
                            maxZoom: 22,
                            tileProvider: CancellableNetworkTileProvider(),
                          ),
                        ),
                      PolygonLayer(
                        polygons: [
                          if (currentPolygonPoints.length >= 3)
                            Polygon(
                              points: currentPolygonPoints,
                              color: Colors.blue.withOpacity(0.2),
                              borderColor: Colors.blue,
                              borderStrokeWidth: 2,
                            ),
                          ...boundaryPolygons.map(
                            (polygon) => Polygon(
                              points: polygon,
                              color: Colors.transparent,
                              borderColor: Colors.green,
                              borderStrokeWidth: 3,
                            ),
                          ),
                          if (widget.highlightPolygon != null &&
                              widget.highlightPolygon!.length >= 3)
                            Polygon(
                              points: widget.highlightPolygon!,
                              color: Colors.white.withOpacity(0.25),
                              borderColor: Colors.white,
                              borderStrokeWidth: 3,
                              isFilled: true,
                            ),
                          ...userPolygons.where((p) => p.length >= 3).where((p) {
                            if (widget.highlightPolygon == null) return true;
                            return !_samePolygon(p, widget.highlightPolygon!);
                          }).map(
                            (polygon) => Polygon(
                              points: polygon,
                              color: polygon == selectedPolygon
                                  ? Colors.white.withOpacity(0.55)
                                  : Colors.blue.withOpacity(0.28),
                              borderColor:
                                  polygon == selectedPolygon ? Colors.white : Colors.blue,
                              borderStrokeWidth: polygon == selectedPolygon ? 3 : 1,
                              isFilled: true,
                            ),
                          ),
                          ...otherPolygons.where((p) => p.length >= 3).map(
                            (polygon) => Polygon(
                              points: polygon,
                              color: polygon == selectedPolygon
                                  ? Colors.white.withOpacity(0.55)
                                  : Colors.grey.withOpacity(0.20),
                              borderColor:
                                  polygon == selectedPolygon ? Colors.white : Colors.grey,
                              borderStrokeWidth: polygon == selectedPolygon ? 3 : 1,
                              isFilled: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          topLeftInfo,
          bottomLeftInfo,
          buildMapControls(),
          if (isDrawing)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Tap map to add points (${currentPolygonPoints.length})',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
