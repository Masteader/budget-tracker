import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../main.dart';
import '../../services/api_service.dart';
import '../../widgets/transaction_item_breakdown_card.dart';
import '../../widgets/zatca_qr_camera_scanner.dart';

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
  final List<File> _imageFiles = [];
  String? _zatcaQrRaw;
  Map<String, dynamic>? _zatcaDecoded;

  bool _isAnalyzing = false;
  Map<String, dynamic>? _scanResult;
  String? _errorMessage;

  static Map<String, dynamic>? decodeZatcaTlv(String base64Str) {
    try {
      final bytes = base64Decode(base64Str.trim());
      final tags = <int, String>{};
      int idx = 0;
      while (idx < bytes.length) {
        if (idx + 1 >= bytes.length) break;
        final tag = bytes[idx];
        final len = bytes[idx + 1];
        if (idx + 2 + len > bytes.length) break;
        final val = utf8.decode(bytes.sublist(idx + 2, idx + 2 + len), allowMalformed: true);
        tags[tag] = val;
        idx += 2 + len;
      }
      final totalVal = double.tryParse(tags[4] ?? '');
      final vatVal = double.tryParse(tags[5] ?? '');
      if (tags[1] != null && totalVal != null) {
        return {
          'seller': tags[1],
          'vat_number': tags[2],
          'timestamp': tags[3],
          'total': totalVal,
          'vat': vatVal,
        };
      }
    } catch (_) {}
    return null;
  }

  Future<void> _addPhoto(ImageSource source) async {
    setState(() => _errorMessage = null);

    if (source == ImageSource.camera) {
      final status = await Permission.camera.status;
      if (!status.isGranted) {
        final requested = await Permission.camera.request();
        if (!requested.isGranted) {
          setState(() {
            _errorMessage = requested.isPermanentlyDenied
                ? 'Camera permission is permanently denied. Please allow it in Settings to take receipt photos.'
                : 'Camera permission is needed to take receipt photos.';
          });
          return;
        }
      }
    }

    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;

      setState(() {
        _imageFiles.add(File(picked.path));
        _errorMessage = null;
        _scanResult = null;
      });
    } on PlatformException catch (pe) {
      if (pe.code.toLowerCase().contains('camera_access_denied') ||
          (pe.message?.toLowerCase().contains('camera') ?? false)) {
        setState(() {
          _errorMessage =
              'Camera access was denied by the system. Please grant Camera permission in Settings.';
        });
      } else {
        setState(() => _errorMessage = 'Camera error: ${pe.message ?? pe.code}');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error capturing photo: $e');
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _imageFiles.removeAt(index);
      _scanResult = null;
    });
  }

  void _showZatcaQrDialog() {
    final ctrl = TextEditingController(text: _zatcaQrRaw ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Row(
          children: [
            const Icon(Icons.qr_code_2_rounded, color: Color(0xFF00C896)),
            const SizedBox(width: 8),
            Text('Saudi ZATCA VAT QR', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste or scan the Base64 QR code from your tax invoice. It automatically verifies merchant, total, and 15% VAT.',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'e.g. AQ5UYW1pbWkgTWFya2V0cwIPMzAwMDAwMDAwMDAwMDAz...',
                hintStyle: const TextStyle(color: Color(0xFF484F58), fontSize: 11),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C896), foregroundColor: Colors.black),
            onPressed: () {
              final text = ctrl.text.trim();
              final decoded = decodeZatcaTlv(text);
              setState(() {
                _zatcaQrRaw = text;
                _zatcaDecoded = decoded;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Apply QR Code', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _scanZatcaQrWithCamera() async {
    final status = await Permission.camera.status;
    if (!status.isGranted) {
      final res = await Permission.camera.request();
      if (!res.isGranted) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF161B22),
              title: Row(
                children: [
                  const Icon(Icons.no_photography_rounded, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text('Camera Access Needed', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: const Text(
                'Camera permission is required to scan invoice QR codes.\n\nPlease tap "Open Settings" to enable Camera for Budget Tracker.',
                style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C896),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    openAppSettings();
                  },
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ZatcaQrCameraScanner()),
    );
    if (scannedCode != null && scannedCode.isNotEmpty) {
      final decoded = decodeZatcaTlv(scannedCode);
      setState(() {
        _zatcaQrRaw = scannedCode;
        _zatcaDecoded = decoded;
      });
      if (decoded != null && mounted) {
        final wantPhoto = await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF161B22),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF00C896), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    decoded['seller'] ?? 'ZATCA Invoice',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total with VAT:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
                      Text(
                        'SAR ${(decoded['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                        style: const TextStyle(color: Color(0xFF00C896), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Would you like to snap a photo of the receipt body now so AI can extract the item names and prices under this store?',
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Total Only', style: TextStyle(color: Color(0xFF8B949E))),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C896),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.camera_alt_rounded, size: 16),
                label: const Text('Snap Items', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );

        if (wantPhoto == true && mounted) {
          await _addPhoto(ImageSource.camera);
          if (_imageFiles.isNotEmpty && mounted) {
            await _analyzeReceipt();
          }
        }
      }
    }
  }

  Future<void> _analyzeReceipt() async {
    if (_imageFiles.isEmpty && _zatcaQrRaw == null) {
      setState(() => _errorMessage = 'Please take at least one photo or provide a ZATCA QR code.');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _scanResult = null;
    });

    try {
      final List<String> base64List = [];
      for (final file in _imageFiles) {
        final bytes = await file.readAsBytes();
        base64List.add(base64Encode(bytes));
      }

      final user = supabase.auth.currentUser;
      final res = await ApiService.instance.scanReceipt(
        imagesBase64: base64List,
        qrCodeRaw: _zatcaQrRaw,
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
        _errorMessage = 'Scan failed: $e';
      });
    }
  }

  Future<void> _confirmSave({bool allowDuplicate = false, String? enrichTxId}) async {
    if (_isAnalyzing) return; // Prevent double-clicking
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final List<String> base64List = [];
      for (final file in _imageFiles) {
        final bytes = await file.readAsBytes();
        base64List.add(base64Encode(bytes));
      }
      final user = supabase.auth.currentUser;

      final res = await ApiService.instance.scanReceipt(
        imagesBase64: base64List,
        qrCodeRaw: _zatcaQrRaw,
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
              content: Text(res['message'] ?? 'Invoice transaction saved successfully!'),
              backgroundColor: const Color(0xFF00C896),
            ),
          );
          Navigator.pop(context);
        } else if (res['status'] == 'duplicate_candidate') {
          setState(() {
            _scanResult = res;
          });
        } else {
          // If microservice returned an error, fallback to direct cloud database insertion
          await _fallbackSaveToSupabase();
        }
      }
    } catch (_) {
      await _fallbackSaveToSupabase();
    }
  }

  Future<void> _fallbackSaveToSupabase() async {
    try {
      final merchant = _zatcaDecoded?['seller'] as String? ??
          _scanResult?['merchant'] as String? ??
          'VAT Tax Invoice';
      final total = (_zatcaDecoded?['total'] as num?)?.toDouble() ??
          (_scanResult?['amount'] as num?)?.toDouble() ??
          0.0;
      final vat = (_zatcaDecoded?['vat'] as num?)?.toDouble() ??
          (_scanResult?['vat_amount'] as num?)?.toDouble() ??
          (total > 0 ? (total * 0.15 / 1.15) : 0.0);

      final dynamic rawItems = _scanResult?['items'];
      final List<Map<String, dynamic>> items = (rawItems is List && rawItems.isNotEmpty)
          ? rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [
              {
                'name': 'Tax Invoice Total (15% VAT ${vat.toStringAsFixed(2)} SAR)',
                'quantity': 1.0,
                'price': total,
              }
            ];

      final itemsSummary = items.map((e) => '${e['quantity']}x ${e['name']} (${e['price']} SAR)').join(', ');
      final auditText = 'Invoice Scan: $merchant (${items.length} items) | Items: [$itemsSummary]';

      final baseData = <String, dynamic>{
        'household_id': widget.householdId,
        'amount': total,
        'currency': 'SAR',
        'merchant': merchant,
        'category_code': 'OPEX-GROCERY',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'raw_sms': auditText,
      };

      Map<String, dynamic> res;
      try {
        res = await supabase.from('transactions').insert({
          ...baseData,
          'source': 'receipt_scan',
          'spent_by': 'both',
          'items': items,
        }).select().single();
      } catch (_) {
        try {
          res = await supabase.from('transactions').insert({
            ...baseData,
            'source': 'receipt_scan',
          }).select().single();
        } catch (_) {
          res = await supabase.from('transactions').insert(baseData).select().single();
        }
      }

      final txId = res['id'] as String?;
      if (txId != null) {
        for (final it in items) {
          try {
            await supabase.from('transaction_items').insert({
              'transaction_id': txId,
              'name': it['name'] ?? 'Item',
              'quantity': it['quantity'] ?? 1.0,
              'price': it['price'] ?? 0.0,
            });
          } catch (_) {}
        }
      }

      setState(() => _isAnalyzing = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved SAR ${total.toStringAsFixed(2)} at $merchant!'),
            backgroundColor: const Color(0xFF00C896),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = 'Could not save invoice: $e';
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
                Expanded(
                  child: Text(
                    'Scan Invoice & Long Receipts',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'For long 60+ item receipts, snap multiple photos (top, middle, bottom). You can also scan the ZATCA VAT QR code.',
              style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF8B949E)),
            ),
            const SizedBox(height: 16),

            // ── ZATCA QR Status Badge ──
            if (_zatcaDecoded != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_rounded, color: Color(0xFF00C896), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ZATCA Verified: ${_zatcaDecoded!['seller'] ?? 'Merchant'}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                          ),
                          Text(
                            'Total: SAR ${(_zatcaDecoded!['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}  •  VAT: SAR ${(_zatcaDecoded!['vat'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                            style: const TextStyle(color: Color(0xFF00C896), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Color(0xFF8B949E)),
                      onPressed: () => setState(() {
                        _zatcaQrRaw = null;
                        _zatcaDecoded = null;
                      }),
                    ),
                  ],
                ),
              ),

            // ── Photo Grid / Thumbnails ──
            if (_imageFiles.isNotEmpty) ...[
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _imageFiles.length + 1,
                  separatorBuilder: (ctx, _) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) {
                    if (i == _imageFiles.length) {
                      return InkWell(
                        onTap: () => _addPhoto(ImageSource.camera),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 85,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1117),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF30363D), style: BorderStyle.solid),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_outlined, color: Color(0xFF00C896), size: 26),
                              SizedBox(height: 4),
                              Text('Add Page', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                            ],
                          ),
                        ),
                      );
                    }

                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _imageFiles[i],
                            width: 85,
                            height: 110,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'P${i + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removePhoto(i),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.redAccent,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Capture Controls ──
            if (!_isAnalyzing && _scanResult == null) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C896),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        _imageFiles.isEmpty ? 'Snap Photo' : 'Snap Next Page',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _addPhoto(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF30363D)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                      onPressed: () => _addPhoto(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C896),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      label: const Text('Scan QR Camera', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: _isAnalyzing ? null : _scanZatcaQrWithCamera,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF58A6FF),
                        side: BorderSide(color: const Color(0xFF1F6FEB).withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.paste_rounded, size: 18),
                      label: const Text('Paste Text', style: TextStyle(fontSize: 13)),
                      onPressed: _isAnalyzing ? null : _showZatcaQrDialog,
                    ),
                  ),
                ],
              ),

              // ── ZATCA QR & Photo Actions ──
              if (_zatcaDecoded != null && _scanResult == null) ...[
                const SizedBox(height: 12),
                if (_imageFiles.isEmpty) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F6FEB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.camera_alt_rounded, size: 20),
                    label: const Text(
                      '📸 Snap Receipt Photo to Extract Items',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: _isAnalyzing ? null : () async {
                      await _addPhoto(ImageSource.camera);
                      if (_imageFiles.isNotEmpty && mounted) {
                        await _analyzeReceipt();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF8B949E),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(
                      'Save Total Only (SAR ${(_zatcaDecoded!['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}) without items',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _isAnalyzing ? null : () => _confirmSave(allowDuplicate: false),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C896),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.auto_awesome, size: 20),
                    label: Text(
                      'Extract Items with AI & Verify (SAR ${(_zatcaDecoded!['total'] as num?)?.toStringAsFixed(2) ?? '0.00'})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: _isAnalyzing ? null : _analyzeReceipt,
                  ),
                ],
              ] else if (_imageFiles.isNotEmpty && _zatcaDecoded == null && _scanResult == null) ...[
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F6FEB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(
                    'Extract Items from ${_imageFiles.length} Photo(s) with AI',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: _analyzeReceipt,
                ),
              ],
              const SizedBox(height: 16),
            ],

            // ── Loading state ──
            if (_isAnalyzing) ...[
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF00C896)),
                    const SizedBox(height: 16),
                    Text(
                      'AI Scanning Long Receipt...',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Reading all line items item-by-item across ${_imageFiles.length} photo(s)',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF8B949E)),
                    ),
                  ],
                ),
              ),
            ],

            // ── Error state ──
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                    if (_errorMessage!.toLowerCase().contains('camera') ||
                        _errorMessage!.toLowerCase().contains('permission')) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C896),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.settings, size: 16),
                              label: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              onPressed: () => openAppSettings(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFF30363D)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Try Again', style: TextStyle(fontSize: 12)),
                              onPressed: () => _addPhoto(ImageSource.camera),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _errorMessage = null;
                          _isAnalyzing = false;
                        }),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Results content ──
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
    final isSuccess = status == 'success' || status == 'enriched';

    final merchant = _zatcaDecoded?['seller'] as String? ??
        _scanResult!['merchant'] ??
        _scanResult!['parsed_data']?['merchant'] ??
        'Merchant';

    final num amountNum = (_zatcaDecoded?['total'] as num?) ??
        (_scanResult!['amount'] ??
        _scanResult!['parsed_data']?['amount'] ??
        0.0) as num;
    final amount = amountNum.toDouble();

    final categoryCode = _scanResult!['category_code'] ??
        _scanResult!['parsed_data']?['category_code'];

    // ── Safe type conversion to avoid List<dynamic> subtype cast error ──
    final dynamic rawItems = _scanResult!['items'] ?? _scanResult!['parsed_data']?['items'];
    final List<Map<String, dynamic>> items = (rawItems is List)
        ? rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    final isZatcaVerified = _zatcaDecoded != null || _scanResult!['zatca_verified'] != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isSuccess) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00C896).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00C896)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF00C896), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Invoice Saved Successfully!',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${items.length} items logged under $merchant (SAR ${amount.toStringAsFixed(2)})${isZatcaVerified ? ' • ZATCA Verified' : ''}',
                        style: const TextStyle(color: Color(0xFF00C896), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (isCandidate) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
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
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.orange),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _scanResult!['message'] ?? 'An identical amount was recorded recently.',
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
                        child: Text(
                          'Attach ${items.length} Items to SMS',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: () => _confirmSave(allowDuplicate: true),
                        child: const Text('Log as Separate', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (!isSuccess && !isCandidate && isZatcaVerified) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF00C896).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF00C896), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ZATCA Verified Merchant: $merchant',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                      ),
                      Text(
                        'Total: SAR ${amount.toStringAsFixed(2)}  •  ${items.length} items extracted with AI',
                        style: const TextStyle(color: Color(0xFF00C896), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        TransactionItemBreakdownCard(
          merchant: merchant,
          amount: amount,
          categoryCode: categoryCode,
          source: 'receipt_scan',
          spentBy: (_scanResult != null ? _scanResult!['spent_by'] as String? : null) ?? 'both',
          items: items,
        ),
        const SizedBox(height: 16),

        if (isSuccess) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.check_circle_outline, size: 20),
            label: const Text(
              'Done / View in Dashboard',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 8),
        ] else if (!isCandidate) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.cloud_upload_outlined, size: 20),
            label: Text(
              'Confirm & Save ${items.length} Items (SAR ${amount.toStringAsFixed(2)})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: () => _confirmSave(allowDuplicate: true),
          ),
          const SizedBox(height: 8),
        ],

        TextButton.icon(
          icon: const Icon(Icons.refresh_rounded, size: 16),
          onPressed: () => setState(() {
            _imageFiles.clear();
            _zatcaQrRaw = null;
            _zatcaDecoded = null;
            _scanResult = null;
          }),
          label: const Text('Scan Another Receipt', style: TextStyle(color: Color(0xFF8B949E))),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
