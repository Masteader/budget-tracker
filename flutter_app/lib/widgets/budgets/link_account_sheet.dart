import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../models/models.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

/// Modal bottom sheet to map a budget category to a specific payment account.
class LinkAccountSheet extends StatefulWidget {
  final String householdId;
  final Budget? budget;
  final String? categoryCode;
  final String? cycleKey;
  final String categoryName;
  final VoidCallback? onMapped;

  const LinkAccountSheet({
    super.key,
    required this.householdId,
    this.budget,
    this.categoryCode,
    this.cycleKey,
    required this.categoryName,
    this.onMapped,
  });

  static Future<void> show(
    BuildContext context, {
    required String householdId,
    Budget? budget,
    String? categoryCode,
    String? cycleKey,
    required String categoryName,
    VoidCallback? onMapped,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LinkAccountSheet(
        householdId: householdId,
        budget: budget,
        categoryCode: categoryCode ?? budget?.categoryCode,
        cycleKey: cycleKey ?? budget?.cycleKey,
        categoryName: categoryName,
        onMapped: onMapped,
      ),
    );
  }

  @override
  State<LinkAccountSheet> createState() => _LinkAccountSheetState();
}

class _LinkAccountSheetState extends State<LinkAccountSheet> {
  List<Account> _accounts = [];
  bool _isLoading = true;
  String? _selectedAccountId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedAccountId = widget.budget?.accountId;
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final list = await AccountService.instance.getAccounts(widget.householdId);
      if (mounted) {
        setState(() {
          _accounts = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLink() async {
    setState(() => _isSaving = true);
    try {
      if (widget.budget != null && widget.budget!.id.isNotEmpty) {
        await AccountService.instance.linkBudgetAccount(widget.budget!.id, _selectedAccountId);
      } else if (widget.categoryCode != null && widget.cycleKey != null) {
        await AccountService.instance.linkCategoryAccount(
          householdId: widget.householdId,
          categoryCode: widget.categoryCode!,
          cycleKey: widget.cycleKey!,
          accountId: _selectedAccountId,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onMapped?.call();
        final acc = _accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
        AppSnackBar.showSuccess(
          context,
          context.trArgs('las_linked_msg', {'category': widget.categoryName, 'account': acc?.name ?? context.tr('no_account')}),
          title: context.tr('las_mapped_title'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackBar.showError(context, context.trArgs('las_failed', {'error': e}));
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: context.borderColor, width: 1.2)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.electricTeal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.link_rounded, color: context.electricTeal, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('link_payment_account'),
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.budget != null
                              ? '${widget.categoryName} (${context.tr('allocated')}: ${context.sar(widget.budget!.allocatedAmount)})'
                              : widget.categoryName,
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                context.tr('map_budget_account_desc'),
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
              else if (_accounts.isEmpty)
                Text(context.tr('no_accounts_configured'), style: TextStyle(color: Colors.orange.shade300, fontSize: 13))
              else
                ..._accounts.map((acc) {
                  final isSelected = _selectedAccountId == acc.id;
                  final hasEnough = widget.budget == null || acc.balance >= widget.budget!.allocatedAmount;
                  final selectColor = context.accentText;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? selectColor.withValues(alpha: 0.1)
                          : context.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? selectColor
                            : context.borderColor,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      leading: Icon(acc.accountType.defaultIcon, color: isSelected ? selectColor : context.textSecondary),
                      title: Text(
                        acc.name,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${context.tr('current_balance')}: ${context.money(acc.balance, acc.currency)} ${!hasEnough ? "(${context.tr('low_balance')})" : ""}',
                        style: TextStyle(
                          color: !hasEnough ? Colors.orange : context.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: context.electricTeal, size: 20)
                          : null,
                      onTap: () => setState(() => _selectedAccountId = acc.id),
                    ),
                  );
                }),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        setState(() => _selectedAccountId = null);
                        _saveLink();
                      },
                      child: Text(context.tr('unlink_account'), style: TextStyle(color: context.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveLink,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.electricTeal,
                        foregroundColor: context.scaffoldBg,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.scaffoldBg))
                          : Text(context.tr('save_link'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
