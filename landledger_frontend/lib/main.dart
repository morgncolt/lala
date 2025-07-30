import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'login_screen.dart';
import 'theme.dart';
import 'splash_screen.dart';
import 'mock_euthereumservice.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize error handlers first
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🚨 Flutter error caught by onError: ${details.exception}');
    debugPrint('${details.stack}');
  };

  await runZonedGuarded(() async {
    // Load environment variables
    try {
      await dotenv.load(fileName: ".env");
    } catch (e) {
      debugPrint("⚠️ Could not load .env file: $e");
      rethrow; // Important to rethrow so we know initialization failed
    }

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final mockService = MockEthereumService();

    runApp(
      MultiProvider(
        providers: [
          // Provide the already initialized service
          ChangeNotifierProvider.value(value: mockService),
        ],
        child: const LandLedgerApp(),
      ),
    );
  }, (error, stackTrace) {
    debugPrint('🚨 Uncaught zone error: $error');
    debugPrint('$stackTrace');
  });
}

class LandLedgerApp extends StatelessWidget {
  const LandLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LandLedger Africa',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
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
  bool _showLogin = false;

  @override
  void initState() {
    super.initState();
    _startSplashDelay();
  }

  void _startSplashDelay() async {
    await Future.delayed(const Duration(seconds: 5));
    if (mounted) {
      setState(() => _showLogin = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _showLogin ? const LoginScreen() : const SplashScreen();
  }
}