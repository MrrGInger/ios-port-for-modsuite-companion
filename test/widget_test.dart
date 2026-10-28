import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ModSuite Companion basic widget test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('ModSuite Companion'),
        ),
      ),
    );

    expect(find.text('ModSuite Companion'), findsOneWidget);
  });
}
