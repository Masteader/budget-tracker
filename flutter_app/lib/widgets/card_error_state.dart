import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_themes.dart';

/// The error state of a card whose data could not be loaded (UX-01). It keeps
/// the card's [title], says what failed and offers a retry, so a failed
/// request never reads as "nothing owed" or "all paid".
class CardErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final IconData icon;

  const CardErrorState({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    this.icon = Icons.cloud_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final danger = context.dangerColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: danger, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: context.textSecondary, fontSize: 12)),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              key: const Key('card_error_retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.tr('try_again')),
            ),
          ),
        ],
      ),
    );
  }
}

/// A one-line notice above data that is still shown from the last successful
/// load when a refresh failed: "Couldn't refresh. Last updated 9:40 PM".
class CardErrorBanner extends StatelessWidget {
  final DateTime? lastUpdated;
  final VoidCallback onRetry;

  const CardErrorBanner({super.key, required this.lastUpdated, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final time = lastUpdated == null ? '' : context.fmtDate(lastUpdated!, 'h:mm a');
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: context.dangerColor.withValues(alpha: context.isDarkMode ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: context.dangerColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.trArgs('load_error_stale', {'time': time}),
              style: TextStyle(color: context.textSecondary, fontSize: 11),
            ),
          ),
          TextButton(
            key: const Key('card_error_banner_retry'),
            onPressed: onRetry,
            child: Text(context.tr('try_again')),
          ),
        ],
      ),
    );
  }
}
