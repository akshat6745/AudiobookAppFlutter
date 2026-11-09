enum NovelSource { cloudflareD1, googleDoc, epubUpload }

NovelSource _parseSource(String? raw) {
  switch (raw) {
    case 'google_doc':
      return NovelSource.googleDoc;
    case 'epub_upload':
      return NovelSource.epubUpload;
    case 'cloudflare_d1':
    default:
      return NovelSource.cloudflareD1;
  }
}

class Novel {
  final String id;
  final String title;
  final String? author;
  final int? chapterCount;
  final NovelSource source;
  final String slug;
  final String? description;
  final bool isPublic;
  final bool isOwner;

  const Novel({
    required this.id,
    required this.title,
    required this.author,
    required this.chapterCount,
    required this.source,
    required this.slug,
    required this.description,
    required this.isPublic,
    this.isOwner = false,
  });

  factory Novel.fromJson(Map<String, dynamic> json) => Novel(
        id: json['id']?.toString() ?? json['slug']?.toString() ?? '',
        title: json['title'] as String? ?? '',
        author: json['author'] as String?,
        chapterCount: (json['chapterCount'] as num?)?.toInt(),
        source: _parseSource(json['source'] as String?),
        slug: json['slug'] as String? ?? '',
        description: json['description'] as String?,
        isPublic: json['isPublic'] as bool? ?? false,
        isOwner: json['isOwner'] as bool? ?? false,
      );
}

/// Response from `POST /upload-epub`.
class NovelUploadResponse {
  final String? slug;
  final String title;
  final String? author;
  final int chapterCount;
  final String message;

  const NovelUploadResponse({
    this.slug,
    required this.title,
    required this.author,
    required this.chapterCount,
    required this.message,
  });

  factory NovelUploadResponse.fromJson(Map<String, dynamic> json) =>
      NovelUploadResponse(
        slug: json['slug'] as String? ?? json['id'] as String?,
        title: json['title'] as String? ?? '',
        author: json['author'] as String?,
        chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
        message: json['message'] as String? ??
            'Novel uploaded and parsed successfully',
      );
}
