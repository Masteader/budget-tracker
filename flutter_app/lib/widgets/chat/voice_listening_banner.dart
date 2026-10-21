import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';

/// Animated pulse banner displayed when the microphone is recording speech for AI chat.
class VoiceListeningBanner extends StatelessWidget {
  final bool isListening;
  final double soundLevel;
  final String selectedLocale;
  final VoidCallback onToggleListening;

  const VoiceListeningBanner({
    super.key,
    required this.isListening,
    required this.soundLevel,
    required this.selectedLocale,
    required this.onToggleListening,
  });

  @override
  Widget build(BuildContext context) {
    if (!isListening) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 10 + (soundLevel.clamp(0.0, 10.0) * 0.8),
            height: 10 + (soundLevel.clamp(0.0, 10.0) * 0.8),
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // Shown in the language being recognised (ar/en/ur).
              AppLocalizations(Locale(selectedLocale.substring(0, 2))).get('vlb_listening'),
              style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          InkWell(
            onTap: onToggleListening,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppThemes.success,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                context.tr('done'),
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
