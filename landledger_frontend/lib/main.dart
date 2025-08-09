import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
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
      rethrow;
    }

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final mockService = MockEthereumService();

    runApp(
      MultiProvider(
        providers: [
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

class RouteConstants {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String dashboard = '/dashboard';
}

class LandLedgerApp extends StatelessWidget {
  const LandLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LandLedger',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      initialRoute: RouteConstants.splash,
      routes: {
        RouteConstants.splash: (context) => const SplashScreenWrapper(),
        RouteConstants.login: (context) => const LoginScreen(),
        RouteConstants.dashboard: (context) => DashboardScreen(
              regionId: 'default_region',
              geojsonPath: 'assets/geojson/default.json',
            ),
      },
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
  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    await Future.delayed(const Duration(seconds: 2));
    
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(
          user == null ? RouteConstants.login : RouteConstants.dashboard,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}

class RouteGuard {
  static String? redirect(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final route = ModalRoute.of(context)?.settings.name;
    
    if (user == null && route != RouteConstants.login) {
      return RouteConstants.login;
    }
    
    if (user != null && route == RouteConstants.login) {
      return RouteConstants.dashboard;
    }
    
    return null;
  }
}