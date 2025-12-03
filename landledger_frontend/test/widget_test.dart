// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:landledger_frontend/main.dart';

void main() {
  testWidgets('App starts correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LandLedgerApp());

    // Wait for the splash screen to load
    await tester.pump(const Duration(seconds: 3));

    // Verify that the app title is displayed (from splash screen or main app)
    expect(find.text('LandLedger'), findsOneWidget);
  });
}
