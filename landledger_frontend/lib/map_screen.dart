import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'region_model.dart';
import 'regions_repository.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart' as ll;

class MapScreen extends StatefulWidget {
  final String regionId;
  final String? geojsonPath; // Pass any country's GeoJSON asset path
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
  // --- State fields ---
  final user = FirebaseAuth.instance.currentUser;
  final mapController = MapController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController walletController = TextEditingController();

  // Switch between Google Maps vs flutter_map
  final bool _useGoogle = true;

  gmap.GoogleMapController? _gController;
  double _currentZoom = 16;

  bool isDrawing = false;
  bool showSatellite = false;
  bool show3D = false;

  List<ll.LatLng> currentPolygonPoints = [];
  List<List<ll.LatLng>> boundaryPolygons = []; // parsed from GeoJSON
  List<List<ll.LatLng>> userPolygons = [];
  List<List<ll.LatLng>> otherPolygons = [];
  List<DocumentSnapshot> userPolygonDocs = [];
  List<DocumentSnapshot> otherPolygonDocs = [];
  List<ll.LatLng>? selectedPolygon;

  Region? currentRegion;
  DocumentSnapshot? _selectedPolygonDoc;
  bool _showPolygonInfo = false;
  ll.LatLng? _currentCenter;

  // Bounds for both stacks (computed after parsing GeoJSON)
  gmap.LatLngBounds? _regionBoundsGoogle;
  LatLngBounds? _regionBoundsFlutter;
  ll.LatLng? _regionCenterComputed; // centroid of all boundary points

  // Helpers to convert LatLng types
  gmap.LatLng _g(ll.LatLng p) => gmap.LatLng(p.latitude, p.longitude);
  List<gmap.LatLng> _gList(List<ll.LatLng> pts) => pts.map(_g).toList();

  // Convert ll.LatLng list to Google bounds
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

  // Compute simple centroid of a list of points
  ll.LatLng _centroid(List<ll.LatLng> pts) {
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    final n = pts.isEmpty ? 1 : pts.length;
    return ll.LatLng(lat / n, lng / n);
  }

