import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'theme.dart'; // 👈 This is your theme file that contains buildDarkTheme()
import 'dart:async';


void main() async {

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🚨 Flutter error caught by onError: ${details.exception}');
    debugPrint('${details.stack}');
  };


  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  

    runZonedGuarded(() {
    runApp(LandLedgerApp());
  }, (Object error, StackTrace stackTrace) {
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

      // ✅ Apply your dark theme correctly
      theme: buildDarkTheme(),

      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/dashboard': (_) => const DashboardScreen(
              regionId: 'Cameroon',
              geojsonPath: 'assets/data/cameroon.geojson',
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
              regionId: 'Cameroon',
              geojsonPath: 'assets/data/cameroon.geojson',
            );
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
