import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'region_model.dart';
import 'regions_repository.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;



class MapScreen extends StatefulWidget {
  final String regionId;
  final String? geojsonPath;
  final bool startDrawing;
  final List<LatLng>? highlightPolygon;
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
  
  bool isDrawing = false;
  bool showSatellite = false;
  bool show3D = false;
  List<LatLng> currentPolygonPoints = [];
  List<List<LatLng>> boundaryPolygons = [];
  List<List<LatLng>> userPolygons = [];
  List<List<LatLng>> otherPolygons = [];
  List<DocumentSnapshot> userPolygonDocs = [];
  List<DocumentSnapshot> otherPolygonDocs = [];
  List<LatLng>? selectedPolygon;
  Region? currentRegion;
  DocumentSnapshot? _selectedPolygonDoc;
  bool _showPolygonInfo = false;
  LatLng? _currentCenter;

  String generateAliasFromCity(String city) {
    final cleaned = city.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();

    if (cleaned.length <= 4) {
      final code = _randomCode();
      return '#${cleaned[0].toUpperCase()}${cleaned.substring(1)}$code';
    }

    // Naive syllable split: take first letter from consonant-vowel transitions
    final vowels = 'aeiouy';
    final buffer = StringBuffer();
    bool lastWasVowel = false;

    for (int i = 0; i < cleaned.length; i++) {
      final char = cleaned[i];
      final isVowel = vowels.contains(char);
      if (isVowel && !lastWasVowel && i > 0) {
        buffer.write(cleaned[i - 1]); // consonant before vowel
      }
      lastWasVowel = isVowel;
    }

    final short = buffer.toString().isNotEmpty ? buffer.toString().toUpperCase() : cleaned.substring(0, 2).toUpperCase();
    return '#$short${_randomCode()}';
  }

  String _randomCode() {
    final rand = DateTime.now().microsecondsSinceEpoch;
    final digits = (1000 + rand % 9000).toString(); // 4-digit number
    return digits;
  }


  String get _mapboxStyleId {
    if (showSatellite) {
      return 'mapbox/satellite-streets-v12';
    } else if (show3D) {
      return 'morgancolt/clxyz3dstyle';
    }
    return 'mapbox/outdoors-v12';
  }

  @override
  void initState() {
    super.initState();
    _initializeRegion();
    if (widget.startDrawing) {
      isDrawing = true;
    }
    _loadUserSavedPolygons();
  }

