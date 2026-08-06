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

  const AudioCacheConfig({
    this.maxCacheSize = 50,
    this.preloadCharacterThreshold = 8000,
    this.maxPreloadDistance = 15,
  });
}
