import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_profile.dart';
import '../services/identity_service.dart';

/// Service for managing user profile data in Firestore
class UserProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Cache for user profiles to reduce Firestore reads
  final Map<String, UserProfile> _profileCache = {};

  /// Get the current user's profile, creating one if it doesn't exist
  Future<UserProfile?> getCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      return await getUserProfile(user.uid);
    } catch (e) {
      debugPrint('Error getting current user profile: $e');
      return null;
    }
  }

  /// Get a user profile by userId, with caching
  Future<UserProfile?> getUserProfile(String userId) async {
    // Check cache first
    if (_profileCache.containsKey(userId)) {
      return _profileCache[userId];
    }

    try {
      final doc = await _firestore.collection('users').doc(userId).get();

      if (!doc.exists) {
        // Try to create a profile from Firebase Auth data if available
        final user = _auth.currentUser;
        if (user != null && user.uid == userId) {
          return await _createProfileFromAuthUser(user);
        }
        return null;
      }

      final profile = UserProfile.fromFirestore(doc);
      _profileCache[userId] = profile;
      return profile;
    } catch (e) {
      debugPrint('Error getting user profile for $userId: $e');
      return null;
    }
  }

  /// Create or update a user profile
  Future<void> createOrUpdateProfile(UserProfile profile) async {
    try {
      await _firestore.collection('users').doc(profile.userId).set(
            profile.toFirestore(),
            SetOptions(merge: true),
          );
      _profileCache[profile.userId] = profile;
    } catch (e) {
      debugPrint('Error creating/updating profile: $e');
      rethrow;
    }
  }

  /// Update the current user's profile
  Future<void> updateCurrentUserProfile({
    String? displayName,
    String? photoURL,
    String? bio,
    String? walletAddress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user logged in');

    try {
      final updates = <String, dynamic>{};
      if (displayName != null) updates['displayName'] = displayName;
      if (photoURL != null) updates['photoURL'] = photoURL;
      if (bio != null) updates['bio'] = bio;
      if (walletAddress != null) updates['walletAddress'] = walletAddress;
      updates['lastActive'] = FieldValue.serverTimestamp();

      await _firestore.collection('users').doc(user.uid).set(
            updates,
            SetOptions(merge: true),
          );

      // Update Firebase Auth display name if changed
      if (displayName != null && displayName != user.displayName) {
        await user.updateDisplayName(displayName);
      }

      // Update Firebase Auth photo URL if changed
      if (photoURL != null && photoURL != user.photoURL) {
        await user.updatePhotoURL(photoURL);
      }

      // Clear cache for this user
      _profileCache.remove(user.uid);
    } catch (e) {
      debugPrint('Error updating profile: $e');
      rethrow;
    }
  }

  /// Create a profile from Firebase Auth user data
  Future<UserProfile> _createProfileFromAuthUser(User user) async {
    const storage = FlutterSecureStorage();
    String username = user.displayName ?? '';
    String? walletAddress;

    // 1. Try to get wallet address from secure storage (this is the blockchain wallet)
    try {
      walletAddress = await getCurrentUserWallet();
      debugPrint('✅ Found wallet address: $walletAddress');
    } catch (e) {
      debugPrint('⚠️ Could not fetch wallet: $e');
    }

    // 2. Try to get username from secure storage
    try {
      final label = canonicalLabel(firebaseUid: user.uid);
      final storedUsername = await storage.read(key: 'username:$label');
      if (storedUsername != null && storedUsername.isNotEmpty) {
        username = storedUsername;
        debugPrint('✅ Found username in secure storage: $username');
      }
    } catch (e) {
      debugPrint('⚠️ Could not fetch username from storage: $e');
    }

    // 3. Check if user document exists in Firestore as fallback
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (username.isEmpty) {
          username = data?['username'] as String? ?? '';
        }
        walletAddress ??= data?['walletAddress'] as String?;
      }
    } catch (e) {
      debugPrint('Error fetching user data from Firestore: $e');
    }

    // 4. If still no username, try email prefix
    if (username.isEmpty) {
      username = user.email?.split('@').first ?? 'user${user.uid.substring(0, 6)}';
      debugPrint('📧 Using email-based username: $username');
    }

    debugPrint('🎯 Creating profile with username: $username, wallet: $walletAddress');

    final profile = UserProfile(
      userId: user.uid,
      displayName: username,
      email: user.email ?? '',
      photoURL: user.photoURL,
      walletAddress: walletAddress,
      createdAt: user.metadata.creationTime,
      lastActive: DateTime.now(),
    );

    await createOrUpdateProfile(profile);
    return profile;
  }

  /// Initialize or sync user profile when user logs in
  Future<void> initializeUserProfile(User user) async {
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (!doc.exists) {
        // Create new profile
        await _createProfileFromAuthUser(user);
      } else {
        // Update last active
        await _firestore.collection('users').doc(user.uid).update({
          'lastActive': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error initializing user profile: $e');
    }
  }

  /// Clear the profile cache (useful when user logs out)
  void clearCache() {
    _profileCache.clear();
  }

  /// Get a stream of user profile updates
  Stream<UserProfile?> getUserProfileStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final profile = UserProfile.fromFirestore(doc);
      _profileCache[userId] = profile;
      return profile;
    });
  }
}
