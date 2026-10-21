import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/nafaqah.dart';
import '../../theme/app_themes.dart';
import 'nafaqah_class_selector.dart';

/// Family-mode review of a scanned or chat expense: the [NafaqahClassSelector]
/// plus, for a husband with several wives, which wife paid. Shown only when
/// [preview] says the recorder can classify (the husband or a wife).
class NafaqahReviewSection extends StatelessWidget {
  final NafaqahPreview preview;
  final String? value;
  final String? wifeId;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String> onWifeChanged;

  /// Hide the "husband paid" option when the chips already say the wife paid.
  final bool showHusbandOption;

  /// Highlights the wife choice after a save attempt without one.
  final bool showWifeRequired;

  const NafaqahReviewSection({
    super.key,
    required this.preview,
    required this.value,
    required this.onChanged,
    required this.onWifeChanged,
    this.wifeId,
    this.showHusbandOption = true,
    this.showWifeRequired = false,
  });

  /// A save may proceed: no wife is needed, or one is chosen.
  static bool hasRequiredWife(NafaqahPreview preview, String? value, String? wifeId) =>
      !preview.needsWifeChoice || value == null || (wifeId != null && wifeId.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (!preview.canClassify) return const SizedBox.shrink();
    final showWives = preview.needsWifeChoice && value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NafaqahClassSelector(
          value: value,
          viewerRole: preview.viewerRole,
          // The wife is the one recording, or the wife chosen (the only one).
          wifeName: preview.viewerIsWife ? null : preview.wifeNameFor(wifeId),
          husbandName: preview.husbandName,
          showHusbandOption: showHusbandOption,
          onChanged: onChanged,
        ),
        if (showWives) ...[
          const SizedBox(height: 8),
          Text(
            context.tr('nafaqah_choose_wife'),
            style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: preview.wives.map((w) {
              final name = (w.displayName ?? '').trim().isNotEmpty ? w.displayName!.trim() : context.tr('wife_spouse_title');
              return ChoiceChip(
                key: ValueKey('nafaqah_wife_${w.id}'),
                label: Text(name),
                selected: wifeId == w.id,
                onSelected: (selected) {
                  if (selected) onWifeChanged(w.id);
                },
              );
            }).toList(),
          ),
          if (showWifeRequired && !hasRequiredWife(preview, value, wifeId)) ...[
            const SizedBox(height: 4),
            Text(
              context.tr('nafaqah_choose_wife_required'),
              style: TextStyle(color: context.dangerColor, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ],
    );
  }
}
