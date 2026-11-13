import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jobfriends_mobile/features/interview/interview_chat_screen.dart';
import 'package:jobfriends_mobile/models/user_profile.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const user = UserProfile(
    email: 'test.interview@jobfriends.local',
    firstName: 'Test',
    lastName: 'User',
    phone: '00000000',
  );

  Future<void> openInterviewChat(WidgetTester tester) async {
    await tester.tap(find.text('Abrir entrevista'));
    await tester.pumpAndSettle();
    expect(find.text('Vacante eliminada'), findsOneWidget);
  }

  testWidgets('back button and system back return to previous screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const InterviewChatScreen(
                        currentUser: user,
                      ),
                    ),
                  );
                },
                child: const Text('Abrir entrevista'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await openInterviewChat(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Abrir entrevista'), findsOneWidget);

    await openInterviewChat(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Abrir entrevista'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
