// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  runApp(const LandLedgerApp());
}

class LandLedgerApp extends StatefulWidget {
  const LandLedgerApp({super.key});

  @override
  State<LandLedgerApp> createState() => _LandLedgerAppState();
}

class _LandLedgerAppState extends State<LandLedgerApp> {
  bool isDarkMode = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LandLedger Africa',
      debugShowCheckedModeBanner: false,
      theme: isDarkMode ? buildDarkTheme() : buildLightTheme(),

      // Named routes for navigation if you need them:
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/dashboard': (_) => const DashboardScreen(
              regionKey: 'Cameroon',
              geojsonPath: 'assets/data/cameroon.geojson',
            ),
      },

      // Wrap your entire app in a real Overlay so Tooltip can work:
      builder: (context, child) {
        return FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(), // prevents crash on focus sorting
          child: Overlay(
            initialEntries: [
              OverlayEntry(builder: (_) => child!),
              // OverlayEntry(builder: (_) {
              //   return Positioned(
              //     top: 16,
              //     right: 16,
              //     child: Tooltip(
              //       message: 'Toggle Theme',
              //       child: FloatingActionButton.small(
              //         backgroundColor: Theme.of(context).colorScheme.surface,
              //         onPressed: () => setState(() => isDarkMode = !isDarkMode),
              //         child: Icon(
              //           isDarkMode ? Icons.light_mode : Icons.dark_mode,
              //           size: 20,
              //         ),
              //       ),
              //     ),
              //   );
              // }),
            ],
          ),
        );
      },

      // Drive initial screen by auth state:
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return const DashboardScreen(
              regionKey: 'Cameroon',
              geojsonPath: 'assets/data/cameroon.geojson',
            );
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
