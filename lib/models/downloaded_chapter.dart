enum DownloadStatusValue { pending, processing, completed, error }

DownloadStatusValue parseDownloadStatus(String? raw) {
  switch (raw) {
    case 'processing':
      return DownloadStatusValue.processing;
    case 'completed':
      return DownloadStatusValue.completed;
    case 'error':
      return DownloadStatusValue.error;
    case 'pending':
    default:
      return DownloadStatusValue.pending;
  }
}

String downloadStatusToString(DownloadStatusValue v) => v.name;

class DownloadStatus {
  final String downloadId;
  final DownloadStatusValue status;
  final double progress;
  final int totalFiles;
  final int completedFiles;
  final String? errorMessage;
  final DownloadFiles? files;

  const DownloadStatus({
    required this.downloadId,
    required this.status,
    required this.progress,
    required this.totalFiles,
    required this.completedFiles,
    this.errorMessage,
    this.files,
  });

  factory DownloadStatus.fromJson(Map<String, dynamic> json) => DownloadStatus(
        downloadId: json['download_id'] as String? ?? '',
        status: parseDownloadStatus(json['status'] as String?),
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        totalFiles: (json['total_files'] as num?)?.toInt() ?? 0,
        completedFiles: (json['completed_files'] as num?)?.toInt() ?? 0,
        errorMessage: json['error_message'] as String?,
        files: json['files'] != null
            ? DownloadFiles.fromJson(json['files'] as Map<String, dynamic>)
            : null,
      );
}

class DownloadFiles {
  final String? content;
  final String? title;
  final List<String> paragraphs;

  const DownloadFiles({
    this.content,
    this.title,
    this.paragraphs = const [],
  });

  factory DownloadFiles.fromJson(Map<String, dynamic> json) {
    final audio = json['audio'] as Map<String, dynamic>?;
    return DownloadFiles(
      content: json['content'] as String?,
      title: audio?['title'] as String?,
      paragraphs: (audio?['paragraphs'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );
  }
}

class DownloadedChapter {
  final String downloadId;
  final String novelName;
  final int chapterNumber;
  final String? chapterTitle;
  final DownloadStatusValue status;
  final double progress;
  final DateTime downloadDate;
  final int totalFiles;
  final int completedFiles;

  const DownloadedChapter({
    required this.downloadId,
    required this.novelName,
    required this.chapterNumber,
    this.chapterTitle,
    required this.status,
    required this.progress,
    required this.downloadDate,
    required this.totalFiles,
    required this.completedFiles,
  });

  DownloadedChapter copyWith({
    String? downloadId,
    String? novelName,
    int? chapterNumber,
    String? chapterTitle,
    DownloadStatusValue? status,
    double? progress,
    DateTime? downloadDate,
    int? totalFiles,
    int? completedFiles,
  }) =>
      DownloadedChapter(
        downloadId: downloadId ?? this.downloadId,
        novelName: novelName ?? this.novelName,
        chapterNumber: chapterNumber ?? this.chapterNumber,
        chapterTitle: chapterTitle ?? this.chapterTitle,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        downloadDate: downloadDate ?? this.downloadDate,
        totalFiles: totalFiles ?? this.totalFiles,
        completedFiles: completedFiles ?? this.completedFiles,
      );

  Map<String, dynamic> toJson() => {
        'downloadId': downloadId,
        'novelName': novelName,
        'chapterNumber': chapterNumber,
        'chapterTitle': chapterTitle,
        'status': status.name,
        'progress': progress,
        'downloadDate': downloadDate.toIso8601String(),
        'totalFiles': totalFiles,
        'completedFiles': completedFiles,
      };

  factory DownloadedChapter.fromJson(Map<String, dynamic> json) =>
      DownloadedChapter(
        downloadId: json['downloadId'] as String,
        novelName: json['novelName'] as String,
        chapterNumber: (json['chapterNumber'] as num).toInt(),
        chapterTitle: json['chapterTitle'] as String?,
        status: parseDownloadStatus(json['status'] as String?),
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        downloadDate: DateTime.parse(json['downloadDate'] as String),
        totalFiles: (json['totalFiles'] as num?)?.toInt() ?? 0,
        completedFiles: (json['completedFiles'] as num?)?.toInt() ?? 0,
      );
}

class DownloadRequest {
  final String novelName;
  final int chapterNumber;
  final String narratorVoice;
  final String dialogueVoice;

  const DownloadRequest({
    required this.novelName,
    required this.chapterNumber,
    required this.narratorVoice,
    required this.dialogueVoice,
  });

  Map<String, dynamic> toJson() => {
        'novel_name': novelName,
        'chapter_number': chapterNumber,
        'narrator_voice': narratorVoice,
        'dialogue_voice': dialogueVoice,
      };
}

class DownloadResponse {
  final String downloadId;
  final String status;
  final String message;

  const DownloadResponse({
    required this.downloadId,
    required this.status,
    required this.message,
  });

  factory DownloadResponse.fromJson(Map<String, dynamic> json) =>
      DownloadResponse(
        downloadId: json['download_id'] as String,
        status: json['status'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );
}
