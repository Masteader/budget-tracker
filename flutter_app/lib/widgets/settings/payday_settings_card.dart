import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_snackbar.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';

/// Card for customizing the household/user monthly payday (1-31).
class PaydaySettingsCard extends StatefulWidget {
  final int initialPayday;
  final Future<bool> Function(int newDay) onSavePayday;

  const PaydaySettingsCard({
    super.key,
    this.initialPayday = 27,
    required this.onSavePayday,
  });

  @override
  State<PaydaySettingsCard> createState() => _PaydaySettingsCardState();
}

class _PaydaySettingsCardState extends State<PaydaySettingsCard> {
  late int _selectedDay;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialPayday;
  }

  @override
  void didUpdateWidget(covariant PaydaySettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPayday != widget.initialPayday) {
      setState(() => _selectedDay = widget.initialPayday);
    }
  }

  /// English ordinal ("27th"); Arabic/Urdu use the plain number.
  static String _ordinal(BuildContext context, int day) =>
      Localizations.localeOf(context).languageCode == 'en' ? getOrdinal(day) : '$day';

  static String getOrdinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }

  Future<void> _handleSave() async {
    setState(() => _saving = true);
    final success = await widget.onSavePayday(_selectedDay);
    if (mounted) {
      setState(() => _saving = false);
      if (success) {
        AppSnackBar.showSuccess(
          context,
          context.trArgs('pds_updated_msg', {'day': _ordinal(context, _selectedDay)}),
          title: context.tr('pds_saved_title'),
          icon: Icons.calendar_month_rounded,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          // Header: Icon + Title + Current Selection Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
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
                      context.tr('pds_title'),
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('pds_subtitle'),
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00C896),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  context.trArgs('pds_of_month', {'day': _ordinal(context, _selectedDay)}),
                  style: const TextStyle(
                    color: Color(0xFF00C896),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Text(
            context.tr('pds_desc'),
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: context.borderColor, height: 1),
          const SizedBox(height: 14),

          // Presets Label
          Text(
            context.tr('pds_presets_caps'),
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip(
                label: context.trArgs('pds_preset_govt', {'day': _ordinal(context, 27)}),
                day: 27,
              ),
              _buildPresetChip(
                label: context.trArgs('pds_preset_calendar', {'day': _ordinal(context, 1)}),
                day: 1,
              ),
              _buildPresetChip(
                label: _ordinal(context, 25),
                day: 25,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Custom Day Dropdown
          Text(
            context.tr('pds_custom_caps'),
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: context.inputBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedDay,
                isExpanded: true,
                dropdownColor: context.cardBg,
                icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00C896)),
                items: List.generate(31, (index) {
                  final day = index + 1;
                  return DropdownMenuItem<int>(
                    value: day,
                    child: Text(
                      context.trArgs('pds_day_option', {'n': day, 'day': _ordinal(context, day)}),
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontSize: 14,
                        fontWeight: day == _selectedDay
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  );
                }),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedDay = val);
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(
                _saving ? context.tr('pds_saving') : context.tr('pds_save'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              onPressed: _saving ? null : _handleSave,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip({
    required String label,
    required int day,
  }) {
    final isSelected = _selectedDay == day;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF00C896).withValues(alpha: 0.25),
      backgroundColor: context.scaffoldBg,
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF00C896) : context.textPrimary,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFF00C896) : context.borderColor,
      ),
      onSelected: (_) {
        setState(() => _selectedDay = day);
      },
    );
  }
}
