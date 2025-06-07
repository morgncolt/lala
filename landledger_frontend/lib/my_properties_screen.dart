import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'map_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'dart:async';

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
  List<Map<String, dynamic>> userProperties = [];
  List<List<LatLng>> polygonPointsList = [];
  List<String> documentIds = [];
  List<bool> showSatelliteList = [];
  bool isLoading = false;
  bool hasMore = true;
  DocumentSnapshot? lastDocument;
  final ScrollController _scrollController = ScrollController();
  final user = FirebaseAuth.instance.currentUser;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    fetchProperties();
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
        if (!isLoading && hasMore) fetchProperties();
      }
    });
  }

  Future<void> fetchProperties() async {
    if (user == null || isLoading || !hasMore) return;
    setState(() => isLoading = true);

    try {
      var query = FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('regions')
          .where('region', isEqualTo: widget.regionKey)
          .orderBy('title_number')
          .limit(10);

      if (lastDocument != null) query = query.startAfterDocument(lastDocument!);

      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
        final props = <Map<String, dynamic>>[];
        final polys = <List<LatLng>>[];
        final ids = <String>[];

        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final coords = (data['coordinates'] as List)
              .where((c) => c is Map && c['lat'] != null && c['lng'] != null)
              .map((c) => LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble()))
              .toList();

          props.add(data);
          polys.add(coords);
          ids.add(doc.id);
        }

        setState(() {
          userProperties.addAll(props);
          polygonPointsList.addAll(polys);
          documentIds.addAll(ids);
          showSatelliteList.addAll(List.filled(props.length, false));
          lastDocument = snapshot.docs.last;
        });
      } else {
        setState(() => hasMore = false);
      }
    } catch (e) {
      debugPrint('Error fetching properties: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> deleteProperty(int index) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    final docId = documentIds[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Property'),
        content: const Text('Are you sure you want to delete this region?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('regions')
          .doc(docId)
          .delete();

      if (!mounted) return;
      setState(() {
        userProperties.removeAt(index);
        polygonPointsList.removeAt(index);
        documentIds.removeAt(index);
        showSatelliteList.removeAt(index);
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Region deleted successfully')));
    } catch (e, st) {
      debugPrint('Failed to delete: $e');
      debugPrintStack(stackTrace: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete region.')));
    }
  }

  void _showDetails(int index) {
    final prop = userProperties[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(prop['title_number'] ?? 'Details', style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Owner: ${prop['owner'] ?? 'Unknown'}', style: const TextStyle(color: Colors.white)),
              Text('Wallet: ${prop['wallet'] ?? 'N/A'}', style: const TextStyle(color: Colors.white)),
              Text('Area: ${prop['area']?.toString() ?? 'N/A'} km²', style: const TextStyle(color: Colors.white)),
              Text('Description: ${prop['description'] ?? ''}', style: const TextStyle(color: Colors.white)),
              Text('Timestamp: ${prop['timestamp'] ?? ''}', style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: userProperties.isEmpty && !isLoading
            ? const Center(child: Text('No saved properties found.'))
            : ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                itemCount: userProperties.length + (hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == userProperties.length) {
                    return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                  }
                  final prop = userProperties[index];
                  final poly = polygonPointsList[index];
                  final isSatellite = showSatelliteList[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen(
                        regionKey: widget.regionKey,
                        geojsonPath: widget.geojsonPath,
                        highlightPolygon: poly,
                      )));
                    },
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            child: SizedBox(
                              height: 160,
                              child: FlutterMap(
                                options: MapOptions(center: poly[0], zoom: 14, interactiveFlags: InteractiveFlag.none),
                                children: [
                                  TileLayer(
                                    urlTemplate: isSatellite
                                        ? 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                        : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    subdomains: isSatellite ? [] : ['a', 'b', 'c'],
                                    userAgentPackageName: 'com.example.landledger',
                                    tileProvider: CancellableNetworkTileProvider(),
                                  ),
                                  PolygonLayer(polygons: [
                                    Polygon(points: poly, borderColor: Colors.green.shade700, color: Colors.green.withOpacity(0.3), borderStrokeWidth: 2),
                                  ]),
                                ],
                              ),
                            ),
                          ),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            title: Text(prop['title_number'] ?? 'Untitled'),
                            subtitle: Text('Owner: ${prop['owner'] ?? 'Unknown'}\n${prop['description'] ?? ''}'),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'satellite') {
                                  setState(() => showSatelliteList[index] = !isSatellite);
                                } else if (value == 'delete') {
                                  deleteProperty(index);
                                } else if (value == 'details') {
                                  _showDetails(index);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'satellite', child: Text(isSatellite ? 'Normal View' : 'Satellite View')),
                                PopupMenuItem(value: 'details', child: const Text('Details')),
                                PopupMenuItem(value: 'delete', child: Text('Delete Property', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
