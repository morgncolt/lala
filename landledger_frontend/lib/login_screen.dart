import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController    = TextEditingController();
  final passwordController = TextEditingController();
  final nameController     = TextEditingController();

  bool _isSigningIn      = false;
  String errorMessage    = "";
  bool isSignUpMode      = false;
  bool isPasswordVisible = false;

  /// Guarded Google sign-in handler
  Future<void> _handleGoogleSignIn() async {
    if (_isSigningIn) return;
    setState(() => _isSigningIn = true);

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // user cancelled
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken:     googleAuth.idToken,
      );

      final userCred = await FirebaseAuth.instance
          .signInWithCredential(credential);

      if (userCred.user != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const DashboardScreen(
              regionKey:      "Cameroon",
              geojsonPath:    "assets/cameroon.geojson",
              initialTabIndex: 0,
            ),
          ),
        );
      }
    } catch (e) {
      _setErrorMessage("Google Sign-In failed: $e");
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _submitEmailPassword() async {
    try {
      late UserCredential userCred;
      if (isSignUpMode) {
        userCred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email:    emailController.text.trim(),
              password: passwordController.text.trim(),
            );
        await userCred.user
            ?.updateDisplayName(nameController.text.trim());
      } else {
        userCred = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email:    emailController.text.trim(),
              password: passwordController.text.trim(),
            );
      }

      if (userCred.user != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const DashboardScreen(
              regionKey:      "Cameroon",
              geojsonPath:    "assets/cameroon.geojson",
              initialTabIndex: 0,
            ),
          ),
        );
      }
    } catch (e) {
      _setErrorMessage(
        "${isSignUpMode ? 'Sign-up' : 'Login'} failed: $e",
      );
    }
  }

  void _setErrorMessage(String msg) {
    setState(() => errorMessage = msg);
  }

  Widget _buildErrorMessage() {
    return errorMessage.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          child: Card(
            elevation: 8,
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize:    MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isSignUpMode ? "Create an Account" : "Welcome Back",
                    style: const TextStyle(
                      fontSize:    24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isSignUpMode
                        ? "Sign up to get started"
                        : "Login to continue",
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  if (isSignUpMode) ...[
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person),
                        labelText:  "Full Name",
                        border:     OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.email),
                      labelText:  "Email",
                      border:     OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: passwordController,
                    obscureText: !isPasswordVisible,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock),
                      labelText:  "Password",
                      border:     const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            isPasswordVisible = !isPasswordVisible;
                          });
                        },
                      ),
                    ),
                  ),

                  _buildErrorMessage(),
                  const SizedBox(height: 16),

                  ElevatedButton(
                    onPressed: _submitEmailPassword,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                    child: Text(
                      isSignUpMode ? "Sign Up" : "Login",
                    ),
                  ),

                  TextButton(
                    onPressed: () {
                      setState(() {
                        isSignUpMode  = !isSignUpMode;
                        errorMessage  = "";
                      });
                    },
                    child: Text(
                      isSignUpMode
                          ? "Already have an account? Log in"
                          : "Don't have an account? Sign up",
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: const [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text("OR"),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),

                  ElevatedButton.icon(
                    onPressed: _isSigningIn ? null : _handleGoogleSignIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _isSigningIn
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : Image.asset(
                            "assets/google_logo.png",
                            height: 24,
                          ),
                    label: Text(
                      _isSigningIn ? 'Signing in…' : 'Sign in with Google',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
