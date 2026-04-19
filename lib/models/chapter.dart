class Chapter {
  final int chapterNumber;
  final String chapterTitle;
  final String? id;
  final int? wordCount;

  const Chapter({
    required this.chapterNumber,
    required this.chapterTitle,
    this.id,
    this.wordCount,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        chapterNumber: (json['chapterNumber'] as num).toInt(),
        chapterTitle: json['chapterTitle'] as String? ?? '',
        id: json['id'] as String?,
        wordCount: (json['wordCount'] as num?)?.toInt(),
      );
}

class ChapterListResponse {
  final List<Chapter> chapters;
  final int totalPages;
  final int currentPage;

  const ChapterListResponse({
    required this.chapters,
    required this.totalPages,
    required this.currentPage,
  });

  factory ChapterListResponse.fromJson(Map<String, dynamic> json) =>
      ChapterListResponse(
        chapters: (json['chapters'] as List<dynamic>? ?? const [])
            .map((e) => Chapter.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
        currentPage: (json['current_page'] as num?)?.toInt() ?? 1,
      );
}

class ChapterContent {
  final List<String> content;
  final int? chapterNumber;
  final String? chapterTitle;

  const ChapterContent({
    required this.content,
    this.chapterNumber,
    this.chapterTitle,
  });

  factory ChapterContent.fromJson(Map<String, dynamic> json) => ChapterContent(
        content: (json['content'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        chapterNumber: (json['chapterNumber'] as num?)?.toInt(),
        chapterTitle: json['chapterTitle'] as String?,
      );
}
