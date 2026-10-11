class UploadedVcfFile {
  final String fileName;
  final String content;
  final DateTime uploadedAt;
  final int geneCount;
  final List<String> genes;

  const UploadedVcfFile({
    required this.fileName,
    required this.content,
    required this.uploadedAt,
    this.geneCount = 0,
    this.genes = const [],
  });

  Map<String, dynamic> toJson() => {
    'file_name': fileName,
    'content': content,
    'uploaded_at': uploadedAt.toIso8601String(),
    'gene_count': geneCount,
    'genes': genes,
  };

  factory UploadedVcfFile.fromJson(Map<String, dynamic> json) => UploadedVcfFile(
    fileName: json['file_name'] as String? ?? '',
    content: json['content'] as String? ?? '',
    uploadedAt:
        DateTime.tryParse(json['uploaded_at'] as String? ?? '') ??
        DateTime.now(),
    geneCount: json['gene_count'] as int? ?? 0,
    genes:
        (json['genes'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
  );
}
