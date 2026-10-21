import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/models.dart';
import '../../services/api/base_api_client.dart' show ApiRequestException;
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import '../../l10n/app_localizations.dart';

class RoleInviteDialog extends StatefulWidget {
  final String householdId;
  final String? initialRole;
  final String? targetMemberId;
  final String? targetMemberName;
  final ValueChanged<HouseholdInvite>? onInviteGenerated;

  /// Creates the invite on the server; defaults to the API. Injectable for tests.
  final Future<HouseholdInvite> Function(String householdId, String role, {String? targetMemberId})? createInvite;

  const RoleInviteDialog({
    super.key,
    required this.householdId,
    this.initialRole,
    this.targetMemberId,
    this.targetMemberName,
    this.onInviteGenerated,
    this.createInvite,
  });

  @override
  State<RoleInviteDialog> createState() => _RoleInviteDialogState();
}

class _RoleInviteDialogState extends State<RoleInviteDialog> {
  String _selectedRole = 'spouse';
  bool _isGenerating = false;
  HouseholdInvite? _generatedInvite;

  @override
  void initState() {
    super.initState();
    if (widget.initialRole != null) {
      final norm = widget.initialRole!.toLowerCase();
      if (norm == 'wife' || norm == 'spouse') {
        _selectedRole = 'spouse';
      } else if (norm == 'roommate' || norm == 'peer') {
        _selectedRole = 'peer';
      } else {
        _selectedRole = 'family_member';
      }
    }
  }

  final List<Map<String, dynamic>> _roles = const [
    {
      'id': 'spouse',
      'title': 'wife_spouse_title',
      'icon': Icons.favorite_rounded,
      'color': Color(0xFFE5A93C),
      'desc': 'rid_spouse_desc',
    },
    {
      'id': 'peer',
      'title': 'invite_role_peer',
      'icon': Icons.group_outlined,
      'color': Color(0xFF38BDF8),
      'desc': 'rid_peer_desc',
    },
    {
      'id': 'family_member',
      'title': 'invite_role_family',
      'icon': Icons.child_care_rounded,
      'color': Color(0xFF34D399),
      'desc': 'rid_family_desc',
    },
  ];

  Future<void> _generateInvite() async {
    setState(() => _isGenerating = true);

    HouseholdInvite invite;
    try {
      final create = widget.createInvite ?? ApiService.instance.createRoleInvite;
      invite = await create(
        widget.householdId,
        _selectedRole,
        targetMemberId: widget.targetMemberId,
      );
    } catch (e) {
      // FR-A-11: no invented "offline" code; it could never be redeemed.
      if (!mounted) return;
      setState(() => _isGenerating = false);
      final status = e is ApiRequestException ? e.statusCode : null;
      final code = e is ApiRequestException ? e.code : null;
      final String message;
      if (status == 403) {
        message = context.tr('rid_admin_only');
      } else if (code == 'invite_role_mismatch') {
        message = context.tr('hh_invite_role_mismatch');
      } else if (status == 400) {
        message = context.tr('rid_invalid_target');
      } else if (status == 404) {
        message = context.tr('rid_target_not_dependent');
      } else {
        message = context.trArgs('rid_generate_failed', {'error': e});
      }
      AppSnackBar.showError(context, message);
      return;
    }

    if (mounted) {
      setState(() {
        _generatedInvite = invite;
        _isGenerating = false;
      });
      widget.onInviteGenerated?.call(invite);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppThemes.success.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: AppThemes.success,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.targetMemberName != null
                          ? context.trArgs('rid_invite_name', {'name': widget.targetMemberName})
                          : context.tr('rid_generate_role_invite'),
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.targetMemberName != null
                    ? context.trArgs('rid_linked_desc', {'name': widget.targetMemberName})
                    : context.tr('rid_select_role_desc'),
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),

              if (_generatedInvite == null) ...[
                // Role Option Cards
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _roles.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final role = _roles[i];
                    final isSelected = _selectedRole == role['id'];
                    final color = role['color'] as Color;

                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() => _selectedRole = role['id'] as String);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: context.isDarkMode ? 0.15 : 0.08)
                              : context.chipBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? color : context.borderColor,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(role['icon'] as IconData, color: color, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr(role['title'] as String),
                                    style: TextStyle(
                                      color: context.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    context.tr(role['desc'] as String),
                                    style: TextStyle(
                                      color: context.textSecondary,
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsetsDirectional.only(start: 8, top: 2),
                              child: Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: isSelected ? color : context.textSecondary,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemes.success,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isGenerating ? null : _generateInvite,
                      child: _isGenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : Text(
                              context.tr('rid_generate_code'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                    ),
                  ],
                ),
              ] else ...[
                // Generated Code Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppThemes.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppThemes.success.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        context.trArgs('rid_generated_for', {'role': context.tr(_generatedInvite!.role == 'spouse' ? 'wife_spouse_title' : (_generatedInvite!.role == 'peer' ? 'invite_role_peer' : 'invite_role_family'))}),
                        style: TextStyle(
                          color: context.successText,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        _generatedInvite!.inviteCode,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr('rid_valid_7_days'),
                        style: TextStyle(color: context.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Copy Code and Done Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(context.tr('copy_code'), style: const TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _generatedInvite!.inviteCode),
                          );
                          if (context.mounted) {
                            AppSnackBar.showSuccess(
                              context,
                              context.trArgs('rid_copied_code', {'code': _generatedInvite!.inviteCode}),
                              title: context.tr('set_code_copied'),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemes.success,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(context.tr('done'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
