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
  final Duration cacheExpiry;

  const AudioCacheConfig({
    this.maxCacheSize = 30,
    this.preloadCharacterThreshold = 3000,
    this.maxPreloadDistance = 15,
    this.cacheExpiry = const Duration(minutes: 30),
  });
}
