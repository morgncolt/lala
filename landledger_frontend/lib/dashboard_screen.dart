import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:landledger_frontend/map_screen.dart';
import 'package:landledger_frontend/my_properties_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'dart:async';
import 'package:landledger_frontend/home_screen.dart';


class DashboardScreen extends StatefulWidget {
  final String regionKey;
  final String geojsonPath;
  final int initialTabIndex;

  const DashboardScreen({
    super.key,
    required this.regionKey,
    required this.geojsonPath,
    this.initialTabIndex = 0,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}


class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> userProperties = [];
  List<List<LatLng>> polygonPointsList = [];
  List<String> documentIds = [];
  bool isLoading = false;
  bool hasMore = true;
  bool showSatellite = false;
  DocumentSnapshot? lastDocument;
  final ScrollController _scrollController = ScrollController();
  final user = FirebaseAuth.instance.currentUser;
  Timer? _debounce;
  int _selectedIndex = 0;


  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex; // <-- Add this line
    //fetchProperties();
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
    if (user == null || isLoading || !hasMore || !mounted) return;

    setState(() => isLoading = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection("users")
          .doc(user?.uid)
          .collection("regions")
          .where("region", isEqualTo: widget.regionKey)
          .orderBy("title_number")
          .limit(10);

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument!);
      }

      final snapshot = await query.get();

      if(!mounted) return; // Check if widget is still mounted

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
        if (!mounted) return; // Check if widget is still mounted
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
    if (user == null ||  !mounted) return;

    final docId = documentIds[index];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Property"),
        content: const Text("Are you sure you want to delete this saved region?"),
        actions: [
          TextButton(
            onPressed: () {
              if (mounted) Navigator.pop(context, false);
            },
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (mounted) Navigator.pop(context, true);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) return;

    await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .collection("regions")
        .doc(docId)
        .delete();

    if (!mounted) return;

    setState(() {
      userProperties.removeAt(index);
      polygonPointsList.removeAt(index);
      documentIds.removeAt(index);
    });
  }

 @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        currentRegionKey: widget.regionKey,
        onRegionSelected: (regionKey, geojsonPath) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DashboardScreen(
                regionKey: regionKey,
                geojsonPath: geojsonPath,
                initialTabIndex: 1,
              ),
            ),
          );
        },
      ),
      MapScreen(
        regionKey: widget.regionKey,
        geojsonPath: widget.geojsonPath,
        onForceStayInMapTab: () {
          if (!mounted) return;
          setState(() {
            _selectedIndex = 1; // Force the tab to stay on Map View
          });
        },
      ),
      MyPropertiesScreen(
        regionKey: widget.regionKey,
        geojsonPath: widget.geojsonPath,
      ),
    ];


    return Scaffold(
      body: Row(
        children: [
          // 🚨 NavigationRail on the left
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              if (!mounted) return; // Ensure widget is still mounted
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            leading: const SizedBox(height: 32),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home),
                label: Text("Home"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.map),
                label: Text("Map View"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.list),
                label: Text("My Properties"),
              ),
            ],
          ),

          // 🧱 Vertical Divider between nav and content
          const VerticalDivider(thickness: 1, width: 1),

          // 📦 Main screen content
          Expanded(
            child: Column(
              children: [
                AppBar(
                  title: Text(
                    _selectedIndex == 0
                        ? "Home (${widget.regionKey.toUpperCase()})"
                        : _selectedIndex == 1
                            ? "Map View (${widget.regionKey.toUpperCase()})"
                            : "My Properties (${widget.regionKey.toUpperCase()})",
                  ),
                  actions: [
                    if (_selectedIndex != 0) // 👈 Only show on Map & Properties tabs
                      IconButton(
                        icon: Icon(showSatellite ? Icons.satellite_alt : Icons.map),
                        onPressed: () {
                          if (!mounted) return; // Ensure widget is still mounted
                          setState(() {
                            showSatellite = !showSatellite;
                          });
                        },
                      ),
                  ],
                ),

                Expanded(child: screens[_selectedIndex]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  
  Widget buildMyPropertiesList() {
    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : userProperties.isEmpty
            ? const Center(child: Text("No saved properties found in this region."))
            : ListView.builder(
                controller: _scrollController,
                itemCount: userProperties.length + 1,
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
                    onTap: () async{
                      if (!mounted) return; // Ensure widget is still mounted
                      await deleteProperty(index);
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
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 150,
                              child: FlutterMap(
                                options: MapOptions(
                                  center: poly[0],
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
                                        points: poly,
                                        color: Colors.purple.withOpacity(0.4),
                                        borderColor: Colors.purple,
                                        borderStrokeWidth: 2,
                                      )
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ListTile(
                            title: Text(prop['title_number'] ?? 'Untitled Region'),
                            subtitle: Text("Owner: ${prop['owner'] ?? 'Unknown'}\n${prop['description'] ?? ''}"),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => deleteProperty(index),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
  }


}
