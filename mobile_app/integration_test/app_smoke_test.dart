import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jobfriends_mobile/app.dart';
import 'package:jobfriends_mobile/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppConfig.initialize(envFile: '.env.dev');
    if (AppConfig.hasSupabaseConfig) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
    }
  });

  group('JobFriends Android smoke', () {
    testWidgets('launches and renders login shell', (tester) async {
      await tester.pumpWidget(const JobFriendsApp());
      await tester.pump(const Duration(seconds: 6));

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders expected action surface safely', (tester) async {
      await tester.pumpWidget(const JobFriendsApp());
      await tester.pump(const Duration(seconds: 6));

      final hasAnyPrimaryAction = find.byType(FilledButton).evaluate().isNotEmpty;
        final hasAnySecondaryAction =
          find.byType(OutlinedButton).evaluate().isNotEmpty ||
          find.byType(TextButton).evaluate().isNotEmpty;
      final hasNavigationBar = find.byType(NavigationBar).evaluate().isNotEmpty;

        expect(hasAnyPrimaryAction || hasAnySecondaryAction || hasNavigationBar, isTrue);

      final registerTab = find.text('Registro');
      if (registerTab.evaluate().isNotEmpty) {
        await tester.tap(registerTab);
        await tester.pumpAndSettle();
      } else {
        final registerTabEn = find.text('Register');
        if (registerTabEn.evaluate().isNotEmpty) {
          await tester.tap(registerTabEn);
          await tester.pumpAndSettle();
        }
      }

      expect(tester.takeException(), isNull);
    });
  });
}
