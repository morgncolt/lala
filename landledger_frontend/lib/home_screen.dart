import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'region_model.dart';
import 'regions_repository.dart';
import 'package:image_picker/image_picker.dart';

class HomeScreen extends StatefulWidget {
  final String? currentRegionId;       // Add this
  final String? initialSelectedId;
  final void Function(String regionId, String geojsonPath)? onRegionSelected;
  final VoidCallback? onGoToMap;
  
  const HomeScreen({
    Key? key,
    this.currentRegionId,
    this.initialSelectedId,
    this.onRegionSelected,
    this.onGoToMap,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final List<Map<String, String>> _regions;
  String? _selectedRegionId;
  final User? _user = FirebaseAuth.instance.currentUser;
  final Map<String, bool> _likedPosts = {};
  final Map<String, TextEditingController> _commentControllers = {};
  bool _hasTriggeredInitialNavigation = false;
  final ImagePicker _picker = ImagePicker();

@override
void initState() {
  super.initState();
  _regions = [
    {"id": "cameroon", "label": "Cameroon", "path": "assets/data/cameroon.geojson"},
    {"id": "ghana", "label": "Ghana", "path": "assets/data/ghana.geojson"},
    {"id": "kenya", "label": "Kenya", "path": "assets/data/kenya.geojson"},
    {"id": "nigeria_abj", "label": "Nigeria (Abuja)", "path": "assets/data/nigeria_abj.geojson"},
    {"id": "nigeria_lagos", "label": "Nigeria (Lagos)", "path": "assets/data/nigeria_lagos.geojson"},
  ];

  final incoming = widget.initialSelectedId ?? widget.currentRegionId;
  final match = _regions.firstWhere(
    (r) => r['id'] == incoming,
    orElse: () => _regions.first,
  );
  _selectedRegionId = match['id'];

  if (widget.currentRegionId != null && !_hasTriggeredInitialNavigation) {
    _hasTriggeredInitialNavigation = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRegionSelected?.call(_selectedRegionId!, match['path']!);
    });
  }
}

  @override
  void dispose() {
    TextEditingController _getOrCreateController(String postId) {
      if (_commentControllers[postId]?.hasListeners != true) {
        _commentControllers[postId]?.dispose();  // Dispose old controller if re-creating
        _commentControllers[postId] = TextEditingController();
      }
      return _commentControllers[postId]!;
    }

    super.dispose();
  }

