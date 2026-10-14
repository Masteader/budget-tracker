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
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.home_work_rounded, color: Color(0xFF00C896), size: 22),
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
                      '${members.length} Active Member${members.length == 1 ? '' : 's'}',
                      style: TextStyle(color: context.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isAdmin
                      ? const Color(0xFF00C896).withValues(alpha: 0.15)
                      : const Color(0xFF58A6FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAdmin ? const Color(0xFF00C896) : const Color(0xFF58A6FF),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  isAdmin ? 'Admin' : 'Member',
                  style: TextStyle(
                    color: isAdmin ? const Color(0xFF00C896) : const Color(0xFF58A6FF),
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
            'HOUSEHOLD INVITE CODE',
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
                      color: const Color(0xFF00C896),
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
                      backgroundColor: const Color(0xFF00C896),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
                    label: const Text('Invite with Role', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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

          // Members Section
          Text(
            'MEMBERS',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          ...members.map((m) {
            final email = m['email'] as String? ?? 'User';
            final role = m['role'] as String? ?? 'member';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 16, color: context.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      email,
                      style: TextStyle(color: context.textPrimary, fontSize: 13),
                    ),
                  ),
                  Text(
                    role.toUpperCase(),
                    style: TextStyle(color: context.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),
          Divider(color: context.borderColor, height: 1),
          const SizedBox(height: 14),

          // Family Dependents & Children Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.child_care_rounded, size: 16, color: Color(0xFF58A6FF)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Paid for Whom (Children & Dependents)',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.textSecondary,
                          letterSpacing: 0.5,
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
                    foregroundColor: const Color(0xFF00C896),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 14),
                  label: const Text(
                    '+ Add Child / Dependent',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  onPressed: onAddDependent,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (dependents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No dependents registered yet. Add children to assign individual expenses.',
                style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF6E7681)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: dependents.map((d) {
                return Chip(
                  backgroundColor: context.scaffoldBg,
                  side: BorderSide(color: context.borderColor),
                  avatar: CircleAvatar(
                    backgroundColor: context.chipBg,
                    child: const Icon(Icons.face_rounded, size: 14, color: Color(0xFF58A6FF)),
                  ),
                  label: Text(
                    d.name,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: context.textPrimary,
                    ),
                  ),
                  deleteIcon: onRemoveDependent != null
                      ? Icon(Icons.close_rounded, size: 14, color: context.textSecondary)
                      : null,
                  onDeleted: onRemoveDependent != null ? () => onRemoveDependent!(d) : null,
                );
              }).toList(),
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
                    backgroundColor: const Color(0xFF00C896),
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
