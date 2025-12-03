// lib/services/identity_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'api_client.dart';

String canonicalLabel({
  String? firebaseUid,
  String? username,
  String? email,
}) {
  if (firebaseUid != null && firebaseUid.isNotEmpty) return firebaseUid;
  if (username != null && username.isNotEmpty) return username.trim();
  if (email != null && email.isNotEmpty) return email.toLowerCase().trim();
  throw StateError('No user identifier available');
}

final _store = const FlutterSecureStorage();
final api = Api();

Future<String> ensureIdentityForCurrentUser({
  String? firebaseUid,
  required String email,
  String? username,
}) async {
  final label = canonicalLabel(firebaseUid: firebaseUid, username: username, email: email);
  final cacheKey = 'displayAddress:$label';
  final cached = await _store.read(key: cacheKey);
  if (cached != null && cached.isNotEmpty) return cached;

  final reg = await api.registerIdentity(uid: label, email: email);
  if (reg['ok'] != true) {
    throw Exception('Register failed (${reg['status']}): ${reg['error'] ?? reg}');
  }
  final display = reg['displayAddress'] as String;

  // Don't block UX if link fails (just log server-side)
  await api.linkIdentity(
    uid: label,
    displayAddress: display,
    fingerprint: reg['fingerprint'] as String?,
    mspId: reg['mspId'] as String?,
  );

  await _store.write(key: cacheKey, value: display);

  // Store username mapping for friendly display
  if (username != null && username.isNotEmpty) {
    await _store.write(key: 'username:$display', value: username);
    await _store.write(key: 'walletToUsername:$display', value: username);
  } else {
    // Extract username from email if no explicit username
    final emailUsername = email.split('@').first;
    await _store.write(key: 'username:$display', value: emailUsername);
    await _store.write(key: 'walletToUsername:$display', value: emailUsername);
  }

  return display;
}

Future<String?> getCurrentUserWallet() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  final label = canonicalLabel(firebaseUid: user.uid);
  return _store.read(key: 'displayAddress:$label');
}

/// Get username for a given wallet address
Future<String?> getUsernameForWallet(String walletAddress) async {
  return _store.read(key: 'walletToUsername:$walletAddress');
}

/// Format wallet address in a user-friendly way: username_last4
/// Example: "mtilong_5b1d" instead of "0x27919a13fe1106fc09d4274715d74e2257a56b1d"
Future<String> formatFriendlyWallet(String walletAddress) async {
  if (walletAddress.isEmpty) return 'Unknown';

  // Try to get username for this wallet
  final username = await getUsernameForWallet(walletAddress);

  // Get last 4 characters of the wallet address
  final cleanAddress = walletAddress.startsWith('0x')
      ? walletAddress.substring(2)
      : walletAddress;
  final last4 = cleanAddress.length >= 4
      ? cleanAddress.substring(cleanAddress.length - 4)
      : cleanAddress;

  if (username != null && username.isNotEmpty) {
    return '${username}_$last4';
  } else {
    // Fallback: use "user" prefix if no username is found
    return 'user_$last4';
  }
}

/// Format wallet address in a user-friendly way (synchronous version for UI)
/// This is a best-effort approach that doesn't require async
String formatFriendlyWalletSync(String walletAddress, {String? knownUsername}) {
  if (walletAddress.isEmpty) return 'Unknown';

  // Get last 4 characters of the wallet address
  final cleanAddress = walletAddress.startsWith('0x')
      ? walletAddress.substring(2)
      : walletAddress;
  final last4 = cleanAddress.length >= 4
      ? cleanAddress.substring(cleanAddress.length - 4)
      : cleanAddress;

  if (knownUsername != null && knownUsername.isNotEmpty) {
    return '${knownUsername}_$last4';
  } else {
    // Fallback: use "user" prefix
    return 'user_$last4';
  }
}

class IdentityService {
  Future<String?> getDisplayAddress(String label) => _store.read(key: 'displayAddress:$label');
}