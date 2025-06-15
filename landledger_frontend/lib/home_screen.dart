import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

class HomeScreen extends StatefulWidget {
  /// Optionally pre‑select a region by its key or label
  final String? currentRegionKey;

  /// Callback when user picks a region
  final void Function(String regionKey, String geojsonPath)? onRegionSelected;
  final String? initialSelectedKey;
  

  const HomeScreen({
    Key? key,
    this.currentRegionKey,
    this.onRegionSelected,
    this.initialSelectedKey,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final List<Map<String, String>> _regions;
  String? _selectedRegionKey;
  final User? _user = FirebaseAuth.instance.currentUser;
  String? _selectedValue; 
  bool _hasTriggeredInitialNavigation = false;


  @override
  void initState() {
    super.initState();

    _regions = [
      {"key": "cameroon",      "label": "Cameroon",        "path": "assets/data/cameroon.geojson"},
      {"key": "ghana",         "label": "Ghana",           "path": "assets/data/ghana.geojson"},
      {"key": "kenya",         "label": "Kenya",           "path": "assets/data/kenya.geojson"},
      {"key": "nigeria_abj",   "label": "Nigeria (Abuja)", "path": "assets/data/nigeria_abj.geojson"},
      {"key": "nigeria_lagos", "label": "Nigeria (Lagos)", "path": "assets/data/nigeria_lagos.geojson"},
    ];

    final incoming = widget.initialSelectedKey ?? widget.currentRegionKey;
    final match = _regions.firstWhere(
      (r) => r['key'] == incoming || r['label'] == incoming,
      orElse: () => _regions.first,
    );
    _selectedRegionKey = match['key'];


    if (widget.currentRegionKey != null && !_hasTriggeredInitialNavigation) {
      _hasTriggeredInitialNavigation = true;
      print("🏁 Initial region provided, navigating once...");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onRegionSelected?.call(
          _selectedRegionKey!,
          match['path']!,
        );
      });
    }
  }


  void _showNewPostModal() {
    final types = [
      'Safety Incident',
      'Infrastructure Damage',
      'New Region',
      'Other',
    ];
    String postType = types.first;
    final descCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('New Post', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedRegionKey,
                decoration: const InputDecoration(labelText: 'Region'),
                items: _regions.map((r) => DropdownMenuItem(
                  value: r['key'],
                  child: Text(r['label']!),
                )).toList(),
                onChanged: (key) {
                  if (key == null) return;
                  setState(() => _selectedRegionKey = key);
                  final region = _regions.firstWhere((r) => r['key'] == key);
                  widget.onRegionSelected?.call(key, region['path']!);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  if (_selectedRegionKey == null || _user == null) return;
                  final postsRef = FirebaseFirestore.instance
                      .collection('regions')
                      .doc(_selectedRegionKey)
                      .collection('posts');
                  await postsRef.add({
                    'type': postType,
                    'description': descCtrl.text,
                    'userId': _user!.uid,
                    'timestamp': FieldValue.serverTimestamp(),
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Post'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedRegionKey == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Select Region & View Posts')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text("Header"),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedRegionKey,
              decoration: const InputDecoration(labelText: 'Region'),
              items: _regions.map((r) => DropdownMenuItem(
                value: r['key'],
                child: Text(r['label']!),
              )).toList(),
              onChanged: (key) {
                if (key == null) return;
                setState(() => _selectedRegionKey = key);
                final region = _regions.firstWhere((r) => r['key'] == key);
                widget.onRegionSelected?.call(key, region['path']!);
              },
            ),
            const SizedBox(height: 24),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('regions')
                    .doc(_selectedRegionKey)
                    .collection('posts')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(child: Text('No posts yet.'));
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final data = docs[i].data()! as Map<String, dynamic>;
                      final type = data['type'] as String? ?? 'Update';
                      final desc = data['description'] as String? ?? '';
                      final ts = data['timestamp'] as Timestamp?;
                      final timeLabel = ts != null
                          ? ts.toDate().toLocal().toString().substring(0, 16)
                          : '';
                      IconData icon;
                      switch (type) {
                        case 'Safety Incident':
                          icon = Icons.warning;
                          break;
                        case 'Infrastructure Damage':
                          icon = Icons.build;
                          break;
                        case 'New Region':
                          icon = Icons.add_location;
                          break;
                        default:
                          icon = Icons.note;
                      }
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          leading: Icon(icon, color: Theme.of(context).primaryColor),
                          title: Text(type),
                          subtitle: Text(desc),
                          trailing: Text(timeLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewPostModal,
        tooltip: 'New Post',
        child: const Icon(Icons.post_add),
      ),
    );
  }
}
