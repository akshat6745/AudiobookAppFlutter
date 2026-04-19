import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage.dart';

class LastPosition {
  final int chapter;
  final int paragraph;
  final String preview;
  final DateTime updatedAt;

  const LastPosition({
    required this.chapter,
    required this.paragraph,
    required this.preview,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'chapter': chapter,
        'paragraph': paragraph,
        'preview': preview,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LastPosition.fromJson(Map<String, dynamic> json) => LastPosition(
        chapter: json['chapter'] as int,
        paragraph: json['paragraph'] as int,
        preview: json['preview'] as String? ?? '',
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
                DateTime.now(),
      );
}

const _storageKey = 'last_positions';

class LastPositionNotifier extends StateNotifier<Map<String, LastPosition>> {
  LastPositionNotifier() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    final raw = await Storage.getString(_storageKey);
    if (raw == null) return;
    try {
      final map = (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, LastPosition.fromJson(v as Map<String, dynamic>)),
      );
      state = map;
    } catch (_) {}
  }

  Future<void> update({
    required String novelSlug,
    required int chapter,
    required int paragraph,
    required String preview,
  }) async {
    final truncated =
        preview.length > 200 ? '${preview.substring(0, 200)}…' : preview;
    final entry = LastPosition(
      chapter: chapter,
      paragraph: paragraph,
      preview: truncated,
      updatedAt: DateTime.now(),
    );
    state = {...state, novelSlug: entry};
    await Storage.setString(
      _storageKey,
      jsonEncode(state.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }
}

final lastPositionProvider =
    StateNotifierProvider<LastPositionNotifier, Map<String, LastPosition>>(
  (_) => LastPositionNotifier(),
);
