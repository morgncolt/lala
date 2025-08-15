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
  final List<Map<String, dynamic>> _userProperties = [];
  final List<List<ll.LatLng>> _polygonPointsList = [];
  final List<String> _documentIds = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final ScrollController _scrollController = ScrollController();
  final User? _user = FirebaseAuth.instance.currentUser;
  Timer? _debounce;
  List<ll.LatLng>? _selectedPolygon;
  bool _showPolygonInfo = false;

  // Store the selected property's data as a Map (not a DocumentSnapshot)
  Map<String, dynamic>? _selectedPolygonDoc;

  // Per-card view state
  final Map<int, bool> _satelliteViewMap = {};
  final Map<int, double> _zoomLevelMap = {};
  final Map<int, ll.LatLng?> _centerMap = {};
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Google Map controllers per item
  final Map<int, gmap.GoogleMapController?> _gControllers = {};

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
    super.dispose();
  }

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

  Future<void> _fetchProperties() async {
    if (_user == null || _isLoading || !_hasMore) return;

    setState(() => _isLoading = true);

    try {
      var query = FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('regions')
          .where('region', isEqualTo: widget.regionId)
          .orderBy('timestamp', descending: true)
          .limit(10);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        final props = <Map<String, dynamic>>[];
        final polys = <List<ll.LatLng>>[];
        final ids = <String>[];

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final coords = (data['coordinates'] as List)
              .where((c) => c is Map && c['lat'] != null && c['lng'] != null)
              .map((c) => ll.LatLng(
                    (c['lat'] as num).toDouble(),
                    (c['lng'] as num).toDouble(),
                  ))
              .toList();

          props.add(data);
          polys.add(coords);
          ids.add(doc.id);

          final index = _userProperties.length + props.length - 1;
          _satelliteViewMap[index] = false;
          _zoomLevelMap[index] = 15.0;
          _centerMap[index] = null;
        }

        setState(() {
          _userProperties.addAll(props);
          _polygonPointsList.addAll(polys);
          _documentIds.addAll(ids);
          _lastDocument = snapshot.docs.last;
        });
      } else {
        setState(() => _hasMore = false);
      }
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

  void _handlePolygonTap(int index) {
    setState(() {
      _selectedPolygon = _polygonPointsList[index];
      _selectedPolygonDoc = _userProperties[index]; // store the map data
      _showPolygonInfo = true;
    });
  }

  void _handleMapTap(int index, ll.LatLng point) {
    setState(() {
      if (_centerMap[index] == null) {
        _centerMap[index] = point;
        _zoomLevelMap[index] = 18.0;
      } else {
        _centerMap[index] = null;
        _zoomLevelMap[index] = 15.0;
      }
    });

    final target = _centerMap[index] ?? point;
    final z = (_zoomLevelMap[index] ?? 15.0).toDouble();
    _gControllers[index]?.animateCamera(
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('regions')
          .doc(docId)
          .delete();

      if (!mounted) return;

      setState(() {
        _userProperties.removeAt(index);
        _polygonPointsList.removeAt(index);
        _documentIds.removeAt(index);
        _satelliteViewMap.remove(index);
        _zoomLevelMap.remove(index);
        _centerMap.remove(index);
        _gControllers.remove(index);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Property deleted successfully')),
        );
      }
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

  Widget _buildPropertyCard(int originalIndex) {
    final prop = _userProperties[originalIndex];
    final poly = _polygonPointsList[originalIndex];

    if (poly.isEmpty) return const SizedBox.shrink();

    // Handle both Firestore and potential blockchain formats (kept for compatibility)
    final titleNumber = prop['title_number'] ?? prop['parcelId'] ?? 'Untitled Property';

    final isSelected = _selectedPolygon == poly;
    final isSatellite = _satelliteViewMap[originalIndex] ?? false;
    final zoomLevel = _zoomLevelMap[originalIndex] ?? 15.0;

    final center = _centerMap[originalIndex] ?? _centroid(poly);

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
                      onTap: () => _handleMapTap(originalIndex, center),
                      child: gmap.GoogleMap(
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
                          _gControllers[originalIndex] = ctrl;
                          await ctrl.moveCamera(
                            gmap.CameraUpdate.newCameraPosition(
                              gmap.CameraPosition(target: _g(center), zoom: zoomLevel.toDouble()),
                            ),
                          );
                        },
                        polygons: {
                          gmap.Polygon(
                            polygonId: gmap.PolygonId('prop_$originalIndex'),
                            points: _gList(poly),
                            strokeWidth: isSelected ? 3 : 2,
                            strokeColor: isSelected ? Colors.white : Colors.blue,
                            fillColor: (isSelected ? Colors.white : Colors.blue)
                                .withOpacity(isSelected ? 0.7 : 0.3),
                            consumeTapEvents: false,
                          ),
                        },
                        onTap: (_) {
                          _handleMapTap(originalIndex, center);
                          final ctrl = _gControllers[originalIndex];
                          if (ctrl != null) {
                            final target = _centerMap[originalIndex] ?? center;
                            final z = (_zoomLevelMap[originalIndex] ?? 15.0).toDouble();
                            ctrl.animateCamera(gmap.CameraUpdate.newLatLngZoom(_g(target), z));
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
                        const PopupMenuItem(
                          value: 'view_blockchain',
                          child: Text('View on Blockchain'),
                        ),
                        const PopupMenuItem(
                          value: 'land_deed',
                          child: Text('View Land Deed'),
                        ),
                        PopupMenuItem(
                          value: 'toggle_view',
                          child: Text(isSatellite ? 'Normal View' : 'Satellite View'),
                        ),
                        const PopupMenuItem(
                          value: 'open_fullscreen', 
                          child: Text('Open Fullscreen Map')),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete Property', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                      onSelected: (value) async {
                        switch (value) {
                          case 'view_blockchain':
                            final parcelId = prop['parcelId'] ??
                                prop['id'] ??
                                (prop['title_number']?.toString().replaceFirst('TN-', 'LL-'));
                            if (parcelId == null || parcelId.isEmpty) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('No parcel ID available')),
                              );
                              return;
                            }
                            try {
                              final url = Uri.parse('http://10.0.2.2:4000/api/landledger/parcel/$parcelId');
                              final response = await http.get(url).timeout(const Duration(seconds: 5));
                              if (response.statusCode == 200) {
                                final data = jsonDecode(response.body);
                                if (!mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LandledgerScreen(selectedRecord: data),
                                  ),
                                );
                              } else {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Blockchain error: ${response.statusCode}')),
                                );
                              }
                            } on TimeoutException {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Request timeout')),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                            break;

                          case 'delete':
                            await _deleteProperty(originalIndex);
                            break;

                          case 'toggle_view':
                            setState(() {
                              _satelliteViewMap[originalIndex] =
                                  !(_satelliteViewMap[originalIndex] ?? false);
                            });
                            break;

                          case 'open_fullscreen':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MapScreen(
                                  regionId: widget.regionId,
                                  geojsonPath: widget.geojsonPath,
                                  highlightPolygon: _polygonPointsList[originalIndex],
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
                _buildInfoRow(
                  'Area',
                  '${(docData['area_sqkm'] is num) ? (docData['area_sqkm'] as num).toStringAsFixed(2) : '0.00'} km²',
                ),
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

  @override
  Widget build(BuildContext context) {
    final displayed = _filteredProperties;

    return Scaffold(
      appBar: AppBar(
        leading: widget.showBackArrow
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  debugPrint('🔙 Back button pressed in MyPropertiesScreen');

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
                    _userProperties.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
                    break;
                  case 'oldest':
                    _userProperties.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
                    break;
                  case 'largest':
                    _userProperties
                        .sort((a, b) => (b['area_sqkm'] ?? 0).compareTo(a['area_sqkm'] ?? 0));
                    break;
                  case 'smallest':
                    _userProperties
                        .sort((a, b) => (a['area_sqkm'] ?? 0).compareTo(b['area_sqkm'] ?? 0));
                    break;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _userProperties.clear();
                _polygonPointsList.clear();
                _documentIds.clear();
                _hasMore = true;
                _lastDocument = null;
                _selectedPolygon = null;
                _showPolygonInfo = false;
                _satelliteViewMap.clear();
                _zoomLevelMap.clear();
                _centerMap.clear();
                _searchQuery = '';
              });
              _fetchProperties();
            },
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
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MapScreen(
                            regionId: widget.regionId,
                            geojsonPath: widget.geojsonPath,
                            startDrawing: true,
                          ),
                        ),
                      );
                    },
                    child: const Text('Create your first property'),
                  ),
                ],
              ),
            )
          else
            RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _userProperties.clear();
                  _polygonPointsList.clear();
                  _documentIds.clear();
                  _hasMore = true;
                  _lastDocument = null;
                  _selectedPolygon = null;
                  _showPolygonInfo = false;
                  _satelliteViewMap.clear();
                  _zoomLevelMap.clear();
                  _centerMap.clear();
                  _searchQuery = '';
                });
                await _fetchProperties();
              },
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
                  // Map filtered item to its original index so parallel arrays stay in sync
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
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MapScreen(
                regionId: widget.regionId,
                geojsonPath: widget.geojsonPath,
                startDrawing: true,
              ),
            ),
          );
        },
      ),
    );
  }
}
