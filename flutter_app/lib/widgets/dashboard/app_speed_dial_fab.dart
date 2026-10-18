import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_themes.dart';
import '../../screens/chat/chat_entry_screen.dart';
import '../../screens/scanner/receipt_scanner_sheet.dart';
import '../../screens/scanner/batch_receipt_scanner_screen.dart';
import '../simulator/affordability_simulator_sheet.dart';
import '../transactions/manual_expense_sheet.dart';
import '../accounts/record_income_sheet.dart';
import '../accounts/account_transfer_sheet.dart';
import '../../l10n/app_localizations.dart';

/// Animated multi-action Speed Dial FAB for quick transaction input and pre-purchase check.
/// Provides direct 1-tap shortcuts to:
/// 1. 📸 Scan Receipt / Invoice (Camera & Gallery)
/// 2. 🎙️ Voice & AI Chat (Conversational expense logging)
/// 3. 💡 Can I Afford This? (Pre-Purchase Affordability Simulator)
/// 4. ✏️ Manual Log (Direct expense logging)
class AppSpeedDialFab extends StatefulWidget {
  final String? householdId;

  const AppSpeedDialFab({super.key, this.householdId});

  @override
  State<AppSpeedDialFab> createState() => _AppSpeedDialFabState();
}

class _AppSpeedDialFabState extends State<AppSpeedDialFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _expandAnimation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      value: 0.0,
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.easeOutQuad,
      parent: _controller,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.lightImpact();
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _close() {
    if (_isOpen) {
      setState(() {
        _isOpen = false;
        _controller.reverse();
      });
    }
  }

  void _onScanReceipt() {
    _close();
    HapticFeedback.selectionClick();
    final hid = widget.householdId;
    if (hid != null && mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ReceiptScannerSheet(householdId: hid),
      );
    }
  }

  void _onBatchScanReceipts() {
    _close();
    HapticFeedback.selectionClick();
    final hid = widget.householdId;
    if (hid != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BatchReceiptScannerScreen(householdId: hid),
        ),
      );
    }
  }

  void _onVoiceEntry() {
    _close();
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatEntryScreen()),
    );
  }

  void _onAffordabilitySimulator() {
    _close();
    HapticFeedback.selectionClick();
    AffordabilitySimulatorSheet.show(context, householdId: widget.householdId);
  }

  void _onManualEntry() {
    _close();
    HapticFeedback.selectionClick();
    ManualExpenseSheet.show(context, householdId: widget.householdId);
  }

  void _onRecordIncome() {
    _close();
    HapticFeedback.selectionClick();
    final hid = widget.householdId;
    if (hid != null && mounted) {
      RecordIncomeSheet.show(context, householdId: hid);
    }
  }

  void _onTransferFunds() {
    _close();
    HapticFeedback.selectionClick();
    final hid = widget.householdId;
    if (hid != null && mounted) {
      AccountTransferSheet.show(context, householdId: hid);
    }
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required double offset,
  }) {
    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        final progress = _expandAnimation.value;
        return Transform.translate(
          offset: Offset(0, -offset * progress),
          child: Opacity(
            opacity: progress.clamp(0.0, 1.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: progress > 0.5 ? onTap : null,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.isDark ? const Color(0xFF071C33) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: context.isDark
                              ? color.withValues(alpha: 0.5)
                              : color.withValues(alpha: 0.7),
                          width: context.isDark ? 1 : 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: context.isDark
                                ? Colors.black.withValues(alpha: 0.4)
                                : const Color(0xFF0F172A).withValues(alpha: 0.10),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        label,
                        style: GoogleFonts.outfit(
                          color: context.isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FloatingActionButton.small(
                  heroTag: null,
                  backgroundColor: color,
                  foregroundColor: Colors.black,
                  elevation: 4,
                  onPressed: progress > 0.5 ? onTap : null,
                  child: Icon(icon, size: 20),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      clipBehavior: Clip.none,
      children: [
        if (_isOpen)
          GestureDetector(
            onTap: _close,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              width: 300,
              height: 480,
            ),
          ),
        _buildOption(
          icon: Icons.dynamic_feed_rounded,
          label: context.tr('batch_scan_receipts'),
          color: const Color(0xFF80E5FF),
          onTap: _onBatchScanReceipts,
          offset: 340,
        ),
        _buildOption(
          icon: Icons.camera_alt_rounded,
          label: context.tr('scan_receipt'),
          color: const Color(0xFF4DE6F7),
          onTap: _onScanReceipt,
          offset: 290,
        ),
        _buildOption(
          icon: Icons.mic_rounded,
          label: context.tr('voice_chat'),
          color: const Color(0xFF00E5BF),
          onTap: _onVoiceEntry,
          offset: 240,
        ),
        _buildOption(
          icon: Icons.savings_rounded,
          label: context.tr('record_income'),
          color: context.electricTeal,
          onTap: _onRecordIncome,
          offset: 190,
        ),
        _buildOption(
          icon: Icons.swap_horiz_rounded,
          label: context.tr('transfer_funds'),
          color: context.iceCyan,
          onTap: _onTransferFunds,
          offset: 140,
        ),
        _buildOption(
          icon: Icons.calculate_outlined,
          label: context.tr('affordability_simulator'),
          color: const Color(0xFFD4AF37),
          onTap: _onAffordabilitySimulator,
          offset: 95,
        ),
        _buildOption(
          icon: Icons.edit_note_rounded,
          label: context.tr('manual_log'),
          color: const Color(0xFFFFA657),
          onTap: _onManualEntry,
          offset: 50,
        ),
        FloatingActionButton.extended(
          heroTag: 'main_speed_dial_fab',
          backgroundColor: const Color(0xFF00E5BF),
          foregroundColor: const Color(0xFF051424),
          elevation: 6,
          onPressed: _toggle,
          icon: AnimatedRotation(
            turns: _isOpen ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Icon(_isOpen ? Icons.close_rounded : Icons.add_rounded, size: 24),
          ),
          label: Text(
            _isOpen ? context.tr('close') : context.tr('add_expense'),
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}
