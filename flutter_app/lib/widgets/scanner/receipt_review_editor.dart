import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/category_catalog.dart';
import '../../models/money.dart';
import '../../theme/app_themes.dart';

/// What the user corrected in a receipt review (UX-12): the total when it
/// differs from the scan and the category when another one was chosen (null =
/// keep the scanned value). [invalid] when the typed total is not a positive amount.
class ReceiptReviewEdits {
  final double? amount;
  final String? categoryCode;
  final bool invalid;
  const ReceiptReviewEdits({this.amount, this.categoryCode, this.invalid = false});

  static ReceiptReviewEdits from({
    required double scannedAmount,
    String? scannedCategory,
    required String amountText,
    String? chosenCategory,
  }) {
    final typed = parseMoneyInput(amountText, allowNegative: false);
    if (typed == null || typed <= 0) return const ReceiptReviewEdits(invalid: true);
    final category = (chosenCategory ?? '').trim();
    return ReceiptReviewEdits(
      amount: (typed - scannedAmount).abs() < 0.005 ? null : typed,
      categoryCode: category.isEmpty || category == (scannedCategory ?? '').trim() ? null : category,
    );
  }
}

/// The editable total and category of a scanned receipt.
class ReceiptReviewEditor extends StatelessWidget {
  final TextEditingController amountController;
  final String categoryCode;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback? onAmountChanged;
  final bool amountInvalid;

  const ReceiptReviewEditor({
    super.key,
    required this.amountController,
    required this.categoryCode,
    required this.onCategoryChanged,
    this.onAmountChanged,
    this.amountInvalid = false,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: context.borderColor),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('receipt_review_amount'),
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onAmountChanged?.call(),
            style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: context.tr('scan_review_amount_label'),
              suffixText: context.tr('sar'),
              errorText: amountInvalid ? context.tr('pec_amount_invalid') : null,
              filled: true,
              fillColor: context.inputBg,
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(borderSide: const BorderSide(color: AppThemes.success)),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const ValueKey('receipt_review_category'),
            initialValue: categoryCode,
            isExpanded: true,
            dropdownColor: context.cardBg,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: context.tr('category'),
              filled: true,
              fillColor: context.inputBg,
              border: border,
              enabledBorder: border,
            ),
            items: CategoryCatalog.pickerCodesIncluding(categoryCode)
                .map((code) => DropdownMenuItem(value: code, child: Text(context.trCat(code))))
                .toList(),
            onChanged: (v) {
              if (v != null) onCategoryChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
