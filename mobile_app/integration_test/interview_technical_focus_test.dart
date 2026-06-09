import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jobfriends_mobile/config/app_config.dart';
import 'package:jobfriends_mobile/data/jobfriends_repository.dart';
import 'package:jobfriends_mobile/features/interview/interview_chat_screen.dart';
import 'package:jobfriends_mobile/models/application_record.dart';
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

  testWidgets('technical first turn stays role-specific', (tester) async {
    await repository.saveApplication(
      applicantEmail: user.email,
      title: 'Flutter Mobile Engineer',
      website: 'JobFriends Test',
      applyLink: 'https://example.com/jobs/flutter-mobile-engineer',
      description: 'Flutter app, APIs, debugging, testing, performance and reliability.',
    );

    final applications = await repository.fetchApplications(user.email);
    final application = applications.firstWhere(
      (item) => item.applicationLink == 'https://example.com/jobs/flutter-mobile-engineer',
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        home: Scaffold(
          body: InterviewChatScreen(
            key: const ValueKey<String>('technical-focus-chat'),
            currentUser: user,
            application: application,
            initialMode: InterviewPracticeMode.technical,
            startNew: true,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 14));
    await tester.pumpAndSettle();

    final session = await repository.fetchLatestInterviewSession(
      applicantEmail: user.email,
      applicationId: application.id,
      mode: InterviewPracticeMode.technical,
    );

    expect(session, isNotNull);

    final messages = await repository.fetchInterviewMessages(sessionId: session!.id);
    expect(messages, isNotEmpty);
    expect(messages.first.role, 'assistant');

    final firstReply = messages.first.content.toLowerCase();
    final genericTerms = [
      'system design',
      'architecture',
      'microservices',
      'distributed system',
      'design the system',
    ];
    final technicalTerms = [
      'flutter',
      'api',
      'debug',
      'test',
      'performance',
      'reliability',
      'stack',
      'data flow',
    ];

    expect(genericTerms.any(firstReply.contains), isFalse);
    expect(technicalTerms.any(firstReply.contains), isTrue);
    expect(tester.takeException(), isNull);
  });
}