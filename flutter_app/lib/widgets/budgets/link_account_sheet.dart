import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../models/models.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

/// Modal bottom sheet to map a budget category to a specific payment account.
class LinkAccountSheet extends StatefulWidget {
  final String householdId;
  final Budget budget;
  final String categoryName;
  final VoidCallback? onMapped;

  const LinkAccountSheet({
    super.key,
    required this.householdId,
    required this.budget,
    required this.categoryName,
    this.onMapped,
  });

  static Future<void> show(
    BuildContext context, {
    required String householdId,
    required Budget budget,
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
    _selectedAccountId = widget.budget.accountId;
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
      await AccountService.instance.linkBudgetAccount(widget.budget.id, _selectedAccountId);
      if (mounted) {
        Navigator.pop(context);
        widget.onMapped?.call();
        final acc = _accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
        AppSnackBar.showSuccess(
          context,
          '${widget.categoryName} linked to ${acc?.name ?? "No Account"}!',
          title: 'Account Mapped',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackBar.showError(context, 'Failed to link account: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');

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
                      color: const Color(0xFF00E5BF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.link_rounded, color: Color(0xFF00E5BF), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Map Budget to Account',
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.categoryName} (Allocated: SAR ${fmt.format(widget.budget.allocatedAmount)})',
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                'Select which bank account, e-wallet, or pool will fund this category. Transactions will consume from this balance by default.',
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
              else if (_accounts.isEmpty)
                Text('No accounts found. Create an account in Accounts & Balances first.', style: TextStyle(color: Colors.orange.shade300, fontSize: 13))
              else
                ..._accounts.map((acc) {
                  final isSelected = _selectedAccountId == acc.id;
                  final hasEnough = acc.balance >= widget.budget.allocatedAmount;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00E5BF).withValues(alpha: 0.1)
                          : context.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF00E5BF)
                            : context.borderColor,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      leading: Icon(acc.accountType.defaultIcon, color: isSelected ? const Color(0xFF00E5BF) : context.textSecondary),
                      title: Text(
                        acc.name,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Balance: ${acc.currency} ${fmt.format(acc.balance)} ${!hasEnough ? "(Low balance)" : ""}',
                        style: TextStyle(
                          color: !hasEnough ? Colors.orange : context.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5BF), size: 20)
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
                      child: Text('Unlink Account', style: TextStyle(color: context.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveLink,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5BF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('Save Link', style: TextStyle(fontWeight: FontWeight.bold)),
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
