import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/widgets/three_d_surface_card.dart';
import '../../core/widgets/three_d_icon_puck.dart';
import '../../models/models.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import 'role_invite_dialog.dart';
import '../../services/household_invite_share.dart';

/// Card for managing household membership, invite code, household switching, and dependents.
class HouseholdManagementCard extends StatelessWidget {
  final String householdName;
  final String inviteCode;
  final String userRole;
  final List<Map<String, dynamic>> members;
  final List<HouseholdDependent> dependents;
  final String? householdId;
  final VoidCallback onCopyInviteCode;

  /// Opens the share sheet with an invite message (shown when the code is
  /// readable, i.e. for admins).
  final VoidCallback? onShareInvite;
  final VoidCallback onLeaveHousehold;
  final VoidCallback onSwitchHousehold;
  final VoidCallback onCreateHousehold;
  final VoidCallback? onAddDependent;
  final ValueChanged<HouseholdDependent>? onRemoveDependent;

  /// Optional embedded roles section (e.g. [HouseholdRolesCard]). When provided,
  /// this authoritative roster replaces the static member rows to avoid duplicate
  /// member listings in the household settings view.
  final Widget? rolesSection;

  const HouseholdManagementCard({
    super.key,
    required this.householdName,
    required this.inviteCode,
    required this.userRole,
    required this.members,
    this.dependents = const [],
    this.householdId,
    required this.onCopyInviteCode,
    this.onShareInvite,
    required this.onLeaveHousehold,
    required this.onSwitchHousehold,
    required this.onCreateHousehold,
    this.onAddDependent,
    this.onRemoveDependent,
    this.rolesSection,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = userRole.toLowerCase() == 'admin';

    return ThreeDSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Name & Role Badge
          Row(
            children: [
              const ThreeDIconPuck(
                icon: Icons.home_work_rounded,
                size: 46,
                iconColor: Colors.white,
                isSquircle: true,
              ),
              const SizedBox(width: 14),
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
                      context.trPlural('hmc_active_members', members.length),
                      style: TextStyle(color: context.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isAdmin
                      ? context.accentSubtleBg
                      : context.infoSubtleBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAdmin ? context.accentText : context.infoColor,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  isAdmin ? context.tr('admin') : context.tr('member'),
                  style: TextStyle(
                    color: isAdmin ? context.accentText : context.infoColor,
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
                      color: context.accentText,
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
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onShareInvite != null && isShareableInviteCode(inviteCode))
                ElevatedButton.icon(
                  key: const ValueKey('share_invite_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.primaryButtonBg,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: Text(context.tr('share_invite'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: onShareInvite,
                ),
              if (isAdmin && householdId != null && householdId!.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.accentText,
                    side: BorderSide(color: context.accentText.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  label: Text(context.tr('hmc_invite_with_role'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => RoleInviteDialog(householdId: householdId!, householdName: householdName),
                    );
                  },
                ),
            ],
          ),

          if (rolesSection != null) ...[
            const SizedBox(height: 16),
            Divider(color: context.borderColor, height: 1),
            const SizedBox(height: 16),
            rolesSection!,
            if (dependents.isNotEmpty || onAddDependent != null) ...[
              const SizedBox(height: 12),
              ...dependents.map((d) => _buildDependentRow(context, d, isAdmin)),
              if (onAddDependent != null) _buildAddDependentButton(context),
            ],
          ] else ...[
            const SizedBox(height: 16),
            // Members & Living Group Hub
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.group_rounded, size: 16, color: context.accentText),
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
              ],
            ),
            const SizedBox(height: 10),

            // Active App Accounts
            ...members.map((m) => _buildMemberRow(context, m)),

            // Pre-created and Dependent Members
            ...dependents.map((d) => _buildDependentRow(context, d, isAdmin)),

            if (onAddDependent != null) _buildAddDependentButton(context),
            if (members.isEmpty && dependents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.tr('hmc_empty'),
                  style: GoogleFonts.outfit(fontSize: 12, color: context.textMuted),
                ),
              ),
          ],

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
                    backgroundColor: context.primaryButtonBg,
                    foregroundColor: Colors.white,
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
                foregroundColor: context.dangerColor,
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

  Widget _buildMemberRow(BuildContext context, Map<String, dynamic> m) {
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
              color: context.accentSubtleBg,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_outline_rounded, color: context.accentText, size: 16),
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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.accentText,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        context.tr('active_account'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.accentText,
                          fontWeight: FontWeight.w500,
                        ),
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
              color: isAdminMember ? (context.pillBg) : context.chipBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              context.tr(isAdminMember ? 'admin' : 'member'),
              style: TextStyle(
                color: isAdminMember ? (context.accentText) : context.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDependentRow(BuildContext context, HouseholdDependent d, bool isAdmin) {
    Color roleColor = context.accentText;
    IconData roleIcon = Icons.child_care_rounded;
    String roleName = context.tr('hmc_child');
    // A child does not "join": it is a dependent. Only a spouse or a
    // roommate profile waits for its invite to be accepted.
    final isDependent = !d.isSpouse && !d.isPeer;
    final statusText = d.isClaimed
        ? context.tr('active_account')
        : (isDependent ? context.tr('hmc_dependent_label') : context.tr('hmc_invite_pending'));
    final statusColor = d.isClaimed ? (context.accentText) : (isDependent ? context.textSecondary : context.warnText);

    if (d.isSpouse) {
      roleColor = context.goldText;
      roleIcon = Icons.favorite_rounded;
      roleName = context.tr('wife_spouse_title');
    } else if (d.isPeer) {
      roleColor = context.infoText;
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
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: roleColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Wraps on narrow phones instead of overflowing (UX-15 / UX-29).
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            statusText,
                            style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    if (d.monthlyAllowance > 0)
                      Text(
                        context.trArgs('hmc_allowance_per_month', {'amount': context.sar(d.monthlyAllowance, decimals: 0)}),
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (!d.isClaimed && householdId != null && householdId!.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              tooltip: context.tr('invite_linked_profile'),
              color: context.accentText,
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
  }

  Widget _buildAddDependentButton(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: context.accentText,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(48, 48),
        ),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
        label: Text(
          context.tr('hmc_add_member'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        onPressed: onAddDependent,
      ),
    );
  }
}