  String generateAliasFromCity(String city) {
    final cleaned = city.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
    if (cleaned.length <= 4) {
      final code = _randomCode();
      return '#${cleaned[0].toUpperCase()}${cleaned.substring(1)}$code';
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
    final short = buffer.isNotEmpty ? buffer.toString().toUpperCase() : cleaned.substring(0, 2).toUpperCase();
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

  @override
  void initState() {
    super.initState();
    _initializeRegion();
    if (widget.startDrawing) isDrawing = true;
    _loadUserSavedPolygons();
  }

  Future<void> _initializeRegion() async {
    currentRegion = RegionsRepository.getById(widget.regionId);

    // Parse GeoJSON => boundaryPolygons and precompute bounds/centroid
    await _loadRegionBoundary();
    if (!mounted) return;

    // Center to region bounds if requested
    if (widget.centerOnRegion && boundaryPolygons.isNotEmpty) {
      if (_useGoogle) {
        if (_gController != null && _regionBoundsGoogle != null) {
          Future.delayed(const Duration(milliseconds: 100), () {
            _gController!.animateCamera(
              gmap.CameraUpdate.newLatLngBounds(_regionBoundsGoogle!, 48),
            );
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_gController != null && _regionBoundsGoogle != null && mounted) {
              _gController!.animateCamera(
                gmap.CameraUpdate.newLatLngBounds(_regionBoundsGoogle!, 48),
              );
            }
          });
        }
      } else if (_regionBoundsFlutter != null) {
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

    // If a specific polygon should be highlighted, center to it
    if (widget.highlightPolygon != null && widget.highlightPolygon!.isNotEmpty) {
      final highlight = widget.highlightPolygon!;
      if (_useGoogle) {
        final gb = _toGoogleBounds(highlight);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_gController != null && mounted) {
            _gController!.animateCamera(
              gmap.CameraUpdate.newLatLngBounds(gb, 40),
            );
          }
        });
      } else {
        final fb = LatLngBounds.fromPoints(highlight);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            mapController.fitBounds(
              fb,
              options: const FitBoundsOptions(padding: EdgeInsets.all(40)),
            );
          }
        });
      }
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
          // outer ring (index 0)
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

      // Save polygons, compute bounds & centroid once
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
    try {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('regions')
          .where('region', isEqualTo: widget.regionId)
          .get();

      final tempUserPolygons = <List<ll.LatLng>>[];
      final tempOtherPolygons = <List<ll.LatLng>>[];
      final tempUserDocs = <DocumentSnapshot>[];
      final tempOtherDocs = <DocumentSnapshot>[];

      for (final doc in snap.docs) {
        final coords = (doc['coordinates'] as List)
            .map((c) => ll.LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble()))
            .toList();

        if (doc.reference.parent.parent?.id == user!.uid) {
          tempUserPolygons.add(coords);
          tempUserDocs.add(doc);
        } else {
          tempOtherPolygons.add(coords);
          tempOtherDocs.add(doc);
        }
      }

      setState(() {
        userPolygons = tempUserPolygons;
        otherPolygons = tempOtherPolygons;
        userPolygonDocs = tempUserDocs;
        otherPolygonDocs = tempOtherDocs;
      });
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

  // flutter_map tap adapter
  void _handleMapTapFlutter(TapPosition _, ll.LatLng p) => _handleTap(p);

  bool pointInPolygon(ll.LatLng point, List<ll.LatLng> polygon) {
    int intersectCount = 0;
    for (int i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      if ((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) {
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
    super.dispose();
  }

  Future<void> centerToUserLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;

      if (_useGoogle && _gController != null) {
        _gController!.animateCamera(
          gmap.CameraUpdate.newLatLngZoom(gmap.LatLng(pos.latitude, pos.longitude), 14),
        );
      } else {
        mapController.move(ll.LatLng(pos.latitude, pos.longitude), 14);
      }
    } catch (e) {
      debugPrint("Location error: $e");
    }
  }

  Widget _buildGoogleMap() {
    // Initial camera target: Region center from repository, OR computed centroid, OR a safe fallback (Africa-ish)
    final ll.LatLng initCenter =
        currentRegion?.center ?? _regionCenterComputed ?? const ll.LatLng(9.0, 8.0);
    final double initZoom = (currentRegion?.zoomLevel ?? 5).toDouble();

    final gmap.CameraPosition camPos = gmap.CameraPosition(
      target: gmap.LatLng(initCenter.latitude, initCenter.longitude),
      zoom: initZoom,
    );

    // Build Google polygon set
    final Set<gmap.Polygon> polys = {};

    if (currentPolygonPoints.isNotEmpty) {
      polys.add(gmap.Polygon(
        polygonId: const gmap.PolygonId('drawing'),
        points: _gList(currentPolygonPoints),
        strokeWidth: 2,
        strokeColor: Colors.blue,
        fillColor: Colors.blue.withOpacity(0.3),
        consumeTapEvents: false,
      ));
    }

    for (int i = 0; i < boundaryPolygons.length; i++) {
      polys.add(gmap.Polygon(
        polygonId: gmap.PolygonId('boundary_$i'),
        points: _gList(boundaryPolygons[i]),
        strokeWidth: 3,
        strokeColor: Colors.green,
        fillColor: Colors.transparent,
        consumeTapEvents: false,
      ));
    }

    if (widget.highlightPolygon != null) {
      polys.add(gmap.Polygon(
        polygonId: const gmap.PolygonId('highlight'),
        points: _gList(widget.highlightPolygon!),
        strokeWidth: 3,
        strokeColor: Colors.white,
        fillColor: Colors.white.withOpacity(0.7),
        consumeTapEvents: false,
      ));
    }

    for (int i = 0; i < userPolygons.length; i++) {
      final isSelected = selectedPolygon == userPolygons[i];
      polys.add(gmap.Polygon(
        polygonId: gmap.PolygonId('user_$i'),
        points: _gList(userPolygons[i]),
        strokeWidth: isSelected ? 3 : 1,
        strokeColor: isSelected ? Colors.white : Colors.blue,
        fillColor: (isSelected ? Colors.white : Colors.blue).withOpacity(isSelected ? 0.7 : 0.3),
        consumeTapEvents: true,
        onTap: () {
          setState(() {
            selectedPolygon = userPolygons[i];
            _selectedPolygonDoc = userPolygonDocs[i];
            _showPolygonInfo = true;
          });
        },
      ));
    }

    for (int i = 0; i < otherPolygons.length; i++) {
      final isSelected = selectedPolygon == otherPolygons[i];
      polys.add(gmap.Polygon(
        polygonId: gmap.PolygonId('other_$i'),
        points: _gList(otherPolygons[i]),
        strokeWidth: isSelected ? 3 : 1,
        strokeColor: isSelected ? Colors.white : Colors.grey,
        fillColor: (isSelected ? Colors.white : Colors.grey).withOpacity(isSelected ? 0.7 : 0.2),
        consumeTapEvents: true,
        onTap: () {
          setState(() {
            selectedPolygon = otherPolygons[i];
            _selectedPolygonDoc = otherPolygonDocs[i];
            _showPolygonInfo = true;
          });
        },
      ));
    }

    return gmap.GoogleMap(
      mapType: showSatellite ? gmap.MapType.hybrid : gmap.MapType.normal,
      initialCameraPosition: camPos,
      polygons: polys,
      myLocationEnabled: false, // avoid permission noise; use the FAB to center with permission
      myLocationButtonEnabled: false,
      onMapCreated: (c) async {
        _gController = c;
        _currentZoom = await c.getZoomLevel();

        // If bounds are already known (after _initializeRegion/_loadRegionBoundary), fly to them
        if (_regionBoundsGoogle != null) {
          await Future.delayed(const Duration(milliseconds: 50));
          _gController!.animateCamera(
            gmap.CameraUpdate.newLatLngBounds(_regionBoundsGoogle!, 48),
          );
        }
      },
      onTap: (gmap.LatLng p) => _handleTap(ll.LatLng(p.latitude, p.longitude)),
      onCameraMove: (pos) {
        _currentZoom = pos.zoom;
        _currentCenter = ll.LatLng(pos.target.latitude, pos.target.longitude);
        setState(() {});
      },
    );
  }

  double calculateArea(List<ll.LatLng> points) {
    double area = 0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      area += points[i].latitude * points[j].longitude;
      area -= points[j].latitude * points[i].longitude;
    }
    return area.abs() / 2 * 111 * 111; // rough km^2 from lat/lng
  }

  ll.LatLng _calculateCentroid(List<ll.LatLng> points) => _centroid(points);

  Future<void> saveToBlockchain(String id, List<ll.LatLng> points, String wallet, String description) async {
    final url = Uri.parse('http://10.0.2.2:4000/api/landledger/register');

    // (Optional) kept for future: GeoJSON structure (currently not used in POST body)
    final geoJson = {
      "type": "Feature",
      "geometry": {
        "type": "Polygon",
        "coordinates": [
          points.map((p) => [p.longitude, p.latitude]).toList()
            ..add([points.first.longitude, points.first.latitude])
        ],
      },
      "properties": {
        "id": id,
        "owner": wallet,
        "description": description,
        "timestamp": DateTime.now().toIso8601String(),
        "verified": false
      }
    };

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "parcelId": id,
          "titleNumber": id,
          "owner": wallet,
          "coordinates": points.map((p) => {"lat": p.latitude, "lng": p.longitude}).toList(),
          "areaSqKm": calculateArea(points),
          "description": description,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("✅ Blockchain Success"),
              content: Text("Polygon $id successfully saved to the blockchain."),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
              ],
            ),
          );
        }
      } else {
        final errMsg = jsonDecode(response.body)['error'] ?? response.body;
        throw Exception("Blockchain Error: $errMsg");
      }
    } catch (e) {
      debugPrint("❌ Error saving to blockchain: $e");
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("❌ Blockchain Error"),
            content: Text("Failed to save to blockchain:\n$e"),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
          ),
        );
      }
    }
  }

  Future<void> savePolygon() async {
    if (currentPolygonPoints.length < 3 || user == null || !mounted) return;

    String llid;
    String alias;

    try {
      final center = _calculateCentroid(currentPolygonPoints);
      final placemarks = await placemarkFromCoordinates(center.latitude, center.longitude);
      final city = placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? 'Region';
      final shortCity = city.replaceAll(' ', '');
      final uniquePart = Uuid().v4().substring(0, 6).toUpperCase();
      llid = 'LL-$shortCity-$uniquePart';
      alias = generateAliasFromCity(city);
    } catch (e) {
      final fallback = DateFormat('yyyyMMdd').format(DateTime.now());
      llid = 'LL-Region-$fallback';
      alias = '#Plot${_randomCode()}';
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Save Region"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Title ID: $llid"),
            TextField(controller: descriptionController, decoration: const InputDecoration(labelText: "Description")),
            TextField(controller: walletController, decoration: const InputDecoration(labelText: "Wallet Address")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Save")),
        ],
      ),
    );

    if (confirm != true) return;

    final closed = [...currentPolygonPoints];
    if (closed.first != closed.last) closed.add(closed.first);

    final areaSqKm = calculateArea(closed);

    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user!.uid)
          .collection("regions")
          .add({
        "title_number": llid,
        "alias": alias,
        "description": descriptionController.text,
        "wallet_address": walletController.text,
        "region": widget.regionId,
        "coordinates": closed.map((p) => {"lat": p.latitude, "lng": p.longitude}).toList(),
        "area_sqkm": areaSqKm,
        "timestamp": FieldValue.serverTimestamp(),
      });

      await saveToBlockchain(llid, closed, walletController.text, descriptionController.text);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Region saved successfully")));
        setState(() {
          currentPolygonPoints = [];
          isDrawing = false;
        });
        _loadUserSavedPolygons();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to save: $e")));
      }
    }
  }

  Future<Map<String, dynamic>?> fetchPolygonFromBlockchain(String id) async {
    final url = Uri.parse('http://10.0.2.2:4000/api/landledger/$id');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final coordinates = (jsonBody['polygon'] as List).map((coord) => ll.LatLng(coord[1], coord[0])).toList();
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
                    await _gController!.animateCamera(gmap.CameraUpdate.zoomTo(_currentZoom));
                  } else {
                    mapController.move(mapController.center, mapController.zoom + 1);
                  }
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
                    await _gController!.animateCamera(gmap.CameraUpdate.zoomTo(_currentZoom));
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
                    Builder(
                      builder: (context) {
                        final areaSqM = calculateArea(currentPolygonPoints) * 1e6;
                        final display = areaSqM >= 100000
                            ? "${(areaSqM / 1e6).toStringAsFixed(2)} km²"
                            : "${areaSqM.toStringAsFixed(0)} m²";
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            display,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
                    FloatingActionButton(
                      heroTag: "btn-save",
                      backgroundColor: Colors.red,
                      child: const Icon(Icons.save),
                      onPressed: savePolygon,
                    ),
                  ],
                )
              else
                FloatingActionButton(
                  heroTag: "btn-draw-toggle",
                  backgroundColor: isDrawing ? Colors.red : const Color.fromARGB(255, 2, 76, 63),
                  child: Icon(isDrawing ? Icons.close : Icons.edit_location_alt),
                  onPressed: () {
                    setState(() {
                      isDrawing = !isDrawing;
                      currentPolygonPoints = [];
                      selectedPolygon = null;
                      _showPolygonInfo = false;
                    });
                  },
                ),
            ],
          ),
        ),

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
    );
  }

  Widget buildPolygonInfoCard() {
    if (_selectedPolygonDoc == null) return const SizedBox.shrink();
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_selectedPolygonDoc!['title_number'] ?? 'No Title', style: Theme.of(context).textTheme.titleLarge),
                if (_selectedPolygonDoc!.data().toString().contains('alias'))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_selectedPolygonDoc!['alias'],
                        style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                  ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _showPolygonInfo = false)),
              ]),
              const SizedBox(height: 8),
              Text('Description: ${_selectedPolygonDoc!['description'] ?? 'No description'}',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text('Wallet: ${_selectedPolygonDoc!['wallet_address'] ?? 'No wallet'}',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final area = _selectedPolygonDoc!['area_sqkm'];
                if (area == null || area == 0) return const Text("Area: Unknown");
                final areaSqM = area * 1e6;
                final formatted = areaSqM >= 100000 ? "${(areaSqM / 1e6).toStringAsFixed(2)} km²" : "${areaSqM.toStringAsFixed(0)} m²";
                return Text("Area: $formatted");
              }),
              const SizedBox(height: 8),
              if (_selectedPolygonDoc!['timestamp'] != null)
                Text(
                  'Created: ${DateFormat('yyyy-MM-dd').format((_selectedPolygonDoc!['timestamp'] as Timestamp).toDate())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<String> getCityNameFromLatLng(ll.LatLng latLng) async {
    try {
      final placemarks = await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
      if (placemarks.isNotEmpty) {
        return placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? 'Unknown City';
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
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20)),
        child: FutureBuilder<String>(
          future: _currentCenter != null ? getCityNameFromLatLng(_currentCenter!) : Future.value('Unknown City'),
          builder: (context, snapshot) {
            final text = (snapshot.connectionState == ConnectionState.waiting)
                ? 'Loading...'
                : (snapshot.hasError || !snapshot.hasData)
                    ? 'Unknown City'
                    : snapshot.data!;
            return Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold));
          },
        ),
      ),
    );

    final bottomLeftInfo = Positioned(
      bottom: 16,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20)),
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
                ? _buildGoogleMap()
                : FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      center: currentRegion?.center ??
                          _regionCenterComputed ??
                          const ll.LatLng(9.0, 8.0), // Africa-ish fallback if repo empty
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
                          colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.5), BlendMode.darken),
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
                          if (currentPolygonPoints.isNotEmpty)
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
                          if (widget.highlightPolygon != null)
                            Polygon(
                              points: widget.highlightPolygon!,
                              color: Colors.white.withOpacity(0.7),
                              borderColor: Colors.white,
                              borderStrokeWidth: 3,
                              isFilled: true,
                            ),
                          ...userPolygons.map(
                            (polygon) => Polygon(
                              points: polygon,
                              color: polygon == selectedPolygon
                                  ? Colors.white.withOpacity(0.7)
                                  : Colors.blue.withOpacity(0.3),
                              borderColor: polygon == selectedPolygon ? Colors.white : Colors.blue,
                              borderStrokeWidth: polygon == selectedPolygon ? 3 : 1,
                              isFilled: true,
                            ),
                          ),
                          ...otherPolygons.map(
                            (polygon) => Polygon(
                              points: polygon,
                              color: polygon == selectedPolygon
                                  ? Colors.white.withOpacity(0.7)
                                  : Colors.grey.withOpacity(0.2),
                              borderColor: polygon == selectedPolygon ? Colors.white : Colors.grey,
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
                  child: Text('Tap map to add points (${currentPolygonPoints.length})',
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
