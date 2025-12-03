import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'landledger_screen.dart';
import 'map_screen.dart';
import 'widgets/consent.dart';
import 'widgets/responsive_text.dart';
import 'widgets/map_error_handler.dart';
import 'services/identity_service.dart';

class MyPropertiesScreen extends StatefulWidget {
  final String regionId;
  final String? geojsonPath;
  final List<ll.LatLng>? highlightPolygon;
  final VoidCallback? onBackToHome;
  final void Function(String regionId, String geojsonPath)? onRegionSelected;
  final bool showBackArrow;
  final void Function(Map<String, dynamic> blockchainData)? onBlockchainRecordSelected;

  const MyPropertiesScreen({
    super.key,
    required this.regionId,
    this.geojsonPath,
    this.highlightPolygon,
    this.onBackToHome,
    this.onRegionSelected,
    this.showBackArrow = false,
    this.onBlockchainRecordSelected,
  });

  @override
  State<MyPropertiesScreen> createState() => _MyPropertiesScreenState();
}

class _MyPropertiesScreenState extends State<MyPropertiesScreen> {
  // Canonicalize region IDs the same way MapScreen does
  String canonicalizeRegionId(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

  final List<Map<String, dynamic>> _userProperties = [];
  final List<List<ll.LatLng>> _polygonPointsList = [];
  final List<String> _documentIds = [];

  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  final User? _user = FirebaseAuth.instance.currentUser;

  List<ll.LatLng>? _selectedPolygon;
  bool _showPolygonInfo = false;
  Map<String, dynamic>? _selectedPolygonDoc;

  // Per-card state keyed by docId
  final Map<String, bool> _satelliteViewById = {};
  final Map<String, double> _zoomById = {};
  final Map<String, ll.LatLng?> _centerById = {};
  final Map<String, gmap.GoogleMapController?> _gControllerById = {};

  

  String _searchQuery = '';
  Timer? _searchDebounce;

  StreamSubscription<QuerySnapshot>? _propsSub;

  gmap.LatLng _g(ll.LatLng p) => gmap.LatLng(p.latitude, p.longitude);
  List<gmap.LatLng> _gList(List<ll.LatLng> pts) => pts.map(_g).toList();

  ll.LatLng _centroid(List<ll.LatLng> pts) {
    if (pts.isEmpty) return const ll.LatLng(0, 0);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return ll.LatLng(lat / pts.length, lng / pts.length);
  }

  @override
  void initState() {
    super.initState();
    _subscribeProperties();
  }
 

  @override
  void dispose() {
    _propsSub?.cancel();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    for (final ctrl in _gControllerById.values) {
      ctrl?.dispose();
    }
    super.dispose();
  }

    // ---- API base to match MapScreen ----
  String get _apiBase {
    // Use localhost for all platforms (ADB reverse port forwarding handles Android connectivity)
    return 'http://localhost:4000';
  }

  String _prettyAdmId(String raw) => raw.replaceFirst(RegExp(r'\s*#\d+$'), '');

  String? _deriveAdm1BaseFromProp(Map<String, dynamic> prop) {
    final a = (prop['adm1Base'] ?? '').toString();
    if (a.isNotEmpty) return a;
    final b = (prop['adm1Id'] ?? '').toString();
    if (b.isNotEmpty) return _prettyAdmId(b);
    return null; // unknown; we can still delete user ADM0 + legacy and sweep
  }

  Future<void> _tryDeleteOnBlockchain(String? parcelId) async {
    if (parcelId == null || parcelId.isEmpty) return;
    try {
      final uri = Uri.parse('$_apiBase/api/landledger/delete/$parcelId');
      final del = await http.delete(uri);
      if (del.statusCode >= 200 && del.statusCode < 300) return;
      // fallback (if your server expects POST)
      await http.post(uri);
    } catch (e) {
      debugPrint('⚠️ Blockchain delete error: $e');
    }
  }

  /// Delete the obvious paths (user copies always; public copies if allowed).
  Future<void> _deleteKnownPaths({
    required String uid,
    required String regionId,
    required String propId,
    String? adm1Base,
  }) async {
    final fs = FirebaseFirestore.instance;

    // --- USER SIDE (do this first; guaranteed by rules) ---
    final userBatch = fs.batch();
    // USER / ADM0
    userBatch.delete(fs.collection('users').doc(uid)
        .collection('regions').doc(regionId)
        .collection('properties').doc(propId));
    // USER / ADM1
    if (adm1Base != null && adm1Base.isNotEmpty) {
      userBatch.delete(fs.collection('users').doc(uid)
          .collection('regions').doc(regionId)
          .collection('adm1').doc(adm1Base)
          .collection('properties').doc(propId));
    }
    // Legacy flat
    userBatch.delete(fs.collection('users').doc(uid)
        .collection('regions').doc(propId));
    await userBatch.commit();

    // --- PUBLIC SIDE (may be blocked by rules; ignore permission errors) ---
    try {
      final pubBatch = fs.batch();
      // PUBLIC / ADM0
      pubBatch.delete(fs.collection('regions').doc(regionId)
          .collection('properties').doc(propId));
      // PUBLIC / ADM1
      if (adm1Base != null && adm1Base.isNotEmpty) {
        pubBatch.delete(fs.collection('regions').doc(regionId)
            .collection('adm1').doc(adm1Base)
            .collection('properties').doc(propId));
      }
      await pubBatch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint('Public deletes blocked by rules — user copies cleaned.');
      } else {
        rethrow;
      }
    }
  }

