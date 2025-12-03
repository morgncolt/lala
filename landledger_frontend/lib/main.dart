import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'theme.dart';
import 'splash_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize error handlers first
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('dYs" Flutter error caught by onError: ${details.exception}');
      debugPrint('${details.stack}');
    };

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
    // --- Initialize App Check early (before any Firestore/Storage/Functions calls) ---
    // Android: use Debug during development (register the token in Firebase Console) and
    // Play Integrity in release. Web: use reCAPTCHA v3 (site key from .env).
    //
    // .env should contain:
    // FIREBASE_RECAPTCHA_V3_SITE_KEY=your_recaptcha_v3_site_key_here
    final recaptchaSiteKey = dotenv.env['FIREBASE_RECAPTCHA_V3_SITE_KEY'] ?? '';

    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.appAttestWithDeviceCheckFallback,
      webProvider: kIsWeb && recaptchaSiteKey.isNotEmpty
          ? ReCaptchaV3Provider(recaptchaSiteKey)
          : null, // safe no-op if not web or key missing
    );

    // Optional: ensure tokens refresh automatically
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    // (Optional but nice) Set auth UI language to remove the locale warning
    try {
      await FirebaseAuth.instance.setLanguageCode('en');
    } catch (_) {
      // ignore if not supported on this platform
    }
    // --- End App Check init ---

    runApp(const LandLedgerApp());
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
      home: const AuthGate(), // Use AuthGate as the entry point
      routes: {
        RouteConstants.splash: (context) => const SplashScreenWrapper(),
        RouteConstants.login: (context) => const LoginScreen(),
        RouteConstants.dashboard: (context) => DashboardScreen(
              regionId: 'united_states',
              geojsonPath: 'assets/data/united_states.geojson',
            ),
      },
      builder: (context, child) {
        // Handle render errors gracefully
        ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
          return Material(
            child: Container(
              color: Colors.red[100],
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Something went wrong',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Error: ${errorDetails.exception}',
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        };

        return FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: child!,
        );
      },
    );
  }
}

/// AuthGate: Continuously monitors Firebase auth state and routes accordingly
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _savedRegionId;
  String? _savedGeojsonPath;
  bool _isLoadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadSavedRegion();
  }

  Future<void> _loadSavedRegion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final regionId = prefs.getString('last_selected_region_id');
      final geojsonPath = prefs.getString('last_selected_geojson_path');

      if (mounted) {
        setState(() {
          _savedRegionId = regionId;
          _savedGeojsonPath = geojsonPath;
          _isLoadingPrefs = false;
        });
      }

      debugPrint('📍 Loaded saved region: ${_savedRegionId ?? "none (first launch)"}');
    } catch (e) {
      debugPrint('⚠️ Failed to load saved region: $e');
      if (mounted) {
        setState(() => _isLoadingPrefs = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if we should skip login (only in debug mode)
    final skipLogin = kDebugMode &&
                      (dotenv.env['SKIP_LOGIN_IN_DEBUG']?.toLowerCase() == 'true');

    if (skipLogin) {
      debugPrint('⚠️ DEBUG MODE: Auth gate bypassed (SKIP_LOGIN_IN_DEBUG=true)');
      return _buildDashboard();
    }

    // PRODUCTION: Always monitor auth state
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show splash while loading auth OR preferences
        if (snapshot.connectionState == ConnectionState.waiting || _isLoadingPrefs) {
          return const SplashScreen();
        }

        // Show login if no user
        if (!snapshot.hasData || snapshot.data == null) {
          debugPrint('🔐 No authenticated user - showing login');
          return const LoginScreen();
        }

        // User is authenticated - show dashboard
        final user = snapshot.data!;
        debugPrint('✅ Authenticated user: ${user.email ?? user.uid}');
        return _buildDashboard();
      },
    );
  }

  Widget _buildDashboard() {
    // If user has a saved region, use it
    if (_savedRegionId != null && _savedGeojsonPath != null) {
      return DashboardScreen(
        regionId: _savedRegionId!,
        geojsonPath: _savedGeojsonPath!,
      );
    }

    // First time user - let them choose via HomeScreen
    // HomeScreen will default to first region in list and save their choice
    return DashboardScreen(
      regionId: '',  // Empty = trigger region selection in HomeScreen
      geojsonPath: '',
    );
  }
}

class SplashScreenWrapper extends StatefulWidget {
  const SplashScreenWrapper({super.key});

  @override
  State<SplashScreenWrapper> createState() => _SplashScreenWrapperState();
}

class _SplashScreenWrapperState extends State<SplashScreenWrapper> {
  StreamSubscription<User?>? _sub;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    await Future.delayed(const Duration(seconds: 2));

    // Check if we should skip login (only in debug mode, controlled by env var)
    final skipLogin = kDebugMode &&
                      (dotenv.env['SKIP_LOGIN_IN_DEBUG']?.toLowerCase() == 'true');

    if (skipLogin) {
      debugPrint('⚠️ DEBUG MODE: Skipping login (SKIP_LOGIN_IN_DEBUG=true)');
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(RouteConstants.dashboard);
      return;
    }

    // PRODUCTION & DEPLOYMENT: Always require Firebase authentication
    _sub = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (!mounted) return;
      debugPrint('🔐 Auth state changed: ${user != null ? "Logged in (${user.email})" : "Logged out"}');
      Navigator.of(context).pushReplacementNamed(
        user == null ? RouteConstants.login : RouteConstants.dashboard,
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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
