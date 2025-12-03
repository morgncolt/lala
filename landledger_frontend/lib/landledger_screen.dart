// lib/landledger_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:async' show Timer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/enhanced_regions_view.dart';
import 'services/identity_service.dart';
import 'models/property_address.dart';

enum _ViewMode { allBlocks, myBlocks, transactions, actors, regions }

/// =====================================================
/// API base resolution (robust across platforms/emulators)
/// =====================================================

// Optional compile-time override:
// flutter run -d chrome --dart-define=API_BASE=http://localhost:4000
const String _apiBaseOverride = String.fromEnvironment('API_BASE', defaultValue: '');

String _defaultApiBase() {
  if (_apiBaseOverride.isNotEmpty) return _apiBaseOverride;

  if (kIsWeb) {
    // Avoid mixed content: if the app is served over HTTPS, prefer HTTPS for API too.
    final isHttps = Uri.base.scheme == 'https';
    final host = Uri.base.host.isEmpty ? 'localhost' : Uri.base.host;
    final port = 4000;
    return '${isHttps ? 'https' : 'http'}://$host:$port';
  }

  // Use localhost for all platforms (ADB reverse port forwarding handles Android connectivity)
  return 'http://localhost:4000';
}

/// Centralized API helper with one-time base resolution + health check.
class Api {
  static Uri? _base;
  static bool _resolving = false;
  static final List<Completer<Uri>> _waiters = [];

  /// Returns a reachable base URI (tries healthz). Caches after first success.
  static Future<Uri> ensureBase() async {
    if (_base != null) return _base!;

    // Coalesce concurrent calls.
    if (_resolving) {
      final c = Completer<Uri>();
      _waiters.add(c);
      return c.future;
    }

    _resolving = true;
    try {
      final candidates = <Uri>[
        Uri.parse(_defaultApiBase()),
        // Genymotion fallback (Android)
        if (!kIsWeb && Platform.isAndroid) Uri.parse('http://10.0.3.2:4000'),
      ];

      for (final u in candidates) {
        try {
          final r = await http
              .get(u.replace(path: '/healthz'))
              .timeout(const Duration(seconds: 3));
          if (r.statusCode == 200) {
            _base = u;
            _notifyWaiters(u);
            debugPrint('LandLedger API_BASE resolved to: $u');
            return u;
          }
        } catch (_) {
          // try next
        }
      }

      // No candidate worked; pick the first to surface clearer errors later.
      final fallback = candidates.first;
      _base = fallback;
      _notifyWaiters(fallback);
      debugPrint('LandLedger API_BASE fell back to: $fallback (healthz failed)');
      return fallback;
    } finally {
      _resolving = false;
    }
  }

  static void _notifyWaiters(Uri base) {
    for (final w in _waiters) {
      if (!w.isCompleted) w.complete(base);
    }
    _waiters.clear();
  }

  /// Convenience to build a URI for a given path using the resolved base.
  static Future<Uri> build(String path) async {
    final base = await ensureBase();
    return base.replace(path: path);
  }
}

/// Cross-platform API base (string form) kept for simple logs/messaging.
String get apiBase => _defaultApiBase();

/// =====================================================
/// BLOCK DATA MODEL
/// =====================================================

class BlockData {
  final int height;
  final String hash;
  final String? prevHash;
  final DateTime timestamp;
  final int txCount;
  final List<String> types;
  final List<String> actors;
  final List<String> regionCodes;
  final Map<String, dynamic> rawData;

  BlockData({
    required this.height,
    required this.hash,
    this.prevHash,
    required this.timestamp,
    required this.txCount,
    required this.types,
    required this.actors,
    required this.regionCodes,
    required this.rawData,
  });

  factory BlockData.fromJson(Map<String, dynamic> json) {
    final raw = json;
    return BlockData(
      height: raw['height'] ?? raw['blockNumber'] ?? 0,
      hash: raw['hash'] ?? raw['blockHash'] ?? '',
      prevHash: raw['prevHash'] ?? raw['previousHash'],
      timestamp: _parseTimestamp(raw['timestamp'] ?? raw['createdAt']),
      txCount: raw['txCount'] ?? raw['transactionCount'] ?? 1,
      types: (raw['types'] as List?)?.cast<String>() ?? ['parcel.create'],
      actors: (raw['actors'] as List?)?.cast<String>() ?? [],
      regionCodes: (raw['regionCodes'] as List?)?.cast<String>() ?? [],
      rawData: raw,
    );
  }

  static DateTime _parseTimestamp(dynamic ts) {
    if (ts == null) return DateTime.now();
    if (ts is String) return DateTime.tryParse(ts) ?? DateTime.now();
    if (ts is int) {
      return ts > 20000000000
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    }
    return DateTime.now();
  }

  bool get isVerified => true; // TODO: Add verification logic
  bool get isFinalized => true; // TODO: Add finalization logic
}

class LandledgerScreen extends StatefulWidget {
  final Map<String, dynamic>? selectedRecord;
  final ValueNotifier<Map<String, dynamic>?>? blockchainDataNotifier;

  /// Pass the signed-in user's identifiers.
  /// "Your Blocks" will match by wallet first; if wallet is null/empty, it falls back to ownerId.
  final String? currentOwnerId;
  final String? currentWalletAddress;

  const LandledgerScreen({
    super.key,
    this.selectedRecord,
    this.blockchainDataNotifier,
    this.currentOwnerId,
    this.currentWalletAddress,
  });

  // 2) Lightweight identicon color from address (no deps)
  static Color identiconColor(String a) {
    if (a.isEmpty) return const Color(0xFF6366F1); // Default blue color for empty addresses

    int h = 0;
    for (final c in a.codeUnits) { h = (h * 31 + c) & 0xFFFFFF; }

    // Ensure we have a valid color with good contrast
    final color = Color(0xFF000000 | h);

    // Avoid very dark or very bright colors that might not render well
    if (color.computeLuminance() < 0.1) {
      // Too dark, lighten it
      return Color.fromARGB(255, (color.red + 100).clamp(0, 255), (color.green + 100).clamp(0, 255), (color.blue + 100).clamp(0, 255));
    } else if (color.computeLuminance() > 0.9) {
      // Too bright, darken it
      return Color.fromARGB(255, (color.red - 100).clamp(0, 255), (color.green - 100).clamp(0, 255), (color.blue - 100).clamp(0, 255));
    }

    return color.withOpacity(1);
  }

  @override
  State<LandledgerScreen> createState() => _LandledgerScreenState();
}

class OwnerChip extends StatelessWidget {
  final String address;        // full hex or id
  final String display;        // name or codename
  final VoidCallback? onView;  // open Owner details
  const OwnerChip({super.key, required this.address, required this.display, this.onView});

  @override
  Widget build(BuildContext context) {
    final short = address.isEmpty ? '—' : (address.startsWith('0x') ? address : '0x$address');
    final pretty = _shortWallet(short);
    final color = address.isEmpty ? const Color(0xFF6366F1) : LandledgerScreen.identiconColor(address);

    return Tooltip(
      message: address.isEmpty ? 'No address available' : address,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar
          CircleAvatar(
            radius: 8,
            backgroundColor: color,
            child: const Icon(Icons.person, size: 10, color: Colors.white),
          ),
          const SizedBox(width: 6),

          // Compact info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Display name
              Text(
                display.isEmpty ? 'Unknown' : display,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
              ),
              // Wallet address
              Text(
                pretty,
                style: const TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),

          const SizedBox(width: 6),

          // Copy button
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            icon: const Icon(Icons.copy, size: 12, color: Colors.grey),
            onPressed: address.isEmpty ? null : () {
              ScaffoldMessenger.of(context).clearSnackBars();
              Clipboard.setData(ClipboardData(text: address));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Address copied!'),
                duration: Duration(seconds: 1),
              ));
            },
            tooltip: 'Copy address',
          ),

          // View button (if provided)
          if (onView != null)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              icon: const Icon(Icons.person_search, size: 12, color: Colors.grey),
              onPressed: onView,
              tooltip: 'View Owner',
            ),
        ],
      ),
    );
  }

  String _shortWallet(String wallet) {
    if (wallet.isEmpty || wallet == '—') return 'No address';
    if (wallet.length <= 10) return wallet;
    return '${wallet.substring(0, 6)}...${wallet.substring(wallet.length - 4)}';
  }
}

class _LandledgerScreenState extends State<LandledgerScreen> {
  // Data - Legacy parcel data (keeping for compatibility)
  List<Map<String, dynamic>> _allParcels = [];
  List<Map<String, dynamic>> _myParcels = [];
  int _blockchainLength = 0;

  // New block data model
  List<BlockData> _allBlocks = [];
  List<BlockData> _filteredBlocks = [];
  BlockData? _selectedBlock;

  // Loading / error
  bool _isLoading = true;
  String _errorMessage = '';

  // Current (selected) record
  Map<String, dynamic>? _currentRecord;

  // Identity (for "Your Blocks")
  String? _myOwnerId;
  String? _myWallet;
  String? _myUsername; // Store the current user's username
  bool _identityLoading = true;
  Timer? _identityTimeoutTimer;

  // Cache for wallet-to-username mappings
  final Map<String, String> _walletUsernameCache = {};

  // Filters
  bool _showOnlyMyBlocks = false;
  String _searchQuery = '';
  DateTimeRange? _dateRange;
  String? _selectedRegion;
  String _sortBy = 'height'; // 'height', 'timestamp', 'type'
  bool _sortAscending = false;

  // UI state
  bool _showDetailsPane = false;
  final int _selectedTabIndex = 0; // 0: Overview, 1: Transactions, 2: Parcels Map, 3: CIF Votes, 4: JSON

  // View modes
  _ViewMode _view = _ViewMode.allBlocks;

