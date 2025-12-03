import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart' show LatLng;

// Import the BlockData class from landledger_screen.dart
// You may need to adjust this import based on your project structure
import '../landledger_screen.dart' show BlockData;

class EnhancedRegionsView extends StatefulWidget {
  final List<BlockData> blocks;
  
  const EnhancedRegionsView({
    super.key,
    required this.blocks,
  });

  @override
  State<EnhancedRegionsView> createState() => _EnhancedRegionsViewState();
}

class _EnhancedRegionsViewState extends State<EnhancedRegionsView> {
  String _selectedRegion = 'all';
  bool _showSatelliteView = false;
  final String _sortBy = 'count'; // count, value, area

  @override
  Widget build(BuildContext context) {
    // Group blocks by country/region for geographical visualization
    final regionData = _groupBlocksByRegion(widget.blocks);
    final filteredData = _selectedRegion == 'all' 
        ? regionData 
        : {_selectedRegion: regionData[_selectedRegion] ?? {}};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enhanced Header with Controls
          _buildEnhancedHeader(regionData),

          const SizedBox(height: 20),

          // Global Statistics Dashboard
          _buildGlobalStatsDashboard(regionData),

          const SizedBox(height: 24),

          // Interactive World Map with Property Markers
          _buildEnhancedWorldMap(regionData),

          const SizedBox(height: 24),

          // Regional Analytics Cards
          _buildRegionalAnalytics(regionData),

          const SizedBox(height: 24),

          // Transaction Value Analysis
          _buildTransactionValueAnalysis(regionData),

          const SizedBox(height: 24),

          // Detailed Region List with Enhanced Stats
          _buildEnhancedRegionList(regionData),
        ],
      ),
    );
  }

  Map<String, Map<String, dynamic>> _groupBlocksByRegion(List<BlockData> blocks) {
    final regionGroups = <String, Map<String, dynamic>>{};

    for (final block in blocks) {
      for (final regionCode in block.regionCodes) {
        if (regionGroups.containsKey(regionCode)) {
          final existing = regionGroups[regionCode]!;
          existing['count'] = (existing['count'] as int) + 1;
          existing['blocks'].add(block);
          
          // Calculate additional statistics
          final blockValue = _extractPropertyValue(block.rawData);
          final blockArea = _extractPropertyArea(block.rawData);
          
          existing['totalValue'] = (existing['totalValue'] as double) + blockValue;
          existing['totalArea'] = (existing['totalArea'] as double) + blockArea;
          existing['lastActivity'] = _getLatestTimestamp(existing['lastActivity'], block.timestamp);
          
        } else {
          final blockValue = _extractPropertyValue(block.rawData);
          final blockArea = _extractPropertyArea(block.rawData);
          
          regionGroups[regionCode] = {
            'count': 1,
            'blocks': [block],
            'countryName': _getCountryName(regionCode),
            'totalValue': blockValue,
            'totalArea': blockArea,
            'averageValue': blockValue,
            'averageArea': blockArea,
            'lastActivity': block.timestamp,
            'coordinates': _extractRegionCoordinates(block.rawData),
          };
        }
      }
    }

    // Calculate averages and additional metrics
    for (final entry in regionGroups.entries) {
      final data = entry.value;
      final count = data['count'] as int;
      data['averageValue'] = (data['totalValue'] as double) / count;
      data['averageArea'] = (data['totalArea'] as double) / count;
      data['activityLevel'] = _calculateActivityLevel(count, data['lastActivity'] as DateTime);
    }

    return regionGroups;
  }

  String _getCountryName(String regionCode) {
    const countryNames = {
      'NG': 'Nigeria',
      'KE': 'Kenya',
      'GH': 'Ghana',
      'CM': 'Cameroon',
      'ZA': 'South Africa',
      'ET': 'Ethiopia',
      'RW': 'Rwanda',
      'UG': 'Uganda',
      'US': 'United States',
      'BR': 'Brazil',
      'MX': 'Mexico',
      'CA': 'Canada',
      'GB': 'United Kingdom',
      'FR': 'France',
      'DE': 'Germany',
      'IN': 'India',
      'CN': 'China',
      'JP': 'Japan',
      'AU': 'Australia',
    };
    return countryNames[regionCode] ?? regionCode;
  }

  // Enhanced header with filtering and view controls
  Widget _buildEnhancedHeader(Map<String, Map<String, dynamic>> regionData) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.public, color: Color(0xFF6366F1), size: 24),
              const SizedBox(width: 8),
              // Let the title shrink/ellipsize
              const Expanded(
                child: Text(
                  'LandLedger Network',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Let the pill shrink instead of forcing overflow
              Flexible(
                fit: FlexFit.loose,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Color(0xFF6366F1).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _propLabel(context),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Region Filter
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRegion,
                      dropdownColor: const Color(0xFF1A1A1A),
                      style: const TextStyle(color: Colors.white),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('🌍 All Regions')),
                        ...regionData.entries.map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text('${_flagEmojiFromISO2(e.key)} ${e.value['countryName']}'),
                        )),
                      ],
                      onChanged: (value) => setState(() => _selectedRegion = value ?? 'all'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Map View Toggle
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.map,
                        color: !_showSatelliteView ? const Color(0xFF6366F1) : Colors.white54,
                      ),
                      onPressed: () => setState(() => _showSatelliteView = false),
                      tooltip: 'Map View',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.satellite_alt,
                        color: _showSatelliteView ? const Color(0xFF6366F1) : Colors.white54,
                      ),
                      onPressed: () => setState(() => _showSatelliteView = true),
                      tooltip: 'Satellite View',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Global statistics dashboard
  Widget _buildGlobalStatsDashboard(Map<String, Map<String, dynamic>> regionData) {
    final totalProperties = regionData.values.fold<int>(0, (sum, data) => sum + (data['count'] as int));
    final totalValue = regionData.values.fold<double>(0, (sum, data) => sum + ((data['totalValue'] as num?)?.toDouble() ?? 0));
    final totalArea = regionData.values.fold<double>(0, (sum, data) => sum + ((data['totalArea'] as num?)?.toDouble() ?? 0));
    final activeRegions = regionData.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Global Portfolio Overview',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatCard(
                icon: Icons.inventory_2,
                title: 'Total Properties',
                value: totalProperties.toString(),
                color: const Color(0xFF6366F1),
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.attach_money,
                title: 'Portfolio Value',
                value: _formatCurrency(totalValue),
                color: const Color(0xFF10B981),
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.square_foot,
                title: 'Total Area',
                value: _formatArea(totalArea),
                color: const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.public,
                title: 'Active Regions',
                value: activeRegions.toString(),
                color: const Color(0xFFEF4444),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Enhanced world map with better markers and information
  Widget _buildEnhancedWorldMap(Map<String, Map<String, dynamic>> regionData) {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Map Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.map, color: Color(0xFF6366F1), size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Property Distribution Map',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  _showSatelliteView ? 'Satellite View' : 'Map View',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          // Map Content
          Expanded(
            child: _buildInteractiveWorldMap(regionData),
          ),
        ],
      ),
    );
  }

  // Interactive world map implementation
  Widget _buildInteractiveWorldMap(Map<String, Map<String, dynamic>> regionData) {
    // Extract all coordinates from blocks for Google Maps visualization
    final allCoordinates = <LatLng>[];
    final markers = <gmap.Marker>[];

    for (final entry in regionData.entries) {
      final regionCode = entry.key;
      final data = entry.value;
      final blocks = data['blocks'] as List<BlockData>;
      final count = data['count'] as int;
      final countryName = data['countryName'] as String;
      final totalValue = (data['totalValue'] as num?)?.toDouble() ?? 0;

      for (final block in blocks) {
        final coords = _parseCoordinatesForMap(block.rawData['coordinates']);
        if (coords.isNotEmpty) {
          allCoordinates.addAll(coords);

          // Create marker for this property
          final center = _centerOf(coords);
          markers.add(
            gmap.Marker(
              markerId: gmap.MarkerId('${regionCode}_${block.hash}'),
              position: _g(center),
              infoWindow: gmap.InfoWindow(
                title: '$countryName (${_flagEmojiFromISO2(regionCode)})',
                snippet: '$count properties • ${_formatCurrency(totalValue)}',
              ),
              icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                _getMarkerHue(count),
              ),
            ),
          );
        }
      }
    }

    if (allCoordinates.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 48, color: Colors.white54),
            SizedBox(height: 16),
            Text(
              'No location data available',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Add coordinates to properties to see them on the map',
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Calculate bounds for all coordinates
    final bounds = _calculateBounds(allCoordinates);

    return Container(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: gmap.GoogleMap(
          initialCameraPosition: gmap.CameraPosition(
            target: _g(_centerOf(allCoordinates)),
            zoom: 2,
          ),
          markers: markers.toSet(),
          mapType: _showSatelliteView ? gmap.MapType.hybrid : gmap.MapType.normal,
          zoomControlsEnabled: true,
          mapToolbarEnabled: true,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          onMapCreated: (controller) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (bounds != null) {
              await controller.animateCamera(
                gmap.CameraUpdate.newLatLngBounds(bounds, 50),
              );
            }
          },
        ),
      ),
    );
  }

  // Regional analytics with charts and insights
  Widget _buildRegionalAnalytics(Map<String, Map<String, dynamic>> regionData) {
    final sortedRegions = regionData.entries.toList()
      ..sort((a, b) => (b.value['count'] as int).compareTo(a.value['count'] as int));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Regional Performance Analytics',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: sortedRegions.length,
              itemBuilder: (context, index) {
                final entry = sortedRegions[index];
                final regionCode = entry.key;
                final data = entry.value;
                final count = data['count'] as int;
                final countryName = data['countryName'] as String;
                final totalValue = (data['totalValue'] as num?)?.toDouble() ?? 0;
                final totalArea = (data['totalArea'] as num?)?.toDouble() ?? 0;

                return Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _flagEmojiFromISO2(regionCode),
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              countryName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildAnalyticsRow(Icons.inventory_2, 'Properties', count.toString(), const Color(0xFF6366F1)),
                      const SizedBox(height: 8),
                      _buildAnalyticsRow(Icons.attach_money, 'Value', _formatCurrency(totalValue), const Color(0xFF10B981)),
                      const SizedBox(height: 8),
                      _buildAnalyticsRow(Icons.square_foot, 'Area', _formatArea(totalArea), const Color(0xFFF59E0B)),
                      const Spacer(),
                      Container(
                        width: double.infinity,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (count / sortedRegions.first.value['count']).clamp(0.1, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // Transaction value analysis
  Widget _buildTransactionValueAnalysis(Map<String, Map<String, dynamic>> regionData) {
    final sortedByValue = regionData.entries.toList()
      ..sort((a, b) => ((b.value['totalValue'] as num?)?.toDouble() ?? 0).compareTo((a.value['totalValue'] as num?)?.toDouble() ?? 0));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Market Value Analysis by Region',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...sortedByValue.take(5).map((entry) {
            final regionCode = entry.key;
            final data = entry.value;
            final totalValue = (data['totalValue'] as num?)?.toDouble() ?? 0;
            final count = data['count'] as int;
            final avgValue = totalValue / count;
            final countryName = data['countryName'] as String;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    _flagEmojiFromISO2(regionCode),
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          countryName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$count properties • Avg: ${_formatCurrency(avgValue)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrency(totalValue),
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        width: 60,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: sortedByValue.isNotEmpty ? (totalValue / ((sortedByValue.first.value['totalValue'] as num?)?.toDouble() ?? 1)).clamp(0.1, 1.0) : 0.1,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // Enhanced region list with detailed statistics
  Widget _buildEnhancedRegionList(Map<String, Map<String, dynamic>> regionData) {
    final sortedRegions = regionData.entries.toList()
      ..sort((a, b) => (b.value['count'] as int).compareTo(a.value['count'] as int));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detailed Regional Breakdown',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...sortedRegions.map((entry) {
            final regionCode = entry.key;
            final data = entry.value;
            final count = data['count'] as int;
            final countryName = data['countryName'] as String;
            final totalValue = (data['totalValue'] as num?)?.toDouble() ?? 0;
            final totalArea = (data['totalArea'] as num?)?.toDouble() ?? 0;
            final avgValue = totalValue / count;
            final avgArea = totalArea / count;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        _flagEmojiFromISO2(regionCode),
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              countryName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$count properties registered',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '#${sortedRegions.indexOf(entry) + 1}',
                          style: const TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRegionStatItem(
                          'Total Value',
                          _formatCurrency(totalValue),
                          const Color(0xFF10B981),
                        ),
                      ),
                      Expanded(
                        child: _buildRegionStatItem(
                          'Avg Value',
                          _formatCurrency(avgValue),
                          const Color(0xFF10B981),
                        ),
                      ),
                      Expanded(
                        child: _buildRegionStatItem(
                          'Total Area',
                          _formatArea(totalArea),
                          const Color(0xFFF59E0B),
                        ),
                      ),
                      Expanded(
                        child: _buildRegionStatItem(
                          'Avg Area',
                          _formatArea(avgArea),
                          const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRegionStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // Helper methods for enhanced functionality
  double _extractPropertyValue(Map<String, dynamic> data) {
    // Extract property value from various possible fields
    final value = data['value'] ?? data['marketValue'] ?? data['assessedValue'] ?? 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  double _extractPropertyArea(Map<String, dynamic> data) {
    // Extract area in square kilometers
    final area = data['areaSqKm'] ?? data['area'] ?? data['size'] ?? 0;
    if (area is num) return area.toDouble();
    if (area is String) return double.tryParse(area) ?? 0;
    return 0;
  }

  DateTime _getLatestTimestamp(DateTime? existing, DateTime current) {
    if (existing == null) return current;
    return current.isAfter(existing) ? current : existing;
  }

  String _calculateActivityLevel(int count, DateTime lastActivity) {
    final daysSinceActivity = DateTime.now().difference(lastActivity).inDays;
    if (count >= 10 && daysSinceActivity <= 30) return 'high';
    if (count >= 5 && daysSinceActivity <= 60) return 'medium';
    return 'low';
  }

  List<LatLng> _extractRegionCoordinates(Map<String, dynamic> data) {
    return _parseCoordinatesForMap(data['coordinates']);
  }

  String _formatCurrency(double value) {
    if (value >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '\$${(value / 1000).toStringAsFixed(1)}K';
    } else {
      return '\$${value.toStringAsFixed(0)}';
    }
  }

  String _formatArea(double areaKm2) {
    if (areaKm2 >= 1) {
      return '${areaKm2.toStringAsFixed(1)} km²';
    } else {
      final m2 = areaKm2 * 1000000;
      return '${m2.toStringAsFixed(0)} m²';
    }
  }

  String _flagEmojiFromISO2(String iso2) {
    const int base = 0x1F1E6;
    if (iso2.length != 2) return '🏳️';
    final a = iso2.codeUnitAt(0) - 65;
    final b = iso2.codeUnitAt(1) - 65;
    return String.fromCharCode(base + a) + String.fromCharCode(base + b);
  }

  String _propLabel(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final n = widget.blocks.length;
    if (w < 360) return '$n Properties';
    if (w < 320) return '$n Props';
    return '$n Properties Worldwide';
  }

  // Helper methods for Google Maps
  LatLng _centerOf(List<LatLng> pts) {
    if (pts.isEmpty) return const LatLng(0, 0);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  gmap.LatLng _g(LatLng p) => gmap.LatLng(p.latitude, p.longitude);

  double _getMarkerHue(int count) {
    if (count >= 10) return gmap.BitmapDescriptor.hueBlue;
    if (count >= 5) return gmap.BitmapDescriptor.hueGreen;
    return gmap.BitmapDescriptor.hueOrange;
  }

  gmap.LatLngBounds? _calculateBounds(List<LatLng> pts) {
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

  // Helper method for parsing coordinates in the regions view
  List<LatLng> _parseCoordinatesForMap(dynamic coords) {
    final out = <LatLng>[];
    if (coords == null) return out;
    if (coords is List) {
      for (final c in coords) {
        if (c is Map) {
          final lat = c['lat'] ?? c['latitude'];
          final lng = c['lng'] ?? c['longitude'];
          if (lat is num && lng is num) {
            out.add(LatLng(lat.toDouble(), lng.toDouble()));
          }
        } else if (c is List && c.length >= 2) {
          // [lng, lat] geojson-style pair
          final lng = c[0], lat = c[1];
          if (lat is num && lng is num) out.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
    }
    return out;
  }
}