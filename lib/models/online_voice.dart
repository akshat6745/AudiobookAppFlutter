/// An online (edge-tts) voice, as returned by the backend's `/tts-voices`
/// endpoint. Mirrors the fields the on-device Kokoro voice picker already
/// surfaces (name, gender, accent, style) so both pickers feel like the same
/// feature rather than two unrelated UIs.
class OnlineVoice {
  const OnlineVoice({
    required this.shortName,
    required this.displayName,
    required this.isFemale,
    required this.locale,
    required this.localeName,
    required this.personalities,
  });

  /// The id actually sent to the backend as `paragraphVoice`/`dialogueVoice`
  /// (e.g. `en-US-AvaMultilingualNeural`).
  final String shortName;

  /// Human-friendly first name (e.g. `Ava`).
  final String displayName;
  final bool isFemale;

  /// e.g. `en-US`.
  final String locale;

  /// e.g. `English (United States)` — shown as the "accent" line.
  final String localeName;

  /// e.g. `[Expressive, Caring, Pleasant, Friendly]` — shown as the
  /// "speaking style" for this voice.
  final List<String> personalities;

  String get styleLabel => personalities.join(', ');

  /// Accent, stripped of the "English (...)" wrapper Azure returns
  /// (`English (United States)` → `American`) — short enough for a chip.
  String get accentLabel {
    final match = RegExp(r'\((.+)\)').firstMatch(localeName);
    return match?.group(1) ?? localeName;
  }

  factory OnlineVoice.fromJson(Map<String, dynamic> json) => OnlineVoice(
        shortName: json['shortName'] as String,
        displayName: json['displayName'] as String,
        isFemale: (json['gender'] as String?)?.toLowerCase() == 'female',
        locale: json['locale'] as String? ?? '',
        localeName: json['localeName'] as String? ?? '',
        personalities: (json['personalities'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
      );
}