  /// Sweep *any* leftover copies via collectionGroup (user + public).
  /// Sweep *any* leftover copies via collectionGroup, but avoid composite indexes.
  Future<void> _collectionGroupSweep({
    required String uid,
    required String regionId,
    required String propId,
  }) async {
    final fs = FirebaseFirestore.instance;

    try {
      // Single-field filter: avoids composite index on (ownerUid, regionId, __name__)
      final q = fs.collectionGroup('properties')
          .where('id', isEqualTo: propId);

      final snap = await q.get();
      if (snap.docs.isEmpty) return;

      const int chunk = 200;
      for (int i = 0; i < snap.docs.length; i += chunk) {
        final slice = snap.docs.skip(i).take(chunk).toList();
        final b = fs.batch();
        for (final d in slice) {
          // Optional: sanity check fields before delete
          final data = d.data() as Map<String, dynamic>? ?? const {};
          if (data['ownerUid'] == uid && data['regionId'] == regionId) {
            b.delete(d.reference);
          }
        }
        try {
          await b.commit();
        } on FirebaseException catch (e) {
          // Ignore permission issues to keep UX smooth
          if (e.code != 'permission-denied') rethrow;
        }
      }
    } on FirebaseException catch (e) {
      // If Firestore still wants an index, skip the sweep—primary deletes already ran.
      if (e.code == 'failed-precondition') {
        debugPrint('ℹ️ Skipping sweep (index required). Primary deletes already completed.');
        return;
      }
      rethrow;
    }
  }



