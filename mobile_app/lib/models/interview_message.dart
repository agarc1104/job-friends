import 'interview_practice_mode.dart';
import 'interview_response_parser.dart';

class InterviewMessage {
  const InterviewMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.coachFeedback = '',
    this.improvedAnswer = '',
    this.nextQuestion = '',
    this.score,
    this.tags = const [],
    this.sessionSummary = '',
  });

  final String role;
  final String content;
  final DateTime createdAt;
  final String coachFeedback;
  final String improvedAnswer;
  final String nextQuestion;
  final double? score;
  final List<String> tags;
  final String sessionSummary;

  bool get isUser => role.trim().toLowerCase() == 'user';

  Map<String, dynamic> toFunctionHistoryMap() {
    return {
      'role': role,
      'content': content,
    };
  }

  Map<String, dynamic> toDatabaseMap({
    required String sessionId,
    required String applicantEmail,
    required String applicationId,
    required InterviewPracticeMode mode,
  }) {
    return {
      'session_id': sessionId,
      'applicant_email': applicantEmail.trim().toLowerCase(),
      'application_id': applicationId,
      'mode': mode.key,
      'role': role,
      'content': content,
      'coach_feedback': coachFeedback,
      'improved_answer': improvedAnswer,
      'next_question': nextQuestion,
      'score': score,
      'tags': tags,
      'session_summary': sessionSummary,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory InterviewMessage.fromDatabaseMap(Map<String, dynamic> data) {
    final rawContent = (data['content'] ?? '').toString();
    final parsedContent = parseInterviewResponseText(rawContent);
    final rawTags = data['tags'];
    final tags = <String>[];

    if (rawTags is List) {
      for (final item in rawTags) {
        final tag = item?.toString().trim() ?? '';
        if (tag.isNotEmpty) {
          tags.add(tag);
        }
      }
    }

    return InterviewMessage(
      role: (data['role'] ?? '').toString(),
      content: parsedContent.hasStructuredSections && parsedContent.reply.isNotEmpty
          ? parsedContent.reply
          : rawContent,
      createdAt: DateTime.tryParse((data['created_at'] ?? '').toString()) ?? DateTime.now(),
      coachFeedback: _preferredValue((data['coach_feedback'] ?? '').toString(), parsedContent.coachFeedback),
      improvedAnswer: _preferredValue((data['improved_answer'] ?? '').toString(), parsedContent.improvedAnswer),
      nextQuestion: _preferredValue((data['next_question'] ?? '').toString(), parsedContent.nextQuestion),
      score: _parseScore(data['score']),
      tags: tags,
      sessionSummary: (data['session_summary'] ?? '').toString(),
    );
  }

  static double? _parseScore(Object? rawScore) {
    if (rawScore == null) {
      return null;
    }
    if (rawScore is double) {
      return rawScore;
    }
    if (rawScore is num) {
      return rawScore.toDouble();
    }
    return double.tryParse(rawScore.toString());
  }

  static String _preferredValue(String storedValue, String parsedValue) {
    final normalizedStoredValue = storedValue.trim();
    if (normalizedStoredValue.isNotEmpty) {
      return normalizedStoredValue;
    }
    return parsedValue.trim();
  }
}
