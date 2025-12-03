import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:latlong2/latlong.dart';
import 'map_screen.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'hashtag_utils.dart';


class CommentSheet extends StatefulWidget {
  final String postId;
  final String regionId;
  final User? user;

  const CommentSheet({
    super.key,
    required this.postId,
    required this.regionId,
    required this.user,
  });

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController walletController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _commentFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    descriptionController.dispose();
    walletController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleHashtagTap(String alias) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final query = await FirebaseFirestore.instance
          .collectionGroup('regions')
          .where('alias', isEqualTo: alias) // keep the #
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No polygon found for $alias")),
        );
        return;
      }

      final doc = query.docs.first;
      final data = doc.data();
      final regionId = data['region'];
      final coords = (data['coordinates'] as List)
          .map((c) => LatLng(c['lat'], c['lng']))
          .toList();

      // Optional: copy alias to clipboard
      await Clipboard.setData(ClipboardData(text: alias));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Opening region $alias on the map...")),
      );

      // Close any sheet/dialog before navigating
      Navigator.pop(context);

      // Navigate to the map with region loaded and highlighted
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapScreen(
            regionId: regionId,
            geojsonPath: null,
            highlightPolygon: coords,
            centerOnRegion: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Hashtag tap error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading map: $e')),
      );
    }
  }

  List<TextSpan> _buildTextWithHashtag(String text) {
    final regex = RegExp(r'#[A-Za-z0-9]+');
    final spans = <TextSpan>[];
    int start = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }

      final hashtag = match.group(0)!;
      spans.add(
        TextSpan(
          text: hashtag,
          style: const TextStyle(
            color: Colors.lightBlueAccent,
            fontWeight: FontWeight.bold,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _handleHashtagTap(hashtag),
        ),
      );
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return spans;
  }

  Future<String?> _uploadImage(XFile imageFile) async {
    try {
      final storageRef = FirebaseStorage.instance.ref()
          .child('comment_images/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await storageRef.putFile(File(imageFile.path));
      return await storageRef.getDownloadURL();
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _addComment(String comment) async {
    if (widget.user == null || comment.isEmpty || !mounted) return;

    setState(() => _isLoading = true);
    
    try {
      await FirebaseFirestore.instance
          .collection('regions')
          .doc(widget.regionId)
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .add({
            'userId': widget.user!.uid,
            'userEmail': widget.user!.email,
            'userPhotoUrl': widget.user!.photoURL,
            'text': comment,
            'timestamp': FieldValue.serverTimestamp(),
            'likes': 0,
            'likedBy': [],
          });

      _controller.clear();
      _commentFocusNode.unfocus();
    } catch (e) {
      debugPrint('Error adding comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post comment: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment?'),
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
    );

    if (shouldDelete != true || !mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Deleting comment...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      await FirebaseFirestore.instance
          .collection('regions')
          .doc(widget.regionId)
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc(commentId)
          .delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comment deleted successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error deleting comment: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete comment: ${e.toString()}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleLike(String commentId, List<String> likedBy) async {
    if (widget.user == null || !mounted) return;

    try {
      final isLiked = likedBy.contains(widget.user!.uid);
      await FirebaseFirestore.instance
          .collection('regions')
          .doc(widget.regionId)
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc(commentId)
          .update({
            'likes': FieldValue.increment(isLiked ? -1 : 1),
            'likedBy': isLiked
                ? FieldValue.arrayRemove([widget.user!.uid])
                : FieldValue.arrayUnion([widget.user!.uid]),
          });
    } catch (e) {
      debugPrint('Error toggling like: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update like')),
        );
      }
    }
  }

  Future<void> _deletePost() async {
    final shouldDelete = await showDialog<bool>(
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
    );

    if (shouldDelete != true || !mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('regions')
          .doc(widget.regionId)
          .collection('posts')
          .doc(widget.postId)
          .delete();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error deleting post: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete post: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildUserAvatar(String? photoUrl, String userEmail) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: CachedNetworkImageProvider(photoUrl),
        radius: 20,
      );
    }
    return CircleAvatar(
      backgroundColor: Colors.blueAccent,
      radius: 20,
      child: Text(
        userEmail.isNotEmpty ? userEmail[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 5,
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '💬 Comments',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  Row(
                    children: [
                      if (widget.user?.uid != null)
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('regions')
                              .doc(widget.regionId)
                              .collection('posts')
                              .doc(widget.postId)
                              .get(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && 
                                snapshot.data?['userId'] == widget.user?.uid) {
                              return IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: _deletePost,
                                tooltip: 'Delete Post',
                              );
                            }
                            return const SizedBox();
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('regions')
                    .doc(widget.regionId)
                    .collection('posts')
                    .doc(widget.postId)
                    .collection('comments')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mode_comment_outlined, 
                              size: 50, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No comments yet',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          Text(
                            'Be the first to comment!',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final doc = docs[i];
                      final data = doc.data() as Map<String, dynamic>;
                      final commentId = doc.id;
                      final text = data['text'] ?? '';
                      final userEmail = data['userEmail'] ?? 'Anonymous';
                      final userPhotoUrl = data['userPhotoUrl'];
                      final ts = data['timestamp'] as Timestamp?;
                      final timeLabel = ts != null
                          ? DateFormat('MMM d, h:mm a').format(ts.toDate())
                          : '';
                      final likes = (data['likes'] ?? 0).toInt();
                      final likedBy = List<String>.from(data['likedBy'] ?? []);
                      final isCurrentUser = widget.user?.uid == data['userId'];
                      final isLiked = widget.user != null && 
                          likedBy.contains(widget.user!.uid);

                      return Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        child: Material(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.grey[200],
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildUserAvatar(userPhotoUrl, userEmail),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: 
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                userEmail.split('@').first,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold, 
                                                  fontSize: 15),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                timeLabel,
                                                style: TextStyle(
                                                  fontSize: 12, 
                                                  color: Colors.grey[600]),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          RichText(
                                            text: TextSpan(
                                              children: _buildTextWithHashtag(text),
                                              style: const TextStyle(
                                                fontSize: 15, 
                                                color: Colors.black),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isCurrentUser)
                                      IconButton(
                                        icon: const Icon(Icons.delete, 
                                            size: 20, color: Colors.grey),
                                        onPressed: () => _deleteComment(commentId),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        isLiked ? Icons.favorite : 
                                            Icons.favorite_border,
                                        color: isLiked ? Colors.red : Colors.grey,
                                        size: 20,
                                      ),
                                      onPressed: widget.user == null
                                          ? null
                                          : () => _toggleLike(commentId, likedBy),
                                    ),
                                    Text(
                                      likes.toString(),
                                      style: TextStyle(
                                        color: isLiked ? Colors.red : Colors.grey,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const Spacer(),
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
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (widget.user?.photoURL != null)
                    CircleAvatar(
                      backgroundImage: NetworkImage(widget.user!.photoURL!),
                      radius: 18,
                    )
                  else if (widget.user != null)
                    CircleAvatar(
                      backgroundColor: const Color.fromARGB(255, 2, 76, 63),
                      radius: 18,
                      child: Text(
                        widget.user!.email![0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _commentFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[200],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        suffixIcon: _isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.send, 
                                    color: Color.fromARGB(255, 2, 76, 63)),
                                onPressed: _isLoading
                                    ? null
                                    : () {
                                        final comment = _controller.text;
                                        if (comment.isNotEmpty) {
                                          _addComment(comment);
                                        }
                                      },
                              ),
                      ),
                      maxLines: 3,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        final comment = _controller.text;
                        if (comment.isNotEmpty) {
                          _addComment(comment);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}