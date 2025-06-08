import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'dart:async';

import 'package:landledger_frontend/home_screen.dart';
import 'package:landledger_frontend/map_screen.dart';
import 'package:landledger_frontend/my_properties_screen.dart';
import 'package:landledger_frontend/landledger_screen.dart';
import 'package:landledger_frontend/cif_screen.dart';
import 'package:landledger_frontend/settings_screen.dart';

// NAV ENTRY MODEL
class _NavEntry {
  final IconData icon;
  final String label;
  final Widget? screen;
  _NavEntry({
    required this.icon,
    required this.label,
    this.screen,
  });
}

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
  // pagination + data
  List<Map<String, dynamic>> userProperties = [];
  List<List<LatLng>> polygonPointsList = [];
  List<String> documentIds = [];
  bool isLoading = false;
  bool hasMore = true;
  DocumentSnapshot? lastDocument;

  // UI state
  bool isDarkMode = true;
  bool showSatellite = false;
  bool isRailExtended = false;                // <-- collapsible rail state

  // scroll debounce
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  // auth
  final user = FirebaseAuth.instance.currentUser;

  // nav
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _scrollController.addListener(_onScroll);
    // optionally fetchProperties() here if you want initial load
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
    if (user == null || isLoading || !hasMore || !mounted) return;

    setState(() => isLoading = true);

    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection("users")
          .doc(user!.uid)
          .collection("regions")
          .where("region", isEqualTo: widget.regionKey)
          .orderBy("title_number")
          .limit(10);

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument!);
      }

      final snapshot = await query.get();
      if (!mounted) return;

      if (snapshot.docs.isNotEmpty) {
        final props = <Map<String, dynamic>>[];
        final polys = <List<LatLng>>[];
        final ids = <String>[];

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final coords = (data["coordinates"] as List)
              .where((c) => c is Map && c["lat"] != null && c["lng"] != null)
              .map((c) => LatLng(
                    (c["lat"] as num).toDouble(),
                    (c["lng"] as num).toDouble(),
                  ))
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
        setState(() => hasMore = false);
      }
    } catch (e) {
      debugPrint("Error fetching paginated properties: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> deleteProperty(int index) async {
    if (user == null || !mounted) return;
    final docId = documentIds[index];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Property"),
        content: const Text("Are you sure you want to delete this saved region?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await FirebaseFirestore.instance
        .collection("users")
        .doc(user!.uid)
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
    final navEntries = <_NavEntry>[
      _NavEntry(
        icon: Icons.home,
        label: 'Home',
        screen: HomeScreen(
          currentRegionKey: widget.regionKey,
          onRegionSelected: (newKey, newPath) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => DashboardScreen(
                  regionKey: newKey,
                  geojsonPath: newPath,
                  initialTabIndex: 1,
                ),
              ),
            );
          },
        ),
      ),
      _NavEntry(
        icon: Icons.list,
        label: 'My Properties',
        screen: MyPropertiesScreen(
          regionKey: widget.regionKey,
          geojsonPath: widget.geojsonPath,
        ),
      ),
      _NavEntry(
        icon: Icons.map,
        label: 'Map View',
        screen: MapScreen(
          regionKey: widget.regionKey,
          geojsonPath: widget.geojsonPath,
          onForceStayInMapTab: () => setState(() => _selectedIndex = 2),
          centerOnRegion: true,
        ),
      ),
      _NavEntry(
        icon: Icons.bar_chart,
        label: 'LandLedger',
        screen: const Center(child: Text('LandLedger 🔜')),
      ),
      _NavEntry(
        icon: Icons.bar_chart,
        label: 'CIF',
        screen: const Center(child: Text('CIF 🔜')),
      ),
      _NavEntry(
        icon: Icons.settings,
        label: 'Settings',
        screen: const Center(child: Text('Settings 🔜')),
      ),
    ];

    return Scaffold(
      body: Row(
        children: [
          Theme(
            data: Theme.of(context).copyWith(
              navigationRailTheme: NavigationRailThemeData(
                backgroundColor: Colors.white,
                elevation: 6,
                indicatorColor: Theme.of(context).primaryColor.withOpacity(0.15),
                indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                selectedIconTheme: IconThemeData(
                  color: Theme.of(context).primaryColor,
                  size: 28,
                ),
                unselectedIconTheme: IconThemeData(
                  color: Colors.grey.shade600,
                  size: 24,
                ),
                selectedLabelTextStyle: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelTextStyle: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            child: NavigationRail(
              extended: isRailExtended,
              minWidth: 56,              // width when collapsed
              minExtendedWidth: 120,     // width when expanded
              labelType: NavigationRailLabelType.none,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) {
                if (navEntries[i].icon == Icons.logout) {
                  FirebaseAuth.instance.signOut();
                  Navigator.pushReplacementNamed(context, '/login');
                } else {
                  setState(() => _selectedIndex = i);
                }
              },
              leading: Column(
                children: [
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: Theme.of(context).primaryColor,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.terrain, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  IconButton(
                    icon: Icon(
                      isRailExtended
                          ? Icons.chevron_left
                          : Icons.chevron_right,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () => setState(() => isRailExtended = !isRailExtended),
                  ),
                ],
              ),
              destinations: navEntries
                  .map((e) => NavigationRailDestination(
                        icon: Icon(e.icon),
                        label: Text(e.label),
                      ))
                  .toList(),
              trailing: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () {
                    FirebaseAuth.instance.signOut();
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                ),
              ),
            ),
          ),

          const VerticalDivider(thickness: 1, width: 1),

          Expanded(
            child: Stack(
              children: [
                // Selected screen
                Positioned.fill(
                  child: navEntries[_selectedIndex].screen!,
                ),

                // Search bar for list/map
                if (_selectedIndex == 1 || _selectedIndex == 2)
                  Positioned(
                    top: 20,
                    left: isRailExtended ? 80 : 56,
                    child: SizedBox(
                      width: 320,
                      child: Material(
                        elevation: 5,
                        borderRadius: BorderRadius.circular(30),
                        color: Colors.white,
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: _selectedIndex == 1
                                ? 'Search properties…'
                                : 'Search map…',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      // Theme toggle
      floatingActionButton: FloatingActionButton.small(
        tooltip: 'Toggle Theme',
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        onPressed: () => setState(() => isDarkMode = !isDarkMode),
        child: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
      ),
    );
  }

  // Legacy list builder (if still needed)
  Widget buildMyPropertiesList() {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (userProperties.isEmpty) return const Center(child: Text("No saved properties found in this region."));

    return ListView.builder(
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
          onTap: () async {
            await deleteProperty(index);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MapScreen(
                  regionKey: widget.regionKey,
                  geojsonPath: widget.geojsonPath,
                  highlightPolygon: poly,
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
                        center: poly.first,
                        zoom: 14,
                        interactiveFlags: InteractiveFlag.none,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: showSatellite
                              ? 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                              : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                          subdomains: showSatellite ? [] : ['a','b','c'],
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
                  subtitle: Text(
                    "Owner: ${prop['owner'] ?? 'Unknown'}\n${prop['description'] ?? ''}",
                  ),
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
