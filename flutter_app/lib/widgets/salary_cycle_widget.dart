import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';

class SalaryCycleWidget extends StatefulWidget {
  final String householdId;

  const SalaryCycleWidget({super.key, required this.householdId});

  @override
  State<SalaryCycleWidget> createState() => _SalaryCycleWidgetState();
}

class _SalaryCycleWidgetState extends State<SalaryCycleWidget> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadForecast();
  }

  Future<void> _loadForecast() async {
    final res = await ApiService.instance.getSalaryCycleForecast(widget.householdId);
    if (mounted) {
      setState(() {
        _data = res;
        _isLoading = false;
      });
    }
  }

  Color _getPaceColor(String? status) {
    switch (status) {
      case 'on_track':
        return const Color(0xFF00C896);
      case 'caution':
        return Colors.orange;
      case 'critical':
      case 'exhausted':
        return Colors.redAccent;
      default:
        return const Color(0xFF58A6FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C896)),
          ),
        ),
      );
    }

    if (_data == null || _data!['cycle'] == null) {
      return const SizedBox.shrink();
    }

    final cycle = _data!['cycle'] as Map<String, dynamic>;
    final daysRemaining = cycle['days_remaining'] as int? ?? 0;
    final daysElapsed = cycle['days_elapsed'] as int? ?? 1;
    final daysTotal = cycle['days_total'] as int? ?? 30;
    final progress = (daysElapsed / daysTotal).clamp(0.0, 1.0);

    final actualBurn = (_data!['actual_burn_rate'] as num?)?.toDouble() ?? 0.0;
    final dailyAllowance = (_data!['daily_remaining_allowance'] as num?)?.toDouble() ?? 0.0;
    final paceStatus = _data!['pace_status'] as String? ?? 'on_track';
    final paceLabel = _data!['pace_label_en'] as String? ?? 'On Track';
    final paceColor = _getPaceColor(paceStatus);
    final fmt = NumberFormat('#,##0.0', 'en_US');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF30363D)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF161B22),
            paceColor.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: paceColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.calendar_month_rounded, color: paceColor, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Salary Cycle (27th)',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: paceColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: paceColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  paceLabel,
                  style: TextStyle(
                    color: paceColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Circular progress ring
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 6,
                      backgroundColor: const Color(0xFF30363D),
                      valueColor: AlwaysStoppedAnimation(paceColor),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$daysRemaining',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'days',
                        style: TextStyle(color: Color(0xFF8B949E), fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$daysRemaining Days to Payday (27th)',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Burn Rate: SAR ${fmt.format(actualBurn)}/day',
                      style: const TextStyle(
                        color: Color(0xFFC9D1D9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Allowable Daily: SAR ${fmt.format(dailyAllowance)}/day remaining',
                      style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
