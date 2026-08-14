class ParagraphAudioData {
  final int paragraphIndex;
  final String paragraphText;
  bool audioReceived;
  String? audioUri;
  Duration? duration;
  bool isLoading;
  final DateTime createdAt;
  final int characterCount;

  ParagraphAudioData({
    required this.paragraphIndex,
    required this.paragraphText,
    this.audioReceived = false,
    this.audioUri,
    this.duration,
    this.isLoading = false,
    DateTime? createdAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        characterCount = paragraphText.length;

  bool get isValid =>
      audioReceived && audioUri != null && audioUri!.isNotEmpty;
}

class AudioCacheConfig {
  final int maxCacheSize;
  final int preloadCharacterThreshold;
  final int maxPreloadDistance;

  /// How many upcoming paragraphs the preload pump may generate at once.
  /// Applies to both engines: the remote backend can genuinely run these in
  /// parallel (independent HTTP requests), and even the on-device engine
  /// benefits — its worker isolate processes one request at a time, but
  /// queuing the next one before the current finishes removes the dispatch
  /// gap between them instead of round-tripping through the main isolate
  /// after every single paragraph.
  final int maxConcurrentPreloads;

  const AudioCacheConfig({
    this.maxCacheSize = 50,
    this.preloadCharacterThreshold = 8000,
    this.maxPreloadDistance = 15,
    this.maxConcurrentPreloads = 3,
  });
}
