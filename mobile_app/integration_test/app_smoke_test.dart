import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jobfriends_mobile/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('JobFriends Android smoke', () {
    testWidgets('launches and renders app shell', (tester) async {
      await tester.pumpWidget(const JobFriendsApp());
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('JobFriends Mobile'), findsOneWidget);
      expect(find.text('Acceso'), findsOneWidget);
      expect(find.text('Vacantes'), findsOneWidget);
      expect(find.text('Aplicaciones'), findsOneWidget);
      expect(find.text('CV Prep'), findsOneWidget);
      expect(find.text('Interview'), findsOneWidget);
    });

    testWidgets('renders navigation icons', (tester) async {
      await tester.pumpWidget(const JobFriendsApp());
      await tester.pump(const Duration(seconds: 3));

      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.travel_explore_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      expect(find.byIcon(Icons.record_voice_over_outlined), findsOneWidget);
    });

    testWidgets('can tap and navigate to CV Prep tab', (tester) async {
      await tester.pumpWidget(const JobFriendsApp());
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.byIcon(Icons.description_outlined));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('CV Prep con IA'), findsOneWidget);
    });

    testWidgets('can tap and navigate to Acceso tab', (tester) async {
      await tester.pumpWidget(const JobFriendsApp());
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.byIcon(Icons.lock_outline_rounded));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Acceso real con Supabase'), findsOneWidget);
    });
  });
}
