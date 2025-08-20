// lib/landledger_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

/// Cross-platform API base:
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
  List<Map<String, dynamic>> _blocks = [];

  // Loading / error
  bool _isLoading = true;
  String _errorMessage = '';

  // Current (selected) record
  Map<String, dynamic>? _currentRecord;

  // ===========================
  // Lifecycle
  // ===========================
  @override
  void initState() {
    super.initState();
    _currentRecord = widget.selectedRecord ?? widget.blockchainDataNotifier?.value;
    _loadBlocks();
    _hydrateCurrentRecord();
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
    _hydrateCurrentRecord();
  }

  // ===========================
  // Networking
  // ===========================
  Future<void> _loadBlocks() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = '';
        });
      }

      // Canonical route for "all parcels"
      final response = await http
          .get(Uri.parse('$apiBase/api/landledger'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> arr = jsonDecode(response.body);
        final list = arr.cast<Map<String, dynamic>>();
        if (mounted) {
          setState(() {
            _blocks = list;
            _isLoading = false;
          });
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      _setError('Request timed out');
    } catch (e) {
      _setError('Network error: $e');
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
    _snack(message, isError: true);
  }

  Future<Map<String, dynamic>?> _fetchParcelById(String id) async {
    try {
      final resp = await http
          .get(Uri.parse('$apiBase/api/landledger/$id'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _deriveParcelId(Map<String, dynamic> m) {
    return m['parcelId'] ??
        m['id'] ??
        m['titleNumber'] ??
        m['title_number'] ??
        m['blockchainId'];
  }

  Future<void> _hydrateCurrentRecord() async {
    final rec = _currentRecord;
    if (rec == null) return;
    final id = _deriveParcelId(rec);
    if (id == null || id.isEmpty) return;
    final fresh = await _fetchParcelById(id);
    if (fresh != null && mounted) {
      setState(() => _currentRecord = fresh);
    }
  }

  // ===========================
  // Helpers (area, coords, UI)
  // ===========================
  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.black87,
      duration: const Duration(seconds: 3),
    ));
  }

  /// Format area nicely: use km² for >= 0.01, else m² for tiny parcels.
  String formatAreaLabel(double? areaKm2) {
    if (areaKm2 == null) return '—';
    if (areaKm2 >= 0.01) {
      return '${areaKm2.toStringAsFixed(2)} km²';
    }
    final m2 = areaKm2 * 1e6;
    String m2Str;
    if (m2 >= 100) {
      m2Str = m2.toStringAsFixed(0);
    } else if (m2 >= 1) {
      m2Str = m2.toStringAsFixed(1);
    } else {
      m2Str = m2.toStringAsFixed(3);
    }
    return '$m2Str m²';
  }

  /// Parse coordinates input into a flat polygon list of LatLng.
  List<LatLng> parseCoordinates(dynamic coords) {
    final out = <LatLng>[];
    if (coords == null) return out;

    if (coords is Map) {
      final lat = coords['lat'] ?? coords['latitude'];
      final lng = coords['lng'] ?? coords['longitude'];
      if (lat is num && lng is num) {
        out.add(LatLng(lat.toDouble(), lng.toDouble()));
      }
      return out;
    }

    if (coords is List && coords.isNotEmpty) {
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

      if (coords.first is List) {
        final firstRing = coords.first as List;
        if (firstRing.isNotEmpty) {
          final firstElem = firstRing.first;
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

  /// Approx area of polygon in km² using equirectangular projection (good for small parcels)
  double? computeAreaKm2(List<LatLng> pts) {
    if (pts.length < 3) return null;

    // Project to meters
    const R = 6371000.0; // Earth radius (m)
    final lat0 = pts.first.latitude * math.pi / 180.0;
    final cos0 = math.cos(lat0);

    double areaMeters2 = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];

      final ax = a.longitude * math.pi / 180.0;
      final ay = a.latitude * math.pi / 180.0;
      final bx = b.longitude * math.pi / 180.0;
      final by = b.latitude * math.pi / 180.0;

      final x1 = R * ax * cos0;
      final y1 = R * ay;
      final x2 = R * bx * cos0;
      final y2 = R * by;

      areaMeters2 += (x1 * y2 - x2 * y1);
    }
    areaMeters2 = areaMeters2.abs() * 0.5;
    return areaMeters2 / 1e6; // m² -> km²
  }

  gmap.LatLng _g(LatLng p) => gmap.LatLng(p.latitude, p.longitude);
  List<gmap.LatLng> _gList(List<LatLng> pts) => pts.map(_g).toList();

  gmap.LatLngBounds? _boundsFrom(List<LatLng> pts) {
    if (pts.isEmpty) return null;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
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

  // ===========================
  // Map preview (with satellite toggle)
  // ===========================
  void _showMapPreview(List<LatLng> coordinates) {
    if (coordinates.isEmpty) {
      _snack('No location data available', isError: true);
      return;
    }

    final center = _centerOf(coordinates);
    final initPos = gmap.CameraPosition(target: _g(center), zoom: 16);
    final bounds = _boundsFrom(coordinates);

    showDialog(
      context: context,
      builder: (context) {
        bool satellite = true;
        gmap.GoogleMapController? ctrl;

        return StatefulBuilder(
          builder: (context, setDlg) {
            return AlertDialog(
              title: Row(
                children: [
                  const Text('Property Location'),
                  const Spacer(),
                  IconButton(
                    tooltip: satellite ? 'Switch to Map' : 'Switch to Satellite',
                    icon: Icon(satellite ? Icons.satellite_alt : Icons.map),
                    onPressed: () => setDlg(() => satellite = !satellite),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 320,
                child: gmap.GoogleMap(
                  mapType: satellite ? gmap.MapType.hybrid : gmap.MapType.normal,
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
                      await Future<void>.delayed(const Duration(milliseconds: 120));
                      await c.animateCamera(gmap.CameraUpdate.newLatLngBounds(bounds, 40));
                    }
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================
  // Details sheet (endpoints)
  // ===========================
  Future<void> _openDetails(Map<String, dynamic> m) async {
    final id = _deriveParcelId(m);
    final owner = (m['owner'] ?? m['ownerId'])?.toString();
    final title = (m['titleNumber'] ?? m['title_number'])?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1F1F1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DefaultTabController(
          length: 5,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    id ?? 'Parcel',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Parcel'),
                      Tab(text: 'Owner'),
                      Tab(text: 'Title'),
                      Tab(text: 'History'),
                      Tab(text: 'Actions'),
                    ],
                  ),
                  SizedBox(
                    height: math.min(MediaQuery.of(ctx).size.height * 0.7, 520),
                    child: TabBarView(
                      children: [
                        _EndpointViewer(path: id != null ? '/api/landledger/$id' : null),
                        _EndpointViewer(path: owner != null ? '/api/landledger/owner/$owner' : null),
                        _EndpointViewer(path: title != null ? '/api/landledger/title/$title' : null),
                        _EndpointViewer(path: id != null ? '/api/landledger/$id/history' : null),
                        _ActionsPane(parcel: m),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================
  // Card / List UI
  // ===========================
  double? _resolveAreaKm2(Map<String, dynamic> m) {
    final raw = m['areaSqKm'] ?? m['area_sqkm'];
    if (raw is num) return raw.toDouble();

    // If not stored, compute from coordinates
    final coords = parseCoordinates(m['coordinates']);
    return computeAreaKm2(coords);
  }

  Widget _buildLedgerCard(Map<String, dynamic> m) {
    final id = _deriveParcelId(m);
    final title = (m['titleNumber'] ?? m['title_number'] ?? id ?? 'Untitled').toString();
    final owner = (m['owner'] ?? m['ownerId'] ?? 'N/A').toString();
    final verified = (m['verified'] ?? true) == true;
    final created = (m['createdAt'] ?? m['timestamp'] ?? '').toString();
    final desc = (m['description'] ?? '').toString();
    final coords = parseCoordinates(m['coordinates']);
    final areaKm2 = _resolveAreaKm2(m);
    final areaLabel = formatAreaLabel(areaKm2);

    return Card(
      color: const Color(0xFF1F1F1F),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetails(m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // top row: ID chip + area chip
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF165B4A),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'LLB-${id ?? 'N/A'}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (areaLabel != '—')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF164C3F),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        areaLabel,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),

              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _meta('Owner', owner),
                  _meta('Verified', verified ? 'Yes' : 'Pending', icon: Icons.verified_rounded,
                      iconColor: verified ? Colors.green : Colors.amber),
                ],
              ),
              const SizedBox(height: 6),

              if (created.isNotEmpty)
                Text('Created: $created', style: TextStyle(color: Colors.white70)),

              if (desc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
              ],

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _showMapPreview(coords),
                  child: const Text('View on Map'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(String label, String value, {IconData? icon, Color? iconColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: iconColor ?? Colors.white70),
          const SizedBox(width: 4),
        ],
        Text('$label: ', style: const TextStyle(color: Colors.white70)),
        Text(value, style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  Widget _loading() => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
  Widget _error(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(msg, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadBlocks, child: const Text('Retry')),
            ],
          ),
        ),
      );

  // ===========================
  // Build
  // ===========================
  @override
  Widget build(BuildContext context) {
    final title = 'LandLedger Blocks — ${_blocks.length}';

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? _loading()
          : _errorMessage.isNotEmpty
              ? _error(_errorMessage)
              : RefreshIndicator(
                  onRefresh: _loadBlocks,
                  child: ListView(
                    padding: const EdgeInsets.only(top: 10, bottom: 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(title,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      if (_currentRecord != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: _buildLedgerCard(_currentRecord!),
                        ),
                      ..._blocks.map(_buildLedgerCard),
                    ],
                  ),
                ),
    );
  }
}

/// =======================================
/// Simple JSON viewer for GET endpoints
/// =======================================
class _EndpointViewer extends StatefulWidget {
  final String? path; // e.g. /api/landledger/:id

  const _EndpointViewer({required this.path});

  @override
  State<_EndpointViewer> createState() => _EndpointViewerState();
}

class _EndpointViewerState extends State<_EndpointViewer> {
  bool _loading = false;
  String? _error;
  dynamic _json;

  @override
  void initState() {
    super.initState();
    if (widget.path != null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _json = null;
    });
    try {
      final resp = await http.get(Uri.parse('$apiBase${widget.path}')).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        setState(() => _json = jsonDecode(resp.body));
      } else {
        setState(() => _error = 'HTTP ${resp.statusCode}');
      }
    } on TimeoutException {
      setState(() => _error = 'Request timed out');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.path == null) {
      return const Center(child: Text('N/A', style: TextStyle(color: Colors.white70)));
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Text(
        const JsonEncoder.withIndent('  ').convert(_json),
        style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
      ),
    );
  }
}

/// =======================================
/// Actions tab: Transfer / Update description / Update geometry
/// =======================================
class _ActionsPane extends StatefulWidget {
  final Map<String, dynamic> parcel;
  const _ActionsPane({required this.parcel});

  @override
  State<_ActionsPane> createState() => _ActionsPaneState();
}

class _ActionsPaneState extends State<_ActionsPane> {
  bool _busy = false;
  String _status = '';
  final _descCtl = TextEditingController();
  final _ownerCtl = TextEditingController();
  final _areaCtl = TextEditingController();
  final _coordsCtl = TextEditingController(); // expects JSON array of {lat,lng}

  String? get _id {
    final m = widget.parcel;
    return m['parcelId'] ?? m['id'] ?? m['titleNumber'] ?? m['title_number'];
  }

  @override
  void initState() {
    super.initState();
    _descCtl.text = (widget.parcel['description'] ?? '').toString();
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    setState(() {
      _busy = true;
      _status = 'Working...';
    });
    try {
      final resp = await http
          .post(
            Uri.parse('$apiBase$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      setState(() => _status = 'HTTP ${resp.statusCode}: ${resp.body}');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _patch(String path, Map<String, dynamic> body) async {
    setState(() {
      _busy = true;
      _status = 'Working...';
    });
    try {
      final resp = await http
          .patch(
            Uri.parse('$apiBase$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      setState(() => _status = 'HTTP ${resp.statusCode}: ${resp.body}');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _id;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (id == null)
            const Text('Parcel ID unavailable', style: TextStyle(color: Colors.white70))
          else ...[
            Text('Parcel ID: $id', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),

            // Transfer
            const Text('Transfer Owner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _ownerCtl,
              decoration: const InputDecoration(
                hintText: 'New owner',
                filled: true,
                fillColor: Color(0xFF2A2A2A),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy || _ownerCtl.text.trim().isEmpty
                  ? null
                  : () => _post('/api/landledger/transfer',
                      {'parcelId': id, 'newOwner': _ownerCtl.text.trim()}),
              child: const Text('Transfer'),
            ),
            const SizedBox(height: 18),

            // Update description
            const Text('Update Description', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtl,
              decoration: const InputDecoration(
                hintText: 'Description',
                filled: true,
                fillColor: Color(0xFF2A2A2A),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed:
                  _busy || _descCtl.text.trim().isEmpty ? null : () => _patch('/api/landledger/$id/description', {'description': _descCtl.text.trim()}),
              child: const Text('Save Description'),
            ),
            const SizedBox(height: 18),

            // Update geometry
            const Text('Update Geometry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _coordsCtl,
              decoration: const InputDecoration(
                hintText: 'Coordinates JSON (e.g. [{"lat":..., "lng":...}, ...])',
                filled: true,
                fillColor: Color(0xFF2A2A2A),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _areaCtl,
              decoration: const InputDecoration(
                hintText: 'Area (km², optional)',
                filled: true,
                fillColor: Color(0xFF2A2A2A),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _patch('/api/landledger/$id/geometry', {
                        if (_coordsCtl.text.trim().isNotEmpty)
                          'coordinates': jsonDecode(_coordsCtl.text.trim()),
                        if (_areaCtl.text.trim().isNotEmpty)
                          'areaSqKm': double.tryParse(_areaCtl.text.trim()),
                      }),
              child: const Text('Save Geometry'),
            ),
          ],
          const SizedBox(height: 12),
          if (_status.isNotEmpty)
            Text(_status,
                style: TextStyle(
                    color: _status.startsWith('HTTP 200') ? Colors.greenAccent : Colors.amberAccent)),
        ],
      ),
    );
  }
}
