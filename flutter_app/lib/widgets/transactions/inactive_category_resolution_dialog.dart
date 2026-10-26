import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';

/// Modal dialog shown when a new transaction is parsed or logged
/// against a category that is currently marked inactive for the household.
class InactiveCategoryResolutionDialog extends StatelessWidget {
  final String categoryName;
  final double amount;
  final String merchant;
  final VoidCallback onReactivate;
  final VoidCallback onChangeCategory;

  const InactiveCategoryResolutionDialog({
    super.key,
    required this.categoryName,
    required this.amount,
    required this.merchant,
    required this.onReactivate,
    required this.onChangeCategory,
  });

  static Future<void> show({
    required BuildContext context,
    required String categoryName,
    required double amount,
    required String merchant,
    required VoidCallback onReactivate,
    required VoidCallback onChangeCategory,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => InactiveCategoryResolutionDialog(
        categoryName: categoryName,
        amount: amount,
        merchant: merchant,
        onReactivate: () {
          Navigator.pop(ctx);
          onReactivate();
        },
        onChangeCategory: () {
          Navigator.pop(ctx);
          onChangeCategory();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.tr('icr_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.trArgs('icr_desc', {'amount': context.sar(amount), 'merchant': merchant, 'category': categoryName}),
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              context.trArgs('icr_question', {'category': categoryName}),
              style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        OutlinedButton(
          onPressed: onChangeCategory,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
          ),
          child: Text(context.tr('icr_other_category')),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: onReactivate,
          style: FilledButton.styleFrom(
            backgroundColor: context.primaryButtonBg,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(40),
          ),
          child: Text(context.tr('icr_reactivate')),
        ),
      ],
    );
  }
}
