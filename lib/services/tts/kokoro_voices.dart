/// Language groups for the Kokoro multilingual model.
enum VoiceLanguage {
  americanEnglish('American English'),
  britishEnglish('British English'),
  spanish('Spanish'),
  french('French'),
  hindi('Hindi'),
  italian('Italian'),
  japanese('Japanese'),
  portuguese('Portuguese'),
  chinese('Chinese');

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

/// Voice catalog for **kokoro-en-v0_19** (28 English voices across 4 accents).
///
/// IMPORTANT: `sid` is the speaker index into the model's `voices.bin`; the
/// order below matches the sherpa-onnx kokoro-multi-lang-v1_1 model card. If
/// you swap models, update this list to match — a wrong index plays the wrong
/// voice.
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
    // Spanish
    KokoroVoice(id: 'ef_dora', sid: 28, name: 'Dora', language: VoiceLanguage.spanish, isFemale: true),
    KokoroVoice(id: 'em_alex', sid: 29, name: 'Alex', language: VoiceLanguage.spanish, isFemale: false),
    // French
    KokoroVoice(id: 'ff_siwis', sid: 30, name: 'Siwis', language: VoiceLanguage.french, isFemale: true),
    // Hindi
    KokoroVoice(id: 'hf_alpha', sid: 31, name: 'Alpha', language: VoiceLanguage.hindi, isFemale: true),
    KokoroVoice(id: 'hf_beta', sid: 32, name: 'Beta', language: VoiceLanguage.hindi, isFemale: true),
    KokoroVoice(id: 'hm_omega', sid: 33, name: 'Omega', language: VoiceLanguage.hindi, isFemale: false),
    KokoroVoice(id: 'hm_psi', sid: 34, name: 'Psi', language: VoiceLanguage.hindi, isFemale: false),
    // Italian
    KokoroVoice(id: 'if_sara', sid: 35, name: 'Sara', language: VoiceLanguage.italian, isFemale: true),
    KokoroVoice(id: 'im_nicola', sid: 36, name: 'Nicola', language: VoiceLanguage.italian, isFemale: false),
    // Japanese
    KokoroVoice(id: 'jf_alpha', sid: 37, name: 'Alpha', language: VoiceLanguage.japanese, isFemale: true),
    KokoroVoice(id: 'jf_gongitsune', sid: 38, name: 'Gongitsune', language: VoiceLanguage.japanese, isFemale: true),
    KokoroVoice(id: 'jf_nezumi', sid: 39, name: 'Nezumi', language: VoiceLanguage.japanese, isFemale: true),
    KokoroVoice(id: 'jf_tebukuro', sid: 40, name: 'Tebukuro', language: VoiceLanguage.japanese, isFemale: true),
    KokoroVoice(id: 'jm_kumo', sid: 41, name: 'Kumo', language: VoiceLanguage.japanese, isFemale: false),
    // Portuguese (Brazilian)
    KokoroVoice(id: 'pf_dora', sid: 42, name: 'Dora', language: VoiceLanguage.portuguese, isFemale: true),
    KokoroVoice(id: 'pm_alex', sid: 43, name: 'Alex', language: VoiceLanguage.portuguese, isFemale: false),
    KokoroVoice(id: 'pm_santa', sid: 44, name: 'Santa', language: VoiceLanguage.portuguese, isFemale: false),
    // Chinese (Mandarin)
    KokoroVoice(id: 'zf_xiaobei', sid: 45, name: 'Xiaobei', language: VoiceLanguage.chinese, isFemale: true),
    KokoroVoice(id: 'zf_xiaoni', sid: 46, name: 'Xiaoni', language: VoiceLanguage.chinese, isFemale: true),
    KokoroVoice(id: 'zf_xiaoxiao', sid: 47, name: 'Xiaoxiao', language: VoiceLanguage.chinese, isFemale: true),
    KokoroVoice(id: 'zf_xiaoyi', sid: 48, name: 'Xiaoyi', language: VoiceLanguage.chinese, isFemale: true),
    KokoroVoice(id: 'zm_yunjian', sid: 49, name: 'Yunjian', language: VoiceLanguage.chinese, isFemale: false),
    KokoroVoice(id: 'zm_yunxi', sid: 50, name: 'Yunxi', language: VoiceLanguage.chinese, isFemale: false),
    KokoroVoice(id: 'zm_yunxia', sid: 51, name: 'Yunxia', language: VoiceLanguage.chinese, isFemale: false),
    KokoroVoice(id: 'zm_yunyang', sid: 52, name: 'Yunyang', language: VoiceLanguage.chinese, isFemale: false),
  ];

  /// Sensible English defaults (narrator = male, dialogue = female).
  static const String defaultNarratorId = 'am_michael';
  static const String defaultDialogueId = 'af_heart';

  static final Map<String, KokoroVoice> _byId = {for (final v in all) v.id: v};

  /// Speaker id for [voiceId], or [fallback] if it isn't a Kokoro voice.
  static int sidFor(String voiceId, {required int fallback}) =>
      _byId[voiceId]?.sid ?? fallback;

  /// Display label for [voiceId], or the id itself if unknown.
  static String labelFor(String voiceId) => _byId[voiceId]?.label ?? voiceId;

  static bool isKokoro(String voiceId) => _byId.containsKey(voiceId);

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
