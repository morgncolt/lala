import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'comments_screen.dart';
import 'hashtag_utils.dart';
import 'services/user_profile_service.dart';
import 'user_profile_screen.dart';


class HomeScreen extends StatefulWidget {
  final String? currentRegionId;
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late List<Map<String, String>> _regions;
  String? _selectedRegionId;
  User? get _user => FirebaseAuth.instance.currentUser;
  bool _hasTriggeredInitialNavigation = false;
  final ImagePicker _picker = ImagePicker();
  final UserProfileService _profileService = UserProfileService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    debugPrint("🏠 HomeScreen initState() with ${widget.currentRegionId}");
    _regions = [
      {"id": "united_states", "label": "United States", "path": "assets/data/united_states.geojson"},
      {"id": "cameroon", "label": "Cameroon", "path": "assets/data/cameroon.geojson"},
      {"id": "ghana", "label": "Ghana", "path": "assets/data/ghana.geojson"},
      {"id": "kenya", "label": "Kenya", "path": "assets/data/kenya.geojson"},
      {"id": "nigeria", "label": "Nigeria", "path": "assets/data/nigeria.geojson"},
    ];

    final incoming = widget.initialSelectedId ?? widget.currentRegionId;
    final match = _regions.firstWhere(
      (r) => r['id'] == incoming,
      orElse: () => _regions.first,
    );
    _selectedRegionId = match['id'];

