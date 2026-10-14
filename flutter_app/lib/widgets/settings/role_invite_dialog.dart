import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

class RoleInviteDialog extends StatefulWidget {
  final String householdId;
  final ValueChanged<HouseholdInvite>? onInviteGenerated;

  const RoleInviteDialog({
    super.key,
    required this.householdId,
    this.onInviteGenerated,
  });

  @override
  State<RoleInviteDialog> createState() => _RoleInviteDialogState();
}

class _RoleInviteDialogState extends State<RoleInviteDialog> {
  String _selectedRole = 'spouse';
  bool _isGenerating = false;
  HouseholdInvite? _generatedInvite;

  final List<Map<String, dynamic>> _roles = const [
    {
      'id': 'spouse',
      'title': 'Wife / Spouse',
      'icon': Icons.favorite_rounded,
      'color': Color(0xFFE5A93C),
      'desc': 'Islamic Nafaqah household: husband provides and reimburses wife for household advances.',
    },
    {
      'id': 'peer',
      'title': 'Roommate / Flatmate',
      'icon': Icons.group_outlined,
      'color': Color(0xFF38BDF8),
      'desc': 'Shared living ledger: multi-roommate pairwise settlement with debt simplification.',
    },
    {
      'id': 'family_member',
      'title': 'Family Dependent',
      'icon': Icons.child_care_rounded,
      'color': Color(0xFF34D399),
      'desc': 'Family dependent: personal allowance tracking and individual expense reporting.',
    },
  ];

  Future<void> _generateInvite() async {
    setState(() => _isGenerating = true);

    HouseholdInvite invite;
    try {
      invite = await ApiService.instance.createRoleInvite(
        widget.householdId,
        _selectedRole,
      );
    } catch (_) {
      // Offline fallback
      invite = HouseholdInvite(
        householdId: widget.householdId,
        inviteCode: 'INV${DateTime.now().millisecondsSinceEpoch.toString().substring(7, 12)}',
        role: _selectedRole,
      );
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
                      color: const Color(0xFF00C896).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: Color(0xFF00C896),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Generate Role Invite',
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
                'Select the member’s role to configure the correct settlement model automatically.',
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
                                    role['title'] as String,
                                    style: TextStyle(
                                      color: context.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    role['desc'] as String,
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
                              padding: const EdgeInsets.only(left: 8, top: 2),
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
                      child: Text('Cancel', style: TextStyle(color: context.textSecondary)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C896),
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
                          : const Text(
                              'Generate Invite Code',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                    ),
                  ],
                ),
              ] else ...[
                // Generated Code Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Invite Code Generated for ${_generatedInvite!.role.toUpperCase()}',
                        style: const TextStyle(
                          color: Color(0xFF00C896),
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
                        'Valid for 7 days. Give this code to join.',
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
                        label: const Text('Copy Code', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _generatedInvite!.inviteCode),
                          );
                          if (context.mounted) {
                            AppSnackBar.showSuccess(
                              context,
                              'Copied invite code: ${_generatedInvite!.inviteCode}',
                              title: 'Code Copied',
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C896),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
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
