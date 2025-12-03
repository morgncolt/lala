import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:landledger_frontend/my_properties_screen.dart';
import 'package:landledger_frontend/map_screen.dart';
import 'package:landledger_frontend/landledger_screen.dart';
import 'package:landledger_frontend/settings_screen.dart';

import 'package:landledger_frontend/home_screen.dart';
import 'package:landledger_frontend/cif_screen.dart';
import 'widgets/responsive_text.dart';
import 'routes.dart';
import 'services/identity_service.dart';



class DashboardScreen extends StatefulWidget {
  final String regionId;
  final String geojsonPath;
  final int initialTabIndex;
  final void Function(String regionId, String geojsonPath)? onRegionSelected;

  const DashboardScreen({
    super.key,
    required this.regionId,
    required this.geojsonPath,
    this.initialTabIndex = 0,
    this.onRegionSelected,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  String? _selectedRegionId;
  String? _geojsonPath;
  final bool _isDrawerOpen = false;
  late final List<NavigationItem> _navigationItems;
  late final Map<String, int> _navIndexLookup;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final ValueNotifier<Map<String, dynamic>?> blockchainDataNotifier;

  // Current user identity
  String? _currentUserId;
  String? _currentUserWallet;

  @override
  void initState() {
    super.initState(); // ✅ This must come first
    blockchainDataNotifier = ValueNotifier(null); // ✅ Must be initialized before use
    _navigationItems = _buildNavigationItems();
    _navIndexLookup = {
      for (var i = 0; i < _navigationItems.length; i++) _navigationItems[i].label: i,
    };
    _selectedIndex = widget.initialTabIndex.clamp(0, _navigationItems.length - 1);
    _selectedRegionId = widget.regionId;
    _geojsonPath = widget.geojsonPath;

    // Initialize current user identity
    _initializeUserIdentity();
  }

  Future<void> _initializeUserIdentity() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      try {
        _currentUserWallet = await getCurrentUserWallet();
        debugPrint('Dashboard: Loaded wallet: $_currentUserWallet');
      } catch (e) {
        debugPrint('Dashboard: Failed to load wallet: $e');
        _currentUserWallet = null;
      }
      debugPrint('Dashboard: Current user ID: $_currentUserId');
      debugPrint('Dashboard: Current user wallet: $_currentUserWallet');
      if (mounted) setState(() {});
    } else {
      debugPrint('Dashboard: No authenticated user');
      // Fallback to demo credentials if no user is logged in
      _currentUserId = 'demo_user_001';
      _currentUserWallet = '0x742d35Cc6635C0532925a3b8D0007d1b7d9Ea5F1';
      debugPrint('Dashboard: Using demo user ID: $_currentUserId');
      debugPrint('Dashboard: Using demo user wallet: $_currentUserWallet');
      if (mounted) setState(() {});
    }
  }

  void _openHomeWithBackToHome() {
    setState(() {
      _selectedIndex = 0; // Switch to Home tab
      _selectedRegionId = widget.regionId; // Ensure region is set
      _geojsonPath = widget.geojsonPath; // Ensure geojson path is set
    });
  }

  void _openMyPropertiesWithBackToHome() {
    setState(() {
      _selectedIndex = 0; // Switch to My Properties tab
      _selectedRegionId = widget.regionId; // Ensure region is set
      _geojsonPath = widget.geojsonPath; // Ensure geojson path is set
    });
  }

  void _openMapForSelectedRegion() {
    final mapIndex = _navIndexLookup['Map'];
    if (mapIndex == null) {
      debugPrint('Dashboard: Map tab missing from navigation.');
      return;
    }
    setState(() {
      _selectedIndex = mapIndex;
      _selectedRegionId ??= widget.regionId;
      _geojsonPath ??= widget.geojsonPath;
    });
  }

  void _openCifWithBackToHome() {
    setState(() {
      _selectedIndex = 4; // Switch to CIF tab
    });
  }
  
  void _openLandLedgerWithBackToHome() {
    setState(() {
      _selectedIndex = 3; // Switch to LandLedger tab
    });
  }

