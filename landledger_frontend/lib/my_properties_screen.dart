import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'map_screen.dart';

class MyPropertiesScreen extends StatefulWidget {
  final String regionKey;
  final String geojsonPath;
  final List<LatLng>? highlightPolygon;

  const MyPropertiesScreen({
    Key? key,
    required this.regionKey,
    required this.geojsonPath,
    this.highlightPolygon,
  }) : super(key: key);

  @override
  State<MyPropertiesScreen> createState() => _MyPropertiesScreenState();
}

class _MyPropertiesScreenState extends State<MyPropertiesScreen> {
  final List<Map<String, dynamic>> _userProperties = [];
  final List<List<LatLng>> _polygonPointsList = [];
  final List<String> _documentIds = [];
  final List<bool> _showSatelliteList = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final ScrollController _scrollController = ScrollController();
  final User? _user = FirebaseAuth.instance.currentUser;
  Timer? _debounce;

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
    super.dispose();
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

  Future<void> _fetchProperties() async {
    if (_user == null || _isLoading || !_hasMore) return;
    
    setState(() => _isLoading = true);

    try {
      var query = FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('regions')
          .where('region', isEqualTo: widget.regionKey)
          .orderBy('title_number')
          .limit(10);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();
      
      if (snapshot.docs.isNotEmpty) {
        final props = <Map<String, dynamic>>[];
        final polys = <List<LatLng>>[];
        final ids = <String>[];

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final coords = (data['coordinates'] as List)
              .where((c) => c is Map && c['lat'] != null && c['lng'] != null)
              .map((c) => LatLng(
                    (c['lat'] as num).toDouble(),
                    (c['lng'] as num).toDouble(),
                  ))
              .toList();

          props.add(data);
          polys.add(coords);
          ids.add(doc.id);
        }

        setState(() {
          _userProperties.addAll(props);
          _polygonPointsList.addAll(polys);
          _documentIds.addAll(ids);
          _showSatelliteList.addAll(List.filled(props.length, false));
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
        _showSatelliteList.removeAt(index);
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

  void _showDetails(int index) {
    final prop = _userProperties[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(prop['title_number'] ?? 'Property Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailItem('Owner', prop['owner']),
              _buildDetailItem('Wallet', prop['wallet_address']),
              _buildDetailItem('Area', '${prop['area_sqkm']?.toStringAsFixed(2) ?? 'N/A'} km²'),
              _buildDetailItem('Description', prop['description']),
              _buildDetailItem(
                'Created',
                prop['timestamp']?.toDate().toString() ?? 'Unknown',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyMap(int index) {
    final poly = _polygonPointsList[index];
    final isSatellite = _showSatelliteList[index];
    
  return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: SizedBox(
        height: 160,
        child: Builder(
          builder: (context) {
            // Dynamically compute the polygon's center
            final polygonBounds = LatLngBounds.fromPoints(poly);
            final polygonCenter = polygonBounds.center;

            return FlutterMap(
              options: MapOptions(
                center: polygonCenter,
                zoom: 16, // Slightly closer for better framing
                interactiveFlags: InteractiveFlag.none, // Disable panning, zoom, tap
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://api.mapbox.com/styles/v1/{id}/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}",
                  additionalOptions: {
                    'accessToken': 'pk.eyJ1IjoibW9yZ25jb2x0IiwiYSI6ImNtYng2eHI0ZjB3cjQybW9zNXZhaDJqanYifQ.0qZEU6MBjiTZiUDPs6JyoQ',
                    'id': isSatellite
                        ? 'mapbox/satellite-v9'
                        : 'mapbox/outdoors-v12',
                  },
                  tileProvider: CancellableNetworkTileProvider(),
                ),
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: poly,
                      borderColor: Colors.green.shade700,
                      color: Colors.green.withOpacity(0.3),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPropertyCard(int index) {
    final prop = _userProperties[index];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Card(
          elevation: 2,
          margin: EdgeInsets.zero,
          color: Colors.grey[900],
          child: Column(
            children: [
              // 🗺️ Compact map height
              SizedBox(
                height: 100,
                child: _buildPropertyMap(index),
              ),

              // 📦 Condensed text content
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 📋 Text block
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prop['title_number'] ?? 'Untitled Property',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Owner: ${prop['owner'] ?? 'Unknown'}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(prop['description'] ?? '').toString()}',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // ⋮ Menu
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onSelected: (value) {
                        switch (value) {
                          case 'satellite':
                            setState(() => _showSatelliteList[index] = !_showSatelliteList[index]);
                            break;
                          case 'details':
                            _showDetails(index);
                            break;
                          case 'delete':
                            _deleteProperty(index);
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'satellite',
                          child: Text(
                            _showSatelliteList[index] ? 'Normal View' : 'Satellite View',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'details',
                          child: Text('Details'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete Property',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Properties in ${widget.regionKey}'),
      ),
      body: SafeArea(
        child: _userProperties.isEmpty && !_isLoading
            ? const Center(
                child: Text(
                  'No properties found',
                  style: TextStyle(fontSize: 18),
                ),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    _userProperties.clear();
                    _polygonPointsList.clear();
                    _documentIds.clear();
                    _showSatelliteList.clear();
                    _hasMore = true;
                    _lastDocument = null;
                  });
                  await _fetchProperties();
                },
                child: ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.zero,
                  itemCount: _userProperties.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _userProperties.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapScreen(
                              regionKey: widget.regionKey,
                              geojsonPath: widget.geojsonPath,
                              highlightPolygon: _polygonPointsList[index],
                            ),
                          ),
                        );
                      },
                      child: _buildPropertyCard(index),
                    );
                  },
                ),
              ),
      ),
    );
  }
}