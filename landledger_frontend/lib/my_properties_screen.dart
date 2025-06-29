import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:intl/intl.dart';
import 'map_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dashboard_screen.dart';

class MyPropertiesScreen extends StatefulWidget {
  final String regionId;
  final String? geojsonPath;
  final List<LatLng>? highlightPolygon;
  final VoidCallback? onBackToHome;
  final void Function(String regionId, String geojsonPath)? onRegionSelected;
  final bool showBackArrow;
  final void Function(Map<String, dynamic> blockchainData)? onBlockchainRecordSelected;

  

  const MyPropertiesScreen({
    Key? key,
    required this.regionId,
    this.geojsonPath,
    this.highlightPolygon,
    this.onBackToHome,
    this.onRegionSelected,
    this.showBackArrow = false,
    this.onBlockchainRecordSelected,
  }) : super(key: key);

  @override
  State<MyPropertiesScreen> createState() => _MyPropertiesScreenState();
}

class _MyPropertiesScreenState extends State<MyPropertiesScreen> {
  final List<Map<String, dynamic>> _userProperties = [];
  final List<List<LatLng>> _polygonPointsList = [];
  final List<String> _documentIds = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final ScrollController _scrollController = ScrollController();
  final User? _user = FirebaseAuth.instance.currentUser;
  Timer? _debounce;
  List<LatLng>? _selectedPolygon;
  bool _showPolygonInfo = false;
  DocumentSnapshot? _selectedPolygonDoc;
  final Map<int, bool> _satelliteViewMap = {};
  final Map<int, double> _zoomLevelMap = {};
  final Map<int, LatLng?> _centerMap = {};
  final Map<int, MapController> _mapControllers = {};
  String _searchQuery = '';
  Timer? _searchDebounce;

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
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>?> fetchPolygonFromBlockchain(String titleNumber) async {
    final url = Uri.parse('http://10.0.2.2:4000/api/landledger/$titleNumber');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        debugPrint('❌ Failed to fetch from blockchain: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Blockchain fetch error: $e');
      return null;
    }
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

  List<Map<String, dynamic>> get _filteredProperties {
    if (_searchQuery.isEmpty) return _userProperties;
    return _userProperties.where((prop) {
      return (prop['title_number']?.toString().toLowerCase().contains(_searchQuery) ?? false) ||
          (prop['description']?.toString().toLowerCase().contains(_searchQuery) ?? false) ||
          (prop['wallet_address']?.toString().toLowerCase().contains(_searchQuery) ?? false);
    }).toList();
  }

