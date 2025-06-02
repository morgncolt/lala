import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'map_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'dart:async';


class MyPropertiesScreen extends StatefulWidget {
  final String regionKey;
  final String geojsonPath;
  final List<LatLng>? highlightPolygon;


  const MyPropertiesScreen({
    super.key,
    required this.regionKey,
    required this.geojsonPath,
    this.highlightPolygon,
  });

  @override
  State<MyPropertiesScreen> createState() => _MyPropertiesScreenState();
}

class _MyPropertiesScreenState extends State<MyPropertiesScreen> {
  List<Map<String, dynamic>> userProperties = [];
  List<List<LatLng>> polygonPointsList = [];
  List<String> documentIds = [];
  bool isLoading = false;
  bool hasMore = true;
  DocumentSnapshot? lastDocument;
  final ScrollController _scrollController = ScrollController();
  final user = FirebaseAuth.instance.currentUser;
  bool showSatellite = false;
  Timer? _debounce;

  @override
  void dispose() {
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    fetchProperties();
    _scrollController.addListener(_onScroll);
  }
  
  void _onScroll() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        if (!isLoading && hasMore) {
          fetchProperties();
        }
      }
    });
  }

  Future<void> fetchProperties() async {
    if (user == null || isLoading || !hasMore) return;

    setState(() => isLoading = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection("users")
          .doc(user?.uid)
          .collection("regions")
          .where("region", isEqualTo: widget.regionKey)
          .orderBy("title_number")
          .limit(10);

      // Use the last fetched document to start after it
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        final props = <Map<String, dynamic>>[];
        final polys = <List<LatLng>>[];
        final ids = <String>[];

        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final coords = (data["coordinates"] as List)
              .where((c) => c is Map && c["lat"] != null && c["lng"] != null)
              .map((c) => LatLng(
                  (c["lat"] as num).toDouble(), (c["lng"] as num).toDouble()))
              .toList();

          props.add(data);
          polys.add(coords);
          ids.add(doc.id);
        }

        setState(() {
          userProperties.addAll(props);
          polygonPointsList.addAll(polys);
          documentIds.addAll(ids);
          lastDocument = snapshot.docs.last;
        });
      } else {
        setState(() {
          hasMore = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching paginated properties: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> deleteProperty(int index) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    final docId = documentIds[index];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text("Delete Property"),
        content: const Text("Are you sure you want to delete this saved region?"),
        actions: [
          TextButton(
            onPressed: () {
              if (mounted) Navigator.of(dialogContext).pop(false);
            },
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (mounted) Navigator.of(dialogContext).pop(true);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .collection("regions")
          .doc(docId)
          .delete();
    } catch (e, st) {
      if (!mounted) return;
      debugPrint("❌ Failed to delete Firestore doc: $e");
      debugPrintStack(stackTrace: st);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to delete region.")),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      userProperties.removeAt(index);
      polygonPointsList.removeAt(index);
      documentIds.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Region deleted successfully")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("My Properties (${widget.regionKey.toUpperCase()})"),
        actions: [
          IconButton(
            icon: Icon(showSatellite ? Icons.satellite_alt : Icons.map),
            onPressed: () {
              setState(() {
                showSatellite = !showSatellite;
              });
            },
          ),
        ],
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : userProperties.isEmpty
              ? const Center(child: Text("No saved properties found in this region."))
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: userProperties.length + 1, // for the loading/footer
                  itemBuilder: (context, index) {
                      if (index == userProperties.length) {
                        return hasMore
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: Text("No more properties to load.")),
                              );
                    }
                  
                    final poly = polygonPointsList[index];
                    final prop = userProperties[index];

                    return GestureDetector(
                      onTap: () async {
                        //if (!mounted) return;
                        await Future.delayed(const Duration(milliseconds: 100)); // slight delay for better UX
                        if (!mounted) return; // check if widget is still mounted
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapScreen(
                              regionKey: widget.regionKey,
                              geojsonPath: widget.geojsonPath,
                              highlightPolygon: polygonPointsList[index],
                            ),
                          ),
                        );
                        
                      },
                      child: AnimatedScale(
                        scale: 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // your map thumbnail
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  height: 150,
                                  child: FlutterMap(
                                    options: MapOptions(
                                      center: polygonPointsList[index][0],
                                      zoom: 14,
                                      interactiveFlags: InteractiveFlag.none,
                                    ),
                                    children: [
                                      TileLayer(
                                        urlTemplate: showSatellite
                                            ? 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                                            : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                        subdomains: showSatellite ? [] : ['a', 'b', 'c'],
                                        userAgentPackageName: 'com.example.landledger',
                                        tileProvider: CancellableNetworkTileProvider(),
                                      ),
                                      PolygonLayer(
                                        polygons: [
                                          Polygon(
                                            points: polygonPointsList[index],
                                            color: const Color.fromARGB(255, 76, 175, 134).withOpacity(0.4),
                                            borderColor: const Color.fromARGB(255, 76, 175, 134),
                                            borderStrokeWidth: 2,
                                          )
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Property info
                              ListTile(
                                title: Text(prop['title_number'] ?? 'Untitled Region'),
                                subtitle: Text("Owner: ${prop['owner'] ?? 'Unknown'}\n${prop['description'] ?? ''}"),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Color.fromARGB(255, 214, 10, 10)),
                                  onPressed: () async {
                                    if (!mounted) return;
                                    await deleteProperty(index);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
