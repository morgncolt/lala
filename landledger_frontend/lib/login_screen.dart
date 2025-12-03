import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import 'dashboard_screen.dart';
import 'services/identity_service.dart';
import 'utils/render_utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController    = TextEditingController();
  final passwordController = TextEditingController();
  final nameController     = TextEditingController();
  final usernameController = TextEditingController();
  final phoneController    = TextEditingController();
  final codeController     = TextEditingController();

  bool _isSigningInGoogle = false;
  bool _isSigningInEmail  = false;
  bool isSignUpMode       = false;
  bool isPhoneSignUp      = false;
  bool isPasswordVisible  = false;
  bool isCodeSent         = false;
  String verificationId   = '';
  bool _isVerifyingPhone  = false;
  String fullPhoneNumber  = "";
  String errorMessage     = "";

  // Web-specific phone auth
  ConfirmationResult? _webPhoneConfirmation;

  // ---- Configure your API base here (matches your server.js) ----
  // Android emulator uses 10.0.2.2; web/desktop/iOS sim uses localhost.
  String get apiBase {
    // Use localhost for all platforms (ADB reverse port forwarding handles Android connectivity)
    return 'http://localhost:4000';
  }

  // Note: Fabric identity provisioning is now handled by ensureIdentityForCurrentUser
  // which calls the correct /api/identity/me endpoint

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isSigningInGoogle) return;
    setState(() => _isSigningInGoogle = true);

    try {
      UserCredential userCred;

      if (kIsWeb) {
        // Web: use popup
        final provider = GoogleAuthProvider();
        userCred = await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        // Mobile: use google_sign_in package
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return; // user cancelled
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken:     googleAuth.idToken,
        );
        userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      final user = userCred.user;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final username = doc.data()?['username'] as String?;
        final display = await ensureIdentityForCurrentUser(
          firebaseUid: user.uid,
          email: user.email ?? 'no-email',
          username: username,
        );
        _toast('Identity registered: $display');
        _goToDashboard();
      }
    } catch (e) {
      _setErrorMessage("Google Sign-In failed: $e");
    } finally {
      if (mounted) setState(() => _isSigningInGoogle = false);
    }
  }

  Future<void> _submitEmailPassword() async {
    if (_isSigningInEmail) return;

    // Basic validation
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _setErrorMessage("Please fill in all fields");
      return;
    }

    setState(() => _isSigningInEmail = true);

    try {
      late UserCredential userCred;
      if (isSignUpMode) {
        userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email:    email,
          password: password,
        );
        await userCred.user?.updateDisplayName(nameController.text.trim());
        // Store username mapping (normalize to lowercase)
        await FirebaseFirestore.instance.collection('usernames').doc(usernameController.text.trim().toLowerCase()).set({
          'uid': userCred.user!.uid,
          'email': userCred.user!.email ?? 'no-email',
        });
      } else {
        // Login
        final input = email;
        if (input.contains('@')) {
          // Treat as email (for backward compatibility)
          userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email:    input,
            password: password,
          );
        } else {
          // Treat as username (normalize to lowercase for lookup)
          final doc = await FirebaseFirestore.instance.collection('usernames').doc(input.toLowerCase()).get();
          if (!doc.exists) throw 'Username not found';
          final data = doc.data();
          if (data == null || !data.containsKey('email')) throw 'Username mapping incomplete';
          final email = data['email'] as String?;
          if (email == null || email.isEmpty) throw 'Username email is missing or empty';
          userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email:    email,
            password: passwordController.text.trim(),
          );
        }
      }

      final user = userCred.user;
      if (user != null) {
        final display = await ensureIdentityForCurrentUser(
          firebaseUid: user.uid,
          email: user.email ?? 'no-email',
          username: isSignUpMode ? usernameController.text.trim() : null,
        );
        // Show it in UI
        _toast('Identity registered: $display');
        _goToDashboard();
      }
    } catch (e) {
      _setErrorMessage(
        "${isSignUpMode ? 'Sign-up' : 'Login'} failed: $e",
      );
    } finally {
      if (mounted) setState(() => _isSigningInEmail = false);
    }
  }

  Future<void> _handlePhoneSignUp() async {
    if (_isVerifyingPhone) return;
    setState(() => _isVerifyingPhone = true);

    try {
      if (kIsWeb) {
        // Web: get confirmation result then show code field
        _webPhoneConfirmation =
            await FirebaseAuth.instance.signInWithPhoneNumber(fullPhoneNumber);
        setState(() => isCodeSent = true);
      } else {
        // Mobile: your existing flow
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: fullPhoneNumber,
          verificationCompleted: (PhoneAuthCredential credential) async {
            final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
            final user = userCred.user;
            if (user != null) {
              await user.updateDisplayName(nameController.text.trim());
              final display = await ensureIdentityForCurrentUser(
                firebaseUid: user.uid,
                email: user.email ?? user.phoneNumber ?? 'phone_user',
                username: usernameController.text.trim(),
              );
              _toast('Identity registered: $display');
              _goToDashboard();
            }
          },
          verificationFailed: (FirebaseAuthException e) {
            _setErrorMessage("Phone verification failed: ${e.message}");
          },
          codeSent: (String verificationId, int? resendToken) {
            setState(() {
              this.verificationId = verificationId;
              isCodeSent = true;
            });
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            this.verificationId = verificationId;
          },
        );
      }
    } catch (e) {
      _setErrorMessage("Phone sign up failed: $e");
    } finally {
      if (mounted) setState(() => _isVerifyingPhone = false);
    }
  }

  Future<void> _verifyPhoneCode() async {
    if (_isVerifyingPhone) return;
    setState(() => _isVerifyingPhone = true);

    try {
      UserCredential userCred;

      if (kIsWeb) {
        if (_webPhoneConfirmation == null) {
          throw 'No pending phone confirmation on web.';
        }
        userCred = await _webPhoneConfirmation!.confirm(codeController.text.trim());
      } else {
        final credential = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: codeController.text.trim(),
        );
        userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      final user = userCred.user;
      if (user != null) {
        await user.updateDisplayName(nameController.text.trim());
        final display = await ensureIdentityForCurrentUser(
          firebaseUid: user.uid,
          email: user.email ?? user.phoneNumber ?? 'phone_user',
          username: usernameController.text.trim(),
        );
        _toast('Identity registered: $display');
        _goToDashboard();
      }
    } catch (e) {
      _setErrorMessage("Code verification failed: $e");
    } finally {
      if (mounted) setState(() => _isVerifyingPhone = false);
    }
  }

  void _goToDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const DashboardScreen(
          regionId:        "Cameroon",
          geojsonPath:     "assets/data/cameroon.geojson",
          initialTabIndex: 0,
        ),
      ),
    );
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
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    usernameController.dispose();
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_isSigningInEmail && !_isSigningInGoogle && !_isVerifyingPhone;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: RenderUtils.safeAreaWrapper(
        Center(
          child: SingleChildScrollView(
            child: RenderUtils.constrainedWrapper(
              Card(
                elevation: 8,
                margin: RenderUtils.getResponsiveMargin(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: RenderUtils.getResponsivePadding(context),
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

                      if (isSignUpMode) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() => isPhoneSignUp = false),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: !isPhoneSignUp ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
                                ),
                                child: const Text("Email"),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() => isPhoneSignUp = true),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isPhoneSignUp ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
                                ),
                                child: const Text("Phone"),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (isSignUpMode) ...[
                        TextField(
                          controller: nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.person),
                            labelText: "Full Name",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        TextField(
                          controller: usernameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.account_circle),
                            labelText: "Username",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (!isSignUpMode || !isPhoneSignUp) ...[
                        TextField(
                          controller: emailController,
                          keyboardType: isSignUpMode && !isPhoneSignUp ? TextInputType.emailAddress : TextInputType.text,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            prefixIcon: Icon(isSignUpMode && !isPhoneSignUp ? Icons.email : Icons.account_circle),
                            labelText: isSignUpMode && !isPhoneSignUp ? "Email" : "Email or Username",
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        TextField(
                          controller: passwordController,
                          enabled: !(isSignUpMode && isPhoneSignUp), // Disable when phone signup (password not used)
                          obscureText: !isPasswordVisible,
                          onSubmitted: (_) => canSubmit ? (isCodeSent ? _verifyPhoneCode() : (isSignUpMode && isPhoneSignUp ? _handlePhoneSignUp() : _submitEmailPassword())) : null,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock),
                            labelText: "Password",
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => isPasswordVisible = !isPasswordVisible),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (isSignUpMode && isPhoneSignUp) ...[
                        IntlPhoneField(
                          controller: phoneController,
                          decoration: const InputDecoration(
                            labelText: "Phone Number",
                            border: OutlineInputBorder(),
                          ),
                          initialCountryCode: 'US',
                          onChanged: (phone) {
                            fullPhoneNumber = phone.completeNumber;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (isCodeSent) ...[
                        TextField(
                          controller: codeController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.code),
                            labelText: "Verification Code",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      _buildErrorMessage(),
                      const SizedBox(height: 16),

                      ElevatedButton(
                        onPressed: canSubmit ? (isCodeSent ? _verifyPhoneCode : (isSignUpMode && isPhoneSignUp ? _handlePhoneSignUp : _submitEmailPassword)) : null,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                        child: (_isSigningInEmail || _isVerifyingPhone)
                            ? const SizedBox(
                                height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(isCodeSent ? "Verify Code" : (isSignUpMode && isPhoneSignUp ? "Send Code" : (isSignUpMode ? "Sign Up" : "Login"))),
                      ),

                      TextButton(
                        onPressed: () {
                          setState(() {
                            isSignUpMode = !isSignUpMode;
                            isPhoneSignUp = false;
                            errorMessage = "";
                            isCodeSent = false;
                            verificationId = '';
                            usernameController.clear();
                            phoneController.clear();
                            codeController.clear();
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
                        onPressed: canSubmit ? _handleGoogleSignIn : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _isSigningInGoogle
                            ? const SizedBox(
                                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Image.asset("assets/google_logo.png", height: 24),
                        label: Text(
                          _isSigningInGoogle ? 'Signing in…' : 'Sign in with Google',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
