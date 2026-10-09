import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../screens/chat/chat_entry_screen.dart';
import '../../screens/scanner/receipt_scanner_sheet.dart';
import 'dashboard_action_sheet.dart';

/// Animated multi-action Speed Dial FAB for quick transaction input.
/// Provides direct 1-tap shortcuts to:
/// 1. 📸 Scan Receipt / Invoice (Camera & Gallery)
/// 2. 🎙️ Voice Entry (Conversational natural language)
/// 3. ✏️ Manual Log (SMS / Form entry)
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
    DashboardActionSheet.show(context, householdId: widget.householdId);
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
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withValues(alpha: 0.5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        label,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
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
              width: 250,
              height: 250,
            ),
          ),
        _buildOption(
          icon: Icons.camera_alt_rounded,
          label: 'Scan Receipt',
          color: const Color(0xFF00C896),
          onTap: _onScanReceipt,
          offset: 160,
        ),
        _buildOption(
          icon: Icons.mic_rounded,
          label: 'Voice / Chat',
          color: const Color(0xFF79C0FF),
          onTap: _onVoiceEntry,
          offset: 110,
        ),
        _buildOption(
          icon: Icons.edit_note_rounded,
          label: 'Manual Log',
          color: const Color(0xFFFFA657),
          onTap: _onManualEntry,
          offset: 60,
        ),
        FloatingActionButton.extended(
          heroTag: 'main_speed_dial_fab',
          backgroundColor: const Color(0xFF00C896),
          foregroundColor: Colors.black,
          elevation: 6,
          onPressed: _toggle,
          icon: AnimatedRotation(
            turns: _isOpen ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Icon(_isOpen ? Icons.close_rounded : Icons.add_rounded, size: 24),
          ),
          label: Text(
            _isOpen ? 'Close' : 'Add Expense',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}