  Future<String?> _uploadImage(XFile imageFile) async {
    try {
      final storageRef = FirebaseStorage.instance.ref()
          .child('post_images/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await storageRef.putFile(File(imageFile.path));
      return await storageRef.getDownloadURL();
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  void _showNewPostModal() {
    final types = ['Safety Incident', 'Infrastructure Damage', 'New Region', 'Other'];
    String postType = types.first;
    final descCtrl = TextEditingController();
    List<String> imageUrls = [];
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'New Post',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedRegionId,
                    decoration: const InputDecoration(labelText: 'Region'),
                    items: _regions.map((r) => DropdownMenuItem(
                      value: r['id'],
                      child: Text(r['label']!),
                    )).toList(),
                    onChanged: (key) {
                      if (key == null) return;
                      setState(() => _selectedRegionId = key);
                      final region = _regions.firstWhere((r) => r['id'] == key);
                      widget.onRegionSelected?.call(key, region['path']!);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: postType,
                    decoration: const InputDecoration(labelText: 'Post Type'),
                    items: types.map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(type),
                    )).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        postType = value;
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Add Photo'),
                        onPressed: () async {
                          final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                          if (image != null) {
                            setState(() => isUploading = true);
                            final url = await _uploadImage(image);
                            if (url != null) {
                              setState(() {
                                imageUrls.add(url);
                                isUploading = false;
                              });
                            }
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      if (isUploading) const CircularProgressIndicator(),
                    ],
                  ),
                  if (imageUrls.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: imageUrls.length,
                        itemBuilder: (ctx, index) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(
                              children: [
                                Image.network(
                                  imageUrls[index],
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                    icon: const Icon(Icons.close, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        imageUrls.removeAt(index);
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: isUploading
                        ? null
                        : () async {
                            if (_selectedRegionId == null || _user == null) return;
                            final postsRef = FirebaseFirestore.instance
                                .collection('regions')
                                .doc(_selectedRegionId)
                                .collection('posts');
                            await postsRef.add({
                              'type': postType,
                              'description': descCtrl.text,
                              'userId': _user!.uid,
                              'userEmail': _user!.email,
                              'timestamp': FieldValue.serverTimestamp(),
                              'likes': 0,
                              'likedBy': [],
                              'imageUrls': imageUrls,
                            });
                            Navigator.pop(ctx);
                            descCtrl.dispose();
                          },
                    child: const Text('Post'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleLike(String postId, List<dynamic> currentLikes) async {
    if (_user == null) return;

    final postRef = FirebaseFirestore.instance
        .collection('regions')
        .doc(_selectedRegionId)
        .collection('posts')
        .doc(postId);

    final isLiked = currentLikes.contains(_user!.uid);

    await postRef.update({
      'likes': isLiked ? FieldValue.increment(-1) : FieldValue.increment(1),
      'likedBy': isLiked 
          ? FieldValue.arrayRemove([_user!.uid])
          : FieldValue.arrayUnion([_user!.uid]),
    });
  }

  Future<void> _addComment(String postId, String comment) async {
    if (_user == null || comment.isEmpty) return;

    final commentsRef = FirebaseFirestore.instance
        .collection('regions')
        .doc(_selectedRegionId)
        .collection('posts')
        .doc(postId)
        .collection('comments');

    await commentsRef.add({
      'userId': _user!.uid,
      'userEmail': _user!.email,
      'text': comment,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _commentControllers[postId]?.clear();
  }

  void _showForwardDialog(String postId, String postText) {
    final regionCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forward Post'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(postText),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRegionId,
              decoration: const InputDecoration(labelText: 'To Region'),
              items: _regions.map((r) => DropdownMenuItem(
                value: r['id'],
                child: Text(r['label']!),
              )).toList(),
              onChanged: (key) {
                if (key != null) {
                  regionCtrl.text = key;
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (regionCtrl.text.isEmpty || _user == null) {
                Navigator.pop(ctx);
                return;
              }

              final targetRegion = regionCtrl.text;
              final postsRef = FirebaseFirestore.instance
                  .collection('regions')
                  .doc(targetRegion)
                  .collection('posts');

              await postsRef.add({
                'type': 'Forwarded Post',
                'description': postText,
                'originalPostId': postId,
                'userId': _user!.uid,
                'userEmail': _user!.email,
                'timestamp': FieldValue.serverTimestamp(),
                'likes': 0,
                'likedBy': [],
              });

              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Post forwarded successfully')),
              );
            },
            child: const Text('Forward'),
          ),
        ],
      ),
    );
  }

  void _showCommentsSheet(String postId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Comments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('regions')
                    .doc(_selectedRegionId)
                    .collection('posts')
                    .doc(postId)
                    .collection('comments')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(child: Text('No comments yet.'));
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final text = data['text'] as String? ?? '';
                      final userEmail = data['userEmail'] as String? ?? 'Anonymous';
                      final ts = data['timestamp'] as Timestamp?;
                      final timeLabel = ts != null
                          ? ts.toDate().toLocal().toString().substring(0, 16)
                          : '';
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text(userEmail),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(text),
                              Text(timeLabel, 
                                style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentControllers[postId] ??= TextEditingController(),
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    final comment = _commentControllers[postId]?.text ?? '';
                    _addComment(postId, comment);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedRegionId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Column(
        children: [
          _CustomAppBar(
            regions: _regions,
            selectedRegionKey: _selectedRegionId,
            onRegionChanged: (key) {
              setState(() => _selectedRegionId = key);
              final region = _regions.firstWhere((r) => r['id'] == key);
              widget.onRegionSelected?.call(key, region['path']!);
            },
            onSearchPressed: () {
              showSearch(
                context: context,
                delegate: PostSearchDelegate(_selectedRegionId!),
              );
            },
            user: _user,
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('regions')
                  .doc(_selectedRegionId)
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
                    final postId = docs[i].id;
                    final data = docs[i].data()! as Map<String, dynamic>;
                    final type = data['type'] as String? ?? 'Update';
                    final desc = data['description'] as String? ?? '';
                    final ts = data['timestamp'] as Timestamp?;
                    final timeLabel = ts?.toDate().toLocal().toString().substring(0, 16) ?? '';
                    final likes = (data['likes'] as int? ?? 0);
                    final likedBy = List<String>.from(data['likedBy'] ?? []);
                    final isLiked = _user != null && likedBy.contains(_user!.uid);
                    final userEmail = data['userEmail'] as String? ?? 'Anonymous';
                    final imageUrls = List<String>.from(data['imageUrls'] ?? []);

                    IconData icon;
                    switch (type) {
                      case 'Safety Incident': icon = Icons.warning; break;
                      case 'Infrastructure Damage': icon = Icons.build; break;
                      case 'New Region': icon = Icons.add_location; break;
                      default: icon = Icons.note;
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(icon, color: Theme.of(context).primaryColor, size: 24),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    type,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Text(
                                  timeLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              desc,
                              style: const TextStyle(fontSize: 14),
                            ),
                            if (imageUrls.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 150,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: imageUrls.length,
                                  itemBuilder: (ctx, index) {
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          imageUrls[index],
                                          width: 150,
                                          height: 150,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Posted by: $userEmail',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            isLiked ? Icons.favorite : Icons.favorite_border,
                                            color: isLiked ? Colors.red : Colors.grey,
                                            size: 20,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _toggleLike(postId, likedBy),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$likes',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.comment, size: 20),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _showCommentsSheet(postId),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.share, size: 20),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _showForwardDialog(postId, desc),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewPostModal,
        tooltip: 'New Post',
        child: const Icon(Icons.post_add),
      ),
    );
  }
}

class _CustomAppBar extends StatelessWidget {
  final List<Map<String, String>> regions;
  final String? selectedRegionKey;
  final Function(String) onRegionChanged;
  final VoidCallback onSearchPressed;
  final User? user;

  const _CustomAppBar({
    required this.regions,
    required this.selectedRegionKey,
    required this.onRegionChanged,
    required this.onSearchPressed,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentRegion = regions.firstWhere(
      (r) => r['id'] == selectedRegionKey,
      orElse: () => regions.first,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.primaryColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 16,
        left: 16,
        right: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Community Posts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.search, size: 24),
                    color: Colors.white,
                    onPressed: onSearchPressed,
                  ),
                  if (user != null)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.8),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: theme.colorScheme.secondary,
                        backgroundImage: user!.photoURL != null
                            ? NetworkImage(user!.photoURL!)
                            : null,
                        child: user!.photoURL == null
                            ? const Icon(Icons.person, 
                                color: Colors.white, 
                                size: 20)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButton<String>(
                value: selectedRegionKey,
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    onRegionChanged(newValue);
                  }
                },
                dropdownColor: theme.primaryColor,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                iconSize: 28,
                underline: const SizedBox(),
                isExpanded: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                selectedItemBuilder: (BuildContext context) {
                  return regions.map<Widget>((Map<String, String> region) {
                    return Container(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          _buildCountryFlag(region['id']!),
                          const SizedBox(width: 12),
                          Text(
                            region['label']!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                },
                items: regions.map<DropdownMenuItem<String>>((Map<String, String> region) {
                  return DropdownMenuItem<String>(
                    value: region['id'],
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          _buildCountryFlag(region['id']!),
                          const SizedBox(width: 12),
                          Text(
                            region['label']!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountryFlag(String countryId) {
    // Assuming you have flag images in your assets folder
    // named as 'cameroon_flag.png', 'ghana_flag.png', etc.
    return Image.asset(
      'assets/flags/${countryId}_flag.png',
      width: 32,
      height: 20,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        // Fallback widget if flag image is missing
        return Container(
          width: 32,
          height: 20,
          color: Colors.grey,
          child: const Center(
            child: Icon(Icons.flag, size: 16, color: Colors.white),
          ),
        );
      },
    );
  }
}

class PostSearchDelegate extends SearchDelegate {
  final String regionKey;

  PostSearchDelegate(this.regionKey);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('regions')
          .doc(regionKey)
          .collection('posts')
          .where('description', isGreaterThanOrEqualTo: query)
          .where('description', isLessThan: query + 'z')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data!.docs;
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final post = results[index].data() as Map<String, dynamic>;
            return ListTile(
              title: Text(post['description']),
              onTap: () {
                // Handle post selection
              },
            );
          },
        );
      },
    );
  }
}