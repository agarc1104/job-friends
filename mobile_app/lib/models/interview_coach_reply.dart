import 'interview_response_parser.dart';

class InterviewCoachReply {
  const InterviewCoachReply({
    required this.reply,
    required this.coachFeedback,
    required this.improvedAnswer,
    required this.nextQuestion,
    required this.score,
    required this.tags,
    required this.sessionSummary,
  });

  final String reply;
  final String coachFeedback;
  final String improvedAnswer;
  final String nextQuestion;
  final double? score;
  final List<String> tags;
  final String sessionSummary;

  factory InterviewCoachReply.fromMap(Map<String, dynamic> payload) {
    final parsed = parseInterviewResponsePayload(payload);
    final rawTags = payload['tags'];
    final tags = <String>[];
    if (rawTags is List) {
      for (final item in rawTags) {
        final normalized = item?.toString().trim() ?? '';
        if (normalized.isNotEmpty) {
          tags.add(normalized);
        }
      }
    }

    return InterviewCoachReply(
      reply: parsed.reply,
      coachFeedback: parsed.coachFeedback,
      improvedAnswer: parsed.improvedAnswer,
      nextQuestion: parsed.nextQuestion,
      score: _parseScore(payload['score']),
      tags: tags,
      sessionSummary: (payload['session_summary'] ?? '').toString(),
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
}
