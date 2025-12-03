import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'models/user_profile.dart';
import 'services/user_profile_service.dart';
import 'package:flutter/services.dart';

/// Screen for viewing and editing user profiles
class UserProfileScreen extends StatefulWidget {
  final String userId;
  final bool isCurrentUser;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.isCurrentUser = false,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final UserProfileService _profileService = UserProfileService();
  final ImagePicker _picker = ImagePicker();

  bool _isEditing = false;
  bool _isUploading = false;
  bool _isPicking = false;

  late TextEditingController _displayNameController;
  late TextEditingController _bioController;
  late TextEditingController _walletController;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _bioController = TextEditingController();
    _walletController = TextEditingController();

    // Initialize profile if viewing own profile
    if (widget.isCurrentUser) {
      _initializeProfile();
    }
  }

  Future<void> _initializeProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        debugPrint('🔍 Current user info:');
        debugPrint('   UID: ${user.uid}');
        debugPrint('   Email: ${user.email}');
        debugPrint('   DisplayName: ${user.displayName}');
        debugPrint('   PhotoURL: ${user.photoURL}');

        await _profileService.initializeUserProfile(user);

        // Force a rebuild to show updated profile
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Error initializing profile: $e');
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _walletController.dispose();
    super.dispose();
  }

  Future<void> _uploadProfilePhoto() async {
    if (_isPicking || _isUploading) return;

    _isPicking = true;
    XFile? image;
    try {
      image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } on PlatformException catch (e) {
      if (e.code != 'already_active') {
        debugPrint('Image picker error: $e');
      }
    } catch (e) {
      debugPrint('Unexpected picker error: $e');
    } finally {
      _isPicking = false;
    }

    if (image == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isUploading = true);

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_photos/${user.uid}.jpg');
      final task = await ref.putFile(File(image.path));
      final photoURL = await task.ref.getDownloadURL();

      await _profileService.updateCurrentUserProfile(photoURL: photoURL);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (e) {
      debugPrint('Error uploading profile photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _saveProfile() async {
    try {
      await _profileService.updateCurrentUserProfile(
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
        walletAddress: _walletController.text.trim(),
      );

      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (widget.isCurrentUser && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveProfile,
            ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _isEditing = false),
            ),
        ],
      ),
      body: StreamBuilder<UserProfile?>(
        stream: _profileService.getUserProfileStream(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final profile = snapshot.data;
          if (profile == null) {
            return const Center(child: Text('User not found'));
          }

          // Update controllers when data loads
          if (!_isEditing) {
            _displayNameController.text = profile.displayName;
            _bioController.text = profile.bio ?? '';
            _walletController.text = profile.walletAddress ?? '';
          }

          // Auto-start editing if profile is Anonymous and this is current user
          if (widget.isCurrentUser &&
              profile.displayName == 'Anonymous' &&
              !_isEditing) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please set your username'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            });
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Profile Photo
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: profile.photoURL != null
                            ? NetworkImage(profile.photoURL!)
                            : null,
                        child: profile.photoURL == null
                            ? const Icon(Icons.person, size: 60)
                            : null,
                      ),
                      if (widget.isCurrentUser)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Theme.of(context).primaryColor,
                            child: _isUploading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.camera_alt, size: 20),
                                    color: Colors.white,
                                    padding: EdgeInsets.zero,
                                    onPressed: _uploadProfilePhoto,
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Display Name
                if (_isEditing)
                  TextField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                      border: OutlineInputBorder(),
                    ),
                  )
                else
                  Text(
                    profile.displayName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                const SizedBox(height: 8),

                // Email (only shown to profile owner)
                if (widget.isCurrentUser)
                  Text(
                    profile.email,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                if (widget.isCurrentUser)
                  const SizedBox(height: 24)
                else
                  const SizedBox(height: 8),

                // Bio
                if (_isEditing)
                  TextField(
                    controller: _bioController,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      hintText: 'Tell us about yourself...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  )
                else if (profile.bio != null && profile.bio!.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bio',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(profile.bio!),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Wallet Address
                if (_isEditing)
                  TextField(
                    controller: _walletController,
                    decoration: const InputDecoration(
                      labelText: 'Wallet Address',
                      hintText: '0x...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.account_balance_wallet),
                    ),
                  )
                else if (profile.walletAddress != null && profile.walletAddress!.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.account_balance_wallet, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Wallet Address',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            profile.walletAddress!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Recent Posts Section
                _buildUserPosts(profile.userId),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildUserPosts(String userId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Posts',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collectionGroup('posts')
              .where('userId', isEqualTo: userId)
              .orderBy('timestamp', descending: true)
              .limit(10)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('No posts yet'));
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final data = doc.data()! as Map<String, dynamic>;
                final desc = (data['description'] as String?) ?? '';
                final type = (data['type'] as String?) ?? 'Update';
                final ts = data['timestamp'] as Timestamp?;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(type),
                    subtitle: Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: ts != null
                        ? Text(
                            _formatDate(ts.toDate()),
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} year${difference.inDays >= 730 ? 's' : ''} ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} month${difference.inDays >= 60 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
}