  @override
  void initState() {
    super.initState();
    debugPrint('API_BASE (initial) => $apiBase');
    debugPrint('LandledgerScreen: currentOwnerId = ${widget.currentOwnerId}');
    debugPrint('LandledgerScreen: currentWalletAddress = ${widget.currentWalletAddress}');
    _currentRecord = widget.selectedRecord ?? widget.blockchainDataNotifier?.value;

    _myOwnerId = (widget.currentOwnerId ?? '').trim().isEmpty ? null : widget.currentOwnerId!.trim();
    _myWallet  = (widget.currentWalletAddress ?? '').trim().isEmpty ? null : widget.currentWalletAddress!.trim();
    debugPrint('LandledgerScreen: _myOwnerId = $_myOwnerId');
    debugPrint('LandledgerScreen: _myWallet = $_myWallet');

    // Load current user's username
    _loadCurrentUserUsername();

    // Set up identity loading timeout (10 seconds)
    _identityTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _identityLoading) {
        debugPrint('LandledgerScreen: Identity loading timeout, proceeding without identity');
        setState(() => _identityLoading = false);
      }
    });

    _inferIdentityFrom(_currentRecord);
    _loadData();
    _hydrateCurrentRecord();
    widget.blockchainDataNotifier?.addListener(_updateCurrentRecord);
  }

  @override
  void didUpdateWidget(covariant LandledgerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('LandledgerScreen: didUpdateWidget called');
    debugPrint('LandledgerScreen: new currentOwnerId = ${widget.currentOwnerId}');
    debugPrint('LandledgerScreen: new currentWalletAddress = ${widget.currentWalletAddress}');

    final newOwnerId = (widget.currentOwnerId ?? '').trim().isEmpty ? null : widget.currentOwnerId!.trim();
    final newWallet = (widget.currentWalletAddress ?? '').trim().isEmpty ? null : widget.currentWalletAddress!.trim();

    if (newOwnerId != _myOwnerId || newWallet != _myWallet) {
      debugPrint('LandledgerScreen: Identity changed, updating...');
      _myOwnerId = newOwnerId;
      _myWallet = newWallet;
      _identityLoading = false;
      _identityTimeoutTimer?.cancel();
      _recomputeMyParcels();
    }
  }

  @override
  void dispose() {
    widget.blockchainDataNotifier?.removeListener(_updateCurrentRecord);
    _identityTimeoutTimer?.cancel();
    super.dispose();
  }

  void _updateCurrentRecord() {
    if (!mounted) return;
    setState(() {
      _currentRecord = widget.blockchainDataNotifier?.value;
      _inferIdentityFrom(_currentRecord);
      _recomputeMyParcels();
    });
    _hydrateCurrentRecord();
  }

  void _inferIdentityFrom(Map<String, dynamic>? rec) {
    if (rec == null) return;
    _myWallet  ??= _walletOf(rec);
    _myOwnerId ??= (rec['owner'] ?? rec['ownerId'] ?? rec['currentOwner'])?.toString().trim();
  }

  // Load current user's username from Firebase
  Future<void> _loadCurrentUserUsername() async {
    try {
      // Try to get username from Firebase displayName or email
      final user = await Future.any([
        Future(() async {
          try {
            // Import FirebaseAuth
            final auth = await Future.delayed(Duration.zero, () {
              // We can't import FirebaseAuth here directly, so we'll extract from email
              return null;
            });
            return auth;
          } catch (_) {
            return null;
          }
        }),
        Future.delayed(const Duration(milliseconds: 500), () => null),
      ]);

      // Extract username from email in the myOwnerId if available
      if (_myOwnerId != null && _myOwnerId!.contains('@')) {
        _myUsername = _myOwnerId!.split('@').first;
        debugPrint('LandledgerScreen: Loaded username from owner ID: $_myUsername');
      } else if (_myOwnerId != null) {
        // If it's not an email, use it as the username
        _myUsername = _myOwnerId;
        debugPrint('LandledgerScreen: Using owner ID as username: $_myUsername');
      }

      // Try to load username mapping for the current wallet
      if (_myWallet != null) {
        final storedUsername = await getUsernameForWallet(_myWallet!);
        if (storedUsername != null) {
          _myUsername = storedUsername;
          debugPrint('LandledgerScreen: Loaded username from secure storage: $_myUsername');
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('LandledgerScreen: Error loading username: $e');
    }
  }

  // Preload usernames for visible wallets
  Future<void> _preloadWalletUsernames() async {
    final walletsToLoad = <String>{};

    // Collect unique wallet addresses from visible blocks
    for (final block in _filteredBlocks.take(50)) { // Load first 50 for performance
      final wallet = _walletOf(block.rawData);
      if (wallet != null && wallet.isNotEmpty && !_walletUsernameCache.containsKey(wallet)) {
        walletsToLoad.add(wallet);
      }
    }

    // Load usernames in parallel
    await Future.wait(walletsToLoad.map((wallet) async {
      try {
        final username = await getUsernameForWallet(wallet);
        if (username != null && mounted) {
          setState(() {
            _walletUsernameCache[wallet] = username;
          });
        }
      } catch (e) {
        debugPrint('Error loading username for wallet $wallet: $e');
      }
    }));
  }

  // ===========================
  // Networking
  // ===========================
  Future<void> _loadData() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = '';
        });
      }

      // Try to load from API first
      try {
        final u = await Api.build('/api/landledger');
        final parcelsResponse = await http
            .get(u)
            .timeout(const Duration(seconds: 12));

        if (parcelsResponse.statusCode == 200) {
          final decoded = jsonDecode(parcelsResponse.body);
          final dynamic listish = (decoded is Map<String, dynamic>)
              ? (decoded['payload'] ?? decoded['data'] ?? decoded['items'] ?? [])
              : decoded;
          if (listish is! List) {
            throw StateError('Expected a list but got ${listish.runtimeType}');
          }
          final List<dynamic> parcelsArr = listish;
          final parcelsList = parcelsArr.cast<Map<String, dynamic>>();
          debugPrint('LandledgerScreen: Loaded ${parcelsList.length} parcels from API');
          for (final parcel in parcelsList) {
            debugPrint('LandledgerScreen: Parcel ${parcel['parcelId']}: owner=${parcel['owner']}');
          }

          await _processParcelsData(parcelsList);
          return; // Successfully loaded from API
        } else {
          throw Exception('HTTP Error: ${parcelsResponse.statusCode}');
        }
      } catch (apiError) {
        debugPrint('LandledgerScreen: API failed: $apiError');
        _setError('Failed to load data from API: $apiError');
      }
    } on TimeoutException {
      debugPrint('LandledgerScreen: API timeout');
      _setError('API request timed out. Please check your connection.');
    } catch (e) {
      final msg = e.toString();
      if (kIsWeb && Uri.base.scheme == 'https' && msg.toLowerCase().contains('blocked')) {
        debugPrint('LandledgerScreen: Mixed content blocked');
        _setError('Mixed content blocked. Please ensure API is served over HTTPS.');
      } else {
        debugPrint('LandledgerScreen: Network error: $e');
        _setError('Network error: $e');
      }
    }
  }

  Future<void> _processParcelsData(List<Map<String, dynamic>> parcelsList) async {
    // Assign chronological block numbers (oldest=1 … newest=N)
    final withBlocks = _withChronologicalBlockNumbers(parcelsList);

    // Create BlockData objects from parcels
    final blocks = <BlockData>[];
    for (int i = 0; i < withBlocks.length; i++) {
      final parcel = withBlocks[i];
      final blockData = {
        'height': parcel['blockNumber'] ?? (i + 1),
        'hash': parcel['blockchainId'] ?? parcel['id'] ?? 'hash_${i + 1}',
        'timestamp': parcel['createdAt'] ?? DateTime.now().toIso8601String(),
        'txCount': 1,
        'types': ['parcel.create'],
        'actors': [parcel['owner'] ?? 'unknown'],
        'regionCodes': [_countryCodeOf(parcel) ?? 'unknown'],
        ...parcel, // Include all original data
      };
      blocks.add(BlockData.fromJson(blockData));
    }

    // Sort blocks by height descending (newest first)
    blocks.sort((a, b) => b.height.compareTo(a.height));

    if (mounted) {
      setState(() {
        _allParcels = withBlocks;
        _allBlocks = blocks;
        _blockchainLength = withBlocks.length;
        _applyFilters();
        _recomputeMyParcels();
        _isLoading = false;
      });

      // Preload usernames for visible wallets
      _preloadWalletUsernames();
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
    _snack(message, isError: true);
  }

  Future<Map<String, dynamic>?> _fetchParcelById(String id) async {
    try {
      final u = await Api.build('/api/landledger/$id');
      final resp = await http
          .get(u)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      throw Exception('HTTP Error: ${resp.statusCode}');
    } catch (e) {
      debugPrint('LandledgerScreen: API failed for parcel $id: $e');
      return null;
    }
  }

  String? _deriveParcelId(Map<String, dynamic> m) {
    return m['parcelId'] ?? m['id'] ?? m['titleNumber'] ?? m['title_number'] ?? m['blockchainId'];
    // If your API returns a block hash/id field, include it above.
  }

  Future<void> _hydrateCurrentRecord() async {
    final rec = _currentRecord;
    if (rec == null) return;
    final id = _deriveParcelId(rec);
    if (id == null || id.isEmpty) return;
    final fresh = await _fetchParcelById(id);
    if (fresh != null && mounted) {
      setState(() => _currentRecord = fresh);
    }
  }

  // ===========================
  // Helpers (area, coords, UI)
  // ===========================
  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.black87,
      duration: const Duration(seconds: 3),
    ));
  }

  String _fmtDate(dynamic val) {
    DateTime? dt;
    if (val == null) return '—';
    if (val is String) dt = DateTime.tryParse(val)?.toLocal();
    if (val is int) {
      dt = val > 20000000000
          ? DateTime.fromMillisecondsSinceEpoch(val).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(val * 1000).toLocal();
    }
    if (val is Map) {
      if (val['ms'] is int) dt = DateTime.fromMillisecondsSinceEpoch(val['ms']).toLocal();
      if (val['seconds'] is int) dt = DateTime.fromMillisecondsSinceEpoch(val['seconds'] * 1000).toLocal();
    }
    if (dt == null) return val.toString();
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String formatAreaLabel(double? areaKm2) {
    if (areaKm2 == null) return '—';
    if (areaKm2 >= 0.01) {
      return '${areaKm2.toStringAsFixed(2)} km²';
    }
    final m2 = areaKm2 * 1e6;
    String m2Str;
    if (m2 >= 100) {
      m2Str = m2.toStringAsFixed(0);
    } else if (m2 >= 1) {
      m2Str = m2.toStringAsFixed(1);
    } else {
      m2Str = m2.toStringAsFixed(3);
    }
    return '$m2Str m²';
  }

  List<LatLng> parseCoordinates(dynamic coords) {
    final out = <LatLng>[];
    if (coords == null) return out;
    if (coords is List) {
      for (final c in coords) {
        if (c is Map) {
          final lat = c['lat'] ?? c['latitude'];
          final lng = c['lng'] ?? c['longitude'];
          if (lat is num && lng is num) {
            out.add(LatLng(lat.toDouble(), lng.toDouble()));
          }
        } else if (c is List && c.length >= 2) {
          // [lng, lat] geojson-style pair
          final lng = c[0], lat = c[1];
          if (lat is num && lng is num) out.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
    }
    return out;
  }

  Map<String, dynamic> _parcelSnapshotFromChaincode(Map<String, dynamic> raw) {
    final snapshot = Map<String, dynamic>.from(raw);
    final id = _deriveParcelId(raw)?.toString() ?? (raw['parcelId'] ?? raw['id'] ?? '').toString();
    final coords = parseCoordinates(raw['coordinates']);
    final normalizedCoords =
        coords.isNotEmpty ? _serializeCoords(coords) : (raw['coordinates'] as List<dynamic>? ?? const []);
    final owner = (raw['owner'] ?? raw['ownerId'] ?? raw['currentOwner'] ?? '').toString();
    final ownerName = (raw['ownerName'] ?? raw['owner_label'])?.toString();
    final ownerEmail = (raw['ownerEmail'] ?? raw['email'])?.toString();
    final ownerPhone = (raw['ownerPhone'] ?? raw['phone'])?.toString();
    final area = (raw['areaSqKm'] is num)
        ? (raw['areaSqKm'] as num).toDouble()
        : (coords.isNotEmpty ? computeAreaKm2(coords) : null);
    snapshot['parcelId'] = id;
    snapshot['titleNumber'] = (raw['titleNumber'] ?? raw['title_number'] ?? id).toString();
    snapshot['owner'] = owner;
    snapshot['ownerId'] = owner;
    if (ownerName != null) snapshot['ownerName'] = ownerName;
    if (ownerEmail != null) snapshot['ownerEmail'] = ownerEmail;
    if (ownerPhone != null) snapshot['ownerPhone'] = ownerPhone;
    snapshot['description'] = (raw['description'] ?? '').toString();
    if (area != null) snapshot['areaSqKm'] = area;
    snapshot['coordinates'] = normalizedCoords;
    snapshot['createdAt'] ??= raw['timestamp'];
    snapshot['verified'] ??= raw['verified'] ?? raw['isVerified'] ?? true;
    snapshot['txId'] ??= raw['txId'] ?? raw['transactionHash'] ?? raw['blockchainId'] ?? raw['hash'];
    snapshot['blockchainId'] ??= raw['hash'];
    return snapshot;
  }

  Map<String, dynamic> _ownerSnapshotFromParcel(Map<String, dynamic> parcel) {
    final ownerId = (parcel['owner'] ?? parcel['ownerId'] ?? '').toString();
    return {
      'ownerId': ownerId,
      'name': (parcel['ownerName'] ?? '').toString(),
      'walletAddress': ownerId,
      'email': (parcel['ownerEmail'] ?? '').toString(),
      'phone': (parcel['ownerPhone'] ?? '').toString(),
      'verified': parcel['ownerVerified'] ?? parcel['verified'] ?? false,
      'createdAt': parcel['ownerCreatedAt'] ?? parcel['createdAt'],
      'parcelCount': 1,
      'parcels': [
        {
          'parcelId': parcel['parcelId'],
          'titleNumber': parcel['titleNumber'],
          'areaSqKm': parcel['areaSqKm'],
          'coordinates': parcel['coordinates'],
          'createdAt': parcel['createdAt'],
        },
      ],
    };
  }

  Map<String, dynamic> _titleSnapshotFromParcel(Map<String, dynamic> parcel) {
    return {
      'titleNumber': parcel['titleNumber'],
      'issuedAt': parcel['titleIssuedAt'] ?? parcel['createdAt'],
      'registrar': parcel['registrar'] ?? parcel['createdBy'] ?? parcel['owner'],
      'docHash': parcel['docHash'] ?? parcel['txId'] ?? parcel['blockchainId'] ?? '',
      'docUrl': parcel['docUrl'] ?? '',
      'encumbrances': parcel['encumbrances'] ?? const [],
      'geometry': parcel['coordinates'],
    };
  }

  List<Map<String, dynamic>> _historySnapshotFromParcel(
    Map<String, dynamic> parcel,
    Map<String, dynamic> raw,
  ) {
    final events = <Map<String, dynamic>>[];
    final createdAt = parcel['createdAt'] ?? raw['timestamp'];
    final owner = (parcel['owner'] ?? '').toString();
    final txId = parcel['txId'] ?? raw['hash'] ?? raw['blockchainId'] ?? '';
    if (createdAt != null) {
      events.add({
        'type': 'CREATE',
        'timestamp': createdAt,
        'toOwner': owner,
        'txId': txId,
      });
    }
    final history = raw['history'];
    if (history is List) {
      for (final entry in history) {
        if (entry is Map<String, dynamic>) {
          events.add(entry);
        }
      }
    }
    return events;
  }

  List<Map<String, double>> _serializeCoords(List<LatLng> coords) {
    return coords
        .map((c) => {'lat': c.latitude, 'lng': c.longitude})
        .toList(growable: false);
  }

  double? computeAreaKm2(List<LatLng> pts) {
    if (pts.length < 3) return null;
    const R = 6371000.0; // meters
    final lat0 = pts.first.latitude * math.pi / 180.0;
    final cos0 = math.cos(lat0);
    double areaMeters2 = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final ax = a.longitude * math.pi / 180.0;
      final ay = a.latitude * math.pi / 180.0;
      final bx = b.longitude * math.pi / 180.0;
      final by = b.latitude * math.pi / 180.0;
      final x1 = R * ax * cos0;
      final y1 = R * ay;
      final x2 = R * bx * cos0;
      final y2 = R * by;
      areaMeters2 += (x1 * y2 - x2 * y1);
    }
    areaMeters2 = areaMeters2.abs() * 0.5;
    return areaMeters2 / 1e6;
  }

  gmap.LatLng _g(LatLng p) => gmap.LatLng(p.latitude, p.longitude);
  List<gmap.LatLng> _gList(List<LatLng> pts) => pts.map(_g).toList();

  gmap.LatLngBounds? _boundsFrom(List<LatLng> pts) {
    if (pts.isEmpty) return null;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    return gmap.LatLngBounds(
      southwest: gmap.LatLng(minLat, minLng),
      northeast: gmap.LatLng(maxLat, maxLng),
    );
  }

  LatLng _centerOf(List<LatLng> pts) {
    if (pts.isEmpty) return const LatLng(0, 0);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  // ===========================
  // Map preview (with satellite toggle)
  // ===========================
  void _showMapPreview(List<LatLng> coordinates) {
    if (coordinates.isEmpty) {
      _snack('No location data available', isError: true);
      return;
    }
    final center = _centerOf(coordinates);
    final initPos = gmap.CameraPosition(target: _g(center), zoom: 16);
    final bounds = _boundsFrom(coordinates);
    showDialog(
      context: context,
      builder: (context) {
        bool satellite = true;
        return StatefulBuilder(
          builder: (context, setDlg) {
            return AlertDialog(
              backgroundColor: const Color(0xFF121212),
              title: Row(
                children: [
                  const Text('Property Location'),
                  const Spacer(),
                  IconButton(
                    tooltip: satellite ? 'Switch to Map' : 'Switch to Satellite',
                    icon: Icon(satellite ? Icons.satellite_alt : Icons.map),
                    onPressed: () => setDlg(() => satellite = !satellite),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 320,
                child: gmap.GoogleMap(
                  mapType: satellite ? gmap.MapType.hybrid : gmap.MapType.normal,
                  initialCameraPosition: initPos,
                  zoomControlsEnabled: true,
                  mapToolbarEnabled: false,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  polygons: {
                    if (coordinates.length >= 3)
                      gmap.Polygon(
                        polygonId: const gmap.PolygonId('parcel'),
                        points: _gList(coordinates),
                        strokeWidth: 2,
                        strokeColor: Colors.blue,
                        fillColor: Colors.blue.withOpacity(0.25),
                      ),
                  },
                  onMapCreated: (c) async {
                    await Future<void>.delayed(const Duration(milliseconds: 120));
                    if (bounds != null) {
                      await c.animateCamera(gmap.CameraUpdate.newLatLngBounds(bounds, 40));
                    } else {
                      await c.animateCamera(gmap.CameraUpdate.newCameraPosition(initPos));
                    }
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================
  // Details bottom sheet (pretty tabs)
  // ===========================
  Future<void> _openDetails(Map<String, dynamic> m, {bool fromBlockchain = false}) async {
    final id = _deriveParcelId(m);
    final owner = (m['owner'] ?? m['ownerId'])?.toString();
    final title = (m['titleNumber'] ?? m['title_number'])?.toString();

    final parcelSnapshot = _parcelSnapshotFromChaincode(m);
    final ownerSnapshot = _ownerSnapshotFromParcel(parcelSnapshot);
    final titleSnapshot = _titleSnapshotFromParcel(parcelSnapshot);
    final historySnapshot = _historySnapshotFromParcel(parcelSnapshot, m);
    final historySummary = {
      'createdAt': parcelSnapshot['createdAt'],
      'currentOwnerSince': parcelSnapshot['ownershipTransferredAt'] ?? parcelSnapshot['createdAt'],
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E0E0E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DefaultTabController(
          length: 5,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    id ?? 'Block',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  if (fromBlockchain && m['blockNumber'] != null)
                    Text(
                      'Block #${m['blockNumber']} / $_blockchainLength',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  const SizedBox(height: 8),
                  const TabBar(
                    isScrollable: true,
                    indicatorColor: Colors.white,
                    tabs: [
                      Tab(text: 'Parcel'),
                      Tab(text: 'Owner'),
                      Tab(text: 'Title'),
                      Tab(text: 'History'),
                      Tab(text: 'Actions'),
                    ],
                  ),
                  SizedBox(
                    height: math.min(MediaQuery.of(ctx).size.height * 0.75, 560),
                    child: TabBarView(
                      children: [
                        _ParcelViewer(parcelId: id, initialParcel: parcelSnapshot),
                        _OwnerViewer(ownerId: owner, initialOwner: ownerSnapshot),
                        _TitleViewer(titleNumber: title, initialTitle: titleSnapshot),
                        _HistoryViewer(
                          parcelId: id,
                          currentOwnerId: owner,
                          initialEvents: historySnapshot,
                          initialSummary: historySummary,
                        ),
                        _ActionsPane(parcel: parcelSnapshot),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================
  // Country helpers (badge)
  // ===========================
  static const Map<String, String> _CITY_TO_ISO2 = {
    // Nigeria
    'abuja': 'NG', 'lagos': 'NG', 'port harcourt': 'NG', 'kano': 'NG',
    'calabar': 'NG', 'ibadan': 'NG', 'benin city': 'NG', 'owerri': 'NG',
    'enugu': 'NG', 'jos': 'NG', 'kaduna': 'NG', 'zaria': 'NG',
    // Kenya
    'mombasa': 'KE', 'nairobi': 'KE', 'kisumu': 'KE', 'nakuru': 'KE', 'eldoret': 'KE',
    // Ghana
    'accra': 'GH', 'kumasi': 'GH', 'tamale': 'GH', 'sekondi-takoradi': 'GH',
    // Cameroon
    'yaounde': 'CM', 'douala': 'CM', 'bamenda': 'CM', 'garoua': 'CM', 'maroua': 'CM',
    // South Africa
    'johannesburg': 'ZA', 'cape town': 'ZA', 'durban': 'ZA', 'pretoria': 'ZA', 'port elizabeth': 'ZA',
    // Ethiopia / Rwanda / Uganda
    'addis ababa': 'ET', 'kigali': 'RW', 'kampala': 'UG',
    // United States
    'mountainview': 'US', 'mountain view': 'US', 'new york': 'US', 'los angeles': 'US',
    'chicago': 'US', 'houston': 'US', 'phoenix': 'US', 'philadelphia': 'US',
    'san antonio': 'US', 'san diego': 'US', 'dallas': 'US', 'san jose': 'US',
  };

  String? _countryCodeOf(Map<String, dynamic> m) {
    // 1) prefer explicit fields
    final raw = m['_raw'];
    String? cc;
    if (m['countryCode'] is String) cc = m['countryCode'];
    if (cc == null && raw is Map) {
      final props = (raw['properties'] as Map?) ?? raw;
      final v = props['countryCode'] ?? props['country_code'] ?? props['iso2'];
      if (v is String) cc = v;
      if (cc == null && props['country'] is String) {
        final name = (props['country'] as String).trim().toLowerCase();
        const byName = {
          'nigeria': 'NG', 'kenya': 'KE', 'ghana': 'GH', 'cameroon': 'CM',
          'south africa': 'ZA', 'ethiopia': 'ET', 'rwanda': 'RW', 'uganda': 'UG',
        };
        cc = byName[name];
      }
    }

    // 2) fall back to parsing city from the parcel id / title
    if (cc == null) {
      final id = (m['parcelId'] ?? m['id'] ?? m['titleNumber'] ?? m['title_number'])?.toString() ?? '';
      final match = RegExp(r'^LL-([A-Za-z ]+)-').firstMatch(id);
      final city = match?.group(1)?.trim().toLowerCase();
      if (city != null && city.isNotEmpty) {
        cc = _CITY_TO_ISO2[city];
      }
    }

    if (cc != null && cc.length == 2) return cc.toUpperCase();
    return null; // unknown
  }

  String _flagEmojiFromISO2(String iso2) {
    const int base = 0x1F1E6;
    final a = iso2.codeUnitAt(0) - 65; // 'A'
    final b = iso2.codeUnitAt(1) - 65;
    return String.fromCharCode(base + a) + String.fromCharCode(base + b);
  }

  // ===========================
  // Card / List UI
  // ===========================
  double? _resolveAreaKm2(Map<String, dynamic> m) {
    final raw = m['areaSqKm'] ?? m['area_sqkm'];
    if (raw is num) return raw.toDouble();
    final coords = parseCoordinates(m['coordinates']);
    return computeAreaKm2(coords);
  }

  Widget _softBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }

  Widget _metaLine(List<String> parts) {
    final visible = parts.where((p) => p.trim().isNotEmpty).toList();
    return RichText(
      text: TextSpan(
        children: [
          for (int i = 0; i < visible.length; i++) ...[
            TextSpan(
              text: visible[i],
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (i != visible.length - 1)
              const TextSpan(text: '  ·  ', style: TextStyle(color: Colors.white24, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _buildParcelCard(Map<String, dynamic> m, {bool isBlockchainView = false}) {
    final id = _deriveParcelId(m) ?? 'N/A';
    final titleNo = (m['titleNumber'] ?? id).toString();
    final ownerRaw = (m['owner'] ?? 'N/A').toString();
    final owner = _shortWallet(ownerRaw);
    final verified = (m['verified'] ?? true) == true;
    final created = (m['createdAt'] ?? '').toString();
    final desc = (m['description'] ?? '').toString();
    final coords = parseCoordinates(m['coordinates']);
    final areaKm2 = _resolveAreaKm2(m);
    final areaLabel = formatAreaLabel(areaKm2);
    final blockNumber = m['blockNumber'] ?? m['index'];

    final iso2 = _countryCodeOf(m);
    final flag = (iso2 != null) ? _flagEmojiFromISO2(iso2) : null;

    final Color accentColor = verified ? const Color(0xFF00C853) : const Color(0xFFFFA000);
    final Color cardColor = const Color(0xFF1A1A1A);
    final Color surfaceColor = const Color(0xFF252525);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      color: cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDetails(m, fromBlockchain: isBlockchainView),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cardColor,
                cardColor,
                surfaceColor.withOpacity(0.3),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER ROW
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Verification Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: verified ? Colors.green.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: verified ? Colors.green.withOpacity(0.5) : Colors.amber.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            verified ? Icons.verified : Icons.schedule,
                            size: 12,
                            color: accentColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            verified ? 'Verified' : 'Pending',
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Block Number Badge
                    if (blockNumber != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF6366F1).withOpacity(0.8),
                              const Color(0xFF8B5CF6).withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '#$blockNumber',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // TITLE ROW
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (flag != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF23313A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$flag $iso2',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    Expanded(
                      child: Text(
                        titleNo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // PROPERTY ID
                Text(
                  'LLB-$id',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 12),

                // METADATA GRID
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Area
                      Flexible(
                        flex: 1,
                        child: _metadataItem(
                          icon: Icons.square_foot,
                          label: 'Area',
                          value: areaLabel,
                        ),
                      ),

                      const VerticalDivider(
                        color: Colors.white24,
                        thickness: 1,
                        indent: 4,
                        endIndent: 4,
                      ),

                      // Owner
                      Expanded(
                        flex: 2,
                        child: _metadataItem(
                          icon: Icons.person_outline,
                          label: 'Owner',
                          value: owner,
                        ),
                      ),

                      const VerticalDivider(
                        color: Colors.white24,
                        thickness: 1,
                        indent: 4,
                        endIndent: 4,
                      ),

                      // Date
                      Flexible(
                        flex: 1,
                        child: _metadataItem(
                          icon: Icons.calendar_today,
                          label: 'Created',
                          value: _fmtDate(created).split(' ').first,
                        ),
                      ),
                    ],
                  ),
                ),

                // DESCRIPTION (if available)
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // ACTION BUTTONS
                Row(
                  children: [
                    // Map Preview Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showMapPreview(coords),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.black.withOpacity(0.3),
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.2),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.map, size: 16),
                        label: const Text(
                          'View on Map',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Details Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _openDetails(m, fromBlockchain: isBlockchainView),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text(
                          'Details',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metadataItem({required IconData icon, required String label, required String value}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white.withOpacity(0.6)),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _sectionHeader({required String title, Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Color(0xFF6366F1),
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Text(
              '',
              style: TextStyle(fontSize: 0),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (trailing != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: trailing,
            ),
        ],
      ),
    );
  }

  Widget _chip(String text, {Color bg = const Color(0xFF2A2A2A)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }

  Widget _meta(String label, String value, {IconData? icon, Color? iconColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: iconColor ?? Colors.white70),
          const SizedBox(width: 4),
        ],
        Text('$label: ', style: const TextStyle(color: Colors.white70)),
        Text(value, style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  // ===========================
  // FILTER BAR
  // ===========================
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search and quick filters row
          Row(
            children: [
              // Search field
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search blocks, hashes, owners...',
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                      _applyFilters();
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),

              // My Blocks toggle
              FilterChip(
                label: const Text('My Blocks'),
                selected: _showOnlyMyBlocks,
                onSelected: (selected) {
                  setState(() {
                    _showOnlyMyBlocks = selected;
                    _applyFilters();
                  });
                },
                backgroundColor: const Color(0xFF2A2A2A),
                selectedColor: const Color(0xFF6366F1).withOpacity(0.2),
                checkmarkColor: const Color(0xFF6366F1),
              ),

              const SizedBox(width: 8),

              // Date range picker
              IconButton(
                icon: const Icon(Icons.date_range, color: Colors.white70),
                tooltip: 'Filter by date range',
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: _dateRange,
                  );
                  if (range != null) {
                    setState(() {
                      _dateRange = range;
                      _applyFilters();
                    });
                  }
                },
              ),

              // Clear filters
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.white70),
                tooltip: 'Clear all filters',
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _showOnlyMyBlocks = false;
                    _dateRange = null;
                    _selectedRegion = null;
                    _applyFilters();
                  });
                },
              ),
            ],
          ),

          if (_dateRange != null || _selectedRegion != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (_dateRange != null)
                  Chip(
                    label: Text(
                      '${DateFormat('MMM d').format(_dateRange!.start)} - ${DateFormat('MMM d').format(_dateRange!.end)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: const Color(0xFF6366F1).withOpacity(0.2),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _dateRange = null;
                        _applyFilters();
                      });
                    },
                  ),
                if (_selectedRegion != null)
                  Chip(
                    label: Text(_selectedRegion!, style: const TextStyle(color: Colors.white)),
                    backgroundColor: const Color(0xFF6366F1).withOpacity(0.2),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _selectedRegion = null;
                        _applyFilters();
                      });
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ===========================
  // METRICS ROW
  // ===========================
  Widget _buildMetricsRow() {
    final totalBlocks = _allBlocks.length;
    final myBlocks = _filteredBlocks.where((block) {
      final wallet = _walletOf(block.rawData);
      final owner = (block.rawData['owner'] ?? block.rawData['ownerId'] ?? block.rawData['currentOwner'])?.toString();
      final matchesWallet = _myWallet != null && _myWallet!.isNotEmpty && wallet == _myWallet;
      final matchesOwner = _myOwnerId != null && _myOwnerId!.isNotEmpty && owner == _myOwnerId;
      return matchesWallet || matchesOwner;
    }).length;

    final totalTransactions = _filteredBlocks.fold<int>(0, (sum, block) => sum + block.txCount);
    final uniqueActors = _filteredBlocks.expand((block) => block.actors).toSet().length;
    final regions = _filteredBlocks.expand((block) => block.regionCodes).toSet().length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          _buildMetricTile(
            label: 'Blocks',
            value: totalBlocks.toString(),
            icon: Icons.inventory_2,
            selected: _view == _ViewMode.allBlocks,
            onTap: () {
              setState(() {
                _view = _ViewMode.allBlocks;
                _showOnlyMyBlocks = false;
                _applyFilters();
              });
            },
          ),
          _buildMetricTile(
            label: 'My Blocks',
            value: myBlocks.toString(),
            icon: Icons.person,
            selected: _view == _ViewMode.myBlocks,
            onTap: () {
              setState(() {
                _view = _ViewMode.myBlocks;
                _showOnlyMyBlocks = true;
                _applyFilters();
              });
            },
          ),
          _buildMetricTile(
            label: 'Transactions',
            value: totalTransactions.toString(),
            icon: Icons.swap_horiz,
            selected: _view == _ViewMode.transactions,
            onTap: () => setState(() => _view = _ViewMode.transactions),
          ),
          _buildMetricTile(
            label: 'Actors',
            value: uniqueActors.toString(),
            icon: Icons.people,
            selected: _view == _ViewMode.actors,
            onTap: () => setState(() => _view = _ViewMode.actors),
          ),
          _buildMetricTile(
            label: 'Regions',
            value: regions.toString(),
            icon: Icons.map,
            selected: _view == _ViewMode.regions,
            onTap: () => setState(() => _view = _ViewMode.regions),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2A2A2A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================
  // BLOCK TABLE
  // ===========================
  Widget _buildBlockTable() {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    // Use post-style feed for the most intuitive user experience
    if (_view == _ViewMode.allBlocks || _view == _ViewMode.myBlocks) {
      return _buildPostStyleBlockchainFeed();
    }

    if (isDesktop) {
      return _buildDesktopTable();
    } else {
      return _buildMobileTable();
    }
  }
  
  /// =======================================
  /// ANALYTICS WIDGETS
  /// =======================================
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  

  Widget _buildDesktopTable() {
    return SingleChildScrollView(
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF1F1F1F)),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF6366F1).withOpacity(0.1);
          }
          return const Color(0xFF121212);
        }),
        columns: [
          DataColumn(
            label: const Text('Height', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onSort: (columnIndex, ascending) {
              setState(() {
                _sortBy = 'height';
                _sortAscending = ascending;
                _applyFilters();
              });
            },
          ),
          DataColumn(
            label: const Text('Parcel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          DataColumn(
            label: const Text('Hash', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          DataColumn(
            label: const Text('Type', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          DataColumn(
            label: const Text('Actors', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          DataColumn(
            label: const Text('Region', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          DataColumn(
            label: const Text('Time', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onSort: (columnIndex, ascending) {
              setState(() {
                _sortBy = 'timestamp';
                _sortAscending = ascending;
                _applyFilters();
              });
            },
          ),
          DataColumn(
            label: const Text('Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
        rows: _filteredBlocks.map((block) {
          final isSelected = _selectedBlock?.hash == block.hash;
          return DataRow(
            selected: isSelected,
            onSelectChanged: (selected) {
              setState(() {
                _selectedBlock = selected == true ? block : null;
                _showDetailsPane = selected == true;
              });
            },
            cells: [
              DataCell(Text(
                '#${block.height}',
                style: const TextStyle(color: Colors.white),
              )),
              DataCell(Builder(builder: (_) {
                final p = _parcelSummary(block.rawData);
                final ownerAddr = (block.rawData['owner'] ?? block.rawData['ownerId'] ?? block.rawData['currentOwner'])?.toString() ?? '';
                final ownerLabel = _ownerLabel(block.rawData);
                final area = formatAreaLabel(p.areaKm2);
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(p.title, style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 4),
                          OwnerChip(address: ownerAddr, display: ownerLabel, onView: ownerAddr.isEmpty ? null : () {
                            _openDetails({'owner': ownerAddr}, fromBlockchain: true);
                          }),
                          const SizedBox(height: 4),
                          Text('Area: $area', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'View on Map',
                      icon: const Icon(Icons.map, size: 18, color: Colors.white70),
                      onPressed: p.coords.isEmpty
                          ? null
                          : () => _showMapPreview(p.coords),
                    ),
                  ],
                );
              })),
              DataCell(
                Row(
                  children: [
                    Text(
                      _shortHash(block.hash),
                      style: const TextStyle(color: Colors.white70, fontFamily: 'monospace'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16, color: Colors.white54),
                      onPressed: () {
                        // TODO: Copy hash to clipboard
                      },
                    ),
                  ],
                ),
              ),
              DataCell(
                Wrap(
                  spacing: 4,
                  children: block.types.map((type) => _buildTypeChip(type)).toList(),
                ),
              ),
              DataCell(Text(
                block.actors.isEmpty
                    ? '—'
                    : (block.actors.length > 1 ? '${block.actors.first} +${block.actors.length - 1}' : block.actors.first),
                style: const TextStyle(color: Colors.white70),
              )),
              DataCell(
                Wrap(
                  spacing: 4,
                  children: (block.regionCodes.isEmpty
                      ? ['—']
                      : block.regionCodes.take(2)).map((region) => _buildRegionChip(region)).toList(),
                ),
              ),
              DataCell(Text(
                DateFormat('MMM d, HH:mm').format(block.timestamp),
                style: const TextStyle(color: Colors.white70),
              )),
              DataCell(
                Row(
                  children: [
                    if (block.isVerified) const Icon(Icons.verified, color: Colors.green, size: 16),
                    if (block.isFinalized) const Icon(Icons.lock, color: Colors.blue, size: 16),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPostStyleBlockchainFeed() {
    return ListView.builder(
      itemCount: _filteredBlocks.length,
      itemBuilder: (context, index) {
        final block = _filteredBlocks[index];
        final p = _parcelSummary(block.rawData);
        final ownerAddr = (block.rawData['owner'] ?? block.rawData['ownerId'] ?? block.rawData['currentOwner'])?.toString() ?? '';
        final ownerLabel = _ownerLabel(block.rawData);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Post Header - Block info and timestamp
              Row(
                children: [
                  // Block height and status
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '#${block.height}',
                          style: const TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        block.isVerified ? Icons.verified : Icons.schedule,
                        size: 14,
                        color: block.isVerified ? Colors.green : Colors.amber,
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Timestamp
                  Text(
                    DateFormat('MMM d, HH:mm').format(block.timestamp),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Property Title and Country
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (p.iso2 != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      _flagEmojiFromISO2(p.iso2!),
                      style: const TextStyle(fontSize: 20),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 8),

              // Hash and Visual
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fingerprint, size: 12, color: Colors.white70),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _shortHash(block.hash),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: block.hash));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Hash copied!')),
                        );
                      },
                      child: Icon(Icons.copy, size: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Transaction Info and Area
              Row(
                children: [
                  // Transaction types
                  ...block.types.map((type) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildTypeChip(type),
                  )),
                  // Transaction count
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F1F1F),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${block.txCount} tx${block.txCount != 1 ? 's' : ''}',
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ),
                  const Spacer(),
                  // Area
                  Text(
                    formatAreaLabel(p.areaKm2),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              // Transaction Details (for parcel.create)
              if (block.types.contains('parcel.create')) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3), width: 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.add_location, size: 14, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Parcel Created',
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Show location if available
                            if (block.rawData['address'] != null || block.rawData['addressString'] != null)
                              () {
                                String locationText = '';
                                if (block.rawData['address'] is Map<String, dynamic>) {
                                  final address = PropertyAddress.fromJson(block.rawData['address']);
                                  // Show city, country for compact display
                                  final parts = <String>[];
                                  if (address.city?.isNotEmpty == true) parts.add(address.city!);
                                  if (address.country?.isNotEmpty == true) parts.add(address.country!);
                                  locationText = parts.isNotEmpty ? parts.join(', ') : address.toDisplayString();
                                } else {
                                  locationText = block.rawData['addressString']?.toString() ?? '';
                                }
                                return Text(
                                  'Location: $locationText',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    height: 1.3,
                                  ),
                                );
                              }()
                            else
                              Text(
                                'Location: ${p.iso2 != null ? 'Unknown location in ${block.rawData['country']?.toString() ?? 'Unknown Country'}' : 'Unknown'}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              'Timestamp: ${DateFormat('MMM d, yyyy HH:mm:ss').format(block.timestamp)}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // Owner Info
              Row(
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: ownerAddr.isEmpty ? const Color(0xFF6366F1) : LandledgerScreen.identiconColor(ownerAddr),
                    child: const Icon(Icons.person, size: 12, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ownerLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _shortWallet(ownerAddr),
                          style: const TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Owner actions
                  Row(
                    children: [
                      GestureDetector(
                        onTap: ownerAddr.isEmpty ? null : () {
                          Clipboard.setData(ClipboardData(text: ownerAddr));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Address copied!')),
                          );
                        },
                        child: Icon(Icons.copy, size: 14, color: Colors.white54),
                      ),
                      const SizedBox(width: 4),
                      if (ownerAddr.isNotEmpty)
                        GestureDetector(
                          onTap: () => _openDetails({'owner': ownerAddr}, fromBlockchain: true),
                          child: Icon(Icons.person_search, size: 14, color: Colors.white54),
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // LandLedger ID
              if (block.rawData['id'] != null || block.rawData['title_number'] != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.badge_outlined, size: 14, color: Color(0xFF6366F1)),
                      const SizedBox(width: 8),
                      Text(
                        'LandLedger ID: ',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          block.rawData['id']?.toString() ?? block.rawData['title_number']?.toString() ?? '',
                          style: const TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          final id = block.rawData['id']?.toString() ?? block.rawData['title_number']?.toString() ?? '';
                          Clipboard.setData(ClipboardData(text: id));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('LandLedger ID copied!')),
                          );
                        },
                        child: const Icon(Icons.copy, size: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Property Address
              if (block.rawData['address'] != null || block.rawData['addressString'] != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.location_on, size: 14, color: Colors.redAccent),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: () {
                          // Try to parse structured address first
                          if (block.rawData['address'] is Map<String, dynamic>) {
                            final address = PropertyAddress.fromJson(block.rawData['address']);
                            return Text(
                              address.toDisplayString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            );
                          }
                          // Fallback to addressString
                          final addressString = block.rawData['addressString']?.toString() ??
                                                block.rawData['address']?.toString() ?? '';
                          return Text(
                            addressString.isNotEmpty ? addressString : 'No address available',
                            style: TextStyle(
                              color: addressString.isNotEmpty ? Colors.white : Colors.white54,
                              fontSize: 12,
                              fontStyle: addressString.isEmpty ? FontStyle.italic : FontStyle.normal,
                              height: 1.4,
                            ),
                          );
                        }(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Action Buttons - Minimal design
              Row(
                children: [
                  if (p.coords.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _showMapPreview(p.coords),
                      icon: const Icon(Icons.map, size: 14),
                      label: const Text('Map', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => _openDetails(block.rawData, fromBlockchain: true),
                    icon: const Icon(Icons.visibility, size: 14),
                    label: const Text('Details', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    ),
                  ),
                ],
              ),

              // Divider between posts
              if (index < _filteredBlocks.length - 1)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  height: 1,
                  color: Colors.white.withOpacity(0.1),
                ),
            ],
          ),
        );
      },
    );
  }

  String _shortWallet(String wallet) {
    if (wallet.isEmpty) return 'No address';
    if (wallet.length <= 10) return wallet;

    // Check cache first
    if (_walletUsernameCache.containsKey(wallet)) {
      final username = _walletUsernameCache[wallet]!;
      final cleanAddress = wallet.startsWith('0x') ? wallet.substring(2) : wallet;
      final last4 = cleanAddress.length >= 4
          ? cleanAddress.substring(cleanAddress.length - 4)
          : cleanAddress;
      return '${username}_$last4';
    }

    // If it's the current user's wallet, use their username
    if (_myWallet != null && wallet == _myWallet && _myUsername != null) {
      final cleanAddress = wallet.startsWith('0x') ? wallet.substring(2) : wallet;
      final last4 = cleanAddress.length >= 4
          ? cleanAddress.substring(cleanAddress.length - 4)
          : cleanAddress;
      return '${_myUsername}_$last4';
    }

    // Fallback: use synchronous formatter
    return formatFriendlyWalletSync(wallet);
  }

  Widget _buildMobileTable() {
    return ListView.builder(
      itemCount: _filteredBlocks.length,
      itemBuilder: (context, index) {
        final block = _filteredBlocks[index];
        final isSelected = _selectedBlock?.hash == block.hash;

        return Card(
          color: isSelected ? const Color(0xFF6366F1).withOpacity(0.1) : const Color(0xFF1A1A1A),
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedBlock = isSelected ? null : block;
                _showDetailsPane = !isSelected;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: LL-Title + status icons
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _parcelSummary(block.rawData).title, // e.g., "LL-Tema-4EDF0E"
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (block.isVerified) const Icon(Icons.verified, color: Colors.green, size: 16),
                      if (block.isFinalized) const Icon(Icons.lock, color: Colors.blue, size: 16),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Type + Region/Country chip (if available)
                  Builder(builder: (_) {
                    final p = _parcelSummary(block.rawData);
                    final chips = <Widget>[
                      ...block.types.map((t) => _buildTypeChip(t)),
                      if (p.iso2 != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF23313A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_flagEmojiFromISO2(p.iso2!)} ${p.iso2}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ];
                    return Wrap(spacing: 8, children: chips);
                  }),

                  const SizedBox(height: 8),

                  // Owner / Title / Area line
                  Builder(builder: (_) {
                    final p = _parcelSummary(block.rawData);
                    final ownerAddr = (block.rawData['owner'] ?? block.rawData['ownerId'] ?? block.rawData['currentOwner'])?.toString() ?? '';
                    final ownerLabel = _ownerLabel(block.rawData);
                    final areaLabel = formatAreaLabel(p.areaKm2);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title + Area on one line
                        _metaLine(['Title: ${p.title}', 'Area: $areaLabel']),
                        const SizedBox(height: 6),

                        // Owner chip (friendly)
                        OwnerChip(
                          address: ownerAddr,
                          display: ownerLabel,
                          onView: ownerAddr.isEmpty
                              ? null
                              : () => _openDetails({'owner': ownerAddr}, fromBlockchain: true),
                        ),
                      ],
                    );
                  }),

                  const SizedBox(height: 8),

                  // Timestamp
                  Text(
                    DateFormat('MMM d, HH:mm').format(block.timestamp),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),

                  const SizedBox(height: 12),

                  // Actions: Map + Details
                  Builder(builder: (_) {
                    final p = _parcelSummary(block.rawData);
                    return Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: p.coords.isEmpty ? null : () => _showMapPreview(p.coords),
                            icon: const Icon(Icons.map, size: 16),
                            label: const Text('View on Map', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white.withOpacity(0.2)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _openDetails(block.rawData, fromBlockchain: true),
                            icon: const Icon(Icons.visibility, size: 16),
                            label: const Text('Details', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypeChip(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getTypeColor(type).withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getTypeColor(type).withOpacity(0.3)),
      ),
      child: Text(
        type,
        style: TextStyle(
          color: _getTypeColor(type),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildRegionChip(String region) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        region,
        style: const TextStyle(
          color: Color(0xFF6366F1),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'parcel.create':
        return Colors.green;
      case 'parcel.transfer':
        return Colors.blue;
      case 'parcel.update':
        return Colors.orange;
      case 'parcel.delete':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Safe string helpers to prevent RangeError
  String _prefix(String s, int n) => s.length <= n ? s : s.substring(0, n);

  String _shortHash(String s, {int head = 8, int tail = 6}) {
    if (s.length <= head + tail + 1) return s;
    return '${s.substring(0, head)}…${s.substring(s.length - tail)}';
  }

  Widget _buildHashVisualization(String hash) {
    // Create a simple 3-dot visual pattern based on hash
    final pattern = <Color>[];

    // Generate 3 colors based on hash characters
    for (int i = 0; i < 3; i++) {
      final char = hash.codeUnitAt(i % hash.length);
      final hue = (char * 137.5) % 360;
      pattern.add(HSVColor.fromAHSV(0.8, hue, 0.7, 0.9).toColor());
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: pattern.asMap().entries.map((entry) {
        final color = entry.value;

        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        );
      }).toList(),
    );
  }

  // Safely extract common parcel fields from a BlockData.rawData map.
  ({String id, String title, String owner, List<LatLng> coords, double? areaKm2, String? iso2})
  _parcelSummary(Map<String, dynamic> m) {
    final id = (m['parcelId'] ?? m['id'] ?? m['titleNumber'] ?? m['title_number'] ?? '—').toString();
    final title = (m['titleNumber'] ?? m['title_number'] ?? id).toString();
    final owner = (m['owner'] ?? m['ownerId'] ?? m['currentOwner'] ?? 'unknown').toString();
    final coords = parseCoordinates(m['coordinates']);
    final areaKm2 = (m['areaSqKm'] is num) ? (m['areaSqKm'] as num).toDouble() : computeAreaKm2(coords);
    final iso2 = _countryCodeOf(m);
    return (id: id, title: title, owner: owner, coords: coords, areaKm2: areaKm2, iso2: iso2);
  }

  // 1) Shorten any long string like a wallet hex
  String _shortHex(String a, {int head = 6, int tail = 4}) {
    if (a.isEmpty) return '—';
    final s = a.startsWith('0x') ? a : '0x$a';
    if (s.length <= head + tail + 2) return s;
    return '${s.substring(0, 2 + head)}…${s.substring(s.length - tail)}';
  }

  // 2) Lightweight identicon color from address (no deps)
  static Color _identiconColor(String a) {
    if (a.isEmpty) return const Color(0xFF6366F1); // Default blue color for empty addresses

    int h = 0;
    for (final c in a.codeUnits) { h = (h * 31 + c) & 0xFFFFFF; }

    // Ensure we have a valid color with good contrast
    final color = Color(0xFF000000 | h);

    // Avoid very dark or very bright colors that might not render well
    if (color.computeLuminance() < 0.1) {
      // Too dark, lighten it
      return Color.fromARGB(255, (color.red + 100).clamp(0, 255), (color.green + 100).clamp(0, 255), (color.blue + 100).clamp(0, 255));
    } else if (color.computeLuminance() > 0.9) {
      // Too bright, darken it
      return Color.fromARGB(255, (color.red - 100).clamp(0, 255), (color.green - 100).clamp(0, 255), (color.blue - 100).clamp(0, 255));
    }

    return color.withOpacity(1);
  }

  // 3) Generate a friendly codename when no display name is known
  static const _adj = ['jade','amber','crimson','teal','indigo','silver','golden','violet','cobalt','emerald'];
  static const _noun = ['lion','heron','falcon','panda','lynx','otter','tiger','orca','phoenix','wolf'];
  String _codename(String a) {
    if (a.isEmpty) return 'anonymous';
    int h = 0; for (final c in a.codeUnits) { h = (h * 131 + c) & 0x7FFFFFFF; }
    final w1 = _adj[h % _adj.length];
    final w2 = _noun[(h >> 8) % _noun.length];
    final suffix = a.length >= 4 ? a.substring(a.length - 4) : a;
    return '$w1-$w2·$suffix';
  }

  // 4) Resolve display name from your data if available
  //    Try ownerName/ownerId/profile map on rawData; fall back to codename.
  String _ownerLabel(Map<String, dynamic> raw) {
    final explicit = (raw['ownerName'] ?? raw['owner_label'])?.toString();
    if (explicit != null && explicit.trim().isNotEmpty) return explicit.trim();
    final addr = (raw['owner'] ?? raw['ownerId'] ?? raw['currentOwner'])?.toString() ?? '';
    // Use friendly wallet format instead of fake codename
    if (addr.startsWith('0x')) return _shortWallet(addr);
    return addr.isNotEmpty ? addr : 'Unknown';
  }

  // ===========================
  // DETAILS PANE
  // ===========================
  Widget _buildDetailsPane() {
    if (_selectedBlock == null) {
      return Container(
        color: const Color(0xFF0E0E0E),
        child: const Center(
          child: Text(
            'Select a block to view details',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final block = _selectedBlock!;
    final parcelData = block.rawData;

    return Container(
      color: const Color(0xFF0E0E0E),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                Text(
                  'Block #${block.height}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () {
                    setState(() {
                      _selectedBlock = null;
                      _showDetailsPane = false;
                    });
                  },
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Overview'),
                      Tab(text: 'Transactions'),
                      Tab(text: 'Parcel'),
                      Tab(text: 'JSON'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildOverviewTab(block),
                        _buildTransactionsTab(block),
                        _buildParcelTab(parcelData),
                        _buildJsonTab(block),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(BlockData block) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow('Block Height', '#${block.height}'),
          _buildDetailRow('Block Hash', block.hash),
          _buildDetailRow('Previous Hash', block.prevHash ?? 'Genesis Block'),
          _buildDetailRow('Timestamp', DateFormat('yyyy-MM-dd HH:mm:ss').format(block.timestamp)),
          _buildDetailRow('Transactions', block.txCount.toString()),
          _buildDetailRow('Status', block.isVerified ? 'Verified' : 'Pending'),

          const SizedBox(height: 16),
          const Text('Types', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: block.types.map((type) => _buildTypeChip(type)).toList(),
          ),

          const SizedBox(height: 16),
          const Text('Actors', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...block.actors.map((actor) => _buildDetailRow('', actor)),

          const SizedBox(height: 16),
          const Text('Regions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: block.regionCodes.map((region) => _buildRegionChip(region)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab(BlockData block) {
    return const Center(
      child: Text(
        'Transaction details will be displayed here',
        style: TextStyle(color: Colors.white54),
      ),
    );
  }

  Widget _buildParcelTab(Map<String, dynamic> parcelData) {
    final iso2 = _countryCodeOf(parcelData);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (iso2 != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF23313A), borderRadius: BorderRadius.circular(8)),
                child: Text('${_flagEmojiFromISO2(iso2)} $iso2',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ]),
          ],
          _buildDetailRow('Parcel ID', parcelData['parcelId']?.toString() ?? 'N/A'),
          _buildDetailRow('Title Number', parcelData['titleNumber']?.toString() ?? 'N/A'),
          _buildDetailRow('Owner', _shortWallet(parcelData['owner']?.toString() ?? '')),
          _buildDetailRow('Area', formatAreaLabel(_resolveAreaKm2(parcelData))),
          _buildDetailRow('Description', parcelData['description']?.toString() ?? 'N/A'),

          const SizedBox(height: 16),
          const Text('Coordinates', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (parcelData['coordinates'] != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                jsonEncode(parcelData['coordinates']),
                style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12),
              ),
            )
          else
            const Text('No coordinates available', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildJsonTab(BlockData block) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          const JsonEncoder.withIndent('  ').convert(block.rawData),
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loading() => const Center(
      child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));

  Widget _error(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(msg, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
            ],
          ),
        ),
      );

  // ===========================
  // Block numbering + filtering
  // ===========================
  DateTime _createdAtOf(Map<String, dynamic> m) {
    final v = m['createdAt'];
    if (v is String) return DateTime.tryParse(v)?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (v is int) {
      return v > 20000000000
          ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true);
    }
    if (v is Map && v['ms'] is int) return DateTime.fromMillisecondsSinceEpoch(v['ms'], isUtc: true);
    if (v is Map && v['seconds'] is int) return DateTime.fromMillisecondsSinceEpoch(v['seconds'] * 1000, isUtc: true);
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  List<Map<String, dynamic>> _withChronologicalBlockNumbers(List<Map<String, dynamic>> list) {
    final asc = List<Map<String, dynamic>>.from(list)
      ..sort((a, b) => _createdAtOf(a).compareTo(_createdAtOf(b)));

    for (int i = 0; i < asc.length; i++) {
      final m = asc[i];
      m['blockNumber'] ??= (i + 1); // 1-based oldest..newest
    }
    return asc;
  }

  String? _walletOf(Map<String, dynamic> m) {
    final raw = m['_raw'];
    if (raw is Map) {
      final props = (raw['properties'] as Map?) ?? raw;
      final w = props['wallet'] ?? props['walletAddress'] ?? props['address'];
      if (w is String && w.trim().isNotEmpty) return w.trim();
    }
    final w2 = m['wallet'] ?? m['walletAddress'];
    if (w2 is String && w2.trim().isNotEmpty) return w2.trim();

    // Also check owner field if it looks like a wallet address (starts with 0x)
    final owner = m['owner']?.toString().trim();
    if (owner != null && owner.isNotEmpty && owner.startsWith('0x')) {
      return owner;
    }

    return null;
  }

  void _recomputeMyParcels() {
    debugPrint('LandledgerScreen: _recomputeMyParcels called');
    debugPrint('LandledgerScreen: _allParcels length = ${_allParcels.length}');
    debugPrint('LandledgerScreen: _myWallet = $_myWallet');
    debugPrint('LandledgerScreen: _myOwnerId = $_myOwnerId');

    // Prioritize wallet match; if wallet unknown, fall back to ownerId match.
    _myParcels = _allParcels.where((m) {
      final wallet = _walletOf(m);
      final owner = (m['owner'] ?? m['ownerId'] ?? m['currentOwner'])?.toString();
      debugPrint('LandledgerScreen: Checking parcel ${m['parcelId']}: wallet=$wallet, owner=$owner');

      if (_myWallet != null && _myWallet!.isNotEmpty) {
        final matches = wallet == _myWallet;
        debugPrint('LandledgerScreen: Wallet match: $matches');
        return matches;
      }
      final matches = (_myOwnerId != null && _myOwnerId!.isNotEmpty && owner == _myOwnerId);
      debugPrint('LandledgerScreen: Owner match: $matches');
      return matches;
    }).toList()
      ..sort((a, b) => (b['blockNumber'] as int).compareTo(a['blockNumber'] as int));

    debugPrint('LandledgerScreen: _myParcels length = ${_myParcels.length}');
  }

  void _applyFilters() {
    debugPrint('LandledgerScreen: _applyFilters called');
    debugPrint('LandledgerScreen: _allBlocks length = ${_allBlocks.length}');

    _filteredBlocks = _allBlocks.where((block) {
      // Apply search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matches = block.hash.toLowerCase().contains(query) ||
                       block.types.any((type) => type.toLowerCase().contains(query)) ||
                       block.actors.any((actor) => actor.toLowerCase().contains(query)) ||
                       block.regionCodes.any((region) => region.toLowerCase().contains(query));
        if (!matches) return false;
      }

      // Apply date range filter
      if (_dateRange != null) {
        if (block.timestamp.isBefore(_dateRange!.start) || block.timestamp.isAfter(_dateRange!.end)) {
          return false;
        }
      }

      // Apply region filter
      if (_selectedRegion != null && _selectedRegion!.isNotEmpty) {
        if (!block.regionCodes.contains(_selectedRegion)) {
          return false;
        }
      }

      // Apply "my blocks" filter
      if (_showOnlyMyBlocks) {
        final wallet = _walletOf(block.rawData);
        final owner = (block.rawData['owner'] ?? block.rawData['ownerId'] ?? block.rawData['currentOwner'])?.toString();
        final matchesWallet = _myWallet != null && _myWallet!.isNotEmpty && wallet == _myWallet;
        final matchesOwner = _myOwnerId != null && _myOwnerId!.isNotEmpty && owner == _myOwnerId;
        if (!matchesWallet && !matchesOwner) return false;
      }

      return true;
    }).toList();

    // Apply sorting
    _filteredBlocks.sort((a, b) {
      int comparison = 0;
      switch (_sortBy) {
        case 'height':
          comparison = a.height.compareTo(b.height);
          break;
        case 'timestamp':
          comparison = a.timestamp.compareTo(b.timestamp);
          break;
        case 'type':
          comparison = a.types.first.compareTo(b.types.first);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });

    debugPrint('LandledgerScreen: _filteredBlocks length = ${_filteredBlocks.length}');
  }

  // ===========================
  // View Helpers
  // ===========================
  bool _isAnalyticsView(_ViewMode v) =>
      v == _ViewMode.transactions || v == _ViewMode.actors || v == _ViewMode.regions;

  Widget _buildAnalyticsView() {
    switch (_view) {
      case _ViewMode.transactions:
        return _TransactionsAnalytics(blocks: _filteredBlocks.isEmpty ? _allBlocks : _filteredBlocks);
      case _ViewMode.actors:
        return _ActorsAnalytics(blocks: _filteredBlocks.isEmpty ? _allBlocks : _filteredBlocks);
      case _ViewMode.regions:
        return EnhancedRegionsView(blocks: _filteredBlocks.isEmpty ? _allBlocks : _filteredBlocks);
      default:
        return const SizedBox.shrink();
    }
  }

  // ===========================
  // Region Map Section for AppBar
  // ===========================
  Widget _buildRegionMapSection() {
    // Get current region data for display
    final regionData = _groupBlocksByRegion(_allBlocks);

    return Container(
      width: 200,
      height: 40,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            // Simple world map representation
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
              ),
              child: Center(
                child: Text(
                  '🗺️',
                  style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.5)),
                ),
              ),
            ),

            // Region markers overlay
            if (regionData.isNotEmpty)
              ...regionData.entries.take(3).map((entry) {
                final regionCode = entry.key;
                final data = entry.value;
                final count = data['count'] as int;
                final position = _getAppBarMapPosition(regionCode);

                return Positioned(
                  left: position.dx,
                  top: position.dy,
                  child: _buildAppBarLocationMarker(count, regionCode),
                );
              }),

            // Region count indicator
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${regionData.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Offset _getAppBarMapPosition(String regionCode) {
    // Position countries in a compact app bar map layout
    const positions = {
      'NG': Offset(80, 15),   // Nigeria (West Africa)
      'KE': Offset(90, 18),   // Kenya (East Africa)
      'GH': Offset(75, 12),   // Ghana (West Africa)
      'CM': Offset(85, 10),   // Cameroon (Central Africa)
      'US': Offset(20, 8),    // United States (North America)
      'ZA': Offset(80, 25),   // South Africa (Southern Africa)
      'ET': Offset(85, 8),    // Ethiopia (Horn of Africa)
      'RW': Offset(88, 16),   // Rwanda (East Africa)
      'UG': Offset(82, 14),   // Uganda (East Africa)
    };

    return positions[regionCode] ?? const Offset(50, 15);
  }

  Widget _buildAppBarLocationMarker(int count, String regionCode) {
    final size = (count * 2 + 8).clamp(8, 16).toDouble();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF6366F1).withOpacity(0.7),
        border: Border.all(
          color: Colors.white.withOpacity(0.8),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          count.toString(),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Map<String, Map<String, dynamic>> _groupBlocksByRegion(List<BlockData> blocks) {
    final regionGroups = <String, Map<String, dynamic>>{};

    for (final block in blocks) {
      for (final regionCode in block.regionCodes) {
        if (regionGroups.containsKey(regionCode)) {
          regionGroups[regionCode]!['count'] = (regionGroups[regionCode]!['count'] as int) + 1;
          regionGroups[regionCode]!['blocks'].add(block);
        } else {
          regionGroups[regionCode] = {
            'count': 1,
            'blocks': [block],
            'countryName': _getCountryName(regionCode),
          };
        }
      }
    }

    return regionGroups;
  }

  String _getCountryName(String regionCode) {
    const countryNames = {
      'NG': 'Nigeria',
      'KE': 'Kenya',
      'GH': 'Ghana',
      'CM': 'Cameroon',
      'ZA': 'South Africa',
      'ET': 'Ethiopia',
      'RW': 'Rwanda',
      'UG': 'Uganda',
      'US': 'United States',
    };
    return countryNames[regionCode] ?? regionCode;
  }

  // ===========================
  // Build
  // ===========================
  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? _loading()
          : _errorMessage.isNotEmpty
              ? _error(_errorMessage)
              : Column(
                  children: [
                    // Filter bar
                    _buildFilterBar(),

                    // Metrics row
                    _buildMetricsRow(),

                    // Main content
                    Expanded(
                      child: _isAnalyticsView(_view)
                          ? _buildAnalyticsView()         // Transactions / Actors / Regions
                          : (isDesktop && _showDetailsPane
                              ? Row(
                                  children: [
                                    // Table (left side)
                                    Expanded(
                                      flex: 2,
                                      child: _buildBlockTable(),
                                    ),
                                    // Details pane (right side)
                                    Container(
                                      width: 400,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(color: Colors.white.withOpacity(0.1)),
                                        ),
                                      ),
                                      child: _buildDetailsPane(),
                                    ),
                                  ],
                                )
                              : RefreshIndicator(
                                  onRefresh: _loadData,
                                  child: _buildBlockTable(),
                                )),
                    ),
                  ],
                ),
    );
  }
}

/// =======================================
/// ANALYTICS WIDGETS
/// =======================================

class _TransactionsAnalytics extends StatelessWidget {
 final List<BlockData> blocks;
 const _TransactionsAnalytics({required this.blocks});

 @override
 Widget build(BuildContext context) {
   final typeCounts = <String, int>{};
   for (final block in blocks) {
     for (final type in block.types) {
       typeCounts[type] = (typeCounts[type] ?? 0) + 1;
     }
   }
   final sorted = typeCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

   return SingleChildScrollView(
     padding: const EdgeInsets.all(16),
     child: Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         const Text('Transaction Types', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
         const SizedBox(height: 16),
         ...sorted.map((entry) => Card(
               color: const Color(0xFF1F1F1F),
               child: ListTile( title: Text(entry.key, style: const TextStyle(color: Colors.white)),
                 trailing: Text('${entry.value}', style: const TextStyle(color: Colors.white70)),
               ),
             )),
       ],
     ),
   );
 }
}

class _ActorsAnalytics extends StatelessWidget {
 final List<BlockData> blocks;
 const _ActorsAnalytics({required this.blocks});

 @override
 Widget build(BuildContext context) {
   final actorCounts = <String, int>{};
   for (final block in blocks) {
     for (final actor in block.actors) {
       actorCounts[actor] = (actorCounts[actor] ?? 0) + 1;
     }
   }
   final sorted = actorCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

   return SingleChildScrollView(
     padding: const EdgeInsets.all(16),
     child: Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         const Text('Actors', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
         const SizedBox(height: 16),
         ...sorted.map((entry) => Card(
               color: const Color(0xFF1F1F1F),
               child: ListTile(
                 title: Text(formatFriendlyWalletSync(entry.key), style: const TextStyle(color: Colors.white)),
                 trailing: Text('${entry.value}', style: const TextStyle(color: Colors.white70)),
               ),
             )),
       ],
     ),
   );
 }
}

class _RegionsMapView extends StatefulWidget {
  final List<BlockData> blocks;
  const _RegionsMapView({required this.blocks});

  @override
  State<_RegionsMapView> createState() => _RegionsMapViewState();
}

class _RegionsMapViewState extends State<_RegionsMapView> {
  final String _selectedRegion = 'all';
  final bool _showSatelliteView = false;
  final String _sortBy = 'count'; // count, value, area
  
  @override
  Widget build(BuildContext context) {
    // Group blocks by country/region for geographical visualization
    final regionData = _groupBlocksByRegion(widget.blocks);
    final filteredData = _selectedRegion == 'all' 
        ? regionData 
        : {_selectedRegion: regionData[_selectedRegion]!};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TODO: Implement enhanced analytics features
          // Enhanced Header with Controls
          // _buildEnhancedHeader(regionData),

          const SizedBox(height: 20),

          // Global Statistics Dashboard
          // _buildGlobalStatsDashboard(regionData),

          const SizedBox(height: 24),

          // Interactive World Map with Property Markers
          // _buildEnhancedWorldMap(regionData),

          const SizedBox(height: 24),

          // Regional Analytics Cards
          // _buildRegionalAnalytics(regionData),

          const SizedBox(height: 24),

          // Transaction Value Analysis
          // _buildTransactionValueAnalysis(regionData),

          const SizedBox(height: 24),

          // Detailed Region List with Enhanced Stats
          // _buildEnhancedRegionList(regionData),

          // Placeholder content for now
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Enhanced analytics features coming soon...',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Map<String, dynamic>> _groupBlocksByRegion(List<BlockData> blocks) {
    final regionGroups = <String, Map<String, dynamic>>{};

    for (final block in blocks) {
      for (final regionCode in block.regionCodes) {
        if (regionGroups.containsKey(regionCode)) {
          regionGroups[regionCode]!['count'] = (regionGroups[regionCode]!['count'] as int) + 1;
          regionGroups[regionCode]!['blocks'].add(block);
        } else {
          regionGroups[regionCode] = {
            'count': 1,
            'blocks': [block],
            'countryName': _getCountryName(regionCode),
          };
        }
      }
    }

    return regionGroups;
  }

  String _getCountryName(String regionCode) {
    const countryNames = {
      'NG': 'Nigeria',
      'KE': 'Kenya',
      'GH': 'Ghana',
      'CM': 'Cameroon',
      'ZA': 'South Africa',
      'ET': 'Ethiopia',
      'RW': 'Rwanda',
      'UG': 'Uganda',
      'US': 'United States',
    };
    return countryNames[regionCode] ?? regionCode;
  }

  Widget _buildDiasporaMapVisualization(Map<String, Map<String, dynamic>> regionData) {
    return Container(
      height: 300,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Map Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                const Text(
                  '🗺️ LandLedger Diaspora Map',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${regionData.values.fold<int>(0, (sum, data) => sum + (data['count'] as int))} Properties',
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Map Content
          Expanded(
            child: _buildInteractiveDiasporaMap(regionData),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveDiasporaMap(Map<String, Map<String, dynamic>> regionData) {
    // Extract all coordinates from blocks for Google Maps visualization
    final allCoordinates = <LatLng>[];
    final countryCoordinates = <String, List<LatLng>>{};
    final markers = <gmap.Marker>[];

    for (final entry in regionData.entries) {
      final regionCode = entry.key;
      final blocks = entry.value['blocks'] as List<BlockData>;

      for (final block in blocks) {
        final coords = _parseCoordinatesForMap(block.rawData['coordinates']);
        if (coords.isNotEmpty) {
          allCoordinates.addAll(coords);
          countryCoordinates[regionCode] ??= [];
          countryCoordinates[regionCode]!.addAll(coords);

          // Create marker for this region
          final center = _centerOf(coords);
          final count = entry.value['count'] as int;
          final countryName = entry.value['countryName'] as String;

          markers.add(
            gmap.Marker(
              markerId: gmap.MarkerId(regionCode),
              position: _g(center),
              infoWindow: gmap.InfoWindow(
                title: '$countryName (${_flagEmojiFromISO2(regionCode)})',
                snippet: '$count properties',
              ),
              icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                _getMarkerHue(count),
              ),
            ),
          );
        }
      }
    }

    if (allCoordinates.isEmpty) {
      return const Center(
        child: Text(
          'No location data available\nAdd coordinates to see the map!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    // Calculate bounds for all coordinates
    final bounds = _calculateBounds(allCoordinates);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Google Maps Widget
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: gmap.GoogleMap(
                  initialCameraPosition: gmap.CameraPosition(
                    target: _g(_centerOf(allCoordinates)),
                    zoom: 2,
                  ),
                  markers: markers.toSet(),
                  mapType: gmap.MapType.normal,
                  zoomControlsEnabled: true,
                  mapToolbarEnabled: true,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  onMapCreated: (controller) async {
                    await Future<void>.delayed(const Duration(milliseconds: 200));
                    if (bounds != null) {
                      await controller.animateCamera(
                        gmap.CameraUpdate.newLatLngBounds(bounds, 50),
                      );
                    }
                  },
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Legend and Summary
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDiasporaLegendItem('High Activity (10+)', const Color(0xFF6366F1)),
                _buildDiasporaLegendItem('Medium Activity (5-9)', const Color(0xFF10B981)),
                _buildDiasporaLegendItem('Low Activity (1-4)', const Color(0xFFF59E0B)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Offset _getDiasporaMapPosition(String regionCode) {
    // Position countries on a simplified world map
    const positions = {
      'NG': Offset(200, 150), // Nigeria (West Africa)
      'KE': Offset(220, 160), // Kenya (East Africa)
      'GH': Offset(190, 140), // Ghana (West Africa)
      'CM': Offset(210, 130), // Cameroon (Central Africa)
      'US': Offset(80, 100),  // United States (North America)
      'ZA': Offset(200, 200), // South Africa (Southern Africa)
      'ET': Offset(210, 120), // Ethiopia (Horn of Africa)
      'RW': Offset(215, 145), // Rwanda (East Africa)
      'UG': Offset(205, 135), // Uganda (East Africa)
    };

    return positions[regionCode] ?? const Offset(150, 100);
  }

  Widget _buildDiasporaLocationMarker(int count, String regionCode, String countryName) {
    // Determine marker size and color based on activity level
    final activityLevel = _getActivityLevel(count);
    final size = _getMarkerSize(count);
    final color = _getActivityColor(activityLevel);

    return GestureDetector(
      onTap: () {
        // TODO: Show location details when context is available
        debugPrint('Region: $regionCode, Country: $countryName, Count: $count');
      },
      child: Tooltip(
        message: '$countryName: $count properties',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: Colors.white.withOpacity(0.8),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getActivityLevel(int count) {
    if (count >= 10) return 'high';
    if (count >= 5) return 'medium';
    return 'low';
  }

  double _getMarkerSize(int count) {
    return (count * 3 + 20).clamp(20, 50).toDouble();
  }

  Color _getActivityColor(String level) {
    switch (level) {
      case 'high':
        return const Color(0xFF6366F1);
      case 'medium':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Widget _buildDiasporaLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }

  void _showDiasporaLocationDetails(BuildContext context, String regionCode, String countryName, int count) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Row(
            children: [
              Text(
                _flagEmojiFromISO2(regionCode),
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 8),
              Text(
                countryName,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Properties in this location: $count',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Click on any location marker to see details about land ownership in that region.',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }


  Widget _buildRegionStatistics(Map<String, Map<String, dynamic>> regionData) {
    final totalProperties = regionData.values.fold<int>(0, (sum, data) => sum + (data['count'] as int));
    final activeRegions = regionData.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Total Properties
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.inventory_2, size: 14, color: Color(0xFF6366F1)),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      totalProperties.toString(),
                      style: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Properties',
                      style: TextStyle(color: Colors.white70, fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Active Regions
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.map, size: 14, color: Color(0xFF10B981)),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeRegions.toString(),
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Countries',
                      style: TextStyle(color: Colors.white70, fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Average per Region
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.analytics, size: 14, color: Color(0xFFF59E0B)),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (totalProperties / activeRegions).toStringAsFixed(1),
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Avg/Country',
                      style: TextStyle(color: Colors.white70, fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegionList(Map<String, Map<String, dynamic>> regionData) {
    final sortedRegions = regionData.entries.toList()
      ..sort((a, b) => (b.value['count'] as int).compareTo(a.value['count'] as int));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Countries by Activity',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        // Horizontal scrollable list of countries
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: sortedRegions.map((entry) {
              final regionCode = entry.key;
              final data = entry.value;
              final count = data['count'] as int;
              final countryName = data['countryName'] as String;

              return Container(
                width: 90,
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      _flagEmojiFromISO2(regionCode),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count.toString(),
                      style: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      countryName,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 8,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _flagEmojiFromISO2(String iso2) {
    const int base = 0x1F1E6;
    final a = iso2.codeUnitAt(0) - 65;
    final b = iso2.codeUnitAt(1) - 65;
    return String.fromCharCode(base + a) + String.fromCharCode(base + b);
  }

  // Helper methods for Google Maps
  LatLng _centerOf(List<LatLng> pts) {
    if (pts.isEmpty) return const LatLng(0, 0);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  gmap.LatLng _g(LatLng p) => gmap.LatLng(p.latitude, p.longitude);

  double _getMarkerHue(int count) {
    if (count >= 10) return gmap.BitmapDescriptor.hueBlue;
    if (count >= 5) return gmap.BitmapDescriptor.hueGreen;
    return gmap.BitmapDescriptor.hueOrange;
  }

  gmap.LatLngBounds? _calculateBounds(List<LatLng> pts) {
    if (pts.isEmpty) return null;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    return gmap.LatLngBounds(
      southwest: gmap.LatLng(minLat, minLng),
      northeast: gmap.LatLng(maxLat, maxLng),
    );
  }

  Set<gmap.Polygon> _createCountryPolygons(Map<String, List<LatLng>> countryCoordinates) {
    final polygons = <gmap.Polygon>{};

    // For now, we'll create simple polygons around country centers
    // In a real implementation, you might want to use actual country boundary data
    for (final entry in countryCoordinates.entries) {
      final regionCode = entry.key;
      final coords = entry.value;

      if (coords.isNotEmpty) {
        final center = _centerOf(coords);
        // Create a simple bounding box polygon for each country
        final polygonPoints = <gmap.LatLng>[
          gmap.LatLng(center.latitude - 0.5, center.longitude - 0.5),
          gmap.LatLng(center.latitude - 0.5, center.longitude + 0.5),
          gmap.LatLng(center.latitude + 0.5, center.longitude + 0.5),
          gmap.LatLng(center.latitude + 0.5, center.longitude - 0.5),
        ];

        polygons.add(
          gmap.Polygon(
            polygonId: gmap.PolygonId('country_$regionCode'),
            points: polygonPoints,
            strokeWidth: 1,
            strokeColor: const Color(0xFF6366F1).withOpacity(0.8),
            fillColor: const Color(0xFF6366F1).withOpacity(0.2),
          ),
        );
      }
    }

    return polygons;
  }

  // Helper method for parsing coordinates in the regions view
  List<LatLng> _parseCoordinatesForMap(dynamic coords) {
    final out = <LatLng>[];
    if (coords == null) return out;
    if (coords is List) {
      for (final c in coords) {
        if (c is Map) {
          final lat = c['lat'] ?? c['latitude'];
          final lng = c['lng'] ?? c['longitude'];
          if (lat is num && lng is num) {
            out.add(LatLng(lat.toDouble(), lng.toDouble()));
          }
        } else if (c is List && c.length >= 2) {
          // [lng, lat] geojson-style pair
          final lng = c[0], lat = c[1];
          if (lat is num && lng is num) out.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
    }
    return out;
  }
}

/// =======================================
/// PRETTY PARCEL VIEWER (tab 1)
/// =======================================
class _ParcelViewer extends StatefulWidget {
  final String? parcelId;
  final Map<String, dynamic>? initialParcel;
  const _ParcelViewer({this.parcelId, this.initialParcel});

  @override
  State<_ParcelViewer> createState() => _ParcelViewerState();
}

class _ParcelViewerState extends State<_ParcelViewer> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _parcel;

  @override
  void initState() {
    super.initState();
    if (widget.initialParcel != null) {
      _parcel = Map<String, dynamic>.from(widget.initialParcel!);
    }
    if (widget.initialParcel == null && widget.parcelId != null && widget.parcelId!.isNotEmpty) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _parcel = null;
    });
    try {
      // Try API first
      final u = await Api.build('/api/landledger/${Uri.encodeComponent(widget.parcelId!)}');
      final resp = await http
          .get(u)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        setState(() => _parcel = (jsonDecode(resp.body) as Map<String, dynamic>));
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } on TimeoutException {
      debugPrint('ParcelViewer: API timeout');
      setState(() => _error = 'Request timed out. Please try again.');
    } catch (e) {
      debugPrint('ParcelViewer: API failed: $e');
      setState(() => _error = 'Failed to load parcel: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _fmtDate(dynamic v) => (_ParcelViewerState._fmtDateStatic(v));
  static String _fmtDateStatic(dynamic val) {
    DateTime? dt;
    if (val == null) return '—';
    if (val is String) dt = DateTime.tryParse(val)?.toLocal();
    if (val is int) {
      dt = val > 20000000000
          ? DateTime.fromMillisecondsSinceEpoch(val).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(val * 1000).toLocal();
    }
    if (val is Map) {
      if (val['ms'] is int) dt = DateTime.fromMillisecondsSinceEpoch(val['ms']).toLocal();
      if (val['seconds'] is int) dt = DateTime.fromMillisecondsSinceEpoch(val['seconds'] * 1000).toLocal();
    }
    if (dt == null) return val.toString();
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  List<LatLng> _coords(dynamic c) {
    final out = <LatLng>[];
    if (c is List) {
      for (final e in c) {
        if (e is Map) {
          final lat = e['lat'] ?? e['latitude'];
          final lng = e['lng'] ?? e['longitude'];
          if (lat is num && lng is num) out.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
    }
    return out;
  }

  String _areaLabel(double? km2) {
    if (km2 == null) return '—';
    if (km2 >= 0.01) return '${km2.toStringAsFixed(2)} km²';
    final m2 = km2 * 1e6;
    return '${m2 >= 100 ? m2.toStringAsFixed(0) : m2.toStringAsFixed(1)} m²';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.parcelId == null || widget.parcelId!.isEmpty) {
      return const Center(child: Text('N/A', style: TextStyle(color: Colors.white70)));
    }
    if (_loading && _parcel == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_parcel == null) return const SizedBox.shrink();

    final p = _parcel!;
    final id = p['parcelId']?.toString() ?? '—';
    final ownerRaw = p['owner']?.toString() ?? '—';
    final owner = formatFriendlyWalletSync(ownerRaw);
    final title = p['titleNumber']?.toString() ?? '—';
    final desc = p['description']?.toString() ?? '';
    final created = p['createdAt'];
    final verified = (p['verified'] ?? true) == true;
    final coords = _coords(p['coordinates']);
    final area = (p['areaSqKm'] is num) ? (p['areaSqKm'] as num).toDouble() : null;

    final canRefresh = widget.parcelId != null && widget.parcelId!.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (canRefresh)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(_parcel == null ? 'Load' : 'Sync latest'),
                  ),
                ],
              ),
            ),
          Card(
            color: const Color(0xFF1F1F1F),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _pill('Parcel', 'LLB-$id'),
                    _pill('Title', title),
                    _pill('Owner', owner),
                    _pill('Verified', verified ? 'Yes' : 'Pending',
                        icon: Icons.verified, iconColor: verified ? Colors.green : Colors.amber),
                    _pill('Area', _areaLabel(area)),
                  ]),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(desc, style: const TextStyle(color: Colors.white)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Created: ${_fmtDate(created)}', style: const TextStyle(color: Colors.white70)),
                      ),
                      TextButton.icon(
                        onPressed: coords.isEmpty
                            ? null
                            : () {
                                final state = context.findAncestorStateOfType<_LandledgerScreenState>();
                                state?._showMapPreview(coords);
                              },
                        icon: const Icon(Icons.map, size: 18),
                        label: const Text('Map'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, String value, {IconData? icon, Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: iconColor ?? Colors.white70),
          const SizedBox(width: 4),
        ],
        Text('$label: ', style: const TextStyle(color: Colors.white70)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// =======================================
/// OWNER VIEWER (tab 2) – pretty summary
/// =======================================
class _OwnerViewer extends StatefulWidget {
  final String? ownerId;
  final Map<String, dynamic>? initialOwner;
  const _OwnerViewer({this.ownerId, this.initialOwner});

  @override
  State<_OwnerViewer> createState() => _OwnerViewerState();
}

class _OwnerViewerState extends State<_OwnerViewer> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _owner;

  @override
  void initState() {
    super.initState();
    if (widget.initialOwner != null) {
      _owner = Map<String, dynamic>.from(widget.initialOwner!);
    }
    if (_owner == null && widget.ownerId != null && widget.ownerId!.isNotEmpty) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _owner = null;
    });
    try {
      // Try API first
      final u = await Api.build('/api/landledger/owner/${Uri.encodeComponent(widget.ownerId!)}');
      final resp = await http
          .get(u)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        setState(() => _owner = (jsonDecode(resp.body) as Map<String, dynamic>));
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } on TimeoutException {
      debugPrint('OwnerViewer: API timeout');
      setState(() => _error = 'Request timed out. Please try again.');
    } catch (e) {
      debugPrint('OwnerViewer: API failed: $e');
      setState(() => _error = 'Failed to load owner: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _fmtDate(dynamic v) => _ParcelViewerState._fmtDateStatic(v);

  String _shortWallet(String wallet) {
    if (wallet.isEmpty) return 'No wallet';
    if (wallet.length <= 10) return wallet;
    return '${wallet.substring(0, 6)}...${wallet.substring(wallet.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ownerId == null || widget.ownerId!.isNotEmpty == false) {
      return const Center(child: Text('N/A', style: TextStyle(color: Colors.white70)));
    }
    if (_loading && _owner == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_owner == null) return const SizedBox.shrink();

    final o = _owner!;
    final name = (o['name'] ?? '').toString();
    final verified = (o['verified'] == true);
    final wallet = (o['walletAddress'] ?? '').toString();
    final email = (o['email'] ?? '').toString();
    final phone = (o['phone'] ?? '').toString();
    final created = o['createdAt'];
    final parcelCount = o['parcelCount'] is num ? (o['parcelCount'] as num).toInt() : 0;
    final parcels = (o['parcels'] is List) ? (o['parcels'] as List).cast<Map<String, dynamic>>() : const <Map<String, dynamic>>[];
    final canRefresh = widget.ownerId != null && widget.ownerId!.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (canRefresh)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(_owner == null ? 'Load' : 'Sync owner'),
                  ),
                ],
              ),
            ),
          Card(
            color: const Color(0xFF1F1F1F),
            child: ListTile( leading: CircleAvatar(
                backgroundColor: const Color(0xFF2F6A5A),
                child: Icon(verified ? Icons.verified : Icons.person, color: verified ? Colors.white : Colors.white70),
              ),
              title: Text(name.isEmpty ? o['ownerId']?.toString() ?? 'Owner' : name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text('Member since: ${_fmtDate(created)}', style: const TextStyle(color: Colors.white70)),
              trailing: verified
                  ? const Chip(label: Text('Verified'), backgroundColor: Color(0xFF164C3F), labelStyle: TextStyle(color: Colors.white))
                  : const Chip(label: Text('Unverified'), backgroundColor: Colors.grey, labelStyle: TextStyle(color: Colors.white)),
            ),
          ),
          if (email.isNotEmpty || phone.isNotEmpty || wallet.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1F1F1F),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    if (email.isNotEmpty) Text('Email: $email', style: const TextStyle(color: Colors.white70)),
                    if (phone.isNotEmpty) Text('Phone: $phone', style: const TextStyle(color: Colors.white70)),
                    if (wallet.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_rounded, size: 14, color: Colors.tealAccent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.teal.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _shortWallet(wallet),
                                      style: const TextStyle(
                                        color: Colors.tealAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'monospace',
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                    icon: const Icon(Icons.copy, size: 12, color: Colors.grey),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: wallet));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Wallet address copied!')),
                                      );
                                    },
                                    tooltip: 'Copy wallet address',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1F1F1F),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Parcels ($parcelCount)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (parcels.isEmpty)
                    const Text('No parcels found for this owner.', style: TextStyle(color: Colors.white70))
                  else
                    ...parcels.map((p) {
                      final id = p['parcelId']?.toString() ?? '—';
                      final title = p['titleNumber']?.toString() ?? id;
                      final area = p['areaSqKm'] is num ? (p['areaSqKm'] as num).toDouble() : null;
                      final coords = (p['coordinates'] as List?) ?? const [];
                      return ListTile(
                        leading: const Icon(Icons.verified),
                        contentPadding: EdgeInsets.zero,
                        title: Text(title, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          [
                            if (area != null)
                              'Area: ${area >= .01 ? '${area.toStringAsFixed(2)} km²' : '${(area * 1e6).toStringAsFixed(0)} m²'}',
                            'Created: ${_fmtDate(p['createdAt'])}',
                          ].join(' • '),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.map, color: Colors.white70),
                          onPressed: coords.isEmpty
                              ? null
                              : () {
                                  final points = <LatLng>[];
                                  for (final e in coords) {
                                    if (e is Map && e['lat'] is num && e['lng'] is num) {
                                      points.add(LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()));
                                    }
                                  }
                                  final screen = context.findAncestorStateOfType<_LandledgerScreenState>();
                                  screen?._showMapPreview(points);
                                },
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =======================================
/// TITLE / DEED VIEWER (tab 3)
/// =======================================
class _TitleViewer extends StatefulWidget {
  final String? titleNumber;
  final Map<String, dynamic>? initialTitle;
  const _TitleViewer({this.titleNumber, this.initialTitle});
  @override
  State<_TitleViewer> createState() => _TitleViewerState();
}

class _TitleViewerState extends State<_TitleViewer> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _deed;

  @override
  void initState() {
    super.initState();
    if (widget.initialTitle != null) {
      _deed = Map<String, dynamic>.from(widget.initialTitle!);
    }
    if (_deed == null && widget.titleNumber != null && widget.titleNumber!.isNotEmpty) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _deed = null;
    });
    try {
      // Try API first
      final u = await Api.build('/api/landledger/title/${Uri.encodeComponent(widget.titleNumber!)}');
      final resp = await http
          .get(u)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        setState(() => _deed = (jsonDecode(resp.body) as Map<String, dynamic>));
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } on TimeoutException {
      debugPrint('TitleViewer: API timeout');
      setState(() => _error = 'Request timed out. Please try again.');
    } catch (e) {
      debugPrint('TitleViewer: API failed: $e');
      setState(() => _error = 'Failed to load title: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _fmtDate(dynamic v) => _ParcelViewerState._fmtDateStatic(v);

  @override
  Widget build(BuildContext context) {
    if (widget.titleNumber == null || widget.titleNumber!.isNotEmpty == false) {
      return const Center(child: Text('N/A', style: TextStyle(color: Colors.white70)));
    }
    if (_loading && _deed == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_deed == null) return const SizedBox.shrink();

    final d = _deed!;
    final title = d['titleNumber']?.toString() ?? widget.titleNumber!;
    final issued = d['issuedAt'];
    final registrar = (d['registrar'] ?? '').toString();
    final docHash = (d['docHash'] ?? '').toString();
    final docUrl = (d['docUrl'] ?? '').toString();
    final enc = (d['encumbrances'] is List) ? (d['encumbrances'] as List) : const [];
    final geometry = d['geometry'];
    final canRefresh = widget.titleNumber != null && widget.titleNumber!.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (canRefresh)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(_deed == null ? 'Load' : 'Sync title'),
                  ),
                ],
              ),
            ),
          Card(
            color: const Color(0xFF1F1F1F),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Title $title',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _miniPill('Issued', _fmtDate(issued)),
                    if (registrar.isNotEmpty) _miniPill('Registrar', registrar),
                  ]),
                  const SizedBox(height: 10),
                  if (docHash.isNotEmpty || docUrl.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Document', style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 4),
                        if (docHash.isNotEmpty)
                          SelectableText('Hash: $docHash', style: const TextStyle(color: Colors.white)),
                        if (docUrl.isNotEmpty)
                          SelectableText('URL: $docUrl', style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (enc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1F1F1F),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Encumbrances', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...enc.take(10).map((e) => Text('- $e', style: const TextStyle(color: Colors.white70))),
                  ],
                ),
              ),
            ),
          ],
          if (geometry is Map && geometry['type'] == 'Polygon') ...[
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1F1F1F),
              child: ListTile(
                title: Text('Preview on map', style: TextStyle(color: Colors.white70)),
                trailing: const Icon(Icons.map, color: Colors.white70),
                onTap: () {
                  final points = <LatLng>[];
                  final ring = (geometry['coordinates'] as List?)?.first as List?;
                  if (ring != null) {
                    for (final pair in ring) {
                      if (pair is List && pair.length >= 2) {
                        final lng = pair[0], lat = pair[1];
                        if (lat is num && lng is num) {
                          points.add(LatLng(lat.toDouble(), lng.toDouble()));
                        }
                      }
                    }
                  }
                  final screen = context.findAncestorStateOfType<_LandledgerScreenState>();
                  screen?._showMapPreview(points);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ', style: const TextStyle(color: Colors.white70)),
        Text(value, style: const TextStyle(color: Colors.white)),
      ]),
    );
  }
}

/// =======================================
/// HISTORY VIEWER (tab 4)
/// =======================================
class _HistoryViewer extends StatefulWidget {
  final String? parcelId;
  final String? currentOwnerId;
  final List<Map<String, dynamic>>? initialEvents;
  final Map<String, dynamic>? initialSummary;
  const _HistoryViewer({
    this.parcelId,
    this.currentOwnerId,
    this.initialEvents,
    this.initialSummary,
  });

  @override
  State<_HistoryViewer> createState() => _HistoryViewerState();
}

class _HistoryViewerState extends State<_HistoryViewer> {
  bool _loading = false;
  String? _error;
  List<dynamic> _events = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initialEvents != null && widget.initialEvents!.isNotEmpty) {
      _events = widget.initialEvents!;
    } else if (widget.parcelId != null && widget.parcelId!.isNotEmpty) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _events = const [];
    });
    try {
      // Try API first
      final u = await Api.build('/api/landledger/${Uri.encodeComponent(widget.parcelId!)}/history');
      final resp = await http
          .get(u)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        setState(() => _events = (jsonDecode(resp.body) as List));
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } on TimeoutException {
      debugPrint('HistoryViewer: API timeout');
      setState(() => _error = 'Request timed out. Please try again.');
    } catch (e) {
      debugPrint('HistoryViewer: API failed: $e');
      setState(() => _error = 'Failed to load history: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _fmtDate(dynamic v) => _ParcelViewerState._fmtDateStatic(v);

  String _fmtDuration(Duration d) {
    if (d.inDays >= 365) {
      final years = d.inDays ~/ 365;
      final remDays = d.inDays % 365;
      final months = remDays ~/ 30;
      return months > 0 ? '$years yr $months mo' : '$years yr';
    }
    if (d.inDays >= 30) {
      final months = d.inDays ~/ 30;
      final days = d.inDays % 30;
      return days > 0 ? '$months mo $days d' : '$months mo';
    }
    if (d.inDays >= 1) return '${d.inDays} d';
    if (d.inHours >= 1) return '${d.inHours} h';
    return '${d.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.parcelId == null || widget.parcelId!.isNotEmpty == false) {
      return const Center(child: Text('N/A', style: TextStyle(color: Colors.white70)));
    }
    if (_loading && _events.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    // Summary widgets
    DateTime? createdAt;
    DateTime? currentOwnerSince;
    final now = DateTime.now();
    final summary = widget.initialSummary ?? const {};
    if (summary['createdAt'] != null) {
      createdAt = _tsToDate(summary['createdAt']);
    }
    if (summary['currentOwnerSince'] != null) {
      currentOwnerSince = _tsToDate(summary['currentOwnerSince']);
    }

    for (final e in _events) {
      final ts = e is Map ? e['timestamp'] : null;
      final dt = _tsToDate(ts);
      if (dt != null) {
        if (createdAt == null || dt.isBefore(createdAt)) createdAt = dt;
      }
    }
    if (widget.currentOwnerId != null && widget.currentOwnerId!.isNotEmpty) {
      for (final e in _events.reversed) {
        if (e is! Map) continue;
        final toOwner = (e['toOwner'] ?? e['owner'])?.toString();
        final typ = (e['type'] ?? 'TX').toString().toUpperCase();
        if (toOwner == widget.currentOwnerId && (typ.contains('TRANSFER') || typ.contains('ASSIGN') || typ.contains('MINT'))) {
          currentOwnerSince = _tsToDate(e['timestamp']) ?? currentOwnerSince;
          break;
        }
      }
    }
    currentOwnerSince ??= createdAt;
    final tenure = (currentOwnerSince != null) ? now.difference(currentOwnerSince) : null;
    final canRefresh = widget.parcelId != null && widget.parcelId!.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (canRefresh)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading && _events.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(_events.isEmpty ? 'Load history' : 'Sync history'),
                  ),
                ],
              ),
            ),
          Card(
            color: const Color(0xFF1F1F1F),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                _pill('Created', _fmtDate(createdAt)),
                if (widget.currentOwnerId != null && widget.currentOwnerId!.isNotEmpty)
                  _pill('Current owner', widget.currentOwnerId!),
                if (currentOwnerSince != null)
                  _pill('Owned since',
                      '${_fmtDate(currentOwnerSince)}${tenure != null ? '  (${_fmtDuration(tenure)})' : ''}'),
                _pill('Events', _events.length.toString()),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          if (_events.isEmpty)
            const Text('No history found.', style: TextStyle(color: Colors.white70))
          else
            ..._events.map((e) {
              if (e is! Map) return const SizedBox.shrink();
              final ts = _fmtDate(e['timestamp']);
              final typ = (e['type'] ?? 'TX').toString();
              final from = (e['fromOwner'] ?? '').toString();
              final to = (e['toOwner'] ?? '').toString();
              final txId = (e['txId'] ?? '').toString();
              final preview = txId.length > 16 ? '${txId.substring(0, 8)}…${txId.substring(txId.length - 6)}' : txId;

              final color = typ.toUpperCase() == 'TRANSFER'
                  ? const Color(0xFF165B4A)
                  : (typ.toUpperCase() == 'DELETE' ? Colors.red : const Color(0xFF2A2A2A));

              return Card(
                color: const Color(0xFF1F1F1F),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color,
                    child: Text(typ.substring(0, 1), style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(typ, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    [
                      ts,
                      if (from.isNotEmpty || to.isNotEmpty) 'Owner: ${from.isEmpty ? '?' : from} → ${to.isEmpty ? '?' : to}',
                      if (txId.isNotEmpty) 'txId: $preview',
                    ].join('\n'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  DateTime? _tsToDate(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    if (v is int) {
      return v > 20000000000
          ? DateTime.fromMillisecondsSinceEpoch(v).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(v * 1000).toLocal();
    }
    if (v is Map) {
      if (v['ms'] is int) return DateTime.fromMillisecondsSinceEpoch(v['ms']).toLocal();
      if (v['seconds'] is int) return DateTime.fromMillisecondsSinceEpoch(v['seconds'] * 1000).toLocal();
    }
    return null;
  }

  Widget _pill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ', style: const TextStyle(color: Colors.white70)),
        Text(value, style: const TextStyle(color: Colors.white)),
      ]),
    );
  }
}

/// =======================================
/// ACTIONS tab
/// =======================================
class _ActionsPane extends StatefulWidget {
  final Map<String, dynamic> parcel;
  const _ActionsPane({required this.parcel});

  @override
  State<_ActionsPane> createState() => _ActionsPaneState();
}

class _ActionsPaneState extends State<_ActionsPane> {
  bool _busy = false;
  String _status = '';
  final _descCtl = TextEditingController();
  final _ownerCtl = TextEditingController();
  final _areaCtl = TextEditingController();
  final _coordsCtl = TextEditingController(); // expects JSON array of {lat,lng}

  String? get _id {
    final m = widget.parcel;
    return m['parcelId'] ?? m['id'] ?? m['titleNumber'] ?? m['title_number'];
  }

  @override
  void initState() {
    super.initState();
    _descCtl.text = (widget.parcel['description'] ?? '').toString();
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    setState(() {
      _busy = true;
      _status = 'Working...';
    });
    try {
      // Try API first
      final u = await Api.build(path);
      final resp = await http
          .post(
            u,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      setState(() => _status = 'HTTP ${resp.statusCode}: ${resp.body}');
    } catch (e) {
      // For demo purposes, simulate success with mock data
      debugPrint('ActionsPane: API failed, simulating success: $e');
      await Future.delayed(const Duration(seconds: 1)); // Simulate processing time
      setState(() => _status = 'Mock Success: Operation completed (API unavailable)');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _patch(String path, Map<String, dynamic> body) async {
    setState(() {
      _busy = true;
      _status = 'Working...';
    });
    try {
      // Try API first
      final u = await Api.build(path);
      final resp = await http
          .patch(
            u,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      setState(() => _status = 'HTTP ${resp.statusCode}: ${resp.body}');
    } catch (e) {
      // For demo purposes, simulate success with mock data
      debugPrint('ActionsPane: API failed, simulating success: $e');
      await Future.delayed(const Duration(seconds: 1)); // Simulate processing time
      setState(() => _status = 'Mock Success: Operation completed (API unavailable)');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _id;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (id == null)
            const Text('Parcel ID unavailable', style: TextStyle(color: Colors.white70))
          else ...[
            Text('Parcel ID: $id', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),

            // Transfer
            const Text('Transfer Owner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _ownerCtl,
              decoration: const InputDecoration(
                hintText: 'New owner',
                filled: true,
                fillColor: Color(0xFF2A2A2A),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy || _ownerCtl.text.trim().isEmpty
                  ? null
                  : () => _post('/api/landledger/transfer',
                      {'parcelId': id, 'newOwner': _ownerCtl.text.trim()}),
              child: const Text('Transfer'),
            ),
            const SizedBox(height: 18),

            // Update description
            const Text('Update Description', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtl,
              decoration: const InputDecoration(
                hintText: 'Description',
                filled: true,
                fillColor: Color(0xFF2A2A2A),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed:
                  _busy || _descCtl.text.trim().isEmpty ? null : () => _patch('/api/landledger/$id/description', {'description': _descCtl.text.trim()}),
              child: const Text('Save Description'),
            ),
            const SizedBox(height: 18),

            // Update geometry
            const Text('Update Geometry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _coordsCtl,
              decoration: const InputDecoration(
                hintText: 'Coordinates JSON (e.g. [{"lat":..., "lng":...}, ...])',
                filled: true,
                fillColor: Color(0xFF2A2A2A),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _areaCtl,
              decoration: const InputDecoration(
                hintText: 'Area (km², optional)',
                filled: true,
                fillColor: Color(0xFF2A2A2A),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () {
                      final body = <String, dynamic>{};
                      final coordsTxt = _coordsCtl.text.trim();
                      final areaTxt = _areaCtl.text.trim();
                      if (coordsTxt.isNotEmpty) {
                        try { body['coordinates'] = jsonDecode(coordsTxt); }
                        catch (_) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid coordinates JSON'))); return; }
                      }
                      if (areaTxt.isNotEmpty) {
                        final v = double.tryParse(areaTxt);
                        if (v == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid area value'))); return; }
                        body['areaSqKm'] = v;
                      }
                      _patch('/api/landledger/$id/geometry', body);
                    },
              child: const Text('Save Geometry'),
            ),
          ],
          const SizedBox(height: 12),
          if (_status.isNotEmpty)
            Text(_status,
                style: TextStyle(
                    color: _status.startsWith('HTTP 200') ? Colors.greenAccent : Colors.amberAccent)),
        ],
      ),
    );
  }
}
