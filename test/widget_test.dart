import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yaqdah_app/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // We pass an empty list of cameras because we are just testing the UI launch.
    await tester.pumpWidget(const YaqdahApp(cameras: []));

    // Verify that the MaterialApp exists (meaning the app launched).
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}