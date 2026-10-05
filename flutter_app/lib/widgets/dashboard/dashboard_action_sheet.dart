import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../screens/chat/chat_entry_screen.dart';
import '../../screens/scanner/receipt_scanner_sheet.dart';

/// Bottom action sheet modal providing shortcuts for adding transactions via
/// AI Conversational Chat / Simulator or ZATCA / Multi-Page Receipt Scanner.
class DashboardActionSheet extends StatelessWidget {
  final String? householdId;

  const DashboardActionSheet({super.key, this.householdId});

  static Future<void> show(BuildContext context, {String? householdId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
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
                color: const Color(0xFF30363D),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Add Transaction',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Color(0xFF00C896), size: 22),
                ),
                title: const Text(
                  'AI Conversational Chat & Simulator',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                ),
                subtitle: const Text(
                  'Say what you spent or ask "Can I afford this?"',
                  style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF8B949E)),
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
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F6FEB).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.document_scanner_outlined,
                    color: Color(0xFF58A6FF),
                    size: 22,
                  ),
                ),
                title: const Text(
                  'Scan VAT Invoice / Receipt (ZATCA & Multi-Page)',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                ),
                subtitle: const Text(
                  'ZATCA QR camera, manual code input, or multi-page photos',
                  style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF8B949E)),
                onTap: () {
                  Navigator.pop(context);
                  if (householdId != null && householdId!.isNotEmpty) {
                    ReceiptScannerSheet.show(context, householdId!);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
