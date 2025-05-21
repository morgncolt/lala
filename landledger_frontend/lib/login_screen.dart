import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final AuthService _authService = AuthService();

  String errorMessage = "";
  bool isSignUpMode = false;
  bool isPasswordVisible = false;

  Future<void> _submit() async {
    try {
      UserCredential userCredential;
      if (isSignUpMode) {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
        await userCredential.user?.updateDisplayName(nameController.text.trim());
      } else {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => DashboardScreen(initialTabIndex: 0)),
      );
    } catch (e) {
      _setErrorMessage("${isSignUpMode ? 'Sign-up' : 'Login'} failed: ${e.toString()}");
    }
  }

  Future<void> _signInWithGoogle() async {
    User? user = await _authService.signInWithGoogle();
    if (user != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => DashboardScreen(initialTabIndex: 0)),
      );
    } else {
      _setErrorMessage("Google Sign-In failed.");
    }
  }

  void _setErrorMessage(String message) {
    setState(() {
      errorMessage = message;
    });
  }

  Widget _buildErrorMessage() {
    if (errorMessage.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isSignUpMode ? "Create an Account" : "Welcome Back",
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isSignUpMode ? "Sign up to get started" : "Login to continue",
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  if (isSignUpMode)
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person),
                        labelText: "Full Name",
                        border: OutlineInputBorder(),
                      ),
                    ),

                  if (isSignUpMode) const SizedBox(height: 16),

                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.email),
                      labelText: "Email",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: passwordController,
                    obscureText: !isPasswordVisible,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock),
                      labelText: "Password",
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() => isPasswordVisible = !isPasswordVisible);
                        },
                      ),
                    ),
                  ),

                  _buildErrorMessage(),
                  const SizedBox(height: 16),

                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    child: Text(isSignUpMode ? "Sign Up" : "Login"),
                  ),

                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () {
                      setState(() {
                        isSignUpMode = !isSignUpMode;
                        errorMessage = "";
                      });
                    },
                    child: Text(
                      isSignUpMode
                          ? "Already have an account? Log in"
                          : "Don't have an account? Sign up",
                    ),
                  ),


                  const SizedBox(height: 12),
                  Row(children: const [Expanded(child: Divider()), Text(" OR "), Expanded(child: Divider())]),

                  const SizedBox(height: 12),

                  ElevatedButton.icon(
                    onPressed: _signInWithGoogle,
                    icon: Image.asset("assets/google_logo.png", height: 24),
                    label: const Text("Sign in with Google"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                  ),

                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () {
                      setState(() {
                        isSignUpMode = !isSignUpMode;
                        errorMessage = "";
                      });
                    },
                    child: Text(
                      isSignUpMode
                          ? "Already have an account? Log in"
                          : "Don't have an account? Sign up",
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