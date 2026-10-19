import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import 'role_invite_dialog.dart';

/// Card for managing household membership, invite code, household switching, and dependents.
class HouseholdManagementCard extends StatelessWidget {
  final String householdName;
  final String inviteCode;
  final String userRole;
  final List<Map<String, dynamic>> members;
  final List<HouseholdDependent> dependents;
  final String? householdId;
  final VoidCallback onCopyInviteCode;
  final VoidCallback onLeaveHousehold;
  final VoidCallback onSwitchHousehold;
  final VoidCallback onCreateHousehold;
  final VoidCallback? onAddDependent;
  final ValueChanged<HouseholdDependent>? onRemoveDependent;

  const HouseholdManagementCard({
    super.key,
    required this.householdName,
    required this.inviteCode,
    required this.userRole,
    required this.members,
    this.dependents = const [],
    this.householdId,
    required this.onCopyInviteCode,
    required this.onLeaveHousehold,
    required this.onSwitchHousehold,
    required this.onCreateHousehold,
    this.onAddDependent,
    this.onRemoveDependent,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = userRole.toLowerCase() == 'admin';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Name & Role Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppThemes.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.home_work_rounded, color: AppThemes.success, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      householdName,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      members.length == 1 ? context.tr('hmc_one_active_member') : context.trArgs('hmc_active_members', {'count': members.length}),
                      style: TextStyle(color: context.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isAdmin
                      ? AppThemes.success.withValues(alpha: 0.15)
                      : const Color(0xFF58A6FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAdmin ? AppThemes.success : const Color(0xFF58A6FF),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  isAdmin ? context.tr('admin') : context.tr('member'),
                  style: TextStyle(
                    color: isAdmin ? AppThemes.success : const Color(0xFF58A6FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: context.borderColor, height: 1),
          const SizedBox(height: 14),

          // Invite Code Section
          Text(
            context.tr('hmc_invite_code_caps'),
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.scaffoldBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    inviteCode,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: context.successText,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textPrimary,
                    side: BorderSide(color: context.borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: Text(context.tr('copy_code'), style: const TextStyle(fontSize: 11)),
                  onPressed: onCopyInviteCode,
                ),
                if (householdId != null && householdId!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemes.success,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
                    label: Text(context.tr('hmc_invite_with_role'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => RoleInviteDialog(householdId: householdId!),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Members & Living Group Hub
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.group_rounded, size: 16, color: AppThemes.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('hmc_members_caps'),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.textSecondary,
                          letterSpacing: 0.8,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (onAddDependent != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppThemes.success,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
                  label: Text(
                    context.tr('hmc_add_member'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  onPressed: onAddDependent,
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Active App Accounts
          ...members.map((m) {
            final email = m['email'] as String? ?? context.tr('set_user');
            final role = m['role'] as String? ?? 'member';
            final isAdminMember = role.toLowerCase() == 'admin';

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.scaffoldBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppThemes.success.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_outline_rounded, color: AppThemes.success, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          email,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppThemes.success,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              context.tr('active_account'),
                              style: TextStyle(
                                fontSize: 11,
                                color: context.successText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isAdminMember
                          ? AppThemes.success.withValues(alpha: 0.15)
                          : context.chipBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      role.toUpperCase(),
                      style: TextStyle(
                        color: isAdminMember ? AppThemes.success : context.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          // Pre-created and Dependent Members
          ...dependents.map((d) {
            Color roleColor = const Color(0xFF34D399);
            IconData roleIcon = Icons.child_care_rounded;
            String roleName = context.tr('hmc_child');

            if (d.isSpouse) {
              roleColor = const Color(0xFFE5A93C);
              roleIcon = Icons.favorite_rounded;
              roleName = context.tr('wife_spouse_title');
            } else if (d.isPeer) {
              roleColor = const Color(0xFF38BDF8);
              roleIcon = Icons.group_outlined;
              roleName = context.tr('role_roommate');
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.scaffoldBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(roleIcon, color: roleColor, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                d.name,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: context.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: roleColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                roleName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: roleColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: d.isClaimed ? AppThemes.success : const Color(0xFFE5A93C),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              d.isClaimed ? context.tr('active_account') : context.tr('pre_account_profile'),
                              style: TextStyle(
                                fontSize: 11,
                                color: d.isClaimed ? AppThemes.success : const Color(0xFFE5A93C),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (d.monthlyAllowance > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                context.trArgs('hmc_allowance_per_month', {'amount': d.monthlyAllowance.toStringAsFixed(0)}),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!d.isClaimed && householdId != null && householdId!.isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      tooltip: context.tr('invite_linked_profile'),
                      color: AppThemes.success,
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => RoleInviteDialog(
                            householdId: householdId!,
                            initialRole: d.relationship,
                            targetMemberId: d.id,
                            targetMemberName: d.name,
                          ),
                        );
                      },
                    ),
                  ],
                  if (onRemoveDependent != null) ...[
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 16, color: context.textSecondary),
                      tooltip: context.tr('set_remove'),
                      onPressed: () => onRemoveDependent!(d),
                    ),
                  ],
                ],
              ),
            );
          }),

          if (members.isEmpty && dependents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.tr('hmc_empty'),
                style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF6E7681)),
              ),
            ),

          const SizedBox(height: 18),
          Divider(color: context.borderColor, height: 1),
          const SizedBox(height: 14),

          // Action Buttons: Join Another, Create New, Leave
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textPrimary,
                    side: BorderSide(color: context.borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.group_add_outlined, size: 16),
                  label: Text(context.tr('join_with_code'), style: const TextStyle(fontSize: 12)),
                  onPressed: onSwitchHousehold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemes.success,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(context.tr('new_household'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: onCreateHousehold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFF85149),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              ),
              icon: const Icon(Icons.logout_rounded, size: 15),
              label: Text(context.tr('leave_household'), style: const TextStyle(fontSize: 12)),
              onPressed: onLeaveHousehold,
            ),
          ),
        ],
      ),
    );
  }
}
