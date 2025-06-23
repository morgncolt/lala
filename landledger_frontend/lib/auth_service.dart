import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    //clientId: "829972798062-j97p91tqtc5nlvqu1pv9hrnvd2nae7vh.apps.googleusercontent.com", // Ensure client ID is correct
    clientId: "829972798062-iujmhdiulvkdalmqvecmvkrrngk4r51m.apps.googleusercontent.com", // Ensure client ID is correct

  );

  AuthService() {
    _initializePersistence();
  }

  /// Sets persistence mode for the user session.
  Future<void> _initializePersistence() async {
    if (kIsWeb) {
      try {
        await _auth.setPersistence(Persistence.LOCAL); // Keeps user session persistent on web.
      } catch (e) {
        debugPrint("Error setting persistence: $e");
      }
    }
  }

  /// Checks if a user is currently logged in.
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  /// Sign up a new user with email, password, and name.
  Future<User?> signUp(String email, String password, String name) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      await userCredential.user?.updateDisplayName(name.trim());
      return userCredential.user;
    } catch (e) {
      debugPrint("Sign-Up Error: $e");
      return null;
    }
  }

  /// Log in a user with email and password.
  Future<User?> login(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return userCredential.user;
    } catch (e) {
      debugPrint("Login Error: $e");
      return null;
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        debugPrint("Google Sign-In was canceled by the user.");
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);

      debugPrint("Google Sign-In successful: ${userCredential.user?.displayName}");

      return userCredential.user;
    } catch (e) {
      debugPrint("Google Sign-In Error: $e");
      return null;
    }
  }


  /// Log out the current user.
  Future<void> logout() async {
    try {
      if (kIsWeb) {
        // Web-specific logout (Firebase only)
        await _auth.signOut();
      } else {
        // Mobile logout (Firebase + Google)
        await _googleSignIn.signOut();
        await _auth.signOut();
      }
      debugPrint("User successfully logged out.");
    } catch (e) {
      debugPrint("Logout Error: $e");
    }
  }
}