    if (widget.currentRegionId != null && !_hasTriggeredInitialNavigation) {
      setState(() {
        _hasTriggeredInitialNavigation = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onRegionSelected?.call(_selectedRegionId!, match['path']!);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Handle paused state
    }
  }

  void _toggleLike(String postId, List<String> likedBy) {
    if (_user == null) return;

    try {
      final isLiked = likedBy.contains(_user!.uid);
      final postRef = FirebaseFirestore.instance
          .collection('regions')
          .doc(_selectedRegionId)
          .collection('posts')
          .doc(postId);

      postRef.update({
        'likes': FieldValue.increment(isLiked ? -1 : 1),
        'likedBy': isLiked
            ? FieldValue.arrayRemove([_user!.uid])
            : FieldValue.arrayUnion([_user!.uid]),
      });
    } catch (e) {
      debugPrint('Error toggling like: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update like')),
      );
    }
  }

  void deletePost(BuildContext context, String regionId, String postId) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    ).then((shouldDelete) {
      if (shouldDelete != true) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleting post...')),
      );

      FirebaseFirestore.instance
          .collection('regions')
          .doc(regionId)
          .collection('posts')
          .doc(postId)
          .delete()
          .then((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted successfully')),
        );
      }).catchError((e) {
        debugPrint('Error deleting post: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete post: $e')),
        );
      });
    });
  }

  void _showCommentsSheet(String postId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CommentSheet(
        postId: postId,
        regionId: _selectedRegionId!,
        user: _user,
      ),
    );
  }

 void _showNewPostModal() {
  final TextEditingController _postController = TextEditingController();
  String? _selectedPostType = 'Update';
  List<XFile> _selectedImages = [];
  bool _isUploading = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Create New Post',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _postController,
                    decoration: const InputDecoration(
                      hintText: 'What would you like to share?',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                    minLines: 1,
                  ),
                  const SizedBox(height: 16),
                  // Image selection preview
                  if (_selectedImages.isNotEmpty)
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _selectedImages.length,
                        itemBuilder: (context, index) {
                          return Stack(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  image: DecorationImage(
                                    image: FileImage(File(_selectedImages[index].path)),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () {
                                    setModalState(() {
                                      _selectedImages.removeAt(index);
                                    });
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.photo_library),
                        onPressed: () async {
                          final images = await _picker.pickMultiImage();
                          if (images != null) {
                            setModalState(() {
                              _selectedImages.addAll(images);
                            });
                          }
                        },
                        tooltip: 'Add Photos',
                      ),
                      DropdownButton<String>(
                        value: _selectedPostType,
                        items: const [
                          DropdownMenuItem(
                            value: 'General',
                            child: Text('General'),
                          ),
                          DropdownMenuItem(
                            value: 'Update',
                            child: Text('Update'),
                          ),
                          DropdownMenuItem(
                            value: 'Safety Incident',
                            child: Text('Safety Incident'),
                          ),
                          DropdownMenuItem(
                            value: 'Infrastructure Damage',
                            child: Text('Infrastructure Damage'),
                          ),
                          DropdownMenuItem(
                            value: 'New Region',
                            child: Text('New Region'),
                          ),
                        ],
                        onChanged: (value) {
                          setModalState(() {
                            _selectedPostType = value;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _isUploading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: () async {
                            if (_postController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Please enter some text')),
                              );
                              return;
                            }

                            setModalState(() {
                              _isUploading = true;
                            });

                            try {
                              // Upload images first
                              List<String> imageUrls = [];
                              for (var image in _selectedImages) {
                                final downloadUrl = await _uploadImage(image);
                                if (downloadUrl != null) {
                                  imageUrls.add(downloadUrl);
                                }
                              }

                              // Get user profile for display name and photo
                              final userProfile = await _profileService.getCurrentUserProfile();

                              // Determine the username to use
                              final String username;
                              if (userProfile != null && userProfile.displayName.isNotEmpty && userProfile.displayName != 'Anonymous') {
                                username = userProfile.displayName;
                              } else if (_user?.displayName != null) {
                                final displayName = _user?.displayName;
                                username = displayName!.isNotEmpty ? displayName : (_user?.email?.split('@').first ?? 'user${_user?.uid.substring(0, 6) ?? 'unknown'}');
                              } else if (_user?.email != null) {
                                final email = _user?.email;
                                username = email!.split('@').first;
                              } else {
                                username = 'user${_user?.uid.substring(0, 6) ?? 'unknown'}';
                              }

                              // Create post
                              await FirebaseFirestore.instance
                                  .collection('regions')
                                  .doc(_selectedRegionId)
                                  .collection('posts')
                                  .add({
                                'userId': _user?.uid,
                                'userEmail': _user?.email ?? '',
                                'displayName': username,
                                'userPhotoURL': userProfile?.photoURL ?? _user?.photoURL,
                                'type': _selectedPostType,
                                'description': _postController.text,
                                'timestamp': FieldValue.serverTimestamp(),
                                'likes': 0,
                                'likedBy': [],
                                'imageUrls': imageUrls,
                              });

                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Post created successfully!')),
                              );
                            } catch (e) {
                              debugPrint('Error creating post: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Failed to create post: $e')),
                              );
                            } finally {
                              setModalState(() {
                                _isUploading = false;
                              });
                            }
                          },
                          child: const Text('Post'),
                        ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<String?> _uploadImage(XFile imageFile) async {
  try {
    final storageRef = FirebaseStorage.instance.ref().child(
        'post_images/${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}');
    await storageRef.putFile(File(imageFile.path));
    return await storageRef.getDownloadURL();
  } catch (e) {
    debugPrint('Error uploading image: $e');
    return null;
  }
}
 
  @override
  Widget build(BuildContext context) {
    try {
      if (_selectedRegionId == null) {
        return const Center(child: CircularProgressIndicator());
      }

      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _CustomAppBar(
                regions: _regions,
                selectedRegionKey: _selectedRegionId,
                onRegionChanged: (key) async {
                setState(() => _selectedRegionId = key);
                final region = _regions.firstWhere((r) => r['id'] == key);

                // Save user's region choice for next launch
                try {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('last_selected_region_id', key);
                  await prefs.setString('last_selected_geojson_path', region['path']!);
                  debugPrint('💾 Saved region preference: $key');
                } catch (e) {
                  debugPrint('⚠️ Failed to save region preference: $e');
                }

                widget.onRegionSelected?.call(key, region['path']!);
              },
              onSearchPressed: () {
                showSearch(
                  context: context,
                  delegate: PostSearchDelegate(
                    _selectedRegionId!,
                    onRegionSelected: widget.onRegionSelected,
                  ),
                );
              },
              user: _user,
            ),

            // MAIN HOME CONTENT
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// ✅ LAND-FOCUSED PROMPTS SECTION
                    HomePromptSection(
                      selectedRegionId: _selectedRegionId!,
                      regions: _regions,
                      onRegionSelected: widget.onRegionSelected,
                      onGoToMap: widget.onGoToMap,
                    ),

                    const SizedBox(height: 24),

                    /// ✅ COMMUNITY POSTS (SECONDARY)
                    Text(
                      'Community activity in this region',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'See what people in ${_regions.firstWhere((r) => r["id"] == _selectedRegionId!)["label"]} are sharing about their land, safety, and infrastructure.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                    const SizedBox(height: 12),

                    // Post creation bar
                    _PostCreationBar(
                      user: _user,
                      onTap: _showNewPostModal,
                    ),
                    const SizedBox(height: 16),

                    CommunityFeedSection(
                      selectedRegionId: _selectedRegionId!,
                      user: _user,
                      onToggleLike: _toggleLike,
                      onDeletePost: (postId) =>
                          deletePost(context, _selectedRegionId!, postId),
                      onShowComments: _showCommentsSheet,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),

      );
    } catch (e, stackTrace) {
      debugPrint("🚨 HomeScreen build() failed: $e\n$stackTrace");
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text("Something went wrong"),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => setState(() {}),
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }
  }
}

// ============================================================================
// LAND-FOCUSED PROMPT SECTION
// ============================================================================

class HomePromptSection extends StatelessWidget {
  final String selectedRegionId;
  final List<Map<String, String>> regions;
  final void Function(String regionId, String geojsonPath)? onRegionSelected;
  final VoidCallback? onGoToMap;

  const HomePromptSection({
    Key? key,
    required this.selectedRegionId,
    required this.regions,
    this.onRegionSelected,
    this.onGoToMap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final region = regions.firstWhere(
      (r) => r['id'] == selectedRegionId,
      orElse: () => regions.first,
    );
    final regionLabel = region['label'] ?? 'this region';
    final geojsonPath = region['path'];
    const quickSteps = <String>[
      'Tap "Add Region"',
      'Drop points along the border',
      'Save & name it',
    ];
    final subtleTextColor =
        theme.textTheme.bodyMedium?.color?.withOpacity(0.75) ?? Colors.grey.shade500;
    final smallTextColor =
        theme.textTheme.bodySmall?.color?.withOpacity(0.75) ?? Colors.grey.shade500;
    final chipBackground = theme.colorScheme.onSurface.withOpacity(0.08);
    final chipAvatarBackground = theme.colorScheme.primary.withOpacity(0.18);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Start mapping in minutes',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Short assists keep you moving. Pick your country, jump to the map, and follow the quick cues below.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: subtleTextColor,
          ),
        ),
        const SizedBox(height: 16),
        _AnimatedPromptCard(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: theme.colorScheme.surface.withOpacity(0.15),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                      child: Icon(
                        Icons.public,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Currently focused on',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: smallTextColor,
                            ),
                          ),
                          Text(
                            regionLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Change it anytime from the dropdown above.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: subtleTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.map_outlined),
                  label: Text('Open map in $regionLabel'),
                  onPressed: () {
                    if (geojsonPath != null && onRegionSelected != null) {
                      onRegionSelected!(selectedRegionId, geojsonPath);
                    } else if (geojsonPath == null) {
                      debugPrint('HomePromptSection: Missing geojson path for $selectedRegionId');
                    }
                    onGoToMap?.call();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _AnimatedPromptCard(
          delay: 160,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withOpacity(0.12),
                  theme.colorScheme.primary.withOpacity(0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.gesture,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Guided drawing',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Do these quick actions once the map opens.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: subtleTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(quickSteps.length, (index) {
                    final label = quickSteps[index];
                    return Chip(
                      avatar: CircleAvatar(
                        backgroundColor: chipAvatarBackground,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      label: Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: chipBackground,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pro tip: zoom in tight before placing points. You can edit or redo a shape anytime.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: smallTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedPromptCard extends StatelessWidget {
  final Widget child;
  final int delay;

  const _AnimatedPromptCard({
    required this.child,
    this.delay = 0,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 500 + delay),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 20),
          child: Opacity(
            opacity: value,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

// ============================================================================
// COMMUNITY FEED SECTION (SECONDARY)
// ============================================================================

class CommunityFeedSection extends StatelessWidget {
  final String selectedRegionId;
  final User? user;
  final void Function(String postId, List<String> likedBy) onToggleLike;
  final void Function(String postId) onDeletePost;
  final void Function(String postId) onShowComments;

  const CommunityFeedSection({
    Key? key,
    required this.selectedRegionId,
    required this.user,
    required this.onToggleLike,
    required this.onDeletePost,
    required this.onShowComments,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('regions')
          .doc(selectedRegionId)
          .collection('posts')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .handleError((error) {
        debugPrint('Posts stream error: $error');
      }),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No posts yet. Be the first to share an update about this region.',
            ),
          );
        }

        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final postId = docs[i].id;
            final data = docs[i].data()! as Map<String, dynamic>;
            final type = data['type'] as String? ?? 'Update';
            final desc = data['description'] as String? ?? '';
            final ts = data['timestamp'] as Timestamp?;
            final timeLabel =
                ts?.toDate().toLocal().toString().substring(0, 16) ?? '';
            final likes = (data['likes'] as int? ?? 0);
            final likedBy = List<String>.from(data['likedBy'] ?? []);
            final isLiked = user != null && likedBy.contains(user!.uid);
            final userEmail = data['userEmail'] as String? ?? '';
            final displayName = data['displayName'] as String? ??
                (userEmail.isNotEmpty ? userEmail.split('@').first : 'User');
            final userPhotoURL = data['userPhotoURL'] as String?;
            final userId = data['userId'] as String?;
            final imageUrls = List<String>.from(data['imageUrls'] ?? []);

            IconData icon;
            switch (type) {
              case 'General':
                icon = Icons.chat_bubble_outline;
                break;
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

            void openProfile() {
              if (userId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(
                      userId: userId,
                      isCurrentUser: user?.uid == userId,
                    ),
                  ),
                );
              }
            }

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: userId != null ? openProfile : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // User row with navigation to profile
                      GestureDetector(
                        onTap: openProfile,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundImage: userPhotoURL != null
                                  ? NetworkImage(userPhotoURL)
                                  : null,
                              child: userPhotoURL == null
                                  ? Text(
                                      displayName[0].toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Type + time
                      Row(
                        children: [
                          Icon(icon, color: Theme.of(context).primaryColor, size: 20),
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

                      // Description with hashtags
                      RichText(
                        text: TextSpan(
                          children: buildTextWithHashtag(context, desc),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),

                      // Images
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

                      // Actions
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
                                onPressed: () => onToggleLike(postId, likedBy),
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
                                onPressed: () => onShowComments(postId),
                              ),
                              const SizedBox(width: 8),
                              if (user?.uid == userId)
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => onDeletePost(postId),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// APP BAR
// ============================================================================

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LandLedger Home',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select your region and start mapping your land',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
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
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(
                              userId: user!.uid,
                              isCurrentUser: true,
                            ),
                          ),
                        );
                      },
                      child: Container(
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
    return Image.asset(
      'assets/flags/${countryId}_flag.png',
      width: 32,
      height: 20,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
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
  final void Function(String regionId, String geojsonPath)? onRegionSelected;

  PostSearchDelegate(this.regionKey, {this.onRegionSelected});

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
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
          .snapshots()
          .handleError((error) {
            debugPrint('Search stream error: $error');
          }),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data!.docs;
        if (results.isEmpty) {
          return const Center(child: Text('No results found'));
        }
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final post = results[index].data() as Map<String, dynamic>;
            return ListTile(
              title: Text(post['description'] ?? 'No description'),
              onTap: () {
                close(context, null);
              },
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// POST CREATION BAR
// ============================================================================

class _PostCreationBar extends StatelessWidget {
  final User? user;
  final VoidCallback onTap;

  const _PostCreationBar({
    required this.user,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // User avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.secondary,
                backgroundImage: user?.photoURL != null
                    ? NetworkImage(user!.photoURL!)
                    : null,
                child: user?.photoURL == null
                    ? Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 20,
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Placeholder text
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'Share an update about this region...',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Image icon
              IconButton(
                icon: Icon(
                  Icons.image,
                  color: theme.primaryColor,
                ),
                onPressed: onTap,
                tooltip: 'Add photos',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
