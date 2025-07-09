import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Generates Google Maps Static Image URL
  String generateGoogleMapsImage(double latitude, double longitude) {
    const String apiKey = "AIzaSyBXK2rKSdBuWXUXgvdZqnm_LP3x5e3VgDQ"; // 🔴 Replace with a secure method!
    return "https://maps.googleapis.com/maps/api/staticmap?"
        "center=$latitude,$longitude"
        "&zoom=15"
        "&size=600x300"
        "&maptype=roadmap"
        "&markers=color:red%7Clabel:L%7C$latitude,$longitude"
        "&key=$apiKey";
  }

  /// Adds a new land record to Firestore
  Future<void> addLandRecord(double latitude, double longitude, double size, String documentUrl) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User is not logged in!");

      // Retrieve user's first and last name from Firebase profile
      String firstName = user.displayName?.split(" ").first ?? "Unknown";
      String lastName = user.displayName?.split(" ").last ?? "User";

      // Generate Google Maps Image URL
      String mapsImageUrl = generateGoogleMapsImage(latitude, longitude);

      // Store record in Firestore
      await _db.collection("landRecords").add({
        "uid": user.uid,
        "firstName": firstName,
        "lastName": lastName,
        "latitude": latitude,
        "longitude": longitude,
        "size": size,
        "documentUrl": documentUrl,
        "mapsImageUrl": mapsImageUrl,
        "timestamp": FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error adding land record: $e");
      throw Exception("Failed to add land record.");
    }
  }

  /// Fetches only the current user's land records
  Stream<QuerySnapshot> getUserLandRecords() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    print("Current User UID: ${user.uid}");

    return _db
        .collection("landRecords")
        .where("uid", isEqualTo: user.uid) // Fetch only current user's records
        .orderBy("timestamp", descending: true)
        .snapshots();
  }

  /// Deletes a land record from Firestore
  Future<void> deleteLandRecord(String documentId) async {
    try {
      DocumentSnapshot record = await _db.collection("landRecords").doc(documentId).get();
      if (record.exists && record["uid"] == _auth.currentUser?.uid) {
        await _db.collection("landRecords").doc(documentId).delete();
      } else {
        throw Exception("You can only delete your own land records.");
      }
    } catch (e) {
      debugPrint("Error deleting land record: $e");
      throw Exception("Failed to delete land record.");
    }
  }
}
