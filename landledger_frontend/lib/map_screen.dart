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

class MapScreen extends StatefulWidget {
  final String regionKey;
  final String geojsonPath;
  final bool startDrawing;
  final List<LatLng>? highlightPolygon;

  final void Function()? onForceStayInMapTab; 


  const MapScreen({
    super.key,
    required this.regionKey,
    required this.geojsonPath,
    this.startDrawing = false,
    this.highlightPolygon,
    this.onForceStayInMapTab, // <-- And this

  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final user = FirebaseAuth.instance.currentUser;
  final mapController = MapController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController walletController = TextEditingController();
  bool isDrawing = false;
  bool showSatellite = false;
  bool isLoading = false;
  bool hasMore = true;
  DocumentSnapshot? lastDocument;
  List<LatLng> currentPolygonPoints = [];
  List<Map<String, dynamic>> userProperties = [];
  List<List<LatLng>> polygonPointsList = [];
  List<String> documentIds = [];
  Timer? _debounce;
  List<List<LatLng>> boundaryPolygons = [];

  @override
  void initState() {
    super.initState();
    fetchProperties();
    _scrollController.addListener(_onScroll);
    loadGeoJsonBoundary();
    centerToUserLocation();
    if (widget.highlightPolygon != null && widget.highlightPolygon!.isNotEmpty) {
      Future.delayed(Duration(milliseconds: 500), () {
        final bounds = LatLngBounds.fromPoints(widget.highlightPolygon!);
        mapController.fitBounds(bounds, options: const FitBoundsOptions(padding: EdgeInsets.all(40)));
      });
    }
  }

  void _onScroll() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (!isLoading && hasMore) {
          fetchProperties();
        }
      }
    });
  }

  Future<void> centerToUserLocation() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
    final position = await Geolocator.getCurrentPosition();
    mapController.move(LatLng(position.latitude, position.longitude), 14);
  }

  Future<void> loadGeoJsonBoundary() async {
    try {
      final geojsonStr = await rootBundle.loadString(widget.geojsonPath);
      final Map<String, dynamic> geoData = json.decode(geojsonStr);
      final features = geoData['features'] as List<dynamic>;

      final parsedPolygons = <List<LatLng>>[];
      for (var feature in features) {
        final geometry = feature['geometry'];
        if (geometry['type'] == 'Polygon') {
          final coords = geometry['coordinates'][0] as List;
          parsedPolygons.add(coords.map<LatLng>((coord) =>
              LatLng(coord[1].toDouble(), coord[0].toDouble())).toList());
        } else if (geometry['type'] == 'MultiPolygon') {
          final multiCoords = geometry['coordinates'] as List;
          for (var polygon in multiCoords) {
            final coords = polygon[0] as List;
            parsedPolygons.add(coords.map<LatLng>((coord) =>
                LatLng(coord[1].toDouble(), coord[0].toDouble())).toList());
          }
        }
      }

      if (mounted) {
        setState(() => boundaryPolygons = parsedPolygons);
      }
    } catch (e) {
      debugPrint("❌ GeoJSON load failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to load boundary GeoJSON.")),
        );
      }
    }
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
      if (lastDocument != null) query = query.startAfterDocument(lastDocument!);
      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
        final props = <Map<String, dynamic>>[];
        final polys = <List<LatLng>>[];
        final ids = <String>[];
        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final coords = (data["coordinates"] as List)
              .where((c) => c is Map && c["lat"] != null && c["lng"] != null)
              .map((c) => LatLng((c["lat"] as num).toDouble(), (c["lng"] as num).toDouble()))
              .toList();
          props.add(data);
          polys.add(coords);
          ids.add(doc.id);
        }
        setState(() {
          userProperties = props;
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

  double calculateArea(List<LatLng> points) {
    double area = 0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      area += points[i].latitude * points[j].longitude;
      area -= points[j].latitude * points[i].longitude;
    }
    return area.abs() / 2 * 111 * 111;
  }

  Future<void> savePolygon() async {
    print("🚨 savePolygon() called");
    try {
      if (currentPolygonPoints.length < 3 || user == null || !mounted){
        print("⛔ Invalid state: user=$user, mounted=$mounted, points=${currentPolygonPoints.length}");
        return;
      }

      print("📝 Preparing to save region with ${currentPolygonPoints.length} points...");

      final uuid = Uuid().v4().substring(0, 8);
      final llid = 'LL-$uuid'.toUpperCase();
      print("🔑 Generated LLID: $llid");

      descriptionController.clear();
      walletController.clear();

      final confirm = await showDialog<bool>(
        context: context,
          builder: (BuildContext dialogContext) {  
          return AlertDialog(
            title: const Text("Save Region"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Generated Title ID: $llid"),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: "Description"),
                  ),
                  TextField(
                    controller: walletController,
                    decoration: const InputDecoration(labelText: "Owner Wallet Address"),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (mounted) Navigator.of(dialogContext).pop(false); // 👈 use dialogContext
                },
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  if (mounted) Navigator.of(dialogContext).pop(true); // 👈 use dialogContext
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      );
      print("🗨️ User confirmed save: $confirm");
      if (!mounted || confirm != true) return;

      print("🔥 Region data prepared.");

      final geojson = jsonEncode({
        "type": "Polygon",
        "coordinates": [
          currentPolygonPoints.map((p) => [p.longitude, p.latitude]).toList()
        ]
      });
      print("🌐 GeoJSON generated:\n$geojson");

      final data = {
        "title_number": llid,
        "description": descriptionController.text.trim(),
        "owner": user!.email ?? "Anonymous",
        "wallet_address": walletController.text.trim(),
        "region": widget.regionKey,
        "coordinates": currentPolygonPoints
            .map((p) => {"lat": p.latitude, "lng": p.longitude})
            .toList(),
        "geojson": geojson,
        "area_sqkm": calculateArea(currentPolygonPoints),
        "timestamp": FieldValue.serverTimestamp(),
      };

      final debugData = Map<String, dynamic>.from(data);
      debugData["timestamp"] = "serverTimestamp()";
      print("📦 Data to be saved (for logging):\n${jsonEncode(debugData)}");
      print("📤 Writing to Firestore...");

      try {
        await FirebaseFirestore.instance
            .collection("users")
            .doc(user!.uid)
            .collection("regions")
            .add(data)
            .timeout(const Duration(seconds: 5)); // timeout safety
        print("✅ Firestore write complete.");
      } catch (e, st) {
        print("❌ Error during Firestore write: $e");
        debugPrintStack(stackTrace: st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Firestore write failed: $e')),
          );
        }
        return;
      }

      if (!mounted) return;

      print("🔄 Fetching properties after save...");
      try {
        await fetchProperties();
        print("✅ Properties fetched.");
      } catch (e, st) {
        print("❌ Error fetching properties after save: $e");
        debugPrintStack(stackTrace: st);
      }

      print("🧹 Resetting drawing state.");
      setState(() {
        currentPolygonPoints = [];
        isDrawing = false;
        hasMore = true;
        lastDocument = null;
        documentIds.clear();
      });

      try {
        final controller = DefaultTabController.of(context);
        if (controller.index != 1) {
          controller.animateTo(1); // Stay on Map View
          debugPrint("🔄 Tab manually locked to Map View (index 1)");
        }
      } catch (e) {
        debugPrint("⚠️ No TabController found: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Region saved successfully")),
        );
      }
    } catch (e, st) {
      debugPrint("❌ Uncaught error during savePolygon: $e");
      debugPrintStack(stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unexpected error while saving')),
        );
      }
    }
  }

  bool pointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int j = 0; j < polygon.length - 1; j++) {
      LatLng a = polygon[j];
      LatLng b = polygon[j + 1];
      if (((a.latitude > point.latitude) != (b.latitude > point.latitude)) &&
          (point.longitude < (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude)) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) == 1;
  }


  void showPropertyDetails(Map<String, dynamic> prop) {
    if (!mounted) return;

    Future.microtask(() {
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(prop['title_number'] ?? 'Region'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Owner: ${prop['owner'] ?? ''}"),
              Text("Wallet: ${prop['wallet_address'] ?? ''}"),
              Text("Area: ${prop['area_sqkm']?.toStringAsFixed(2) ?? '--'} km²"),
              Text("Description: ${prop['description'] ?? ''}"),
              Text("Timestamp: ${prop['timestamp'] != null ? prop['timestamp'].toDate().toString() : 'Pending'}"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Use local context here
              },
              child: const Text("Close"),
            )
          ],
        ),
      );

    });
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        appBar: AppBar(
          title: Text("Map View (${widget.regionKey.toUpperCase()})"),
          actions: [
            IconButton(
              icon: Icon(showSatellite ? Icons.satellite_alt : Icons.map),
              onPressed: () => setState(() => showSatellite = !showSatellite),
            ),
          ],
        ),
        body: FlutterMap(
          mapController: mapController,
          options: MapOptions(
            center: LatLng(0, 0),
            zoom: 5,
            onTap: (_, tapPoint) async {
              if (!mounted) return;

              if (isDrawing) {
                setState(() => currentPolygonPoints.add(tapPoint));
                return;
              }

              for (int i = 0; i < polygonPointsList.length; i++) {
                if (pointInPolygon(tapPoint, polygonPointsList[i])) {
                  final prop = userProperties[i];
                  await Future.delayed(const Duration(milliseconds: 50));
                  if (!mounted) return;
                  showPropertyDetails(prop);
                  break;
                }
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: showSatellite
                  ? 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: showSatellite ? [] : ['a', 'b', 'c'],
              userAgentPackageName: 'com.example.landledger',
              tileProvider: CancellableNetworkTileProvider(),
            ),
            PolygonLayer(
              polygons: [
                if (currentPolygonPoints.isNotEmpty)
                  Polygon(
                    points: currentPolygonPoints,
                    borderColor: const Color.fromARGB(255, 46, 176, 130),
                    color: const Color.fromARGB(255, 46, 23, 173).withOpacity(0.5),
                    borderStrokeWidth: 2,
                  ),
                ...polygonPointsList.asMap().entries.map((entry) {
                  final index = entry.key;
                  final points = entry.value;
                  final prop = userProperties[index];
                  return Polygon(
                    points: points,
                    color: const Color.fromARGB(255, 54, 244, 127).withOpacity(0.4),
                    borderColor: const Color.fromARGB(255, 2, 58, 23),
                    borderStrokeWidth: 2,
                    isFilled: true,
                    label: "Property",
                    labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                  );
                }),
                if (widget.highlightPolygon != null && widget.highlightPolygon!.isNotEmpty)
                  Polygon(
                    points: widget.highlightPolygon!,
                    color: const Color.fromARGB(255, 54, 244, 127).withOpacity(0.4),
                    borderColor: const Color.fromARGB(255, 2, 58, 23),
                    borderStrokeWidth: 3,
                  ),
                ...boundaryPolygons.map(
                  (polygon) => Polygon(
                    points: polygon,
                    borderColor: const Color.fromARGB(255, 1, 83, 3),
                    color: Colors.transparent,
                    borderStrokeWidth: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: Icon(isDrawing ? Icons.save : Icons.edit),
          label: Text(isDrawing ? "Save Region" : "Add Region"),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("🟢 Button Pressed")),
            );
            print("🟢 FAB tapped - isDrawing=$isDrawing, points=${currentPolygonPoints.length}");
            if (isDrawing && currentPolygonPoints.length >= 3) {
              savePolygon();
            } else {
              setState(() => isDrawing = !isDrawing);
            }
          },
        ),
      );
    } catch (e, st) {
      debugPrint("❌ Uncaught error in MapScreen build: $e");
      debugPrintStack(stackTrace: st);
      return const Scaffold(
        body: Center(
          child: Text(
            "An error occurred while loading the map. Please try again later.",
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }
  }
}