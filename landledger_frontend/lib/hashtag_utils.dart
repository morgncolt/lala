// hashtag_utils.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'map_screen.dart';

String _stripLeadingHashes(String s) => s.trim().replaceFirst(RegExp(r'^#+'), '');
String _ensureSingleHash(String s) => '#${_stripLeadingHashes(s)}';
String _aliasKeyFrom(String s) => _stripLeadingHashes(s).toUpperCase();

Future<void> handleHashtagTap(BuildContext context, String rawTag) async {
  final fs = FirebaseFirestore.instance;
  final display = _ensureSingleHash(rawTag);
  final aliasKey = _aliasKeyFrom(rawTag);

  try {
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await fs.collectionGroup('properties')
          .where('aliasKey', isEqualTo: aliasKey)
          .limit(1).get();
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        // Fallback while the single-field CG index builds
        snap = await fs.collectionGroup('properties')
            .where('alias', isEqualTo: display)
            .limit(1).get();
      } else {
        rethrow;
      }
    }

    if (snap.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No polygon found for $display')),
      );
      return;
    }

    final doc = snap.docs.first;
    final data = doc.data();
    String regionId = (data['regionId'] ?? '').toString();
    if (regionId.isEmpty) {
      final segs = doc.reference.path.split('/');
      for (int i = 0; i < segs.length - 1; i++) {
        if (segs[i] == 'regions' && i + 1 < segs.length) { regionId = segs[i + 1]; break; }
      }
      if (regionId.isEmpty) regionId = 'cameroon';
    }

    final coordsList = (data['coordinates'] as List? ?? const []);
    final coords = coordsList.map<ll.LatLng>(
      (c) => ll.LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble())
    ).toList();

    if (coords.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No polygon coordinates found for $display')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: display));
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MapScreen(
        regionId: regionId,
        geojsonPath: null,
        highlightPolygon: coords,
        centerOnRegion: false,
        showBackArrow: true,
      ),
    ));
  } on FirebaseException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error opening $display: ${e.message}')),
    );
  }
}

List<TextSpan> buildTextWithHashtag(BuildContext context, String text) {
  final rx = RegExp(r'(#+[A-Za-z][A-Za-z0-9_]*)');
  final spans = <TextSpan>[];
  int i = 0;
  for (final m in rx.allMatches(text)) {
    if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
    final raw = m.group(0)!;
    spans.add(TextSpan(
      text: _ensureSingleHash(raw),
      style: const TextStyle(
        color: Colors.lightBlueAccent,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => handleHashtagTap(context, raw),
    ));
    i = m.end;
  }
  if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
  return spans;
}
