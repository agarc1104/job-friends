class CvDraftResult {
  const CvDraftResult({
    required this.draftId,
    required this.outputFormat,
    required this.latex,
    required this.source,
  });

  final String draftId;
  final String outputFormat;
  final String latex;
  final String source;

  factory CvDraftResult.fromMap(Map<String, dynamic> data) {
    return CvDraftResult(
      draftId: data['draft_id']?.toString() ?? '',
      outputFormat: data['output_format']?.toString() ?? 'pdf',
      latex: data['latex']?.toString() ?? '',
      source: data['source']?.toString() ?? 'draft',
    );
  }
}