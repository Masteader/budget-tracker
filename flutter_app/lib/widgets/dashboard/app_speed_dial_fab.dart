import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_themes.dart';
import '../../screens/chat/chat_entry_screen.dart';
import '../../screens/scanner/receipt_scanner_sheet.dart';
import '../transactions/manual_expense_sheet.dart';
import '../../l10n/app_localizations.dart';

/// Speed-dial FAB with the three ways to add an expense: manual entry,
/// voice / AI chat and the receipt scanner. Everything else is on the
/// Tools screen.
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
      ReceiptScannerSheet.show(context, hid);
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

  void _onManualEntry() {
    _close();
    HapticFeedback.selectionClick();
    ManualExpenseSheet.show(context, householdId: widget.householdId);
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
                        color: context.isDark ? AppThemes.deepGlacial : Colors.white,
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
                                : context.primaryButtonBg.withValues(alpha: 0.10),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        label,
                        style: GoogleFonts.outfit(
                          color: context.textPrimary,
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
                  foregroundColor: Colors.white,
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
      alignment: AlignmentDirectional.bottomEnd,
      clipBehavior: Clip.none,
      children: [
        if (_isOpen)
          GestureDetector(
            onTap: _close,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              width: 300,
              height: 240,
            ),
          ),
        // Three primary actions (R3/R7): manual entry first, then chat, then
        // the receipt scanner. Batch scan, income, transfers and the
        // affordability simulator live on the Tools screen.
        _buildOption(
          icon: Icons.camera_alt_rounded,
          label: context.tr('scan_receipt'),
          color: context.primaryButtonBg,
          onTap: _onScanReceipt,
          offset: 150,
        ),
        _buildOption(
          icon: Icons.mic_rounded,
          label: context.tr('voice_chat'),
          color: context.accentText,
          onTap: _onVoiceEntry,
          offset: 100,
        ),
        _buildOption(
          icon: Icons.edit_note_rounded,
          label: context.tr('manual_log'),
          color: context.primaryButtonBg,
          onTap: _onManualEntry,
          offset: 50,
        ),
        FloatingActionButton.extended(
          heroTag: 'main_speed_dial_fab',
          backgroundColor: context.primaryButtonBg,
          foregroundColor: Colors.white,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: context.accentSubtleBorder, width: 1.5),
          ),
          onPressed: _toggle,
          icon: AnimatedRotation(
            turns: _isOpen ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Icon(_isOpen ? Icons.close_rounded : Icons.add_rounded, size: 24, color: context.primaryButtonFg),
          ),
          label: Text(
            _isOpen ? context.tr('close') : context.tr('add_expense'),
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
