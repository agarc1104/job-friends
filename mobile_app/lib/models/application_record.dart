class ApplicationRecord {
  const ApplicationRecord({
    required this.id,
    required this.website,
    required this.vacancy,
    required this.status,
    required this.applicationLink,
    required this.description,
    this.createdAt,
  });

  final String id;
  final String website;
  final String vacancy;
  final String status;
  final String applicationLink;
  final String description;
  final DateTime? createdAt;

  bool get isOlderThanThreeMonths {
    final created = createdAt;
    if (created == null) {
      return false;
    }
    return DateTime.now().toUtc().difference(created.toUtc()) > const Duration(days: 90);
  }

  factory ApplicationRecord.fromMap(Map<String, dynamic> data) {
    return ApplicationRecord(
      id: (data['id'] ?? '').toString(),
      website: (data['website'] ?? '').toString(),
      vacancy: (data['vaccancy'] ?? '').toString(),
      status: (data['status'] ?? 'Aplicado').toString(),
      applicationLink: (data['application_link'] ?? '').toString(),
      description: (data['Description'] ?? '').toString(),
      createdAt: DateTime.tryParse((data['added_at'] ?? '').toString()),
    );
  }
}