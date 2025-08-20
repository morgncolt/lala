// map_screen.dart
// Fixed: region-fill toggle + non-interactive ADM polygons + see-through highlight
// At the top of map_screen.dart with your other imports
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:uuid/uuid.dart';

import 'country_region_interact.dart';
import 'region_model.dart';
import 'regions_repository.dart';
import 'package:flutter/services.dart';


class MapScreen extends StatefulWidget {
  final String regionId;
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

  const MapScreen({
    Key? key,
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
  }) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final user = FirebaseAuth.instance.currentUser;
  final mapController = MapController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController walletController = TextEditingController();

  final bool _useGoogle = true;
  String canonicalizeRegionId(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

  gmap.GoogleMapController? _gController;
  double _currentZoom = 16;

  bool isDrawing = false;
  bool showSatellite = false;
  bool show3D = false;

  bool _isSaving = false;

  List<ll.LatLng> currentPolygonPoints = [];
  List<List<ll.LatLng>> boundaryPolygons = [];
  List<List<ll.LatLng>> userPolygons = [];
  List<List<ll.LatLng>> otherPolygons = [];
  List<DocumentSnapshot> userPolygonDocs = [];
  List<DocumentSnapshot> otherPolygonDocs = [];
  List<ll.LatLng>? selectedPolygon;

  Region? currentRegion;
  DocumentSnapshot? _selectedPolygonDoc;
  bool _showPolygonInfo = false;
  ll.LatLng? _currentCenter;

  gmap.LatLngBounds? _regionBoundsGoogle;
  LatLngBounds? _regionBoundsFlutter;
  ll.LatLng? _regionCenterComputed;

  gmap.LatLng _g(ll.LatLng p) => gmap.LatLng(p.latitude, p.longitude);
  List<gmap.LatLng> _gList(List<ll.LatLng> pts) => pts.map(_g).toList();



  // Same logic you used in landledger_screen.dart
  String get _apiBase {
    if (kIsWeb) return 'http://localhost:4000';
    if (Platform.isAndroid) return 'http://10.0.2.2:4000';
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
          18,
        ),
      );
      return;
    }

    final bounds = _boundsFromLl(poly);
    await _gController!.animateCamera(
      gmap.CameraUpdate.newLatLngBounds(bounds, 48.0),
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
      final ridRaw = (data['region'] ?? data['regionId'] ?? widget.regionId).toString();
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

  ll.LatLng _centroid(List<ll.LatLng> pts) {
    if (pts.isEmpty) return const ll.LatLng(0, 0);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return ll.LatLng(lat / pts.length, lng / pts.length);
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

  bool _regionFillVisible = true;

  List<List<ll.LatLng>> _regionRingsLL(String regionId) {
    final ringsG = _admCtl.regionExteriors(regionId);
    return ringsG
        .map((ring) => ring
            .map((p) => ll.LatLng(p.latitude, p.longitude))
            .toList(growable: false))
        .toList(growable: false);
  }

  late CountryRegionController _admCtl;
  bool _admCtlInit = false;

  String? _lastTappedRegion;

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

    _initializeRegion();
    if (widget.startDrawing) isDrawing = true;
    _loadUserSavedPolygons();
  }

  void _promptRegionDetails(String regionId) {
    _lastTappedRegion = regionId;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(regionId),
        action: SnackBarAction(
          label: 'Show properties',
          onPressed: () => _showRegionSheet(regionId),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  bool _didCenterInitial = false;

  Future<void> _centerInitialIfReady() async {
    if (!_useGoogle || _gController == null || _didCenterInitial) return;

    final hp = widget.highlightPolygon;
    if (hp != null && hp.length >= 3) {
      final b = _boundsFromLl(hp);
      await _gController!.animateCamera(gmap.CameraUpdate.newLatLngBounds(b, 48));
      _didCenterInitial = true;
      return;
    }

    if (_regionBoundsGoogle != null) {
      await _gController!.animateCamera(
        gmap.CameraUpdate.newLatLngBounds(_regionBoundsGoogle!, 60),
      );
      _didCenterInitial = true;
      return;
    }

    final c = currentRegion?.center;
    final z = (currentRegion?.zoomLevel ?? 5).toDouble();
    if (c != null) {
      await _gController!.moveCamera(
        gmap.CameraUpdate.newLatLngZoom(gmap.LatLng(c.latitude, c.longitude), z),
      );
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
            options: const FitBoundsOptions(padding: EdgeInsets.all(60)),
          );
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

      final geojsonStr = await rootBundle.loadString(path);
      final geoData = json.decode(geojsonStr) as Map<String, dynamic>;
      final features = (geoData['features'] as List).cast<Map<String, dynamic>>();

      final parsedPolygons = <List<ll.LatLng>>[];

      for (final f in features) {
        final geometry = f['geometry'] as Map<String, dynamic>;
        final type = geometry['type'] as String;
        final coordinates = geometry['coordinates'] as List<dynamic>;

        if (type == 'Polygon') {
          final coords = (coordinates[0] as List).cast<List>();
          parsedPolygons.add(coords.map<ll.LatLng>((pair) {
            final lng = (pair[0] as num).toDouble();
            final lat = (pair[1] as num).toDouble();
            return ll.LatLng(lat, lng);
          }).toList());
        } else if (type == 'MultiPolygon') {
          for (final poly in coordinates) {
            final outer = (poly as List)[0] as List;
            parsedPolygons.add(outer.map<ll.LatLng>((pair) {
              final lng = (pair[0] as num).toDouble();
              final lat = (pair[1] as num).toDouble();
              return ll.LatLng(lat, lng);
            }).toList());
          }
        }
      }

      if (!mounted) return;

      final allPts = parsedPolygons.expand((e) => e).toList();
      ll.LatLng? computedCenter;
      gmap.LatLngBounds? gBounds;
      LatLngBounds? fBounds;

      if (allPts.isNotEmpty) {
        computedCenter = _centroid(allPts);
        gBounds = _toGoogleBounds(allPts);
        fBounds = LatLngBounds.fromPoints(allPts);
      }

      setState(() {
        boundaryPolygons = parsedPolygons;
        _regionCenterComputed = computedCenter;
        _regionBoundsGoogle = gBounds;
        _regionBoundsFlutter = fBounds;
      });

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
    final regIdCanonical = canonicalizeRegionId(widget.regionId);
    final regName = currentRegion?.name ?? widget.regionId;

    try {
      // 1) NEW nested path
      final myNested = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('regions')
          .doc(regIdCanonical)
          .collection('properties')
          .orderBy('updatedAt', descending: true)
          .get();

      // 2) LEGACY flat path
      final myFlat = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('regions')
          .get();

      // 3) PUBLIC others
      final othersSnap = await FirebaseFirestore.instance
          .collection('regions')
          .doc(regIdCanonical)
          .collection('properties')
          .where('ownerUid', isNotEqualTo: user!.uid)
          .get();

      final tmpUserPolys = <List<ll.LatLng>>[];
      final tmpUserDocs = <DocumentSnapshot>[];

      List<ll.LatLng> _coordsFromDoc(DocumentSnapshot d) {
        final coords = (d['coordinates'] as List);
        return coords
            .map<ll.LatLng>((c) => ll.LatLng(
                  (c['lat'] as num).toDouble(),
                  (c['lng'] as num).toDouble(),
                ))
            .toList();
      }

      for (final d in myNested.docs) {
        tmpUserPolys.add(_coordsFromDoc(d));
        tmpUserDocs.add(d);
      }

      for (final d in myFlat.docs) {
        final data = d.data() as Map<String, dynamic>;
        final regionField = (data['region'] ?? data['regionId'] ?? '').toString();
        if (regionField.isEmpty) continue;

        final matches = canonicalizeRegionId(regionField) == regIdCanonical ||
            regionField.trim().toLowerCase() == regName.trim().toLowerCase();

        if (matches && data.containsKey('coordinates')) {
          tmpUserPolys.add(_coordsFromDoc(d));
          tmpUserDocs.add(d);
        }
      }

      final tmpOtherPolys = <List<ll.LatLng>>[];
      final tmpOtherDocs = <DocumentSnapshot>[];
      for (final d in othersSnap.docs) {
        tmpOtherPolys.add(_coordsFromDoc(d));
        tmpOtherDocs.add(d);
      }

      setState(() {
        userPolygons = tmpUserPolys;
        otherPolygons = tmpOtherPolys;
        userPolygonDocs = tmpUserDocs;
        otherPolygonDocs = tmpOtherDocs;
      });

      debugPrint(
          '👤 userPolygons=${userPolygons.length}, 👥 otherPolygons=${otherPolygons.length} for region $regIdCanonical');
    } catch (e) {
      debugPrint("Failed to load saved polygons: $e");
    }
  }

  void _handleTap(ll.LatLng point) {
    if (isDrawing) {
      setState(() {
        currentPolygonPoints.add(point);
        _showPolygonInfo = false;
      });
      debugPrint(
          '✍️ point added: ${point.latitude}, ${point.longitude} (total ${currentPolygonPoints.length})');
      return;
    }

    for (int i = 0; i < userPolygons.length; i++) {
      if (pointInPolygon(point, userPolygons[i])) {
        setState(() {
          selectedPolygon = userPolygons[i];
          _selectedPolygonDoc = userPolygonDocs[i];
          _showPolygonInfo = true;
        });
        return;
      }
    }
    for (int i = 0; i < otherPolygons.length; i++) {
      if (pointInPolygon(point, otherPolygons[i])) {
        setState(() {
          selectedPolygon = otherPolygons[i];
          _selectedPolygonDoc = otherPolygonDocs[i];
          _showPolygonInfo = true;
        });
        return;
      }
    }
    setState(() {
      selectedPolygon = null;
      _showPolygonInfo = false;
      _selectedPolygonDoc = null;
    });
  }

  void _handleMapTapFlutter(TapPosition _, ll.LatLng p) => _handleTap(p);

  bool pointInPolygon(ll.LatLng point, List<ll.LatLng> polygon) {
    int intersectCount = 0;
    for (int i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      if ((polygon[i].latitude > point.latitude) !=
          (polygon[j].latitude > point.latitude)) {
        final x = (polygon[j].longitude - polygon[i].longitude) *
                (point.latitude - polygon[i].latitude) /
                (polygon[j].latitude - polygon[i].latitude) +
            polygon[i].longitude;
        if (point.longitude < x) intersectCount++;
      }
    }
    return intersectCount % 2 == 1;
  }

  @override
  void dispose() {
    descriptionController.dispose();
    walletController.dispose();
    _admCtl.dispose();
    super.dispose();
  }

  Future<void> centerToUserLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;

      if (_useGoogle && _gController != null) {
        _gController!.animateCamera(
          gmap.CameraUpdate.newLatLngZoom(
              gmap.LatLng(pos.latitude, pos.longitude), 14),
        );
      } else {
        mapController.move(ll.LatLng(pos.latitude, pos.longitude), 14);
      }
    } catch (e) {
      debugPrint("Location error: $e");
    }
  }

  void _showRegionSheet(String id) {
    final regionRings = _regionRingsLL(id);

    bool _pointIn(ll.LatLng p, List<ll.LatLng> ring) => pointInPolygon(p, ring);
    bool _centroidInside(List<ll.LatLng> poly) {
      final c = _calculateCentroid(poly);
      return regionRings.any((r) => _pointIn(c, r));
    }

    final myItems = <int>[];
    final othersCountByRegion = <int>[];

    for (int i = 0; i < userPolygons.length; i++) {
      if (_centroidInside(userPolygons[i])) myItems.add(i);
    }
    for (int i = 0; i < otherPolygons.length; i++) {
      if (_centroidInside(otherPolygons[i])) othersCountByRegion.add(i);
    }

    final othersCount = othersCountByRegion.length;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.45,
          minChildSize: 0.25,
          maxChildSize: 0.9,
          builder: (ctx, scrollController) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          id,
                          style: Theme.of(ctx).textTheme.titleLarge,
                        ),
                      ),
                      if (othersCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$othersCount other ${othersCount == 1 ? "property" : "properties"}',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (myItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        "You have no saved properties in $id.",
                        style: Theme.of(ctx).textTheme.bodyMedium,
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: myItems.length,
                      itemBuilder: (c, idxInMy) {
                        final idx = myItems[idxInMy];
                        final doc = userPolygonDocs[idx];
                        final poly = userPolygons[idx];
                        final title =
                            (doc.data() as Map).containsKey('title_number')
                                ? (doc['title_number'] ?? 'Untitled') as String
                                : 'Untitled';
                        final alias = (doc.data() as Map).containsKey('alias')
                            ? (doc['alias'] ?? '')
                            : '';
                        final areaKm2 = (doc.data() as Map)
                                .containsKey('area_sqkm')
                            ? (doc['area_sqkm'] ?? 0.0) as num
                            : 0.0;
                        final areaSqM = areaKm2 * 1e6;
                        final areaDisplay = areaSqM >= 100000
                            ? "${(areaSqM / 1e6).toStringAsFixed(2)} km²"
                            : "${areaSqM.toStringAsFixed(0)} m²";

                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(title),
                            subtitle: Text([
                              if (alias.toString().isNotEmpty) "#$alias",
                              "Area: $areaDisplay",
                            ]
                                .where((s) => s.isNotEmpty)
                                .join(" • ")),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                IconButton(
                                  tooltip: "Focus on polygon",
                                  icon: const Icon(Icons.center_focus_strong),
                                  onPressed: () async {
                                    if (_gController != null && poly.isNotEmpty) {
                                      if (poly.length == 1) {
                                        await _gController!.animateCamera(
                                          gmap.CameraUpdate.newLatLngZoom(
                                            gmap.LatLng(poly.first.latitude,
                                                poly.first.longitude),
                                            18,
                                          ),
                                        );
                                      } else {
                                        final b = _boundsFromLl(poly);
                                        await _gController!.animateCamera(
                                          gmap.CameraUpdate
                                              .newLatLngBounds(b, 48),
                                        );
                                      }
                                    }
                                    if (mounted) Navigator.pop(context);
                                  },
                                ),
                                IconButton(
                                  tooltip: "Open My Properties",
                                  icon: const Icon(Icons.folder_open),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    widget.onOpenMyProperties?.call();
                                  },
                                ),
                              ],
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
                      label: const Text("Close"),
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

  Widget _buildGoogleMap() {
    final ll.LatLng initCenter =
        currentRegion?.center ?? _regionCenterComputed ?? const ll.LatLng(9.0, 8.0);
    final double initZoom = (currentRegion?.zoomLevel ?? 5).toDouble();

    final gmap.CameraPosition camPos = gmap.CameraPosition(
      target: gmap.LatLng(initCenter.latitude, initCenter.longitude),
      zoom: initZoom,
    );

    return ValueListenableBuilder<Set<gmap.Polygon>>(
      valueListenable: _admCtl.polygonsNotifier,
      builder: (context, admPolys, _) {
        // Build our polygons manually so ADM polygons never intercept taps
        final Set<gmap.Polygon> polys = <gmap.Polygon>{};

        if (!isDrawing) {
          // Clone ADM polygons with no tap consumption and dynamic fill
          for (final p in admPolys) {
            polys.add(gmap.Polygon(
              polygonId: p.polygonId,
              points: p.points,
              strokeWidth: p.strokeWidth,
              strokeColor: p.strokeColor,
              fillColor: _regionFillVisible ? p.fillColor : p.fillColor.withOpacity(0.0),
              consumeTapEvents: false, // <-- critical: don't steal taps
              zIndex: 500,             // keep ADM under user polygons
            ));
          }
        }

        if (currentPolygonPoints.length >= 3) {
          polys.add(gmap.Polygon(
            polygonId: const gmap.PolygonId('drawing'),
            points: _gList(currentPolygonPoints),
            strokeWidth: 2,
            strokeColor: Colors.blue,
            fillColor: Colors.blue.withOpacity(0.30),
            consumeTapEvents: false,
            zIndex: 1200,
          ));
        }

        // Highlight polygon from MyProperties (see-through)
        if (widget.highlightPolygon != null && widget.highlightPolygon!.length >= 3) {
          polys.add(gmap.Polygon(
            polygonId: const gmap.PolygonId('highlight'),
            points: _gList(widget.highlightPolygon!),
            strokeWidth: 3,
            strokeColor: Colors.blue,
            fillColor: Colors.blue.withOpacity(0.22), // lighter, see-through
            consumeTapEvents: false,
            zIndex: 1100,
          ));
        }

        // User polygons (skip if equal to highlight to avoid double-draw)
        for (int i = 0; i < userPolygons.length; i++) {
          final poly = userPolygons[i];
          if (poly.length < 3) continue;

          if (widget.highlightPolygon != null &&
              _samePolygon(poly, widget.highlightPolygon!)) {
            continue; // let the highlight be the only copy
          }

          final isSelected = identical(selectedPolygon, poly);
          polys.add(gmap.Polygon(
            polygonId: gmap.PolygonId('user_$i'),
            points: _gList(poly),
            strokeWidth: isSelected ? 3 : 1,
            strokeColor: isSelected ? Colors.white : Colors.blue,
            fillColor: (isSelected ? Colors.white : Colors.blue)
                .withOpacity(isSelected ? 0.55 : 0.28),
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
            zIndex: isSelected ? 1050 : 1030,
          ));
        }

        // Others
        for (int i = 0; i < otherPolygons.length; i++) {
          final poly = otherPolygons[i];
          if (poly.length < 3) continue;
          final isSelected = identical(selectedPolygon, poly);
          polys.add(gmap.Polygon(
            polygonId: gmap.PolygonId('other_$i'),
            points: _gList(poly),
            strokeWidth: isSelected ? 3 : 1,
            strokeColor: isSelected ? Colors.white : Colors.grey,
            fillColor:
                (isSelected ? Colors.white : Colors.grey).withOpacity(isSelected ? 0.55 : 0.20),
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

        return gmap.GoogleMap(
          mapType: showSatellite ? gmap.MapType.hybrid : gmap.MapType.normal,
          initialCameraPosition: camPos,
          polygons: polys,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          onMapCreated: (c) async {
            _gController = c;
            _admCtl.attachMapController(c);
            _currentZoom = await c.getZoomLevel();

            await _centerInitialIfReady();

            if (widget.highlightPolygon != null &&
                widget.highlightPolygon!.isNotEmpty) {
              await _fitToPolygonIfAny();
            } else if (widget.centerOnRegion && _regionBoundsGoogle != null) {
              await Future.delayed(const Duration(milliseconds: 50));
              if (mounted) {
                _gController!.animateCamera(
                  gmap.CameraUpdate.newLatLngBounds(_regionBoundsGoogle!, 48),
                );
              }
            }
          },
          onTap: (gmap.LatLng p) =>
              _handleTap(ll.LatLng(p.latitude, p.longitude)),
          onCameraMove: (pos) {
            _currentZoom = pos.zoom;
            _currentCenter =
                ll.LatLng(pos.target.latitude, pos.target.longitude);
            setState(() {});
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
  ) async {
    final url = Uri.parse('$_apiBase/api/landledger/register');
    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "parcelId": id,
          "titleNumber": id,
          "owner": wallet,
          "coordinates": points
              .map((p) => {"lat": p.latitude, "lng": p.longitude})
              .toList(),
          "areaSqKm": calculateArea(points),
          "description": description,
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

      // Try to parse response to extract createdAt (optional)
      DateTime? created;
      try {
        final jsonBody = jsonDecode(res.body);
        final createdRaw = jsonBody['createdAt'] ?? jsonBody['timestamp'];
        if (createdRaw is String && createdRaw.isNotEmpty) {
          created = DateTime.tryParse(createdRaw);
        }
      } catch (_) {}

      // Let parent listeners react if they care
      widget.onBlockchainUpdate?.call({
        "parcelId": id,
        "owner": wallet,
        "description": description,
        "createdAt": created?.toIso8601String(),
      });

      // ✅ Show success popup card
      _showBlockchainSuccessCard(
        parcelId: id,
        owner: wallet.isEmpty ? '—' : wallet,
        description: description,
        createdAt: created,
      );
    } catch (e) {
      debugPrint("❌ Blockchain request failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Blockchain request failed")),
        );
      }
    }
  }



  // ======= SAVE POLYGON (decoupled + immediate UI update) =======
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

    // 1) Build title + alias (with fallback) — unchanged
    String llid, alias;
    try {
      final center = _calculateCentroid(currentPolygonPoints);
      final placemarks =
          await placemarkFromCoordinates(center.latitude, center.longitude)
              .timeout(const Duration(seconds: 3));
      final city = placemarks.isNotEmpty
          ? (placemarks.first.locality ??
              placemarks.first.subAdministrativeArea ??
              'Region')
          : 'Region';
      final shortCity = city.replaceAll(' ', '');
      final uniquePart = const Uuid().v4().substring(0, 6).toUpperCase();
      llid = 'LL-$shortCity-$uniquePart';
      alias = generateAliasFromCity(city);
    } catch (_) {
      final fallback = DateFormat('yyyyMMdd').format(DateTime.now());
      llid = 'LL-Region-$fallback';
      alias = '#Plot${_randomCode()}';
    }

    // 2) Confirm dialog — unchanged
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Save Property"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Title ID: $llid"),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: "Description"),
            ),
            TextField(
              controller: walletController,
              decoration: const InputDecoration(labelText: "Wallet Address"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Save")),
        ],
      ),
    );

    if (ok != true) {
      if (mounted) setState(() => _isSaving = false);
      return;
    }

    // 3) IMPORTANT: capture user inputs BEFORE clearing controllers
    final capturedDescription = descriptionController.text.trim();
    final capturedWallet = walletController.text.trim();

    try {
      // Close the ring for storage
      final closed = [...currentPolygonPoints];
      if (closed.first != closed.last) closed.add(closed.first);

      final regionId = canonicalizeRegionId(widget.regionId);
      final propId = llid;

      final centroid = _calculateCentroid(closed);
      final areaSqKm = calculateArea(closed);

      final now = FieldValue.serverTimestamp();
      final displayRegionName = currentRegion?.name ?? widget.regionId;

      final baseData = {
        "id": propId,
        "title_number": llid,
        "alias": alias,
        "description": capturedDescription,
        "wallet_address": capturedWallet,
        "region": displayRegionName, // human readable (legacy)
        "regionId": regionId,        // canonical
        "ownerUid": user!.uid,
        "coordinates": closed
            .map((p) => {"lat": p.latitude, "lng": p.longitude})
            .toList(),
        "centroid": {"lat": centroid.latitude, "lng": centroid.longitude},
        "area_sqkm": areaSqKm,
        "createdAt": now,
        "updatedAt": now,
        "timestamp": now, // legacy UIs
      };

      final batch = FirebaseFirestore.instance.batch();

      // NEW nested
      final userDocNew = FirebaseFirestore.instance
          .collection("users").doc(user!.uid)
          .collection("regions").doc(regionId)
          .collection("properties").doc(propId);
      batch.set(userDocNew, baseData, SetOptions(merge: true));

      // LEGACY flat
      final userDocFlat = FirebaseFirestore.instance
          .collection("users").doc(user!.uid)
          .collection("regions").doc(propId);
      batch.set(userDocFlat, baseData, SetOptions(merge: true));

      // PUBLIC by region
      final publicDoc = FirebaseFirestore.instance
          .collection("regions").doc(regionId)
          .collection("properties").doc(propId);
      batch.set(publicDoc, baseData, SetOptions(merge: true));

      await batch.commit();

      // Re-read the one we'll keep in memory (prefer the new path)
      final newSnap = await userDocNew.get();

      if (!mounted) return;
      setState(() {
        userPolygons.add(closed);
        userPolygonDocs.add(newSnap.exists ? newSnap : userDocFlat as DocumentSnapshot<Object?>);
        selectedPolygon = closed;
        _selectedPolygonDoc = newSnap.exists ? newSnap : null;
        isDrawing = false;
        currentPolygonPoints = [];
      });

      // Now it's safe to clear the inputs
      descriptionController.clear();
      walletController.clear();

      _admCtl.setShading(_regionFillVisible);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Property saved successfully")),
      );

      // 4) Blockchain write uses CAPTURED values, not cleared controllers
      //    (fire-and-forget)
      // ignore: unawaited_futures
      saveToBlockchainSilent(llid, closed, capturedWallet, capturedDescription);

      // Refresh lists
      // ignore: unawaited_futures
      _loadUserSavedPolygons();
    } catch (e) {
      debugPrint("❌ Save failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Failed to save: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }


  Future<Map<String, dynamic>?> fetchPolygonFromBlockchain(String id) async {
    final url = Uri.parse('http://10.0.2.2:4000/api/landledger/$id');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final coordinates = (jsonBody['polygon'] as List)
            .map((coord) => ll.LatLng(coord[1], coord[0]))
            .toList();
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
        Positioned(
          bottom: 100,
          right: 16,
          child: Column(
            children: [
              FloatingActionButton(
                heroTag: "btn-zoom-in",
                mini: true,
                child: const Icon(Icons.add),
                onPressed: () async {
                  if (_useGoogle && _gController != null) {
                    _currentZoom += 1;
                    await _gController!.animateCamera(
                        gmap.CameraUpdate.zoomTo(_currentZoom));
                  } else {
                    mapController.move(mapController.center, mapController.zoom + 1);
                  }
                },
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: "btn-toggle-region-fill",
                mini: true,
                tooltip: _regionFillVisible ? "Hide region highlight" : "Show region highlight",
                child: Icon(_regionFillVisible ? Icons.layers_clear : Icons.layers),
                onPressed: () {
                  setState(() => _regionFillVisible = !_regionFillVisible);
                  // keep region shading off while drawing; mirror in ADM polygons
                  _admCtl.setShading(_regionFillVisible && !isDrawing);
                },
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: "btn-zoom-out",
                mini: true,
                child: const Icon(Icons.remove),
                onPressed: () async {
                  if (_useGoogle && _gController != null) {
                    _currentZoom -= 1;
                    await _gController!.animateCamera(
                        gmap.CameraUpdate.zoomTo(_currentZoom));
                  } else {
                    mapController.move(mapController.center, mapController.zoom - 1);
                  }
                },
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: "btn-center",
                mini: true,
                child: const Icon(Icons.my_location),
                onPressed: centerToUserLocation,
              ),
              const SizedBox(height: 8),
              if (currentPolygonPoints.length >= 3 && isDrawing)
                Column(
                  children: [
                    Builder(builder: (context) {
                      final areaSqM = calculateArea(currentPolygonPoints) * 1e6;
                      final display = areaSqM >= 100000
                          ? "${(areaSqM / 1e6).toStringAsFixed(2)} km²"
                          : "${areaSqM.toStringAsFixed(0)} m²";
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          display,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      );
                    }),
                    FloatingActionButton(
                      heroTag: "btn-save",
                      backgroundColor: Colors.red,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save),
                      onPressed: _isSaving ? null : savePolygon,
                    ),
                  ],
                )
              else
                FloatingActionButton(
                  heroTag: "btn-draw-toggle",
                  backgroundColor:
                      isDrawing ? Colors.red : const Color.fromARGB(255, 2, 76, 63),
                  child: Icon(isDrawing ? Icons.close : Icons.edit_location_alt),
                  onPressed: () {
                    setState(() {
                      isDrawing = !isDrawing;
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
        onTap: () => setState(() => _showPolygonInfo = false),
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
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        (data['alias'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _showPolygonInfo = false),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Description: ${data['description'] ?? 'No description'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Wallet: ${data['wallet_address'] ?? 'No wallet'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Builder(builder: (context) {
                  final area = (data['area_sqkm'] ?? 0) as num;
                  final areaSqM = area * 1e6;
                  final formatted = areaSqM >= 100000
                      ? "${(areaSqM / 1e6).toStringAsFixed(2)} km²"
                      : "${areaSqM.toStringAsFixed(0)} m²";
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

  Future<String> getCityNameFromLatLng(ll.LatLng latLng) async {
    try {
      final placemarks =
          await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
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

  @override
  Widget build(BuildContext context) {
    final topLeftInfo = Positioned(
      top: 16,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20)),
        child: FutureBuilder<String>(
          future: _currentCenter != null
              ? getCityNameFromLatLng(_currentCenter!)
              : Future.value('Unknown City'),
          builder: (context, snapshot) {
            final text = (snapshot.connectionState == ConnectionState.waiting)
                ? 'Loading...'
                : (snapshot.hasError || !snapshot.hasData)
                    ? 'Unknown City'
                    : snapshot.data!;
            return Text(
              text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
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
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20)),
        child: Text(
          _currentCenter != null
              ? 'Lat: ${_currentCenter!.latitude.toStringAsFixed(5)}, Lng: ${_currentCenter!.longitude.toStringAsFixed(5)}'
              : 'Coords unavailable',
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
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
                    } else if (widget.openedFromTab &&
                        widget.onOpenMyProperties != null) {
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
                ? _buildGoogleMap()
                : FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      center: currentRegion?.center ??
                          _regionCenterComputed ??
                          const ll.LatLng(9.0, 8.0),
                      zoom: currentRegion?.zoomLevel ?? 5,
                      onTap: _handleMapTapFlutter,
                      onPositionChanged:
                          (MapPosition position, bool hasGesture) {
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
                          colorFilter: ColorFilter.mode(
                              Colors.black.withOpacity(0.5), BlendMode.darken),
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
                              color: Colors.blue.withOpacity(0.3),
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
                          ...userPolygons
                              .where((p) => p.length >= 3)
                              .where((p) {
                            if (widget.highlightPolygon == null) return true;
                            return !_samePolygon(p, widget.highlightPolygon!);
                          }).map(
                            (polygon) => Polygon(
                              points: polygon,
                              color: polygon == selectedPolygon
                                  ? Colors.white.withOpacity(0.55)
                                  : Colors.blue.withOpacity(0.28),
                              borderColor: polygon == selectedPolygon
                                  ? Colors.white
                                  : Colors.blue,
                              borderStrokeWidth:
                                  polygon == selectedPolygon ? 3 : 1,
                              isFilled: true,
                            ),
                          ),
                          ...otherPolygons.where((p) => p.length >= 3).map(
                            (polygon) => Polygon(
                              points: polygon,
                              color: polygon == selectedPolygon
                                  ? Colors.white.withOpacity(0.55)
                                  : Colors.grey.withOpacity(0.20),
                              borderColor: polygon == selectedPolygon
                                  ? Colors.white
                                  : Colors.grey,
                              borderStrokeWidth:
                                  polygon == selectedPolygon ? 3 : 1,
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
