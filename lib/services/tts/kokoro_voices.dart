/// Accent groups for the installed **kokoro-en-v0_19** model (English only).
enum VoiceLanguage {
  americanEnglish('American English'),
  britishEnglish('British English');

  const VoiceLanguage(this.label);
  final String label;
}

/// One selectable on-device Kokoro voice and its speaker id.
class KokoroVoice {
  const KokoroVoice({
    required this.id,
    required this.sid,
    required this.name,
    required this.language,
    required this.isFemale,
  });

  /// Stable key stored in the voice providers (e.g. `af_sarah`).
  final String id;

  /// Speaker index passed to `OfflineTts.generate(sid: …)`.
  final int sid;

  /// Human-friendly display name (e.g. `Sarah`).
  final String name;
  final VoiceLanguage language;
  final bool isFemale;

  String get gender => isFemale ? '♀' : '♂';

  /// e.g. "Sarah ♀"
  String get label => '$name $gender';
}

/// A curated narrator + dialogue pairing that achieves a specific tonal character.
class VoicePreset {
  const VoicePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.narratorId,
    required this.dialogueId,
  });

  final String id;
  final String name;
  final String description;
  final String narratorId;
  final String dialogueId;
}

/// Voice catalog for **kokoro-en-v0_19**, the model actually downloaded by
/// [TtsModelManager.kokoro] — 28 English voices across American/British
/// accents. This list intentionally matches only what that model ships: the
/// broader multi-lingual `kokoro-multi-lang-v1_1` model has additional
/// speakers, but installing that model is a separate decision (bigger
/// download, more languages) — see OFFLINE_TTS_POC_PLAN.md. If you swap
/// models, update this list and [TtsModelManager] together; a sid with no
/// matching voice in the installed model plays the wrong (or no) speaker.
class KokoroVoices {
  const KokoroVoices._();

  static const List<KokoroVoice> all = [
    // American English ♀
    KokoroVoice(id: 'af_alloy', sid: 0, name: 'Alloy', language: VoiceLanguage.americanEnglish, isFemale: true),
    KokoroVoice(id: 'af_aoede', sid: 1, name: 'Aoede', language: VoiceLanguage.americanEnglish, isFemale: true),
    KokoroVoice(id: 'af_bella', sid: 2, name: 'Bella', language: VoiceLanguage.americanEnglish, isFemale: true),
    KokoroVoice(id: 'af_heart', sid: 3, name: 'Heart', language: VoiceLanguage.americanEnglish, isFemale: true),
    KokoroVoice(id: 'af_jessica', sid: 4, name: 'Jessica', language: VoiceLanguage.americanEnglish, isFemale: true),
    KokoroVoice(id: 'af_kore', sid: 5, name: 'Kore', language: VoiceLanguage.americanEnglish, isFemale: true),
    KokoroVoice(id: 'af_nicole', sid: 6, name: 'Nicole', language: VoiceLanguage.americanEnglish, isFemale: true),
    KokoroVoice(id: 'af_nova', sid: 7, name: 'Nova', language: VoiceLanguage.americanEnglish, isFemale: true),
    KokoroVoice(id: 'af_river', sid: 8, name: 'River', language: VoiceLanguage.americanEnglish, isFemale: true),
    KokoroVoice(id: 'af_sarah', sid: 9, name: 'Sarah', language: VoiceLanguage.americanEnglish, isFemale: true),
    KokoroVoice(id: 'af_sky', sid: 10, name: 'Sky', language: VoiceLanguage.americanEnglish, isFemale: true),
    // American English ♂
    KokoroVoice(id: 'am_adam', sid: 11, name: 'Adam', language: VoiceLanguage.americanEnglish, isFemale: false),
    KokoroVoice(id: 'am_echo', sid: 12, name: 'Echo', language: VoiceLanguage.americanEnglish, isFemale: false),
    KokoroVoice(id: 'am_eric', sid: 13, name: 'Eric', language: VoiceLanguage.americanEnglish, isFemale: false),
    KokoroVoice(id: 'am_fenrir', sid: 14, name: 'Fenrir', language: VoiceLanguage.americanEnglish, isFemale: false),
    KokoroVoice(id: 'am_liam', sid: 15, name: 'Liam', language: VoiceLanguage.americanEnglish, isFemale: false),
    KokoroVoice(id: 'am_michael', sid: 16, name: 'Michael', language: VoiceLanguage.americanEnglish, isFemale: false),
    KokoroVoice(id: 'am_onyx', sid: 17, name: 'Onyx', language: VoiceLanguage.americanEnglish, isFemale: false),
    KokoroVoice(id: 'am_puck', sid: 18, name: 'Puck', language: VoiceLanguage.americanEnglish, isFemale: false),
    KokoroVoice(id: 'am_santa', sid: 19, name: 'Santa', language: VoiceLanguage.americanEnglish, isFemale: false),
    // British English ♀
    KokoroVoice(id: 'bf_alice', sid: 20, name: 'Alice', language: VoiceLanguage.britishEnglish, isFemale: true),
    KokoroVoice(id: 'bf_emma', sid: 21, name: 'Emma', language: VoiceLanguage.britishEnglish, isFemale: true),
    KokoroVoice(id: 'bf_isabella', sid: 22, name: 'Isabella', language: VoiceLanguage.britishEnglish, isFemale: true),
    KokoroVoice(id: 'bf_lily', sid: 23, name: 'Lily', language: VoiceLanguage.britishEnglish, isFemale: true),
    // British English ♂
    KokoroVoice(id: 'bm_daniel', sid: 24, name: 'Daniel', language: VoiceLanguage.britishEnglish, isFemale: false),
    KokoroVoice(id: 'bm_fable', sid: 25, name: 'Fable', language: VoiceLanguage.britishEnglish, isFemale: false),
    KokoroVoice(id: 'bm_george', sid: 26, name: 'George', language: VoiceLanguage.britishEnglish, isFemale: false),
    KokoroVoice(id: 'bm_lewis', sid: 27, name: 'Lewis', language: VoiceLanguage.britishEnglish, isFemale: false),
  ];

