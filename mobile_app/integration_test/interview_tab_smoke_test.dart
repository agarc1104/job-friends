import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jobfriends_mobile/config/app_config.dart';
import 'package:jobfriends_mobile/data/jobfriends_repository.dart';
import 'package:jobfriends_mobile/features/interview/interview_prep_screen.dart';
import 'package:jobfriends_mobile/models/interview_message.dart';
import 'package:jobfriends_mobile/models/interview_practice_mode.dart';
import 'package:jobfriends_mobile/models/user_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const repository = JobFriendsRepository();
  const user = UserProfile(
    email: 'test.interview@jobfriends.local',
    firstName: 'Test',
    lastName: 'User',
    phone: '00000000',
  );
  var supabaseInitialized = false;

  setUpAll(() async {
    await AppConfig.initialize(envFile: '.env.dev');
    if (!supabaseInitialized) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      supabaseInitialized = true;
    }
  });

  Future<void> resetInterviewFixtures() async {
    final applications = await repository.fetchApplications(user.email);
    for (final application in applications) {
      await repository.deleteInterviewDataForApplication(
        applicantEmail: user.email,
        applicationId: application.id,
      );
      await repository.deleteApplication(applicationId: application.id);
    }
  }

  setUp(() async {
    await resetInterviewFixtures();
  });

  tearDown(() async {
    await resetInterviewFixtures();
  });

  testWidgets('interview screen opens new chat sheet when vacancy exists', (tester) async {
    await repository.saveApplication(
      applicantEmail: user.email,
      title: 'Backend Test Vacancy',
      website: 'JobFriends Test',
      applyLink: 'https://example.com/jobs/backend-test',
      description: 'Vacante de prueba para simulacion de entrevista.',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InterviewPrepScreen(
            currentUser: user,
            applicationsRevision: 0,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 6));

    expect(find.text('Nuevo chat'), findsOneWidget);
    await tester.tap(find.text('Nuevo chat'));
    await tester.pumpAndSettle();

    expect(find.text('Nuevo chat de entrevista'), findsOneWidget);
    expect(find.text('Iniciar chat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interview history item opens existing chat', (tester) async {
    await repository.saveApplication(
      applicantEmail: user.email,
      title: 'Mobile QA Vacancy',
      website: 'JobFriends Test',
      applyLink: 'https://example.com/jobs/mobile-qa',
      description: 'Vacante de prueba para abrir historial.',
    );

    final applications = await repository.fetchApplications(user.email);
    final application = applications.firstWhere(
      (item) => item.applicationLink == 'https://example.com/jobs/mobile-qa',
    );

    final session = await repository.createInterviewSession(
      applicantEmail: user.email,
      applicationId: application.id,
      mode: InterviewPracticeMode.simulation,
    );

    expect(session, isNotNull);

    await repository.saveInterviewMessage(
      message: InterviewMessage(
        role: 'assistant',
        content: 'Bienvenido a tu sesion de prueba.',
        createdAt: DateTime.now(),
      ),
      sessionId: session!.id,
      applicantEmail: user.email,
      applicationId: application.id,
      mode: InterviewPracticeMode.simulation,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InterviewPrepScreen(
            currentUser: user,
            applicationsRevision: 0,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 6));

    expect(find.text('Mobile QA Vacancy'), findsOneWidget);
    await tester.tap(find.text('Mobile QA Vacancy'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('Bienvenido a tu sesion de prueba.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
