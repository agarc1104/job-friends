class CvGeneratedResult {
  const CvGeneratedResult({
    required this.fileName,
    required this.outputFormat,
    required this.publicUrl,
    required this.storagePath,
    required this.source,
  });

  final String fileName;
  final String outputFormat;
  final String publicUrl;
  final String storagePath;
  final String source;

  factory CvGeneratedResult.fromMap(Map<String, dynamic> data) {
    return CvGeneratedResult(
      fileName: data['file_name']?.toString() ?? '',
      outputFormat: data['output_format']?.toString() ?? 'docx',
      publicUrl: data['public_url']?.toString() ?? '',
      storagePath: data['storage_path']?.toString() ?? '',
      source: data['source']?.toString() ?? 'ai_generated',
    );
  }
}