  void updateBlockchainDataAndNavigate(Map<String, dynamic> record) {
    blockchainDataNotifier.value = record;
    setState(() {
      _selectedIndex = 3;
    });
  }

  List<NavigationItem> _buildNavigationItems() {
    return [
      NavigationItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_filled,
        label: 'Home',
        builder: (context, regionId, geojsonPath) => HomeScreen(
          key: const ValueKey('home_screen'),
          currentRegionId: regionId ?? widget.regionId,
          initialSelectedId: regionId ?? widget.regionId,
          onRegionSelected: _onRegionSelected,
          onGoToMap: _openMapForSelectedRegion,
        ),
      ),
      NavigationItem(
        icon: Icons.list_alt_outlined,
        activeIcon: Icons.list_alt,
        label: 'Properties',
        builder: (context, regionId, geojsonPath) => MyPropertiesScreen(
          regionId: regionId ?? widget.regionId,
          geojsonPath: geojsonPath ?? widget.geojsonPath,
          onBackToHome: _openMyPropertiesWithBackToHome,
          showBackArrow: true,
          onBlockchainRecordSelected: updateBlockchainDataAndNavigate,
        ),
      ),
      NavigationItem(
        icon: Icons.map_outlined,
        activeIcon: Icons.map,
        label: 'Map',
        builder: (context, regionId, geojsonPath) => MapScreen(
          regionId: regionId ?? widget.regionId,
          geojsonPath: geojsonPath ?? widget.geojsonPath,
          openedFromTab: true,
          onRegionSelected: _onRegionSelected,
          onOpenMyProperties: _openHomeWithBackToHome,
          showBackArrow: true,
        ),
      ),
      NavigationItem(
        icon: Icons.analytics_outlined,
        activeIcon: Icons.analytics,
        label: 'LandLedger',
        builder: (context, _, __) => LandledgerScreen(
          blockchainDataNotifier: blockchainDataNotifier,
          currentOwnerId: _currentUserId,
          currentWalletAddress: _currentUserWallet,
        ),
        onTap: _openLandLedgerWithBackToHome,
      ),
      NavigationItem(
        icon: Icons.assessment_outlined,
        activeIcon: Icons.assessment,
        label: 'CIF',
        builder: (context, _, __) => const CifScreen(),
        onTap: _openCifWithBackToHome,
      ),
    ];
  }

  void _onRegionSelected(String regionId, String geojsonPath) {
    setState(() {
      _selectedRegionId = regionId;
      _geojsonPath = geojsonPath;
    });
    widget.onRegionSelected?.call(regionId, geojsonPath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLargeScreen = MediaQuery.of(context).size.width > 800;
    final allDestinations = [
      ..._navigationItems,
      NavigationItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: 'Settings',
        builder: (_, __, ___) => const SettingsScreen(),
      ),
      NavigationItem(
        icon: Icons.logout,
        activeIcon: Icons.logout,
        label: 'Logout',
        builder: (_, __, ___) => Container(),
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      appBar: isLargeScreen
          ? null
          : AppBar(
              title: Text(_navigationItems[_selectedIndex].label),
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
            ),
      drawer: isLargeScreen ? null : _buildMobileDrawer(theme),
      body: SafeArea(
        child: Row(
          children: [
            if (isLargeScreen) _buildDesktopSidebar(theme),
            Expanded(
              child: _navigationItems[_selectedIndex].builder(
                context,
                _selectedRegionId ?? widget.regionId,
                _geojsonPath ?? widget.geojsonPath,
              ),
            ),

          ],
        ),
      ),

    );
  }

  Widget _buildDesktopSidebar(ThemeData theme) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildLogoHeader(theme),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _navigationItems.length,
                itemBuilder: (context, index) {
                  final item = _navigationItems[index];
                  return _buildSidebarItem(theme, item, index);
                },
              ),
            ),
            const Divider(),
            _buildSidebarItem(
              theme,
              NavigationItem(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: 'Settings',
                builder: (_, __, ___) => const SettingsScreen(),
              ),
              _navigationItems.length,
            ),
            // In both _buildDesktopSidebar and _buildMobileDrawer methods:
            _buildSidebarItem(
              theme,
              NavigationItem(
                icon: Icons.logout,
                activeIcon: Icons.logout,
                label: 'Logout',
                builder: (_, __, ___) => Container(),
                onTap: () async {
                  try {
                    await FirebaseAuth.instance.signOut();
                    if (mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        RouteConstants.login,  // Using the constant from main.dart
                        (Route<dynamic> route) => false,  // Remove all routes
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Logout failed: ${e.toString()}')),
                      );
                    }
                  }
                },
              ),
              _navigationItems.length + 1,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDrawer(ThemeData theme) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _buildDrawerHeader(theme),
            Expanded(
              child: ListView.builder(
                itemCount: _navigationItems.length,
                itemBuilder: (context, index) {
                  final item = _navigationItems[index];
                  return _buildDrawerItem(theme, item, index);
                },
              ),
            ),
            const Divider(),
            _buildDrawerItem(
              theme,
              NavigationItem(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: 'Settings',
                builder: (_, __, ___) => const SettingsScreen(),
              ),
              _navigationItems.length,
            ),
            _buildDrawerItem(
              theme,
              NavigationItem(
                icon: Icons.logout,
                activeIcon: Icons.logout,
                label: 'Logout',
                builder: (_, __, ___) => Container(),
                onTap: () {
                  FirebaseAuth.instance.signOut();
                  Navigator.pushReplacementNamed(context, '/login');
                },
              ),
              _navigationItems.length + 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerHeader(ThemeData theme) {
    return DrawerHeader(
      decoration: BoxDecoration(
        color: theme.primaryColor.withOpacity(0.1),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: theme.primaryColor,
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(8),
                child: Image.asset(
                  'assets/images/landledger_logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'LandLedger',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: theme.primaryColor,
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(6),
              child: Image.asset(
                'assets/images/land.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'LandLedger',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(ThemeData theme, NavigationItem item, int index) {
    final isSelected = _selectedIndex == index;
    final isSettings = index == _navigationItems.length;
    final isLogout = index == _navigationItems.length + 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? theme.primaryColor.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          isSelected ? item.activeIcon : item.icon,
          color: isSelected ? theme.primaryColor : theme.iconTheme.color,
        ),
        title: ResponsiveText(
          item.label,
          style: TextStyle(
            color: isSelected ? theme.primaryColor : theme.textTheme.bodyLarge?.color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          maxLines: 1,
        ),
        onTap: () {
          if (isSettings) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          } else if (isLogout) {
            FirebaseAuth.instance.signOut();
            Navigator.pushReplacementNamed(context, '/login');
          } else {
            if (item.onTap != null) {
              item.onTap!();
            } else {
              setState(() => _selectedIndex = index);
            }
          }
        },
          selected: isSelected,
          selectedTileColor: theme.primaryColor.withOpacity(0.1),

      ),
    );
  }

  Widget _buildDrawerItem(ThemeData theme, NavigationItem item, int index) {
  final isSelected = _selectedIndex == index;
  final isSettings = index == _navigationItems.length;
  final isLogout = index == _navigationItems.length + 1;

  return ListTile(
    leading: Icon(
      isSelected ? item.activeIcon : item.icon,
      color: isSelected ? theme.primaryColor : theme.iconTheme.color,
    ),
    title: ResponsiveText(item.label, maxLines: 1),
    selected: isSelected,
    selectedTileColor: theme.primaryColor.withOpacity(0.1),
    onTap: () {
      Navigator.pop(context);
      if (isSettings) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      } else if (isLogout) {
        FirebaseAuth.instance.signOut();
        Navigator.pushReplacementNamed(context, '/login');
      } else {
        if (item.onTap != null) {
          item.onTap!();
        } else {
          setState(() => _selectedIndex = index);
        }
      }
    },

  );
  }
}


class NavigationItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget Function(BuildContext, String?, String?) builder;
  final VoidCallback? onTap; // ✅ Add this

  const NavigationItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.builder,
    this.onTap,
  });
}
