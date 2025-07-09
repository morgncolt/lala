import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

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
  List<Map<String, dynamic>> _allProperties = [];
  List<Map<String, dynamic>> blockchainBlocks = [];
  bool _isLoading = true;
  String _errorMessage = '';
  Map<String, dynamic>? _currentRecord;
  bool _blocksLoading = true;
  String _blocksError = '';

  @override
  void initState() {
    super.initState();
    _currentRecord = widget.selectedRecord ?? widget.blockchainDataNotifier?.value;
    _loadInitialData();
    widget.blockchainDataNotifier?.addListener(_updateCurrentRecord);
  }

  @override
  void dispose() {
    widget.blockchainDataNotifier?.removeListener(_updateCurrentRecord);
    super.dispose();
  }

  void _updateCurrentRecord() {
    if (mounted) {
      setState(() {
        _currentRecord = widget.blockchainDataNotifier?.value;
      });
    }
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _fetchAllProperties(),
      _fetchBlockchainBlocks(),
    ]);
  }

  Future<void> _fetchAllProperties() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = '';
        });
      }

      final response = await http.get(
        Uri.parse('http://10.0.2.2:4000/api/landledger/blocks'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> properties = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _allProperties = properties.cast<Map<String, dynamic>>();
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Failed with status: ${response.statusCode}');
      }
    } on TimeoutException {
      _setErrorState('Request timed out');
    } catch (e) {
      _setErrorState('Network error: ${e.toString()}');
    }
  }

  Future<void> _fetchBlockchainBlocks() async {
    try {
      if (mounted) {
        setState(() {
          _blocksLoading = true;
          _blocksError = '';
        });
      }

      final response = await http.get(
        Uri.parse('http://10.0.2.2:4000/api/landledger/blocks'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> blocks = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            blockchainBlocks = blocks.cast<Map<String, dynamic>>();
            _blocksLoading = false;
          });
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      _setBlockErrorState('Request timed out');
    } catch (e) {
      _setBlockErrorState('Error: ${e.toString()}');
    }
  }

  void _setErrorState(String message) {
    if (mounted) {
      setState(() {
        _errorMessage = message;
        _isLoading = false;
      });
      _showErrorSnackbar(message);
    }
  }

  void _setBlockErrorState(String message) {
    if (mounted) {
      setState(() {
        _blocksError = message;
        _blocksLoading = false;
      });
      _showErrorSnackbar(message);
    }
  }

  void _showErrorSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showMapPreview(List<LatLng> coordinates) {
    if (coordinates.isEmpty) {
      _showErrorSnackbar('No location data available');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Property Location'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: FlutterMap(
            options: MapOptions(
              center: LatLngBounds.fromPoints(coordinates).center,
              zoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}",
                additionalOptions: {
                  'accessToken': 'pk.eyJ1IjoibW9yZ25jb2x0IiwiYSI6ImNtYng2eHI0ZjB3cjQybW9zNXZhaDJqanYifQ.0qZEU6MBjiTZiUDPs6JyoQ',
                  'id': 'mapbox/outdoors-v12',
                },
              ),
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: coordinates,
                    color: Colors.blue.withOpacity(0.3),
                    borderColor: Colors.blue,
                    borderStrokeWidth: 2,
                    isFilled: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyCard(Map<String, dynamic> property) {
    final titleNumber = property['title_number'] ?? property['parcelId'] ?? 'Untitled Property';
    final owner = property['owner'] ?? property['ownerId'] ?? 'Unknown Owner';
    final area = (property['area_sqkm'] is num) ? (property['area_sqkm'] as num).toStringAsFixed(2) : '0.00';
    final timestamp = property['timestamp'] ?? property['createdAt'] ?? '';
    final verified = property['verified'] ?? true;
    final description = property['description'] ?? 'No description';
    final coordinates = property['coordinates'] is List
        ? (property['coordinates'] as List)
            .where((c) => c is Map && c.containsKey('lat') && c.containsKey('lng'))
            .map((c) => LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble()))
            .toList()
        : <LatLng>[];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Owner: $owner'),
            Text('Verified: ${verified ? "✅ Yes" : "🟡 Pending"}'),
            const SizedBox(height: 4),
            Text(
              'Description: $description',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (timestamp.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Registered: ${DateTime.tryParse(timestamp)?.toLocal().toString().split(' ')[0] ?? timestamp}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // Removes default back button
        title: const Text('LandLedger'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialData,
            tooltip: 'Refresh data',
          ),
        ],
      ),

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
                              const Text('Current Record', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            child: Container(
                                              width: 180,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(12),
                                                gradient: LinearGradient(
                                                  colors: [const Color.fromARGB(255, 22, 76, 63), Colors.green.shade100],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    block['parcelId'] ?? 'Parcel #N/A',
                                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    block['description'] ?? 'No description',
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    block['createdAt'] ?? '',
                                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                      ),
                      const SizedBox(height: 12),
                      ..._allProperties.map(_buildPropertyCard).toList(),
                    ],
                  ),
                ),
    );
  }
}
