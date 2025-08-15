// lib/landledger_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

/// Cross‑platform API base:
/// - Android emulator: http://10.0.2.2:4000
/// - Web/desktop/iOS sim: http://localhost:4000
String get apiBase {
  if (kIsWeb) return 'http://localhost:4000';
  if (Platform.isAndroid) return 'http://10.0.2.2:4000';
  return 'http://localhost:4000';
}

class LandledgerScreen extends StatefulWidget {
  final Map<String, dynamic>? selectedRecord;
  final ValueNotifier<Map<String, dynamic>?>? blockchainDataNotifier;

  const LandledgerScreen({
    Key? key,
    this.selectedRecord,
    this.blockchainDataNotifier,
  }) : super(key: key);

  @override
  State<LandledgerScreen> createState() => _LandledgerScreenState();
}

class _LandledgerScreenState extends State<LandledgerScreen> {
  // Data
  List<Map<String, dynamic>> _allProperties = [];
  List<Map<String, dynamic>> blockchainBlocks = [];

  // Loading / error
  bool _isLoading = true;
  String _errorMessage = '';
  bool _blocksLoading = true;
  String _blocksError = '';

  // Current (selected) record
  Map<String, dynamic>? _currentRecord;

  // ===========================
  // Lifecycle
  // ===========================
  @override
  void initState() {
    super.initState();
    _currentRecord = widget.selectedRecord ?? widget.blockchainDataNotifier?.value;
    _loadInitialData();
    _hydrateCurrentRecord(); // ⟵ NEW: refresh from /api/landledger/:id if we only have a local/partial record
    widget.blockchainDataNotifier?.addListener(_updateCurrentRecord);
  }

  @override
  void dispose() {
    widget.blockchainDataNotifier?.removeListener(_updateCurrentRecord);
    super.dispose();
  }

  void _updateCurrentRecord() {
    if (!mounted) return;
    setState(() {
      _currentRecord = widget.blockchainDataNotifier?.value;
    });
    _hydrateCurrentRecord(); // ⟵ NEW: also hydrate when notifier pushes a new record
  }

  // ===========================
  // Networking
  // ===========================
  Future<void> _loadInitialData() async {
    await Future.wait([
      _fetchAllProperties(),
      _fetchBlockchainBlocks(),
    ]);
  }

  /// NEW: derive an ID we can query with /api/landledger/:id
  String? _deriveParcelId(Map<String, dynamic> m) {
    return m['blockchainId'] ??
           m['parcelId'] ??
           m['id'] ??
           m['title_number'] ??
           m['titleNumber'];
  }