  Future<void> _initializeRegion() async {
    currentRegion = RegionsRepository.getById(widget.regionId);
    if (currentRegion != null) {
      await _loadRegionBoundary();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.centerOnRegion && boundaryPolygons.isNotEmpty && mounted) {
          final bounds = LatLngBounds.fromPoints(boundaryPolygons.expand((p) => p).toList());
          mapController.fitBounds(bounds, options: const FitBoundsOptions(padding: EdgeInsets.all(60)));
        }
      });
    }

    if (widget.highlightPolygon != null && widget.highlightPolygon!.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          final bounds = LatLngBounds.fromPoints(widget.highlightPolygon!);
          mapController.fitBounds(bounds, options: const FitBoundsOptions(padding: EdgeInsets.all(40)));
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
      final features = geoData['features'] as List<dynamic>;

      final parsedPolygons = <List<LatLng>>[];

      for (final feature in features) {
        final geometry = feature['geometry'] as Map<String, dynamic>;
        final type = geometry['type'] as String;
        final coordinates = geometry['coordinates'] as List<dynamic>;

        if (type == 'Polygon') {
          final coords = coordinates[0] as List<dynamic>;
          parsedPolygons.add(coords.map<LatLng>((coord) {
            return LatLng(
              (coord[1] as num).toDouble(),
              (coord[0] as num).toDouble(),
            );
          }).toList());
        } else if (type == 'MultiPolygon') {
          for (final polygon in coordinates) {
            final coords = (polygon as List<dynamic>)[0] as List<dynamic>;
            parsedPolygons.add(coords.map<LatLng>((coord) {
              return LatLng(
                (coord[1] as num).toDouble(),
                (coord[0] as num).toDouble(),
              );
            }).toList());
          }
        }
      }

      if (mounted) {
        setState(() => boundaryPolygons = parsedPolygons);
      }
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
      // Get all polygons in the current region
      final allPolygonsSnapshot = await FirebaseFirestore.instance
          .collectionGroup('regions')
          .where('region', isEqualTo: widget.regionId)
          .get();

      // Separate into user-owned and other polygons
      final tempUserPolygons = <List<LatLng>>[];
      final tempOtherPolygons = <List<LatLng>>[];
      final tempUserDocs = <DocumentSnapshot>[];
      final tempOtherDocs = <DocumentSnapshot>[];

      for (final doc in allPolygonsSnapshot.docs) {
        final coords = (doc['coordinates'] as List).map((c) => 
          LatLng(c['lat'] as double, c['lng'] as double)).toList();
        
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

  void _handleMapTap(TapPosition tapPosition, LatLng point) async {
    if (isDrawing) {
      setState(() {
        currentPolygonPoints.add(point);
        _showPolygonInfo = false;
      });
      return;
    }

    // Check user polygons first
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

    // Then check other polygons
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
    
    // If no polygon was tapped, deselect
    setState(() {
      selectedPolygon = null;
      _showPolygonInfo = false;
      _selectedPolygonDoc = null;
    });
  }

  bool pointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      if (((polygon[i].latitude > point.latitude) != 
           (polygon[j].latitude > point.latitude))) {
        final intersect = point.longitude < 
            (polygon[j].longitude - polygon[i].longitude) * 
            (point.latitude - polygon[i].latitude) / 
            (polygon[j].latitude - polygon[i].latitude) + 
            polygon[i].longitude;
        if (intersect) intersectCount++;
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
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        mapController.move(LatLng(position.latitude, position.longitude), 14);
      }
    } catch (e) {
      debugPrint("Location error: $e");
    }
  }

  double calculateArea(List<LatLng> points) {
    double area = 0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      area += points[i].latitude * points[j].longitude;
      area -= points[j].latitude * points[i].longitude;
    }
    return area.abs() / 2 * 111 * 111;
  }

  LatLng _calculateCentroid(List<LatLng> points) {
  double latSum = 0, lngSum = 0;
    for (var point in points) {
      latSum += point.latitude;
      lngSum += point.longitude;
    }
    return LatLng(latSum / points.length, lngSum / points.length);
  }

  Future<void> saveToBlockchain(String id, List<LatLng> points, String wallet, String description) async {
    final url = Uri.parse('http://10.0.2.2:4000/api/landledger/register');

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
        final blockchainRecord = jsonDecode(response.body);
        debugPrint("✅ Blockchain registration success");

        // Show confirmation dialog
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("✅ Blockchain Success"),
              content: Text("Polygon ${id} successfully saved to the blockchain."),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Save"),
          ),
        ],
      ),
    );

  if (confirm != true) return;

  // Ensure polygon is closed before calculating area and saving
  final closedPolygon = [...currentPolygonPoints];
  if (closedPolygon.first != closedPolygon.last) {
    closedPolygon.add(closedPolygon.first);
  }

  final areaSqKm = calculateArea(closedPolygon);

  try {
    // Save to Firestore
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
      "coordinates": closedPolygon.map((p) => {
        "lat": p.latitude,
        "lng": p.longitude,
      }).toList(),
      "area_sqkm": areaSqKm,
      "timestamp": FieldValue.serverTimestamp(),
    });
    debugPrint("✅ Polygon saved to Firestore with ID: $llid");

    // Save to Blockchain (Node.js API)
    await saveToBlockchain(
      llid,
      closedPolygon,
      walletController.text,
      descriptionController.text,
    );

    debugPrint("✅ Polygon saved successfully with ID: $llid");

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Region saved successfully")),
      );
      setState(() {
        currentPolygonPoints = [];
        isDrawing = false;
      });
      _loadUserSavedPolygons();
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save: $e")),
      );
    }
  }
}

  Future<Map<String, dynamic>?> fetchPolygonFromBlockchain(String id) async {
    final url = Uri.parse('http://10.0.2.2:4000/api/landledger/$id');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final coordinates = (jsonBody['polygon'] as List)
            .map((coord) => LatLng(coord[1], coord[0]))
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
      if (_showPolygonInfo && _selectedPolygonDoc != null)
        buildPolygonInfoCard(),

      // Main floating buttons (zoom, center, draw/save)
      Positioned(
        bottom: 100,
        right: 16,
        child: Column(
          children: [
            // Zoom In
            FloatingActionButton(
              heroTag: "btn-zoom-in",
              mini: true,
              child: const Icon(Icons.add),
              onPressed: () => mapController.move(
                mapController.center,
                mapController.zoom + 1,
              ),
            ),
            const SizedBox(height: 8),

            // Zoom Out
            FloatingActionButton(
              heroTag: "btn-zoom-out",
              mini: true,
              child: const Icon(Icons.remove),
              onPressed: () => mapController.move(
                mapController.center,
                mapController.zoom - 1,
              ),
            ),
            const SizedBox(height: 8),

            // Center to user
            FloatingActionButton(
              heroTag: "btn-center",
              mini: true,
              child: const Icon(Icons.my_location),
              onPressed: centerToUserLocation,
            ),
            const SizedBox(height: 8),

            // Draw or Save toggle with area display
            if (currentPolygonPoints.length >= 3 && isDrawing)
              Column(
                children: [
                  // Area pill with unit switching
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),

                  // Save button
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
                backgroundColor:
                    isDrawing ? Colors.red : const Color.fromARGB(255, 2, 76, 63),
                child: Icon(
                    isDrawing ? Icons.close : Icons.edit_location_alt),
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

      // Drawing instruction hint
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedPolygonDoc!['title_number'] ?? 'No Title',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_selectedPolygonDoc!.data().toString().contains('alias'))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _selectedPolygonDoc!['alias'],
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _showPolygonInfo = false),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Description: ${_selectedPolygonDoc!['description'] ?? 'No description'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Wallet: ${_selectedPolygonDoc!['wallet_address'] ?? 'No wallet'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final area = _selectedPolygonDoc!['area_sqkm'];
                    if (area == null || area == 0) return const Text("Area: Unknown");

                    final areaSqM = area * 1e6;
                    final formatted = areaSqM >= 100000
                        ? "${(areaSqM / 1e6).toStringAsFixed(2)} km²"
                        : "${areaSqM.toStringAsFixed(0)} m²";

                    return Text("Area: $formatted");
                  },
                ),


                const SizedBox(height: 8),
                if (_selectedPolygonDoc!['timestamp'] != null)
                  Text(
                    'Created: ${DateFormat('yyyy-MM-dd').format((_selectedPolygonDoc!['timestamp'] as Timestamp).toDate())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String> getCityNameFromLatLng(LatLng latLng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
      if (placemarks.isNotEmpty) {
        return placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? 'Unknown City';
      }
    } catch (e) {
      print("Error during reverse geocoding: $e");
    }
    return 'Unknown City';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(currentRegion?.name ?? 'Map View'),
        leading: widget.showBackArrow
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                debugPrint("🔙 Back button pressed: mounted=$mounted");

                if (widget.onBackToHome != null) {
                  debugPrint("➡️ Calling onBackToHome callback");
                  widget.onBackToHome!();
                } else {
                  final navigator = Navigator.of(context);
                  if (navigator.canPop()) {
                    debugPrint("✅ Navigator.pop called");
                    navigator.pop();
                  } else {
                    debugPrint("⚠️ Nothing to pop from Navigator stack");
                    // Optional: Route to home or use another fallback
                    if (widget.openedFromTab && widget.onOpenMyProperties != null) {
                      widget.onOpenMyProperties!();
                    }
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
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                center: currentRegion?.center ?? const LatLng(0, 0),
                zoom: currentRegion?.zoomLevel ?? 5,
                onTap: _handleMapTap,
                onPositionChanged: (MapPosition position, bool hasGesture) {
                  setState(() {
                    _currentCenter = position.center;
                  });
                },
              ),

            children: [
              TileLayer(
                urlTemplate: "https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}",
                additionalOptions: {
                  'accessToken': 'pk.eyJ1IjoibW9yZ25jb2x0IiwiYSI6ImNtYng2eHI0ZjB3cjQybW9zNXZhaDJqanYifQ.0qZEU6MBjiTZiUDPs6JyoQ',
                  'id': _mapboxStyleId,
                },
                tileSize: 512,
                zoomOffset: -1,
                tileProvider: CancellableNetworkTileProvider(),
              ),

              if (selectedPolygon != null)
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.5),
                    BlendMode.darken,
                  ),
                  child: TileLayer(
                    urlTemplate: "https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}",
                    additionalOptions: {
                      'accessToken': 'pk.eyJ1IjoibW9yZ25jb2x0IiwiYSI6ImNtYng2eHI0ZjB3cjQybW9zNXZhaDJqanYifQ.0qZEU6MBjiTZiUDPs6JyoQ',
                      'id': _mapboxStyleId,
                    },
                    tileSize: 512,
                    zoomOffset: -1,
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
                      borderColor: polygon == selectedPolygon
                        ? Colors.white
                        : Colors.blue,
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
                      borderColor: polygon == selectedPolygon
                        ? Colors.white
                        : Colors.grey,
                      borderStrokeWidth: polygon == selectedPolygon ? 3 : 1,
                      isFilled: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: FutureBuilder<String>(
                future: _currentCenter != null
                    ? getCityNameFromLatLng(_currentCenter!)
                    : Future.value('Unknown City'),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text(
                      'Loading...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  } else if (snapshot.hasError || !snapshot.hasData) {
                    return const Text(
                      'Unknown City',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  } else {
                    return Text(
                      snapshot.data!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }
                },
              ),
            ),
          ),

          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _currentCenter != null
                    ? 'Lat: ${_currentCenter!.latitude.toStringAsFixed(5)}, '
                      'Lng: ${_currentCenter!.longitude.toStringAsFixed(5)}'
                    : 'Coords unavailable',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),


          

          buildMapControls(),

          // Show polygon info card if selected
            // Instructional text while drawing
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