  // ---------- Networking helpers ----------
  Future<Map<String, dynamic>?> fetchLandRecord(String parcelId) async {
    final url = Uri.parse('http://localhost:4000/api/landledger/$parcelId');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['title_number'] == null || data['coordinates'] == null) {
          debugPrint('⚠️ Invalid record format received');
          return null;
        }
        return data;
      } else if (response.statusCode == 404) {
        debugPrint('🔍 Land record $parcelId not found on blockchain');
        return null;
      } else {
        debugPrint('❌ Server error: ${response.statusCode}');
        return null;
      }
    } on TimeoutException {
      debugPrint('⏱️ Timeout fetching land record');
      return null;
    } catch (e) {
      debugPrint('❌ Network error: $e');
      return null;
    }
  }

  List<Map<String, dynamic>> get _filteredProperties {
    if (_searchQuery.isEmpty) return _userProperties;
    final q = _searchQuery.toLowerCase();
    return _userProperties.where((prop) {
      return (prop['title_number']?.toString().toLowerCase().contains(q) ?? false) ||
          (prop['alias']?.toString().toLowerCase().contains(q) ?? false) ||
          (prop['description']?.toString().toLowerCase().contains(q) ?? false) ||
          (prop['wallet_address']?.toString().toLowerCase().contains(q) ?? false) ||
          (prop['adm1Base']?.toString().toLowerCase().contains(q) ?? false);
    }).toList();
  }

  _NormalizedProp? _normalizeDoc(DocumentSnapshot d) {
    final data = d.data();
    if (data is! Map<String, dynamic>) return null;

    final coordsRaw = (data['coordinates'] as List? ?? const []);
    final coords = coordsRaw
        .where((c) => c is Map && c['lat'] != null && c['lng'] != null)
        .map((c) => ll.LatLng(
              (c['lat'] as num).toDouble(),
              (c['lng'] as num).toDouble(),
            ))
        .toList();

    final id = (data['id'] ?? d.id).toString();
    if (id.isEmpty) return null;

    return _NormalizedProp(
      prop: data,
      polygon: coords,
      stableId: id,
    );
  }

  /// Real-time listener using collectionGroup('properties') filtered by owner+region.
  void _subscribeProperties() {
    if (_user == null) return;
    setState(() => _isLoading = true);

    final regionIdCanonical = canonicalizeRegionId(widget.regionId);

    // Listen to ALL user properties in this country, regardless of ADM1 folder.
    final q = FirebaseFirestore.instance
        .collectionGroup('properties')
        .where('ownerUid', isEqualTo: _user.uid)
        .where('regionId', isEqualTo: regionIdCanonical);

    _propsSub = q.snapshots().listen((snap) {
      final merged = <String, _NormalizedProp>{};

      for (final d in snap.docs) {
        final norm = _normalizeDoc(d);
        if (norm != null) {
          merged[norm.stableId] = norm;
        }
      }

      // Sort newest first client-side (fallback to timestamp if updatedAt absent)
      final list = merged.values.toList()
        ..sort((a, b) {
          final atA = a.prop['updatedAt'] ?? a.prop['timestamp'];
          final atB = b.prop['updatedAt'] ?? b.prop['timestamp'];
          final ta = (atA is Timestamp) ? atA.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          final tb = (atB is Timestamp) ? atB.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });

      setState(() {
        _userProperties
          ..clear()
          ..addAll(list.map((e) => e.prop));
        _polygonPointsList
          ..clear()
          ..addAll(list.map((e) => e.polygon));
        _documentIds
          ..clear()
          ..addAll(list.map((e) => e.stableId));

        // Ensure per-card state exists
        for (final n in list) {
          _satelliteViewById.putIfAbsent(n.stableId, () => false);
          _zoomById.putIfAbsent(n.stableId, () => 15.0);
          _centerById.putIfAbsent(n.stableId, () => _centroid(n.polygon));
        }

        _isLoading = false;
      });
    }, onError: (e) {
      debugPrint('❌ properties stream error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading properties')),
        );
      }
    });
  }

  Future<void> _refreshAll() async {
    // Pull-to-refresh just replays current snapshot; nudge UI.
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  // ---------- Interactions ----------
  void _handlePolygonTap(int index) {
    setState(() {
      _selectedPolygon = _polygonPointsList[index];
      _selectedPolygonDoc = _userProperties[index];
      _showPolygonInfo = true;
    });
  }

  void _handleMiniMapTap(String docId, ll.LatLng point) {
    setState(() {
      if (_centerById[docId] == null) {
        _centerById[docId] = point;
        _zoomById[docId] = 18.0;
      } else {
        _centerById[docId] = null;
        _zoomById[docId] = 15.0;
      }
    });

    final target = _centerById[docId] ?? point;
    final z = (_zoomById[docId] ?? 15.0).toDouble();
    _gControllerById[docId]?.animateCamera(
      gmap.CameraUpdate.newLatLngZoom(_g(target), z),
    );
  }

  Future<void> _deletePropertyById({
    required String docId,                // stable ID for the property
    required Map<String, dynamic> prop,   // the doc data you already have
  }) async {
    if (_user == null || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Property'),
        content: const Text('Are you sure you want to delete this property?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final uid = _user.uid;
      final regionId = canonicalizeRegionId((prop['regionId'] ?? widget.regionId).toString());
      final adm1Base = _deriveAdm1BaseFromProp(prop);
      final blockchainId = (prop['blockchainId'] ?? prop['id'] ?? prop['title_number'] ?? docId).toString();

      // 1) Known paths by direct refs (no index needed)
      await _deleteKnownPaths(
        uid: uid,
        regionId: regionId,
        propId: docId,
        adm1Base: adm1Base,
      );

      // 2) Optional sweep (already index-safe from last message)
      await _collectionGroupSweep(
        uid: uid,
        regionId: regionId,
        propId: docId,
      );

      // 3) Fire-and-forget blockchain delete
      // ignore: unawaited_futures
      _tryDeleteOnBlockchain(blockchainId);

      // 4) DO NOT mutate _userProperties/_polygonPointsList/_documentIds here.
      //    The stream listener will emit a new snapshot and rebuild safely.

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Property deleted')),
      );
    } catch (e) {
      debugPrint('❌ Delete failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete property: $e')),
        );
      }
    }
  }



  String formatArea(dynamic value) {
    if (value == null || value == 0) return 'Area: Unknown';
    final areaSqKm = value as num;
    final areaSqM = areaSqKm * 1e6;
    return areaSqM >= 100000
        ? '${(areaSqM / 1e6).toStringAsFixed(2)} km²'
        : '${areaSqM.toStringAsFixed(0)} m²';
  }

  // ---------- UI ----------
  Widget _buildPropertyCard(int originalIndex) {
    final prop = _userProperties[originalIndex];
    final poly = _polygonPointsList[originalIndex];
    final docId = _documentIds[originalIndex];

    final titleNumber = prop['title_number'] ?? prop['parcelId'] ?? 'Untitled Property';

    final isSelected = identical(_selectedPolygon, poly);
    final isSatellite = _satelliteViewById[docId] ?? false;
    final zoomLevel = _zoomById[docId] ?? 15.0;

    final center = _centerById[docId] ?? _centroid(poly);
    final miniMapKey = ValueKey('miniMap_$docId');

    return GestureDetector(
      onTap: () => _handlePolygonTap(originalIndex),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                children: [
                  SizedBox(
                    height: 180,
                    child: GestureDetector(
                      onTap: () => _handleMiniMapTap(docId, center),
                      child: gmap.GoogleMap(
                        key: miniMapKey,
                        mapType: isSatellite ? gmap.MapType.hybrid : gmap.MapType.normal,
                        initialCameraPosition: gmap.CameraPosition(
                          target: _g(center),
                          zoom: zoomLevel.toDouble(),
                        ),
                        zoomGesturesEnabled: false,
                        scrollGesturesEnabled: false,
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: true,
                        mapToolbarEnabled: false,
                        onMapCreated: (ctrl) async {
                          _gControllerById[docId] = ctrl;
                          await ctrl.moveCamera(
                            gmap.CameraUpdate.newCameraPosition(
                              gmap.CameraPosition(target: _g(center), zoom: zoomLevel.toDouble()),
                            ),
                          );
                        },
                        polygons: {
                          if (poly.length >= 3)
                            gmap.Polygon(
                              polygonId: gmap.PolygonId('prop_$docId'),
                              points: _gList(poly),
                              strokeWidth: isSelected ? 3 : 2,
                              strokeColor: isSelected ? Colors.white : Colors.blue,
                              fillColor: (isSelected ? Colors.white : Colors.blue)
                                  .withOpacity(isSelected ? 0.7 : 0.3),
                              consumeTapEvents: false,
                            ),
                        },
                        onTap: (_) {
                          _handleMiniMapTap(docId, center);
                          final ctrl = _gControllerById[docId];
                          if (ctrl != null) {
                            final target = _centerById[docId] ?? center;
                            final z = (_zoomById[docId] ?? 15.0).toDouble();
                            ctrl.animateCamera(
                                gmap.CameraUpdate.newLatLngZoom(_g(target), z));
                          }
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Color.fromARGB(255, 10, 10, 10)),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'toggle_view',
                          child: Text(isSatellite ? 'Normal View' : 'Satellite View'),
                        ),
                        const PopupMenuItem(
                          value: 'open_fullscreen',
                          child: Text('Open Fullscreen Map'),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete Property', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                      onSelected: (value) async {
                        switch (value) {
                          case 'delete':
                            await _deletePropertyById( docId: docId, prop: prop, );
                            break;
                          case 'toggle_view':
                            setState(() {
                              _satelliteViewById[docId] = !(_satelliteViewById[docId] ?? false);
                            });
                            break;
                          case 'open_fullscreen':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MapScreen(
                                  regionId: widget.regionId,
                                  geojsonPath: widget.geojsonPath,
                                  highlightPolygon: poly,
                                  startDrawing: false,
                                  centerOnRegion: false,
                                  showBackArrow: true,
                                ),
                              ),
                            );
                            break;
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titleNumber,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (prop.containsKey('alias') && prop['alias'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        prop['alias'],
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: () {
                                          Clipboard.setData(
                                              ClipboardData(text: prop['alias']));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text("Alias copied to clipboard"),
                                              duration: Duration(seconds: 1),
                                            ),
                                          );
                                        },
                                        child: const Icon(
                                          Icons.copy,
                                          size: 16,
                                          color: Colors.black45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(
                          formatArea(prop['area_sqkm']),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    prop['description'] ?? 'No description',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          formatFriendlyWalletSync(prop['wallet_address'] ?? ''),
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (prop['timestamp'] != null)
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM d, y').format(
                            (prop['timestamp'] as Timestamp).toDate(),
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolygonInfoCard() {
    if (_selectedPolygonDoc == null || !_showPolygonInfo) return const SizedBox();

    final docData = _selectedPolygonDoc!;

    String areaFormatted(num? areaSqKm) {
      final a = areaSqKm ?? 0;
      final m2 = a * 1e6;
      return m2 >= 100000 ? '${(m2 / 1e6).toStringAsFixed(2)} km²' : '${m2.toStringAsFixed(0)} m²';
    }

    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: () => setState(() => _showPolygonInfo = false),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            docData['title_number'] ?? 'Property Details',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (docData.containsKey('alias') && docData['alias'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      docData['alias'],
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () {
                                        Clipboard.setData(
                                          ClipboardData(text: docData['alias']),
                                        );
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text("Alias copied to clipboard"),
                                            duration: Duration(seconds: 1),
                                          ),
                                        );
                                      },
                                      child: const Icon(
                                        Icons.copy,
                                        size: 16,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _showPolygonInfo = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow('Description', docData['description']),
                _buildInfoRow('Wallet', formatFriendlyWalletSync(docData['wallet_address'] ?? '')),
                _buildInfoRow('Area', areaFormatted(docData['area_sqkm'] as num?)),
                if (docData['timestamp'] != null)
                  _buildInfoRow(
                    'Created',
                    DateFormat('MMMM d, y').format(
                      (docData['timestamp'] as Timestamp).toDate(),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.public),
                      label: const Text('View on Blockchain'),
                      onPressed: () {
                        if (widget.onBlockchainRecordSelected != null) {
                          widget.onBlockchainRecordSelected!(docData);
                        }
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.description),
                      label: const Text('Land Deed'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Showing land deed...')),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value ?? 'Not available'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreator() async {
    final ok = await confirmOnChain(context,
      title: 'Create Parcel',
      summary: 'You are about to create a new parcel. This action will be signed by your identity.');
    if (!ok) return;

    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          regionId: widget.regionId,
          geojsonPath: widget.geojsonPath,
          startDrawing: true,
          showBackArrow: true,
        ),
      ),
    );
    if (created == true) {
      // Stream will auto-update; this nudges the UI state.
      await _refreshAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _filteredProperties;

    return Scaffold(
      appBar: AppBar(
        leading: widget.showBackArrow
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (widget.onBackToHome != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.onBackToHome!();
                    });
                  } else {
                    Navigator.pop(context);
                  }
                },
              )
            : null,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Search properties (title, alias, ADM1, wallet)...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (value) {
              if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              });
            },
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_alt),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'newest', child: Text('Newest First')),
              PopupMenuItem(value: 'oldest', child: Text('Oldest First')),
              PopupMenuItem(value: 'largest', child: Text('Largest Area')),
              PopupMenuItem(value: 'smallest', child: Text('Smallest Area')),
            ],
            onSelected: (value) {
              setState(() {
                switch (value) {
                  case 'newest':
                    _userProperties.sort((a, b) {
                      final atA = a['updatedAt'] ?? a['timestamp'];
                      final atB = b['updatedAt'] ?? b['timestamp'];
                      final ta = (atA is Timestamp) ? atA.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                      final tb = (atB is Timestamp) ? atB.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                      return tb.compareTo(ta);
                    });
                    break;
                  case 'oldest':
                    _userProperties.sort((a, b) {
                      final atA = a['updatedAt'] ?? a['timestamp'];
                      final atB = b['updatedAt'] ?? b['timestamp'];
                      final ta = (atA is Timestamp) ? atA.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                      final tb = (atB is Timestamp) ? atB.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                      return ta.compareTo(tb);
                    });
                    break;
                  case 'largest':
                    _userProperties.sort((a, b) =>
                        (b['area_sqkm'] ?? 0).compareTo(a['area_sqkm'] ?? 0));
                    break;
                  case 'smallest':
                    _userProperties.sort((a, b) =>
                        (a['area_sqkm'] ?? 0).compareTo(b['area_sqkm'] ?? 0));
                    break;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (displayed.isEmpty && !_isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.map_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isEmpty ? 'No properties found' : 'No matching properties',
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _openCreator,
                    child: const Text('Create your first property'),
                  ),
                ],
              ),
            )
          else
            RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: displayed.length,
                itemBuilder: (context, idx) {
                  final prop = displayed[idx];
                  final originalIndex = _userProperties.indexOf(prop);
                  if (originalIndex < 0) return const SizedBox.shrink();
                  return _buildPropertyCard(originalIndex);
                },
              ),
            ),
          _buildPolygonInfoCard(),
          if (_isLoading)
            const Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreator,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _NormalizedProp {
  final Map<String, dynamic> prop;
  final List<ll.LatLng> polygon;
  final String stableId;

  _NormalizedProp({
    required this.prop,
    required this.polygon,
    required this.stableId,
  });
}
