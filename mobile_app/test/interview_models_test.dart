import 'package:flutter_test/flutter_test.dart';
import 'package:jobfriends_mobile/models/application_record.dart';
import 'package:jobfriends_mobile/models/interview_coach_reply.dart';
import 'package:jobfriends_mobile/models/interview_message.dart';
import 'package:jobfriends_mobile/models/interview_practice_mode.dart';

void main() {
  group('Interview models', () {
    test('parses structured coach reply payload', () {
      final reply = InterviewCoachReply.fromMap({
        'reply': 'Buen trabajo',
        'coach_feedback': 'Mas precision',
        'improved_answer': 'Respuesta mejorada',
        'next_question': 'Dame un ejemplo',
        'score': '8.5',
        'tags': ['claridad', 'impacto'],
        'session_summary': 'Buen avance',
      });

      expect(reply.reply, 'Buen trabajo');
      expect(reply.coachFeedback, 'Mas precision');
      expect(reply.improvedAnswer, 'Respuesta mejorada');
      expect(reply.nextQuestion, 'Dame un ejemplo');
      expect(reply.score, 8.5);
      expect(reply.tags, ['claridad', 'impacto']);
      expect(reply.sessionSummary, 'Buen avance');
    });

    test('extracts plain reply and sections from prefixed json text', () {
      final reply = InterviewCoachReply.fromMap({
        'reply': 'json:\n{\n  "reply": "Tu respuesta es correcta y clara.",\n  "coach_feedback": "Mas impacto medible.",\n  "improved_answer": "Explica la accion con cifras.",\n  "next_question": "Que haras distinto la proxima vez?",\n  "score": 9,\n  "tags": ["claridad"],\n  "session_summary": "Buen avance"\n}',
        'coach_feedback': '',
        'improved_answer': '',
        'next_question': '',
        'score': null,
        'tags': const [],
        'session_summary': '',
      });

      expect(reply.reply, 'Tu respuesta es correcta y clara.');
      expect(reply.coachFeedback, 'Mas impacto medible.');
      expect(reply.improvedAnswer, 'Explica la accion con cifras.');
      expect(reply.nextQuestion, 'Que haras distinto la proxima vez?');
    });

    test('extracts plain reply and sections from labeled text', () {
      final reply = InterviewCoachReply.fromMap({
        'reply': 'Buen enfoque para el rol.\n\nFeedback:\nSe mas concreto.\n\nImproved version:\nIncluye un ejemplo con cifras.\n\nNext challenge:\nComo medirias el impacto?',
        'coach_feedback': '',
        'improved_answer': '',
        'next_question': '',
        'score': null,
        'tags': const [],
        'session_summary': '',
      });

      expect(reply.reply, 'Buen enfoque para el rol.');
      expect(reply.coachFeedback, 'Se mas concreto.');
      expect(reply.improvedAnswer, 'Incluye un ejemplo con cifras.');
      expect(reply.nextQuestion, 'Como medirias el impacto?');
    });

    test('maps message to function and database payload', () {
      final message = InterviewMessage(
        role: 'user',
        content: 'Mi respuesta',
        createdAt: DateTime.parse('2026-05-15T10:00:00Z'),
      );

      final functionPayload = message.toFunctionHistoryMap();
      final databasePayload = message.toDatabaseMap(
        sessionId: 'session-123',
        applicantEmail: 'USER@MAIL.COM',
        applicationId: '42',
        mode: InterviewPracticeMode.technical,
      );

      expect(functionPayload['role'], 'user');
      expect(functionPayload['content'], 'Mi respuesta');
      expect(databasePayload['mode'], 'technical');
      expect(databasePayload['applicant_email'], 'user@mail.com');
      expect(databasePayload['session_id'], 'session-123');
    });

    test('detects application age over three months', () {
      final recent = ApplicationRecord.fromMap({
        'id': '1',
        'website': 'site',
        'vaccancy': 'Role',
        'status': 'Aplicado',
        'application_link': 'https://example.com',
        'Description': 'Desc',
        'added_at': DateTime.now().toUtc().subtract(const Duration(days: 45)).toIso8601String(),
      });

      final old = ApplicationRecord.fromMap({
        'id': '2',
        'website': 'site',
        'vaccancy': 'Role',
        'status': 'Aplicado',
        'application_link': 'https://example.com',
        'Description': 'Desc',
        'added_at': DateTime.now().toUtc().subtract(const Duration(days: 120)).toIso8601String(),
      });

      expect(recent.isOlderThanThreeMonths, isFalse);
      expect(old.isOlderThanThreeMonths, isTrue);
    });

    test('normalizes stored interview messages with embedded sections', () {
      final message = InterviewMessage.fromDatabaseMap({
        'role': 'assistant',
        'content': 'Respuesta principal.\n\nFeedback:\nMas detalle.\n\nImproved version:\nAnade contexto.',
        'coach_feedback': '',
        'improved_answer': '',
        'next_question': '',
        'created_at': '2026-05-15T10:00:00Z',
        'score': null,
        'tags': const [],
        'session_summary': '',
      });

      expect(message.content, 'Respuesta principal.');
      expect(message.coachFeedback, 'Mas detalle.');
      expect(message.improvedAnswer, 'Anade contexto.');
    });

    test('resolves mode from persisted key', () {
      expect(
        InterviewPracticeModeX.fromKey('hard_questions'),
        InterviewPracticeMode.hardQuestions,
      );
      expect(
        InterviewPracticeModeX.fromKey('simulation'),
        InterviewPracticeMode.simulation,
      );
      expect(
        InterviewPracticeModeX.fromKey('unexpected'),
        InterviewPracticeMode.simulation,
      );
    });
  });
}
