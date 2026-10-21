import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';

/// Example messages offered as chips in the chat, in the app language (UX-18).
const List<String> chatExampleKeys = ['chat_example_1', 'chat_example_2', 'chat_example_3', 'chat_example_4'];

/// The language the microphone listens in. One 48 dp control (UX-19) instead
/// of three small pills; the assistant itself reads any of the three
/// languages, so this only matters for dictation.
class VoiceLanguageButton extends StatelessWidget {
  /// Speech recognition locale: 'ar_SA', 'en_US' or 'ur_PK'.
  final String localeId;
  final ValueChanged<String> onChanged;

  const VoiceLanguageButton({super.key, required this.localeId, required this.onChanged});

  static const _options = [('ar_SA', 'ar'), ('en_US', 'en'), ('ur_PK', 'ur')];

  /// A language's own name ("العربية", "English", "اردو").
  static String _selfName(String lang) => AppLocalizations(Locale(lang)).get('language_$lang');

  @override
  Widget build(BuildContext context) {
    final current = _options.firstWhere((o) => o.$1 == localeId, orElse: () => _options.first);
    return PopupMenuButton<String>(
      tooltip: context.tr('chat_voice_language'),
      initialValue: current.$1,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final o in _options)
          PopupMenuItem<String>(
            value: o.$1,
            child: Text(_selfName(o.$2)),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 8, end: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.record_voice_over_outlined, size: 20, color: context.accentText),
              const SizedBox(width: 6),
              Text(
                _selfName(current.$2),
                style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Icon(Icons.arrow_drop_down_rounded, color: context.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
