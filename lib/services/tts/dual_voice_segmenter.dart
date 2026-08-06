/// One contiguous run of text destined for a single voice.
class VoiceSegment {
  const VoiceSegment(this.text, this.isDialogue);

  final String text;

  /// `true` → speak with the dialogue voice; `false` → narrator voice.
  final bool isDialogue;
}

/// Splits a paragraph into narrator vs. dialogue segments.
///
/// Direct port of `app/api/tts.py :: text_to_speech_dual_voice` so on-device
/// output matches the backend: text inside curly/straight double-quotes is
/// dialogue; everything else is narration. Also mirrors the two pre-cleanups
/// (scene-break asterisks and the web-novel promo line).
class DualVoiceSegmenter {
  static final RegExp _asterisks = RegExp(r'\*\s*\*\s*\*');

  // Web-novel promo line the backend strips before synthesis.
  static final RegExp _promoLine = RegExp(
    r'\s*([^S]*?website on Google to access chapters of novels early and in the highest quality[^.]*\.)\s*',
    caseSensitive: false,
  );

  // Curly-open / curly-close / straight double quote around the dialogue.
  static final RegExp _dialogue = RegExp('[“”"](.*?)[“”"]');

  static List<VoiceSegment> segment(String text) {
    text = text.replaceAll(_asterisks, 'Asterisk Asterisk Asterisk');
    text = text.replaceAll(_promoLine, ' ');

    final segments = <VoiceSegment>[];
    var lastIndex = 0;

    for (final m in _dialogue.allMatches(text)) {
      final narration = text.substring(lastIndex, m.start).trim();
      if (narration.isNotEmpty) {
        segments.add(VoiceSegment(narration, false));
      }

      final dialogue = (m.group(1) ?? '').trim();
      if (dialogue.isNotEmpty) {
        segments.add(VoiceSegment(dialogue, true));
      }

      lastIndex = m.end;
    }

    final remaining = text.substring(lastIndex).trim();
    if (remaining.isNotEmpty) {
      segments.add(VoiceSegment(remaining, false));
    }

    return segments;
  }
}
