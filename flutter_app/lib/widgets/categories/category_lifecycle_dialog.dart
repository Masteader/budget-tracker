import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';

enum CategoryLifecycleAction {
  replaceAndArchive,
  renameOnly,
}

class CategoryLifecycleDialog extends StatefulWidget {
  final String categoryCode;
  final String currentName;
  final int transactionCount;
  final void Function(CategoryLifecycleAction action, String newName) onConfirm;

  const CategoryLifecycleDialog({
    super.key,
    required this.categoryCode,
    required this.currentName,
    required this.transactionCount,
    required this.onConfirm,
  });

  static Future<void> show({
    required BuildContext context,
    required String categoryCode,
    required String currentName,
    required int transactionCount,
    required void Function(CategoryLifecycleAction action, String newName) onConfirm,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => CategoryLifecycleDialog(
        categoryCode: categoryCode,
        currentName: currentName,
        transactionCount: transactionCount,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<CategoryLifecycleDialog> createState() => _CategoryLifecycleDialogState();
}

class _CategoryLifecycleDialogState extends State<CategoryLifecycleDialog> {
  late CategoryLifecycleAction _selectedAction;
  late TextEditingController _nameCtrl;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _selectedAction = CategoryLifecycleAction.replaceAndArchive;
    _nameCtrl = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _handleConfirm() {
    final text = _nameCtrl.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorText = context.tr('enter_new_category_name');
      });
      return;
    }
    Navigator.of(context).pop();
    widget.onConfirm(_selectedAction, text);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final trArgs = context.trArgs;

    return AlertDialog(
      backgroundColor: context.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.accentText.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.swap_horiz_rounded, color: context.accentText, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('category_lifecycle_title'),
              style: TextStyle(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Expense count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trArgs('past_expenses_recorded', {'count': widget.transactionCount.toString()}),
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Option 1: Replace & Archive (Recommended)
            _buildOptionTile(
              action: CategoryLifecycleAction.replaceAndArchive,
              title: tr('replace_and_archive_opt'),
              desc: tr('replace_and_archive_desc'),
              isRecommended: true,
            ),
            const SizedBox(height: 10),

            // Option 2: Rename Only
            _buildOptionTile(
              action: CategoryLifecycleAction.renameOnly,
              title: tr('rename_only_opt'),
              desc: tr('rename_only_desc'),
              isRecommended: false,
            ),
            const SizedBox(height: 16),

            // New Name input
            Text(
              tr('new_category_name_label'),
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: TextStyle(color: context.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: context.textSecondary.withValues(alpha: 0.07),
                hintText: tr('rename_category_hint'),
                hintStyle: TextStyle(color: context.textSecondary.withValues(alpha: 0.6), fontSize: 13),
                errorText: _errorText,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.textSecondary.withValues(alpha: 0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.textSecondary.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.accentText, width: 1.5),
                ),
              ),
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            tr('cancel'),
            style: TextStyle(color: context.textSecondary, fontWeight: FontWeight.w600),
          ),
        ),
        ElevatedButton(
          onPressed: _handleConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.primaryButtonBg,
            foregroundColor: context.primaryButtonFg,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            tr('save'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionTile({
    required CategoryLifecycleAction action,
    required String title,
    required String desc,
    required bool isRecommended,
  }) {
    final isSelected = _selectedAction == action;
    return InkWell(
      onTap: () => setState(() => _selectedAction = action),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? context.accentText.withValues(alpha: 0.08)
              : context.textSecondary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? context.accentText
                : context.textSecondary.withValues(alpha: 0.15),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? context.accentText : context.textSecondary.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.accentText,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? context.accentText : context.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
