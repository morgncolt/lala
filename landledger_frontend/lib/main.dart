import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'firebase_options.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'theme.dart';
import 'splash_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }

    runApp(const LandLedgerApp());
  }, (Object error, StackTrace stackTrace) {
    debugPrint('🚨 Uncaught zone error: $error');
    debugPrint('$stackTrace');
  });

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🚨 Flutter error caught by onError: ${details.exception}');
    debugPrint('${details.stack}');
  };
}

class LandLedgerApp extends StatelessWidget {
  const LandLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LandLedger Africa',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),

      // ✅ Corrected: only ONE widget in `home:`
      home: const SplashScreenWrapper(),

      builder: (context, child) {
        return FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Overlay(
            initialEntries: [
              OverlayEntry(builder: (_) => child!),
            ],
          ),
        );
      },
    );
  }
}

class SplashScreenWrapper extends StatefulWidget {
  const SplashScreenWrapper({super.key});

  @override
  State<SplashScreenWrapper> createState() => _SplashScreenWrapperState();
}

class _SplashScreenWrapperState extends State<SplashScreenWrapper> {
  bool _showAuthScreen = false;

  @override
  void initState() {
    super.initState();
    _startSplashDelay();
  }

  void _startSplashDelay() async {
    await Future.delayed(const Duration(seconds: 5));
    if (mounted) {
      setState(() => _showAuthScreen = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_showAuthScreen) {
      return const SplashScreen();
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator(color: Color.fromARGB(255, 2, 2, 2))),
          );
        }
        if (snapshot.hasData) {
          return const DashboardScreen(
            regionId: 'Cameroon',
            geojsonPath: 'assets/data/cameroon.geojson',
          );
        }
        return const LoginScreen();
      },
    );
  }
}
