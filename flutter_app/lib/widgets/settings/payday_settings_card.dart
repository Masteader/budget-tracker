import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Payday updated to ${getOrdinal(_selectedDay)} of every month!',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xFF00C896),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
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
                      'Salary & Payday Cycle',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Custom monthly salary arrival date',
                      style: const TextStyle(
                        color: Color(0xFF8B949E),
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
                  '${getOrdinal(_selectedDay)} of month',
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
            'Budget cycles, remaining days counter, daily burn rate allowances, and automatic budget rollover will dynamically sync to this date.',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: const Color(0xFF8B949E),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF21262D), height: 1),
          const SizedBox(height: 14),

          // Presets Label
          Text(
            'COMMON PRESETS',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8B949E),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip(
                label: '27th (Govt / Standard)',
                day: 27,
              ),
              _buildPresetChip(
                label: '1st (Calendar Month)',
                day: 1,
              ),
              _buildPresetChip(
                label: '25th',
                day: 25,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Custom Day Dropdown
          Text(
            'SELECT CUSTOM DAY',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8B949E),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedDay,
                isExpanded: true,
                dropdownColor: const Color(0xFF161B22),
                icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00C896)),
                items: List.generate(31, (index) {
                  final day = index + 1;
                  return DropdownMenuItem<int>(
                    value: day,
                    child: Text(
                      'Day $day (${getOrdinal(day)} of every month)',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
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
                _saving ? 'Saving...' : 'Save Payday',
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
      backgroundColor: const Color(0xFF0D1117),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF00C896) : const Color(0xFFC9D1D9),
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFF00C896) : const Color(0xFF30363D),
      ),
      onSelected: (_) {
        setState(() => _selectedDay = day);
      },
    );
  }
}
