import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/chat/chat_entry_screen.dart';
import '../../screens/scanner/receipt_scanner_sheet.dart';
import '../../theme/app_themes.dart';
import '../simulator/affordability_simulator_sheet.dart';
import '../transactions/manual_expense_sheet.dart';

/// Bottom action sheet modal providing non-duplicate shortcuts for:
/// 1. Scan VAT Invoice / Receipt
/// 2. AI Voice & Conversational Expense Assistant
/// 3. Pre-Purchase Affordability Simulator ("Can I Afford This?")
/// 4. Manual Expense Log
class DashboardActionSheet extends StatelessWidget {
  final String? householdId;

  const DashboardActionSheet({super.key, this.householdId});

  static Future<void> show(BuildContext context, {String? householdId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DashboardActionSheet(householdId: householdId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('fast_actions'),
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // 1. Scan Receipt
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.pillBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.document_scanner_outlined,
                    color: context.accentText,
                    size: 22,
                  ),
                ),
                title: Text(
                  context.tr('scan_receipt'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: context.textPrimary),
                ),
                subtitle: Text(
                  context.tr('action_scan_desc'),
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right, color: context.textSecondary),
                onTap: () {
                  Navigator.pop(context);
                  if (householdId != null && householdId!.isNotEmpty) {
                    ReceiptScannerSheet.show(context, householdId!);
                  }
                },
              ),
            ),
            const SizedBox(height: 6),

            // 2. AI Assistant / Voice Chat
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.infoSubtleBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.mic_rounded, color: context.infoColor, size: 22),
                ),
                title: Text(
                  context.tr('voice_chat'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: context.textPrimary),
                ),
                subtitle: Text(
                  context.tr('action_voice_desc'),
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right, color: context.textSecondary),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChatEntryScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),

            // 3. Pre-Purchase Simulator
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.accentSubtleBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.calculate_outlined, color: context.accentText, size: 22),
                ),
                title: Text(
                  context.tr('affordability_simulator'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: context.textPrimary),
                ),
                subtitle: Text(
                  context.tr('affordability_simulator_desc'),
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right, color: context.textSecondary),
                onTap: () {
                  Navigator.pop(context);
                  AffordabilitySimulatorSheet.show(context, householdId: householdId);
                },
              ),
            ),
            const SizedBox(height: 6),

            // 4. Manual Log
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.alertWarningBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.edit_note_rounded, color: context.warnText, size: 22),
                ),
                title: Text(
                  context.tr('manual_log'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: context.textPrimary),
                ),
                subtitle: Text(
                  context.tr('manual_log_desc'),
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right, color: context.textSecondary),
                onTap: () {
                  Navigator.pop(context);
                  ManualExpenseSheet.show(context, householdId: householdId);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
