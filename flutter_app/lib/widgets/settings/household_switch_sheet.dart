import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/household_membership.dart';
import '../../providers/budget_provider.dart';
import '../../providers/household_role_provider.dart';
import '../../providers/installment_provider.dart';
import '../../providers/recurring_bills_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

/// Modal bottom sheet for switching active household context and managing multiple household memberships.
class HouseholdSwitchSheet extends StatefulWidget {
  final String currentHouseholdId;
  final VoidCallback? onSwitched;
  final VoidCallback? onJoinNew;
  final VoidCallback? onCreateNew;

  const HouseholdSwitchSheet({
    super.key,
    required this.currentHouseholdId,
    this.onSwitched,
    this.onJoinNew,
    this.onCreateNew,
  });

  static Future<void> show(
    BuildContext context, {
    required String currentHouseholdId,
    VoidCallback? onSwitched,
    VoidCallback? onJoinNew,
    VoidCallback? onCreateNew,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => HouseholdSwitchSheet(
        currentHouseholdId: currentHouseholdId,
        onSwitched: onSwitched,
        onJoinNew: onJoinNew,
        onCreateNew: onCreateNew,
      ),
    );
  }

  @override
  State<HouseholdSwitchSheet> createState() => _HouseholdSwitchSheetState();
}

class _HouseholdSwitchSheetState extends State<HouseholdSwitchSheet> {
  List<HouseholdMembership> _memberships = [];
  bool _isLoading = true;
  String? _switchingToId;

  @override
  void initState() {
    super.initState();
    _loadMemberships();
  }

  Future<void> _loadMemberships() async {
    setState(() => _isLoading = true);
    try {
      final list = await ApiService.instance.getUserHouseholds();
      if (mounted) {
        setState(() {
          _memberships = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSwitch(String householdId) async {
    if (householdId == widget.currentHouseholdId) return;
    setState(() => _switchingToId = householdId);

    try {
      final success = await ApiService.instance.switchActiveHousehold(householdId);
      if (success && mounted) {
        // Invalidate and re-hydrate providers
        try {
          context.read<TransactionProvider>().init(householdId);
        } catch (_) {}
        try {
          context.read<BudgetProvider>().init(householdId);
        } catch (_) {}
        try {
          context.read<HouseholdRoleProvider>().load(householdId);
        } catch (_) {}
        // Bills and plans of the new household (reminders reschedule from them).
        try {
          context.read<RecurringBillsProvider>().init(householdId);
        } catch (_) {}
        try {
          context.read<InstallmentProvider>().init(householdId);
        } catch (_) {}

        AppSnackBar.showSuccess(
          context,
          context.tr('household_switched_success'),
          title: context.tr('switch_household'),
        );

        widget.onSwitched?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, e.toString(), title: context.tr('hss_failed'));
      }
    } finally {
      if (mounted) setState(() => _switchingToId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 260,
        alignment: Alignment.center,
        child: CircularProgressIndicator(
          color: context.accentText,
        ),
      );
    }

    return HouseholdSwitchSheetContent(
      memberships: _memberships,
      currentHouseholdId: widget.currentHouseholdId,
      switchingToId: _switchingToId,
      onSwitch: _handleSwitch,
      onJoinNew: () {
        Navigator.pop(context);
        widget.onJoinNew?.call();
      },
      onCreateNew: () {
        Navigator.pop(context);
        widget.onCreateNew?.call();
      },
    );
  }
}

/// Pure presentation content widget for HouseholdSwitchSheet, testable without network.
class HouseholdSwitchSheetContent extends StatelessWidget {
  final List<HouseholdMembership> memberships;
  final String currentHouseholdId;
  final String? switchingToId;
  final ValueChanged<String> onSwitch;
  final VoidCallback onJoinNew;
  final VoidCallback onCreateNew;

  const HouseholdSwitchSheetContent({
    super.key,
    required this.memberships,
    required this.currentHouseholdId,
    this.switchingToId,
    required this.onSwitch,
    required this.onJoinNew,
    required this.onCreateNew,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.accentSubtleBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    color: context.accentText,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('switch_household'),
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        context.tr('switch_household_desc'),
                        style: TextStyle(color: context.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Memberships List
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: memberships.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, index) {
                  final m = memberships[index];
                  final isActive = m.householdId == currentHouseholdId || m.isActive;
                  final isSwitching = switchingToId == m.householdId;

                  return InkWell(
                    onTap: isSwitching ? null : () => onSwitch(m.householdId),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isActive
                            ? (context.accentSubtleBg)
                            : context.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isActive
                              ? (context.accentText)
                              : context.borderColor,
                          width: isActive ? 1.4 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isActive
                                ? (context.accentText)
                                : context.textSecondary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        m.householdName,
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: context.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: m.isAdmin
                                            ? (context.accentSubtleBg)
                                            : context.accentSubtleBg,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: m.isAdmin
                                              ? (context.accentText)
                                              : (context.textSecondary),
                                          width: 0.6,
                                        ),
                                      ),
                                      child: Text(
                                        m.isAdmin ? context.tr('admin') : context.tr('member'),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: m.isAdmin
                                              ? (context.accentText)
                                              : (context.textSecondary),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (m.inviteCode.isNotEmpty)
                                  Text(
                                    context.trArgs('sba_code', {'code': m.inviteCode}),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: context.textSecondary,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: context.accentText.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                context.tr('active_badge'),
                                style: TextStyle(
                                  color: context.accentText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (isSwitching)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.accentText,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Actions row: Join Another Household or Create New
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: context.borderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.group_add_outlined, size: 18),
                    label: Text(
                      context.tr('join_another_household'),
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: onJoinNew,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.primaryButtonBg,
                      foregroundColor: context.primaryButtonFg,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_home_outlined, size: 18),
                    label: Text(
                      context.tr('create_new_household'),
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    onPressed: onCreateNew,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
