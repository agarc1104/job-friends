import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobfriends_mobile/features/interview/interview_prep_screen.dart';

void main() {
  group('InterviewPrepScreen', () {
    testWidgets('renders history header and new chat button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InterviewPrepScreen(
              currentUser: null,
              applicationsRevision: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nuevo chat'), findsOneWidget);
      expect(find.text('Aun no tienes chats de entrevista'), findsOneWidget);
    });

    testWidgets('keeps new chat button visible without user session', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InterviewPrepScreen(
              currentUser: null,
              applicationsRevision: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nuevo chat'), findsOneWidget);
    });
  });
}
