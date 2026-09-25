import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../main.dart';
import '../../services/api_service.dart';
import '../../widgets/transaction_item_breakdown_card.dart';

class ReceiptScannerSheet extends StatefulWidget {
  final String householdId;

  const ReceiptScannerSheet({
    super.key,
    required this.householdId,
  });

  static Future<void> show(BuildContext context, String householdId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ReceiptScannerSheet(householdId: householdId),
    );
  }

  @override
  State<ReceiptScannerSheet> createState() => _ReceiptScannerSheetState();
}

class _ReceiptScannerSheetState extends State<ReceiptScannerSheet> {
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _scanResult;
  String? _errorMessage;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;

      setState(() {
        _imageFile = File(picked.path);
        _isAnalyzing = true;
        _errorMessage = null;
        _scanResult = null;
      });

      final bytes = await _imageFile!.readAsBytes();
      final base64Img = base64Encode(bytes);

      final user = supabase.auth.currentUser;
      final res = await ApiService.instance.scanReceipt(
        imageBase64: base64Img,
        householdId: widget.householdId,
        userId: user?.id,
      );

      setState(() {
        _isAnalyzing = false;
        if (res['status'] == 'error') {
          _errorMessage = res['message'] ?? 'Failed to analyze receipt.';
        } else {
          _scanResult = res;
        }
      });
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = 'Error capturing receipt: $e';
      });
    }
  }

  Future<void> _confirmSave({bool allowDuplicate = false, String? enrichTxId}) async {
    if (_imageFile == null) return;
    setState(() => _isAnalyzing = true);

    try {
      final bytes = await _imageFile!.readAsBytes();
      final base64Img = base64Encode(bytes);
      final user = supabase.auth.currentUser;

      final res = await ApiService.instance.scanReceipt(
        imageBase64: base64Img,
        householdId: widget.householdId,
        userId: user?.id,
        allowDuplicate: allowDuplicate,
        enrichTxId: enrichTxId,
      );

      setState(() => _isAnalyzing = false);

      if (mounted) {
        if (res['status'] == 'success' || res['status'] == 'enriched') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message'] ?? 'Receipt saved successfully!'),
              backgroundColor: const Color(0xFF00C896),
            ),
          );
          Navigator.pop(context);
        } else {
          setState(() {
            _scanResult = res;
          });
        }
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = 'Failed to save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF30363D),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.document_scanner_outlined, color: Color(0xFF00C896), size: 24),
                const SizedBox(width: 10),
                Text(
                  'Scan Receipt / Tax Invoice',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Snap a picture of a paper or thermal receipt to extract line items and track spending.',
              style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF8B949E)),
            ),
            const SizedBox(height: 20),

            if (_imageFile == null && !_isAnalyzing) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C896),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => _pickImage(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF30363D)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                      onPressed: () => _pickImage(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            if (_isAnalyzing) ...[
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF00C896)),
                    const SizedBox(height: 16),
                    Text(
                      'AI Scanning Receipt...',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Extracting merchant, VAT, and line items',
                      style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF8B949E)),
                    ),
                  ],
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => setState(() => _imageFile = null),
                child: const Text('Try Again'),
              ),
              const SizedBox(height: 16),
            ],

            if (_scanResult != null && !_isAnalyzing) ...[
              _buildResultContent(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultContent() {
    final status = _scanResult!['status'] as String? ?? '';
    final isCandidate = status == 'duplicate_candidate';

    final merchant = _scanResult!['merchant'] ??
        _scanResult!['parsed_data']?['merchant'] ??
        'Merchant';
    final amount = ((_scanResult!['amount'] ??
            _scanResult!['parsed_data']?['amount'] ??
            0.0) as num)
        .toDouble();
    final categoryCode = _scanResult!['category_code'] ??
        _scanResult!['parsed_data']?['category_code'];
    final items = (_scanResult!['items'] ??
            _scanResult!['parsed_data']?['items'] as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCandidate) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Matching Transaction Found',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _scanResult!['message'] ??
                      'An identical amount was recorded recently.',
                  style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C896),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {
                          final cId = _scanResult!['candidate_transaction_id'];
                          _confirmSave(enrichTxId: cId);
                        },
                        child: const Text('Attach Items to SMS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: () => _confirmSave(allowDuplicate: true),
                        child: const Text('Log as Separate', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        TransactionItemBreakdownCard(
          merchant: merchant,
          amount: amount,
          categoryCode: categoryCode,
          source: 'receipt_scan',
          items: items,
        ),
        const SizedBox(height: 16),

        if (!isCandidate && status != 'success') ...[
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _confirmSave(allowDuplicate: true),
            child: const Text('Confirm & Save Transaction', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
        ],

        TextButton(
          onPressed: () => setState(() => _imageFile = null),
          child: const Text('Scan Another Receipt', style: TextStyle(color: Color(0xFF8B949E))),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
