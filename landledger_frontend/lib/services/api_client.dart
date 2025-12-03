// lib/services/api_client.dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;

String apiBase() => Platform.isAndroid ? 'http://192.168.0.23:4000' : 'http://localhost:4000';
Uri apiUri(String path) => Uri.parse(apiBase()).replace(path: path);

Future<String> fetchWalletLabel(String uid, String email) async {
  final uri = apiUri('/api/identity/me').replace(queryParameters: {
    'uid': uid,
    'email': email,
  });
  final resp = await http.get(uri);
  final data = jsonDecode(resp.body);
  if (resp.statusCode == 200 && data['ok'] == true) {
    return data['walletLabel'] as String;
  }
  throw Exception(data['error'] ?? 'Failed to fetch wallet');
}

class Api {
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await http.post(
      apiUri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final Map<String, dynamic> js = jsonDecode(r.body.isEmpty ? '{}' : r.body);
    return {'status': r.statusCode, ...js};
  }

  Future<Map<String, dynamic>> registerIdentity({required String uid, required String email}) =>
      _post('/api/identity/provision', {'uid': uid, 'email': email});

  Future<Map<String, dynamic>> linkIdentity({required String uid, required String displayAddress, String? fingerprint, String? mspId}) =>
      _post('/api/identity/link', {
        'uid': uid,
        'displayAddress': displayAddress,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (mspId != null) 'mspId': mspId,
      });

  Future<Map<String, dynamic>> evaluateTx({required String uid, required String fcn, List<String> args = const []}) =>
      _post('/api/tx/evaluate', {'uid': uid, 'fcn': fcn, 'args': args});

  Future<Map<String, dynamic>> submitTx({required String uid, required String fcn, List<String> args = const []}) =>
      _post('/api/tx/submit', {'uid': uid, 'fcn': fcn, 'args': args});
}

class Parcel {
  final String id;
  final String? meta;
  Parcel({required this.id, this.meta});
  factory Parcel.fromJson(Map<String, dynamic> j) =>
      Parcel(id: j['id'] ?? j['parcelId'] ?? j['key'] ?? '', meta: j['meta']);
}

Future<List<Parcel>> fetchParcels() async {
  final r = await http.get(apiUri('/api/landledger'));
  if (r.statusCode >= 400) {
    throw Exception('HTTP ${r.statusCode}: ${r.body}');
  }

  final decoded = jsonDecode(r.body);

  // Accept both shapes: {ok:true, payload:[...]} OR just [...]
  final dynamic listish = (decoded is Map<String, dynamic>)
      ? (decoded['payload'] ?? decoded['data'] ?? decoded['items'] ?? [])
      : decoded;

  if (listish is! List) {
    throw StateError('Expected a list but got ${listish.runtimeType}');
  }

  return listish
      .cast<Map<String, dynamic>>()
      .map((e) => Parcel.fromJson(e))
      .toList();
}

Future<Parcel> fetchParcel(String id) async {
  final r = await http.get(apiUri('/api/landledger/$id'));
  final decoded = jsonDecode(r.body);
  final Map<String, dynamic> obj = (decoded is Map && decoded['payload'] is Map)
      ? decoded['payload']
      : (decoded as Map<String, dynamic>);
  return Parcel.fromJson(obj);
}