  /// Sensible English defaults (narrator = male, dialogue = female).
  static const String defaultNarratorId = 'am_michael';
  static const String defaultDialogueId = 'af_heart';

  /// Seeded on first launch (see `FavoriteVoicesNotifier`) — three voices
  /// with clearly distinct timbre so favorites are useful immediately,
  /// rather than an empty section.
  static const List<String> defaultFavoriteIds = [
    'am_eric',
    'am_michael',
    'af_heart',
  ];

  /// Fixed sentence used for the picker's "play sample" button — short
  /// enough to synthesize quickly on-device for every voice.
  static const String previewSentence =
      'The old lighthouse keeper watched the storm roll in from the sea.';

  static final Map<String, KokoroVoice> _byId = {for (final v in all) v.id: v};

  /// Speaker id for [voiceId], or [fallback] if it isn't a Kokoro voice.
  static int sidFor(String voiceId, {required int fallback}) =>
      _byId[voiceId]?.sid ?? fallback;

  /// Display label for [voiceId], or the id itself if unknown.
  static String labelFor(String voiceId) => _byId[voiceId]?.label ?? voiceId;

  static bool isKokoro(String voiceId) => _byId.containsKey(voiceId);

  static KokoroVoice? byId(String voiceId) => _byId[voiceId];

  /// Voices grouped by language, preserving the catalog order (English first).
  static Map<VoiceLanguage, List<KokoroVoice>> byLanguage() {
    final map = <VoiceLanguage, List<KokoroVoice>>{};
    for (final v in all) {
      (map[v.language] ??= <KokoroVoice>[]).add(v);
    }
    return map;
  }

  /// Curated presets. Each preset pairs a narrator voice with a dialogue voice
  /// to achieve a specific tonal character across a whole book.
  static const List<VoicePreset> presets = [
    VoicePreset(
      id: 'epic_narrator',
      name: 'Epic Narrator',
      description: 'Deep British narrator with bright female dialogue',
      narratorId: 'bm_george',
      dialogueId: 'af_bella',
    ),
    VoicePreset(
      id: 'american_classic',
      name: 'American Classic',
      description: 'Smooth deep American narrator with airy female dialogue',
      narratorId: 'am_adam',
      dialogueId: 'af_sky',
    ),
    VoicePreset(
      id: 'contemporary',
      name: 'Contemporary',
      description: 'Warm American narrator with conversational female dialogue',
      narratorId: 'am_michael',
      dialogueId: 'af_nicole',
    ),
    VoicePreset(
      id: 'british_elegance',
      name: 'British Elegance',
      description: 'Refined British narrator with crisp British female dialogue',
      narratorId: 'bm_lewis',
      dialogueId: 'bf_emma',
    ),
  ];

  /// Case-insensitive search over voice name and language label.
  static List<KokoroVoice> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((v) =>
            v.name.toLowerCase().contains(q) ||
            v.language.label.toLowerCase().contains(q) ||
            v.id.toLowerCase().contains(q))
        .toList(growable: false);
  }
}
