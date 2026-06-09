import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jobfriends_mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Interview Tab Layout Test', () {
    testWidgets('Navigate to Interview tab without RenderBox crash',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Find and tap login button (assuming it exists)
      expect(find.text('Entrar'), findsOneWidget);
      
      // Enter email
      await tester.enterText(
        find.byType(TextField).first,
        'quintero981104@gmail.com',
      );
      await tester.pumpAndSettle();

      // Enter password
      await tester.enterText(
        find.byType(TextField).last,
        'D3n1s3a9',
      );
      await tester.pumpAndSettle();

      // Tap login button
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify we're logged in (should see home screen)
      expect(find.text('Mis Empleos'), findsWidgets);

      // Navigate to Interview tab (index 3 in bottom nav)
      print('[TEST] Tapping Interview tab...');
      final interviewTab = find.byIcon(Icons.smart_toy_outlined);
      expect(interviewTab, findsOneWidget);
      
      await tester.tap(interviewTab);
      print('[TEST] Interview tab tapped, waiting for render...');
      
      await tester.pumpAndSettle(const Duration(seconds: 2));
      print('[TEST] Render complete - checking for crash...');

      // If we get here without an exception, test passes
      expect(find.text('Entrevista IA'), findsOneWidget);
      print('[TEST] SUCCESS: Interview tab rendered without crash!');
    });
  });
}
