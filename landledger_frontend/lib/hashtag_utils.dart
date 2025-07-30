import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'map_screen.dart';

Future<void> handleHashtagTap(BuildContext context, String alias) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final query = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('regions')
      .where('alias', isEqualTo: alias)
      .limit(1)
      .get();


  if (query.docs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("No polygon found for #$alias")),
    );
    return;
  }

  final doc = query.docs.first;
  final data = doc.data();
  final regionId = data['region'];
  final coords = (data['coordinates'] as List)
      .map((c) => LatLng(c['lat'], c['lng']))
      .toList();

  await Clipboard.setData(ClipboardData(text: alias));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text("Copied $alias to clipboard and opening map...")),
  );

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MapScreen(
        regionId: regionId,
        geojsonPath: '', // Update if needed
        highlightPolygon: coords,
      ),
    ),
  );
}

List<TextSpan> buildTextWithHashtag(BuildContext context, String text) {
  final regex = RegExp(r"(#[A-Za-z0-9_]+)");
  final spans = <TextSpan>[];

  text.splitMapJoin(
    regex,
    onMatch: (m) {
      final alias = m.group(0)!;
      spans.add(
        TextSpan(
          text: alias,
          style: const TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => handleHashtagTap(context, alias),
        ),
      );
      return '';
    },
    onNonMatch: (nonMatch) {
      spans.add(TextSpan(text: nonMatch));
      return '';
    },
  );

  return spans;
}

List<String> detectHashtags(String text) {
  final regex = RegExp(r"(#[A-Za-z0-9_]+)");
  return regex.allMatches(text).map((m) => m.group(0)!).toList();
}
