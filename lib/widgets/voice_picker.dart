import 'package:flutter/material.dart';

import '../services/tts/kokoro_voices.dart';
import '../theme/app_theme.dart';

/// Opens a searchable, language-grouped voice picker and calls [onSelected]
/// with the chosen voice id. Scales to the full Kokoro catalog (50+ voices)
/// without the unusable wall-of-chips.
Future<void> showVoicePicker({
  required BuildContext context,
  required String title,
  required String currentVoiceId,
  required ValueChanged<String> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _VoicePickerSheet(
      title: title,
      currentVoiceId: currentVoiceId,
      onSelected: onSelected,
    ),
  );
}

class _VoicePickerSheet extends StatefulWidget {
  const _VoicePickerSheet({
    required this.title,
    required this.currentVoiceId,
    required this.onSelected,
  });

  final String title;
  final String currentVoiceId;
  final ValueChanged<String> onSelected;

  @override
  State<_VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends State<_VoicePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = KokoroVoices.search(_query);
    // Group filtered results by language, preserving catalog order.
    final groups = <VoiceLanguage, List<KokoroVoice>>{};
    for (final v in results) {
      (groups[v.language] ??= <KokoroVoice>[]).add(v);
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search voice or language…',
                    filled: true,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: results.isEmpty
                    ? const Center(child: Text('No voices match'))
                    : ListView(
                        controller: scrollController,
                        children: [
                          for (final entry in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                              child: Text(
                                entry.key.label.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                            for (final v in entry.value)
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  v.isFemale ? Icons.woman : Icons.man,
                                  color: AppColors.textMuted,
                                ),
                                title: Text(v.name),
                                subtitle: Text('${v.language.label} ${v.gender}'),
                                trailing: v.id == widget.currentVoiceId
                                    ? const Icon(Icons.check_circle,
                                        color: AppColors.primary)
                                    : null,
                                selected: v.id == widget.currentVoiceId,
                                onTap: () {
                                  widget.onSelected(v.id);
                                  Navigator.of(context).pop();
                                },
                              ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