  /// NEW: fetch one record by id from /api/landledger/:id
  Future<Map<String, dynamic>?> _fetchParcelById(String id) async {
    try {
      final resp = await http
          .get(Uri.parse('$apiBase/api/landledger/$id'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } else if (resp.statusCode == 404) {
        // Not on-chain yet; keep local record silently.
        return null;
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } on TimeoutException {
      return null; // Keep local record on timeout
    } catch (_) {
      return null; // Keep local record on any error
    }
  }

  /// NEW: if we have a local/partial record, refresh it from the blockchain API
  Future<void> _hydrateCurrentRecord() async {
    final rec = _currentRecord;
    if (rec == null) return;

    final id = _deriveParcelId(rec);
    if (id == null || id.toString().isEmpty) return;

    final onChain = await _fetchParcelById(id.toString());
    if (onChain != null && mounted) {
      setState(() => _currentRecord = onChain);
    }
  }

  /// Fetch all parcels from the API (correct route: /api/landledger)
  Future<void> _fetchAllProperties() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = '';
        });
      }

      final response = await http
          .get(Uri.parse('$apiBase/api/landledger'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> arr = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _allProperties = arr.cast<Map<String, dynamic>>();
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Failed with status: ${response.statusCode}');
      }
    } on TimeoutException {
      _setErrorState('Request timed out');
    } catch (e) {
      _setErrorState('Network error: $e');
    }
  }

  /// Optional "blocks" carousel — tolerate 404 until backend route exists
  Future<void> _fetchBlockchainBlocks() async {
    try {
      if (mounted) {
        setState(() {
          _blocksLoading = true;
          _blocksError = '';
        });
      }

      final response = await http
          .get(Uri.parse('$apiBase/api/landledger/blocks'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> blocks = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            blockchainBlocks = blocks.cast<Map<String, dynamic>>();
            _blocksLoading = false;
          });
        }
      } else if (response.statusCode == 404) {
        if (mounted) {
          setState(() {
            blockchainBlocks = [];
            _blocksLoading = false;
          });
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      _setBlockErrorState('Request timed out');
    } catch (_) {
      if (mounted) {
        setState(() {
          blockchainBlocks = [];
          _blocksLoading = false;
        });
      }
    }
  }

  void _setErrorState(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
    _showErrorSnackbar(message);
  }

  void _setBlockErrorState(String message) {
    if (!mounted) return;
    setState(() {
      _blocksError = message;
      _blocksLoading = false;
    });
    _showErrorSnackbar(message);
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ===========================
  // Coordinate parsing helpers
  // ===========================
  gmap.LatLng _g(LatLng p) => gmap.LatLng(p.latitude, p.longitude);
  List<gmap.LatLng> _gList(List<LatLng> pts) => pts.map(_g).toList();

  gmap.LatLngBounds? _boundsFrom(List<LatLng> pts) {
    if (pts.isEmpty) return null;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return gmap.LatLngBounds(
      southwest: gmap.LatLng(minLat, minLng),
      northeast: gmap.LatLng(maxLat, maxLng),
    );
  }

  LatLng _centerOf(List<LatLng> pts) {
    if (pts.isEmpty) return const LatLng(0, 0);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  /// Accepts several shapes and returns a simple polygon List<LatLng>:
  /// - {lat,lng} single point
  /// - [{lat,lng}, ...] flat list
  /// - [[[lng,lat], ...]] GeoJSON Polygon (first ring)
  /// - [[{lat,lng}, ...]] nested rings with objects
  List<LatLng> parseCoordinates(dynamic coords) {
    final out = <LatLng>[];
    if (coords == null) return out;

    // Case 1: single {lat,lng}
    if (coords is Map) {
      final lat = coords['lat'] ?? coords['latitude'];
      final lng = coords['lng'] ?? coords['longitude'];
      if (lat is num && lng is num) {
        out.add(LatLng(lat.toDouble(), lng.toDouble()));
      }
      return out;
    }

    if (coords is List && coords.isNotEmpty) {
      // Case 2: flat list of {lat,lng}
      if (coords.first is Map) {
        for (final c in coords) {
          if (c is Map) {
            final lat = c['lat'] ?? c['latitude'];
            final lng = c['lng'] ?? c['longitude'];
            if (lat is num && lng is num) {
              out.add(LatLng(lat.toDouble(), lng.toDouble()));
            }
          }
        }
        return out;
      }

      // Case 3: nested (rings)
      if (coords.first is List) {
        final firstRing = coords.first as List;
        if (firstRing.isNotEmpty) {
          final firstElem = firstRing.first;

          // Numbers: [lng, lat]
          if (firstElem is List && firstElem.length >= 2) {
            for (final pair in firstRing) {
              if (pair is List && pair.length >= 2) {
                final lng = pair[0];
                final lat = pair[1];
                if (lat is num && lng is num) {
                  out.add(LatLng(lat.toDouble(), lng.toDouble()));
                }
              }
            }
            return out;
          }

          // Objects: [{lat,lng}, ...]
          if (firstElem is Map) {
            for (final obj in firstRing) {
              if (obj is Map) {
                final lat = obj['lat'] ?? obj['latitude'];
                final lng = obj['lng'] ?? obj['longitude'];
                if (lat is num && lng is num) {
                  out.add(LatLng(lat.toDouble(), lng.toDouble()));
                }
              }
            }
            return out;
          }
        }
      }
    }

    return out;
  }

  void _showMapPreview(List<LatLng> coordinates) {
    if (coordinates.isEmpty) {
      _showErrorSnackbar('No location data available');
      return;
    }

    final center = _centerOf(coordinates);
    final initPos = gmap.CameraPosition(
      target: _g(center),
      zoom: 14, // will refit to bounds on map created
    );
    final bounds = _boundsFrom(coordinates);

    showDialog(
      context: context,
      builder: (context) {
        gmap.GoogleMapController? ctrl;

        return AlertDialog(
          title: const Text('Property Location'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: gmap.GoogleMap(
              mapType: gmap.MapType.normal,
              initialCameraPosition: initPos,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              polygons: {
                if (coordinates.length >= 3)
                  gmap.Polygon(
                    polygonId: const gmap.PolygonId('parcel'),
                    points: _gList(coordinates),
                    strokeWidth: 2,
                    strokeColor: Colors.blue,
                    fillColor: Colors.blue.withOpacity(0.30),
                  ),
              },
              onMapCreated: (c) async {
                ctrl = c;
                if (bounds != null) {
                  await Future<void>.delayed(const Duration(milliseconds: 100));
                  await c.animateCamera(gmap.CameraUpdate.newLatLngBounds(bounds, 40));
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ===========================
  // UI Builders
  // ===========================
  Widget _buildPropertyCard(Map<String, dynamic> property) {
    final titleNumber = property['titleNumber'] ??
        property['title_number'] ??
        property['parcelId'] ??
        'Untitled Property';
    final owner = property['owner'] ?? property['ownerId'] ?? 'Unknown Owner';

    final area = (() {
      final v = property['areaSqKm'] ?? property['area_sqkm'];
      return (v is num) ? v.toStringAsFixed(2) : '0.00';
    })();

    final timestamp = property['createdAt'] ?? property['timestamp'] ?? '';
    final verified = property['verified'] ?? true;
    final description = property['description'] ?? 'No description';

    final coordinates = parseCoordinates(property['coordinates']);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    titleNumber,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text('$area km²'),
                  backgroundColor: const Color.fromARGB(255, 22, 76, 63),
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Basic info
            Text('Owner: $owner'),
            Text('Verified: ${verified ? "✅ Yes" : "🟡 Pending"}'),
            const SizedBox(height: 4),

            // Description
            Text(
              'Description: $description',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // Timestamp
            if (timestamp.toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Registered: ${DateTime.tryParse(timestamp)?.toLocal().toString().split(' ').first ?? timestamp}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),

            // Map preview button
            if (coordinates.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _showMapPreview(coordinates),
                  child: const Text('View on Map'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildErrorWidget(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInitialData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================
  // Build
  // ===========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? _buildLoadingIndicator()
          : _errorMessage.isNotEmpty
              ? _buildErrorWidget(_errorMessage)
              : RefreshIndicator(
                  onRefresh: _loadInitialData,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'LandLedger Africa - ${_allProperties.length} properties registered',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),

                      // Current selected record (if any)
                      if (_currentRecord != null)
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Current Record',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              const SizedBox(height: 8),
                              Text('🆔 ID: ${_currentRecord!["id"] ?? _currentRecord!["parcelId"] ?? "N/A"}'),
                              Text('👤 Owner: ${_currentRecord!["owner"] ?? _currentRecord!["ownerId"] ?? "N/A"}'),
                              Text('🕓 Timestamp: ${_currentRecord!["timestamp"] ?? _currentRecord!["createdAt"] ?? "N/A"}'),
                              Text('✅ Verified: ${_currentRecord!["verified"] ?? "Yes"}'),
                              const SizedBox(height: 8),
                              Text('📄 Description:\n${_currentRecord!["description"] ?? "N/A"}'),
                            ],
                          ),
                        ),

                      const Divider(),

                      // Verified Updates carousel (optional)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Verified Updates', style: Theme.of(context).textTheme.titleLarge),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 200,
                        child: _blocksLoading
                            ? _buildLoadingIndicator()
                            : _blocksError.isNotEmpty
                                ? _buildErrorWidget(_blocksError)
                                : blockchainBlocks.isEmpty
                                    ? const Center(child: Text('No verified updates yet.'))
                                    : ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: blockchainBlocks.length,
                                        itemBuilder: (context, index) {
                                          final block = blockchainBlocks[index];
                                          return Card(
                                            margin: const EdgeInsets.only(left: 16, right: 8),
                                            elevation: 4,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Container(
                                              width: 200,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(12),
                                                gradient: LinearGradient(
                                                  colors: [
                                                    const Color.fromARGB(255, 22, 76, 63),
                                                    Colors.green.shade100
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    block['parcelId'] ?? 'Parcel #N/A',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    block['description'] ?? 'No description',
                                                    maxLines: 3,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(color: Colors.white),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    block['createdAt'] ?? '',
                                                    style: TextStyle(
                                                      color: Colors.white.withOpacity(0.9),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                      ),
                      const SizedBox(height: 12),

                      // Properties list
                      ..._allProperties.map(_buildPropertyCard).toList(),
                    ],
                  ),
                ),
    );
  }
}
