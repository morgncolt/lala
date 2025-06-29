import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;


class LandledgerScreen extends StatefulWidget {
  final ValueNotifier<Map<String, dynamic>?> blockchainDataNotifier;

  const LandledgerScreen({Key? key, required this.blockchainDataNotifier}) : super(key: key);

  @override
  State<LandledgerScreen> createState() => _LandledgerScreenState();
}

class _LandledgerScreenState extends State<LandledgerScreen> {
  List<Map<String, dynamic>> blockchainBlocks = [];
  final List<Map<String, dynamic>> trustedPartners = [
    {'name': 'Ministry of Lands', 'logo': '🏛️'},
    {'name': 'Land Registry', 'logo': '📜'},
    {'name': 'Surveyor General', 'logo': '🧭'},
    {'name': 'Community Leaders', 'logo': '👥'},
    {'name': 'Legal Advisors', 'logo': '⚖️'},
    {'name': 'Tech Partners', 'logo': '💻'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchBlockchainBlocks();
  }

  Future<void> _fetchBlockchainBlocks() async {
    try {
      final response = await Uri.parse('http://<your-ip>:4000/api/landledger/blocks').resolveUri(Uri());
      final res = await http.get(response);

      if (res.statusCode == 200) {
        final List<dynamic> blocks = jsonDecode(res.body);
        setState(() {
          blockchainBlocks = blocks.cast<Map<String, dynamic>>();
        });
      } else {
        print("❌ Error fetching blocks: ${res.statusCode}");
      }
    } catch (e) {
      print("❌ Exception fetching blocks: $e");
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LandLedger Security Center'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LandLedger Africa',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your land. Verified, protected, and always in your control.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  
                  // Stats Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCard('14', 'Communities'),
                      _buildStatCard('2,580', 'Records Logged'),
                      _buildStatCard('12', 'Issues Resolving'),
                    ],
                  ),
                ],
              ),
            ),
            
            // Blockchain Data Section (existing functionality)
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: widget.blockchainDataNotifier,
              builder: (context, data, _) {
                if (data != null) {
                  return Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Record',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text('🆔 ID: ${data["id"] ?? data["parcelId"] ?? "N/A"}'),
                        Text('👤 Owner: ${data["owner"] ?? data["ownerId"] ?? "N/A"}'),
                        Text('🕓 Timestamp: ${data["timestamp"] ?? data["createdAt"] ?? "N/A"}'),
                        Text('✅ Verified: ${data["verified"] ?? "Yes"}'),
                        const SizedBox(height: 8),
                        Text('📄 Description:\n${data["description"] ?? "N/A"}'),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            
            // Blockchain Blocks Section
            SizedBox(
              height: 200,
              child: blockchainBlocks.isEmpty
                  ? const Center(child: Text('No verified updates yet.'))
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: blockchainBlocks.length,
                      itemBuilder: (context, index) {
                        final block = blockchainBlocks[index];
                        return Card(
                          margin: const EdgeInsets.only(right: 12),
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Container(
                            width: 180,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                colors: [Colors.green.shade50, Colors.green.shade100],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  block['block'] ?? 'Block #N/A',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(block['transactions'] ?? 'N/A'),
                                const Spacer(),
                                Text(
                                  block['timestamp'] ?? '',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Trusted Partners Section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trusted Partners',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: trustedPartners.map((partner) {
                      return Chip(
                        avatar: Text(partner['logo']),
                        label: Text(partner['name']),
                        backgroundColor: Colors.grey.shade100,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}