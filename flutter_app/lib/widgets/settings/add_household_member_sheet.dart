import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';

typedef AddMemberCallback = Future<void> Function({
  required String name,
  required String relationship,
  required double monthlyAllowance,
  String? avatarIcon,
});

class AddHouseholdMemberResult {
  final String name;
  final String relationship;
  final double monthlyAllowance;
  final String avatarIcon;

  const AddHouseholdMemberResult({
    required this.name,
    required this.relationship,
    required this.monthlyAllowance,
    required this.avatarIcon,
  });
}

class AddHouseholdMemberSheet extends StatefulWidget {
  final AddMemberCallback? onMemberAdded;

  const AddHouseholdMemberSheet({
    super.key,
    this.onMemberAdded,
  });

  static Future<AddHouseholdMemberResult?> show(BuildContext context) {
    return showModalBottomSheet<AddHouseholdMemberResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const AddHouseholdMemberSheet(),
      ),
    );
  }

  @override
  State<AddHouseholdMemberSheet> createState() => _AddHouseholdMemberSheetState();
}

class _AddHouseholdMemberSheetState extends State<AddHouseholdMemberSheet> {
  final _nameController = TextEditingController();
  final _allowanceController = TextEditingController();
  String _selectedRole = 'spouse';
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<Map<String, dynamic>> _roleOptions = const [
    {
      'id': 'spouse',
      'title': 'wife_spouse_title',
      'icon': Icons.favorite_rounded,
      'color': Color(0xFFE5A93C),
      'avatar': 'wife',
      'desc': 'ahm_spouse_desc',
    },
    {
      'id': 'roommate',
      'title': 'roommate_partner_title',
      'icon': Icons.group_outlined,
      'color': Color(0xFF38BDF8),
      'avatar': 'roommate',
      'desc': 'ahm_peer_desc',
    },
    {
      'id': 'child',
      'title': 'child_dependent_title',
      'icon': Icons.child_care_rounded,
      'color': Color(0xFF34D399),
      'avatar': 'child',
      'desc': 'ahm_child_desc',
    },
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _allowanceController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = context.tr('ahm_enter_name'));
      return;
    }

    final allowance = double.tryParse(_allowanceController.text.trim()) ?? 0.0;
    final selectedOption = _roleOptions.firstWhere((r) => r['id'] == _selectedRole);
    final avatar = selectedOption['avatar'] as String;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      if (widget.onMemberAdded != null) {
        await widget.onMemberAdded!(
          name: name,
          relationship: _selectedRole,
          monthlyAllowance: allowance,
          avatarIcon: avatar,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(
          AddHouseholdMemberResult(
            name: name,
            relationship: _selectedRole,
            monthlyAllowance: allowance,
            avatarIcon: avatar,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.borderColor),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
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

            // Title Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: Color(0xFF00C896),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('ahm_title'),
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr('ahm_subtitle'),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: context.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Member Name Input
            Text(
              context.tr('ahm_member_name_caps'),
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const Key('add_member_name_input'),
              controller: _nameController,
              autofocus: true,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                hintText: context.tr('ahm_name_hint'),
                hintStyle: TextStyle(color: context.textSecondary.withValues(alpha: 0.6)),
                filled: true,
                fillColor: context.inputBg,
                prefixIcon: const Icon(Icons.person_rounded, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF00C896)),
                ),
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
            ),

            const SizedBox(height: 16),

            // Living Role Selection
            Text(
              context.tr('ahm_living_role_caps'),
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),

            ..._roleOptions.map((opt) {
              final isSelected = _selectedRole == opt['id'];
              final color = opt['color'] as Color;

              return InkWell(
                key: Key('role_chip_${opt['id']}'),
                onTap: () => setState(() => _selectedRole = opt['id'] as String),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withValues(alpha: 0.1) : context.scaffoldBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? color : context.borderColor,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(opt['icon'] as IconData, color: color, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr(opt['title'] as String),
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.tr(opt['desc'] as String),
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? color : context.borderColor,
                            width: isSelected ? 6 : 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 12),

            // Monthly Allowance (Masroof) Input
            Text(
              context.tr('ahm_allowance_caps'),
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const Key('add_member_allowance_input'),
              controller: _allowanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                hintText: '0.00 ${context.tr('sar')}',
                hintStyle: TextStyle(color: context.textSecondary.withValues(alpha: 0.6)),
                filled: true,
                fillColor: context.inputBg,
                prefixIcon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
                suffixText: context.tr('sar'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF00C896)),
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF85149).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF85149).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFF85149), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xFFF85149), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                key: const Key('add_member_submit_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C896),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  _isSubmitting ? context.tr('ahm_creating') : context.tr('create_member_profile'),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _isSubmitting ? null : _handleSubmit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
