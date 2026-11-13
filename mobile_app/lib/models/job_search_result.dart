class JobSearchResult {
  const JobSearchResult({
    required this.title,
    required this.company,
    required this.location,
    required this.summary,
    required this.applyLink,
  });

  final String title;
  final String company;
  final String location;
  final String summary;
  final String applyLink;

  factory JobSearchResult.fromMap(Map<String, dynamic> data) {
    final highlights = (data['job_highlights'] as List?)
            ?.whereType<Map>()
            .expand((block) {
              final rawItems = block['items'];
              if (rawItems is List) {
                return rawItems.whereType<Object>().map((item) => item.toString());
              }
              return const <String>[];
            })
            .take(3)
            .toList() ??
        const <String>[];

    final summary = data['description']?.toString().trim() ?? '';
    final applyOptions = data['apply_options'] as List?;
    final firstApply =
        applyOptions != null && applyOptions.isNotEmpty && applyOptions.first is Map
            ? applyOptions.first as Map
            : null;

    return JobSearchResult(
      title: data['title']?.toString().trim().isNotEmpty == true
          ? data['title'].toString().trim()
          : 'Untitled job',
      company: data['company_name']?.toString().trim().isNotEmpty == true
          ? data['company_name'].toString().trim()
          : (data['detected_extensions']?['posted_by']?.toString().trim() ?? 'Company unavailable'),
      location: data['location']?.toString().trim().isNotEmpty == true
          ? data['location'].toString().trim()
          : 'Location unavailable',
      summary: summary.isNotEmpty
          ? summary
          : (highlights.isEmpty ? 'No additional description.' : highlights.join(' • ')),
      applyLink: firstApply?['link']?.toString() ??
          data['share_link']?.toString() ??
          '#',
    );
  }
}