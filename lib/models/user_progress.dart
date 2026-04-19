class UserProgress {
  final String novelName;
  final int lastChapterRead;
  final DateTime? lastReadDate;

  const UserProgress({
    required this.novelName,
    required this.lastChapterRead,
    this.lastReadDate,
  });

  factory UserProgress.fromJson(Map<String, dynamic> json) => UserProgress(
        novelName: json['novelName'] as String? ?? '',
        lastChapterRead: (json['lastChapterRead'] as num?)?.toInt() ?? 0,
        lastReadDate: json['lastReadDate'] != null
            ? DateTime.tryParse(json['lastReadDate'] as String)
            : null,
      );
}
