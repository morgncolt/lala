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

class MyPropertiesScreen extends StatefulWidget {
  final String regionId;
  final String? geojsonPath;
  final List<ll.LatLng>? highlightPolygon;
  final VoidCallback? onBackToHome;
  final void Function(String regionId, String geojsonPath)? onRegionSelected;
  final bool showBackArrow;
  final void Function(Map<String, dynamic> blockchainData)? onBlockchainRecordSelected;

  const MyPropertiesScreen({
    Key? key,
    required this.regionId,
    this.geojsonPath,
    this.highlightPolygon,
    this.onBackToHome,
    this.onRegionSelected,
    this.showBackArrow = false,
    this.onBlockchainRecordSelected,
  }) : super(key: key);

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
  bool _hasMore = true; // applies to legacy listing pagination
  DocumentSnapshot? _lastDocument; // legacy paging
  final ScrollController _scrollController = ScrollController();
  final User? _user = FirebaseAuth.instance.currentUser;
  Timer? _debounce;

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
    _fetchProperties();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _debounce?.cancel();
    _searchDebounce?.cancel();
    for (final ctrl in _gControllerById.values) {
      ctrl?.dispose();
    }
    super.dispose();
  }

  // ---------- Networking helpers ----------
  Future<Map<String, dynamic>?> fetchLandRecord(String parcelId) async {
    final url = Uri.parse('http://10.0.2.2:4000/api/landledger/$parcelId');
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

  // ---------- Paging / search ----------
  void _onScroll() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        if (!_isLoading && _hasMore) _fetchProperties();
      }
    });
  }

  List<Map<String, dynamic>> get _filteredProperties {
    if (_searchQuery.isEmpty) return _userProperties;
    final q = _searchQuery.toLowerCase();
    return _userProperties.where((prop) {
      return (prop['title_number']?.toString().toLowerCase().contains(q) ?? false) ||
          (prop['description']?.toString().toLowerCase().contains(q) ?? false) ||
          (prop['wallet_address']?.toString().toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// Normalizes a Firestore doc (from either path) to a renderable property + polygon.
  /// Returns a _NormalizedProp or null if malformed.
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

  /// Fetch from BOTH:
  /// 1) NEW nested: users/{uid}/regions/{regionIdCanonical}/properties (complete list)
  /// 2) LEGACY flat: users/{uid}/regions (paged) — keep pagination behavior for large old sets
  Future<void> _fetchProperties() async {
    if (_user == null || _isLoading) return;

    setState(() => _isLoading = true);

    final regionIdCanonical = canonicalizeRegionId(widget.regionId);
    final mergedById = <String, _NormalizedProp>{};

    try {
      // ---- 1) NEW nested path (full read for this region) ----
      final nestedSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('regions')
          .doc(regionIdCanonical)
          .collection('properties')
          .orderBy('updatedAt', descending: true)
          .get();

      for (final d in nestedSnap.docs) {
        final norm = _normalizeDoc(d);
        if (norm != null) {
          mergedById[norm.stableId] = norm;
        }
      }

      // ---- 2) LEGACY flat path (paged) ----
      QuerySnapshot<Map<String, dynamic>>? legacySnap;

      try {
        var legacyQuery = FirebaseFirestore.instance
            .collection('users')
            .doc(_user!.uid)
            .collection('regions')
            .orderBy('timestamp', descending: true)
            .limit(10);

        if (_lastDocument != null) {
          legacyQuery = legacyQuery.startAfterDocument(_lastDocument!);
        }

        legacySnap = await legacyQuery.get();
      } catch (e) {
        // If legacy path errors, keep going with what we have from nested
        debugPrint('Legacy fetch error: $e');
        legacySnap = null;
      }

      if (legacySnap == null || legacySnap.docs.isEmpty) {
        // No more legacy docs to page through
        _hasMore = false;
      } else {
        _lastDocument = legacySnap.docs.last;

        for (final d in legacySnap.docs) {
          final norm = _normalizeDoc(d);
          if (norm == null) continue;

          // Only include legacy entries for this region (match by canonical or human)
          final regionField = (norm.prop['region'] ?? norm.prop['regionId'] ?? '').toString();
          final matches = canonicalizeRegionId(regionField) == regionIdCanonical ||
              regionField.trim().toLowerCase() == widget.regionId.trim().toLowerCase();

          if (!matches) continue;

          // Prefer the NEW nested version if already present; otherwise add legacy
          if (!mergedById.containsKey(norm.stableId)) {
            mergedById[norm.stableId] = norm;
          }
        }
      }

      // ---- Merge into UI lists (append-only to support lazy loading on legacy) ----
      // We append only the entries that are not already present in _documentIds
      final newEntries = mergedById.values
          .where((e) => !_documentIds.contains(e.stableId))
          .toList();

      // Sort newest first by 'updatedAt' (fallback to 'timestamp')
      newEntries.sort((a, b) {
        final atA = a.prop['updatedAt'] ?? a.prop['timestamp'];
        final atB = b.prop['updatedAt'] ?? b.prop['timestamp'];
        final ta = (atA is Timestamp) ? atA.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        final tb = (atB is Timestamp) ? atB.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });

      setState(() {
        for (final n in newEntries) {
          _userProperties.add(n.prop);
          _polygonPointsList.add(n.polygon);
          _documentIds.add(n.stableId);

          _satelliteViewById.putIfAbsent(n.stableId, () => false);
          _zoomById.putIfAbsent(n.stableId, () => 15.0);
          _centerById.putIfAbsent(n.stableId, () => _centroid(n.polygon));
        }
      });
    } catch (e) {
      debugPrint('Error fetching properties: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading properties')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    setState(() {
      _userProperties.clear();
      _polygonPointsList.clear();
      _documentIds.clear();
      _hasMore = true;
      _lastDocument = null;
      _selectedPolygon = null;
      _showPolygonInfo = false;
      _satelliteViewById.clear();
      _zoomById.clear();
      _centerById.clear();
      _gControllerById.clear();
      _searchQuery = '';
    });
    await _fetchProperties();
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

  Future<void> _deleteProperty(int index) async {
    if (_user == null || !mounted) return;

    final docId = _documentIds[index];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Property'),
        content: const Text('Are you sure you want to delete this property?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final regionIdCanonical = canonicalizeRegionId(widget.regionId);

      // Delete in BOTH locations to stay consistent with MapScreen.savePolygon
      final legacyRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('regions')
          .doc(docId);

      final nestedRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('regions')
          .doc(regionIdCanonical)
          .collection('properties')
          .doc(docId);

      final batch = FirebaseFirestore.instance.batch();
      batch.delete(legacyRef);
      batch.delete(nestedRef);
      await batch.commit();

      if (!mounted) return;

      setState(() {
        _userProperties.removeAt(index);
        _polygonPointsList.removeAt(index);
        _documentIds.removeAt(index);

        _satelliteViewById.remove(docId);
        _zoomById.remove(docId);
        _centerById.remove(docId);
        _gControllerById.remove(docId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Property deleted successfully')),
      );
    } catch (e) {
      debugPrint('Failed to delete: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete property')),
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
                            await _deleteProperty(originalIndex);
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
                          prop['wallet_address'] ?? 'No wallet',
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

    String _areaFormatted(num? areaSqKm) {
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
                _buildInfoRow('Wallet', docData['wallet_address']),
                _buildInfoRow('Area', _areaFormatted(docData['area_sqkm'] as num?)),
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
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          regionId: widget.regionId,
          geojsonPath: widget.geojsonPath,
          startDrawing: true,
        ),
      ),
    );
    if (created == true) {
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
              hintText: 'Search properties...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (value) {
              if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 500), () {
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
                    _userProperties.sort(
                      (a, b) => (b['timestamp'] ?? b['updatedAt'])
                          .compareTo(a['timestamp'] ?? a['updatedAt']),
                    );
                    break;
                  case 'oldest':
                    _userProperties.sort(
                      (a, b) => (a['timestamp'] ?? a['updatedAt'])
                          .compareTo(b['timestamp'] ?? b['updatedAt']),
                    );
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
                itemCount: displayed.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, idx) {
                  if (idx == displayed.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final prop = displayed[idx];
                  final originalIndex = _userProperties.indexOf(prop);
                  if (originalIndex < 0) return const SizedBox.shrink();
                  return _buildPropertyCard(originalIndex);
                },
              ),
            ),
          _buildPolygonInfoCard(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: _openCreator,
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
