class ApplicationRecord {
  const ApplicationRecord({
    required this.id,
    required this.website,
    required this.vacancy,
    required this.status,
    required this.applicationLink,
    required this.description,
  });

  final String id;
  final String website;
  final String vacancy;
  final String status;
  final String applicationLink;
  final String description;

  factory ApplicationRecord.fromMap(Map<String, dynamic> data) {
    return ApplicationRecord(
      id: (data['id'] ?? '').toString(),
      website: (data['website'] ?? '').toString(),
      vacancy: (data['vaccancy'] ?? '').toString(),
      status: (data['status'] ?? 'Aplicado').toString(),
      applicationLink: (data['application_link'] ?? '').toString(),
      description: (data['Description'] ?? '').toString(),
    );
  }
}