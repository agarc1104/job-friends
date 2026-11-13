import 'interview_practice_mode.dart';

class InterviewSession {
  const InterviewSession({
    required this.id,
    required this.applicantEmail,
    required this.applicationId,
    required this.mode,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.lastSummary = '',
  });

  final String id;
  final String applicantEmail;
  final String applicationId;
  final InterviewPracticeMode mode;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastSummary;

  factory InterviewSession.fromMap(Map<String, dynamic> data) {
    return InterviewSession(
      id: (data['id'] ?? '').toString(),
      applicantEmail: (data['applicant_email'] ?? '').toString(),
      applicationId: (data['application_id'] ?? '').toString(),
      mode: InterviewPracticeModeX.fromKey(data['mode']?.toString()),
      status: (data['status'] ?? 'active').toString(),
      createdAt: DateTime.tryParse((data['created_at'] ?? '').toString()) ?? DateTime.now(),
      updatedAt: DateTime.tryParse((data['updated_at'] ?? '').toString()) ?? DateTime.now(),
      lastSummary: (data['last_summary'] ?? '').toString(),
    );
  }
}
