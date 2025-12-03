import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a user's profile information
class UserProfile {
  final String userId;
  final String displayName;
  final String email;
  final String? photoURL;
  final String? bio;
  final String? walletAddress;
  final DateTime? createdAt;
  final DateTime? lastActive;

  UserProfile({
    required this.userId,
    required this.displayName,
    required this.email,
    this.photoURL,
    this.bio,
    this.walletAddress,
    this.createdAt,
    this.lastActive,
  });

  /// Create UserProfile from Firestore document
  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    return UserProfile(
      userId: doc.id,
      displayName: data?['displayName'] as String? ?? 'Anonymous',
      email: data?['email'] as String? ?? '',
      photoURL: data?['photoURL'] as String?,
      bio: data?['bio'] as String?,
      walletAddress: data?['walletAddress'] as String?,
      createdAt: (data?['createdAt'] as Timestamp?)?.toDate(),
      lastActive: (data?['lastActive'] as Timestamp?)?.toDate(),
    );
  }

  /// Convert UserProfile to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'email': email,
      'photoURL': photoURL,
      'bio': bio,
      'walletAddress': walletAddress,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
    };
  }

  /// Create a copy with updated fields
  UserProfile copyWith({
    String? displayName,
    String? email,
    String? photoURL,
    String? bio,
    String? walletAddress,
    DateTime? createdAt,
    DateTime? lastActive,
  }) {
    return UserProfile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoURL: photoURL ?? this.photoURL,
      bio: bio ?? this.bio,
      walletAddress: walletAddress ?? this.walletAddress,
      createdAt: createdAt ?? this.createdAt,
      lastActive: lastActive ?? this.lastActive,
    );
  }
}
