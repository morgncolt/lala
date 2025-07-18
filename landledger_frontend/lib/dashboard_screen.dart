import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

import 'package:landledger_frontend/home_screen.dart';
import 'package:landledger_frontend/my_properties_screen.dart';
import 'package:landledger_frontend/map_screen.dart';
import 'package:landledger_frontend/landledger_screen.dart';
import 'package:landledger_frontend/cif_screen.dart';
import 'package:landledger_frontend/settings_screen.dart';

// Simple model for navigation entries
class _NavEntry {
  final IconData icon;
  final String label;
  final Widget screen;

  const _NavEntry({required this.icon, required this.label, required this.screen});
}

class DashboardScreen extends StatefulWidget {
  final String regionKey;
  final String geojsonPath;
  final int initialTabIndex;

  const DashboardScreen({
    Key? key,
    required this.regionKey,
    required this.geojsonPath,
    this.initialTabIndex = 0,
  }) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Tracks which tab is selected
  int _selectedIndex = 0;
  bool _isRailExtended = false;
  bool _showMoreMenu = false;
  bool _isDarkMode = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedIndex = widget.initialTabIndex.clamp(0, 2);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Primary tabs: Home, My Properties, Map
    final primaryNavEntries = <_NavEntry>[
      _NavEntry(
        icon: Icons.home,
        label: 'Home',
        screen: HomeScreen(
          currentRegionKey: null, // 👈 this prevents the loop
          initialSelectedKey: widget.regionKey, // ✅ pass last selected region
          onRegionSelected: (key, path) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              print('🌍 Navigating to region: $key with $path');
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => DashboardScreen(
                    regionKey: key,
                    geojsonPath: path,
                    initialTabIndex: 0,
                  ),
                ),
              );
            });
          },
        ),

      ),
      _NavEntry(
        icon: Icons.list,
        label: 'My Properties',
        screen: MyPropertiesScreen(
          regionKey: widget.regionKey,
          geojsonPath: widget.geojsonPath,
        ),
      ),
      _NavEntry(
        icon: Icons.map,
        label: 'Map View',
        screen: MapScreen(
          regionKey: widget.regionKey,
          geojsonPath: widget.geojsonPath,
          centerOnRegion: true,
        ),
      ),
    ];

    // Secondary tabs under "More"
    final secondaryNavEntries = <_NavEntry>[
      const _NavEntry(
        icon: Icons.bar_chart,
        label: 'LandLedger',
        screen: Center(child: Text('LandLedger 🔜')),
      ),
      const _NavEntry(
        icon: Icons.assessment,
        label: 'CIF',
        screen: Center(child: Text('CIF 🔜')),
      ),
      const _NavEntry(
        icon: Icons.settings,
        label: 'Settings',
        screen: Center(child: Text('Settings 🔜')),
      ),
    ];

    // Build rail destinations dynamically
    final destinations = <NavigationRailDestination>[
      ...primaryNavEntries.map(
        (e) => NavigationRailDestination(
          icon: Icon(e.icon),
          label: Text(e.label),
        ),
      ),
      NavigationRailDestination(
        icon: Icon(_showMoreMenu ? Icons.expand_less : Icons.more_horiz),
        label: const Text('More'),
      ),
      if (_showMoreMenu)
        ...secondaryNavEntries.map(
          (e) => NavigationRailDestination(
            icon: Icon(e.icon),
            label: Text(e.label),
          ),
        ),
    ];

    // Clamp selected index
    final safeIndex = _selectedIndex < destinations.length ? _selectedIndex : 0;

    return Scaffold(
      body: Row(
        children: [
          Theme(
            data: Theme.of(context).copyWith(
              navigationRailTheme: NavigationRailThemeData(
                backgroundColor: Colors.white,
                elevation: 4,
                indicatorColor: Theme.of(context).primaryColor.withOpacity(0.15),
                indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                selectedIconTheme: IconThemeData(color: Theme.of(context).primaryColor, size: 28),
                unselectedIconTheme: IconThemeData(color: Colors.grey.shade600, size: 24),
                selectedLabelTextStyle: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w600),
                unselectedLabelTextStyle: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            child: NavigationRail(
              extended: _isRailExtended,
              minWidth: 56,
              minExtendedWidth: 120,
              labelType: NavigationRailLabelType.none,
              selectedIndex: safeIndex,
              onDestinationSelected: (i) {
                if (i == primaryNavEntries.length) {
                  setState(() => _showMoreMenu = !_showMoreMenu);
                } else {
                  setState(() {
                    _selectedIndex = i;
                    _showMoreMenu = false;
                  });
                }
              },
              leading: Column(
                children: [
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: Theme.of(context).primaryColor,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.terrain, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  IconButton(
                    icon: Icon(
                      _isRailExtended ? Icons.chevron_left : Icons.chevron_right,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () => setState(() => _isRailExtended = !_isRailExtended),
                  ),
                ],
              ),
              destinations: destinations,
              trailing: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () {
                    FirebaseAuth.instance.signOut();
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                ),
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: safeIndex < primaryNavEntries.length
                ? primaryNavEntries[safeIndex].screen
                : secondaryNavEntries[safeIndex - primaryNavEntries.length - 1].screen,
          ),
        ],
      ),
    
    );
  }
}
