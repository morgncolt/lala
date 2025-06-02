import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:landledger_frontend/dashboard_screen.dart';
import 'package:landledger_frontend/map_screen.dart';
import 'package:landledger_frontend/my_properties_screen.dart';
import 'package:landledger_frontend/theme.dart';
import 'login_screen.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
      builder: (context, child) {
        return Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => Stack(
              children: [
                child!,
                Positioned(
                  top: 40,
                  right: 16,
                  child: Tooltip(
                    message: 'Toggle Theme',
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.grey[800],
                      foregroundColor: Colors.white,
                      onPressed: () => setState(() => isDarkMode = !isDarkMode),
                      child: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasData) {
            return DashboardScreen(
              regionKey: "Cameroon",
              geojsonPath: "assets/data/cameroon.geojson",
              initialTabIndex: 0,
            );
          } else {
            return LoginScreen();
          }
        },
      ),
    );
   
  }
}