  Future<void> _fetchProperties() async {
    if (_user == null || _isLoading || !_hasMore) return;
    
    setState(() => _isLoading = true);

    try {
      var query = FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('regions')
          .where('region', isEqualTo: widget.regionId)
          .orderBy('timestamp', descending: true)
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
          
          // Initialize view settings for each property
          final index = _userProperties.length + props.length - 1;
          _mapControllers[index] = MapController();
          _satelliteViewMap[index] = false;
          _zoomLevelMap[index] = 15.0;
          _centerMap[index] = null;
        }

        setState(() {
          _userProperties.addAll(props);
          _polygonPointsList.addAll(polys);
          _documentIds.addAll(ids);
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

  void _handlePolygonTap(int index) {
    setState(() {
      _selectedPolygon = _polygonPointsList[index];
      _selectedPolygonDoc = _userProperties[index] as DocumentSnapshot?;
      _showPolygonInfo = true;
    });
  }

  void _handleMapTap(int index, LatLng point) {
    setState(() {
      if (_centerMap[index] == null) {
        _centerMap[index] = point;
        _zoomLevelMap[index] = 18.0;
      } else {
        _centerMap[index] = null;
        _zoomLevelMap[index] = 15.0;
      }
    });
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
        _satelliteViewMap.remove(index);
        _zoomLevelMap.remove(index);
        _centerMap.remove(index);
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

Widget _buildPropertyCard(int index) {
    final prop = _userProperties[index];
    final poly = _polygonPointsList[index];
    final isSelected = _selectedPolygon == poly;
    final isSatellite = _satelliteViewMap[index] ?? false;
    final zoomLevel = _zoomLevelMap[index] ?? 15.0;
    final center = _centerMap[index] ?? LatLngBounds.fromPoints(poly).center;
    final titleNumber = prop['title_number'] ?? 'Untitled Property';

    return GestureDetector(
      onTap: () => _handlePolygonTap(index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                children: [
                  SizedBox(
                    height: 180,
                    child: GestureDetector(
                      onTap: () => _handleMapTap(index, center),
                      child: FlutterMap(
                        mapController: _mapControllers[index],
                        options: MapOptions(
                          center: center,
                          zoom: zoomLevel,
                          interactiveFlags: InteractiveFlag.none,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: "https://api.mapbox.com/styles/v1/{id}/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}",
                            additionalOptions: {
                              'accessToken': 'pk.eyJ1IjoibW9yZ25jb2x0IiwiYSI6ImNtYng2eHI0ZjB3cjQybW9zNXZhaDJqanYifQ.0qZEU6MBjiTZiUDPs6JyoQ',
                              'id': isSatellite 
                                  ? 'mapbox/satellite-streets-v12' 
                                  : 'mapbox/outdoors-v12',
                            },
                            tileProvider: CancellableNetworkTileProvider(),
                          ),
                          if (isSelected)
                            ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                Colors.black.withOpacity(0.5),
                                BlendMode.darken,
                              ),
                              child: TileLayer(
                                urlTemplate: "https://api.mapbox.com/styles/v1/{id}/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}",
                                additionalOptions: {
                                  'accessToken': 'pk.eyJ1IjoibW9yZ25jb2x0IiwiYSI6ImNtYng2eHI0ZjB3cjQybW9zNXZhaDJqanYifQ.0qZEU6MBjiTZiUDPs6JyoQ',
                                  'id': isSatellite 
                                      ? 'mapbox/satellite-streets-v12' 
                                      : 'mapbox/outdoors-v12',
                                },
                              ),
                            ),
                          PolygonLayer(
                            polygons: [
                              Polygon(
                                points: poly,
                                color: isSelected
                                    ? Colors.white.withOpacity(0.7)
                                    : Colors.blue.withOpacity(0.3),
                                borderColor: isSelected ? Colors.white : Colors.blue,
                                borderStrokeWidth: isSelected ? 3 : 2,
                                isFilled: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: FloatingActionButton(
                      mini: true,
                      heroTag: 'fullscreen_$index',
                      child: const Icon(Icons.fullscreen),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapScreen(
                              regionId: widget.regionId,
                              geojsonPath: widget.geojsonPath,
                              highlightPolygon: _polygonPointsList[index],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'view_blockchain',
                          child: const Text('View on Blockchain'),
                        ),
                        PopupMenuItem(
                          value: 'land_deed',
                          child: const Text('View Land Deed'),
                        ),
                        PopupMenuItem(
                          value: 'toggle_view',
                          child: Text(isSatellite ? 'Normal View' : 'Satellite View'),
                        ),
                        const PopupMenuItem(
                          value: 'zoom_in',
                          child: Text('Zoom In'),
                        ),
                        const PopupMenuItem(
                          value: 'zoom_out',
                          child: Text('Zoom Out'),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: const Text('Delete Property', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                     onSelected: (value) async {
                      switch (value) {
                        case 'view_blockchain':
                          final titleNumber = prop['title_number'];
                          final url = Uri.parse('http://10.0.2.2:4000/api/landledger/$titleNumber');

                          try {
                            final response = await http.get(url);
                            if (response.statusCode == 200) {
                              final data = jsonDecode(response.body);

                              if (widget.onBlockchainRecordSelected != null) {
                                widget.onBlockchainRecordSelected!(data);
                              }

                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('❌ Not found: ${response.statusCode}')),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('❌ Error: $e')),
                            );
                          }
                          break;
                      case 'delete':
                        await _deleteProperty(index);
                        break;

                      case 'toggle_view':
                        setState(() {
                          _satelliteViewMap[index] = !(_satelliteViewMap[index] ?? false);
                        });
                        break;

                      case 'zoom_in':
                        setState(() {
                          _zoomLevelMap[index] = (_zoomLevelMap[index] ?? 15.0) + 1;
                          _mapControllers[index]?.move(center, _zoomLevelMap[index]!);
                        });
                        break;

                      case 'zoom_out':
                        setState(() {
                          _zoomLevelMap[index] = (_zoomLevelMap[index] ?? 15.0) - 1;
                          _mapControllers[index]?.move(center, _zoomLevelMap[index]!);
                        });
                        break;
                      }

                    },
                    

                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        prop['title_number'] ?? 'Untitled Property',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Chip(
                        label: Text(
                          '${prop['area_sqkm']?.toStringAsFixed(2) ?? '0.00'} km²',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    prop['description'] ?? 'No description',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          prop['wallet_address'] ?? 'No wallet',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (prop['timestamp'] != null)
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM d, y').format(
                            (prop['timestamp'] as Timestamp).toDate()),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolygonInfoCard() {
    if (_selectedPolygonDoc == null || !_showPolygonInfo) return const SizedBox();

    return Positioned(
      bottom: 16,
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
                      _selectedPolygonDoc!['title_number'] ?? 'Property Details',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _showPolygonInfo = false),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildInfoRow('Description', _selectedPolygonDoc!['description']),
                _buildInfoRow('Wallet', _selectedPolygonDoc!['wallet_address']),
                _buildInfoRow('Area', '${_selectedPolygonDoc!['area_sqkm']?.toStringAsFixed(2) ?? '0.00'} km²'),
                if (_selectedPolygonDoc!['timestamp'] != null)
                  _buildInfoRow(
                    'Created',
                    DateFormat('MMMM d, y').format(
                      (_selectedPolygonDoc!['timestamp'] as Timestamp).toDate()),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.public),
                      label: const Text('View on Blockchain'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Opening blockchain explorer...')),
                        );
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.description),
                      label: const Text('Land Deed'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Showing land deed...')),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value ?? 'Not available'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.showBackArrow 
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                debugPrint('🔙 Back button pressed in MyPropertiesScreen');

                if (widget.onBackToHome != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    widget.onBackToHome!(); // safe tab switch
                  });
                } else {
                  Navigator.pop(context);
                }
              },
            )
          : null,
          
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Search properties...',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (value) {
              if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 500), () {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              });
            },
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_alt),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'newest',
                child: Text('Newest First'),
              ),
              const PopupMenuItem(
                value: 'oldest',
                child: Text('Oldest First'),
              ),
              const PopupMenuItem(
                value: 'largest',
                child: Text('Largest Area'),
              ),
              const PopupMenuItem(
                value: 'smallest',
                child: Text('Smallest Area'),
              ),
            ],
            onSelected: (value) {
              setState(() {
                switch (value) {
                  case 'newest':
                    _userProperties.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
                    break;
                  case 'oldest':
                    _userProperties.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
                    break;
                  case 'largest':
                    _userProperties.sort((a, b) => (b['area_sqkm'] ?? 0).compareTo(a['area_sqkm'] ?? 0));
                    break;
                  case 'smallest':
                    _userProperties.sort((a, b) => (a['area_sqkm'] ?? 0).compareTo(b['area_sqkm'] ?? 0));
                    break;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _userProperties.clear();
                _polygonPointsList.clear();
                _documentIds.clear();
                _hasMore = true;
                _lastDocument = null;
                _selectedPolygon = null;
                _showPolygonInfo = false;
                _satelliteViewMap.clear();
                _zoomLevelMap.clear();
                _centerMap.clear();
                _searchQuery = '';
              });
              _fetchProperties();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_filteredProperties.isEmpty && !_isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.map_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isEmpty ? 'No properties found' : 'No matching properties',
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MapScreen(
                            regionId: widget.regionId,
                            geojsonPath: widget.geojsonPath,
                            startDrawing: true,
                          ),
                        ),
                      );
                    },
                    child: const Text('Create your first property'),
                  ),
                ],
              ),
            )
          else
            RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _userProperties.clear();
                  _polygonPointsList.clear();
                  _documentIds.clear();
                  _hasMore = true;
                  _lastDocument = null;
                  _selectedPolygon = null;
                  _showPolygonInfo = false;
                  _satelliteViewMap.clear();
                  _zoomLevelMap.clear();
                  _centerMap.clear();
                  _searchQuery = '';
                });
                await _fetchProperties();
              },
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: _filteredProperties.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _filteredProperties.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _buildPropertyCard(index);
                },
              ),
            ),
          _buildPolygonInfoCard(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MapScreen(
                regionId: widget.regionId,
                geojsonPath: widget.geojsonPath,
                startDrawing: true,
              ),
            ),
          );
        },
      ),
    );
  }
}