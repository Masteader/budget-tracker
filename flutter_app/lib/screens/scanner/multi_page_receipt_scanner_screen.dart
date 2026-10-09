import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/offline_sync_service.dart';
import '../../widgets/zatca_qr_camera_scanner.dart';
import '../../widgets/app_snackbar.dart';

class MultiPageReceiptScannerScreen extends StatefulWidget {
  final String householdId;

  const MultiPageReceiptScannerScreen({super.key, required this.householdId});

  @override
  State<MultiPageReceiptScannerScreen> createState() => _MultiPageReceiptScannerScreenState();
}

class _MultiPageReceiptScannerScreenState extends State<MultiPageReceiptScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<File> _capturedShots = [];
  bool _isProcessing = false;
  String? _errorMessage;

  final List<String> _guideSteps = [
    'Shot 1: Top header & ZATCA QR code',
    'Shot 2: Middle line items (overlap with shot 1)',
    'Shot 3: Bottom subtotal, VAT, and totals',
    'Shot 4+: Additional continuous segments if needed',
  ];

  Future<void> _captureShot() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked != null) {
        setState(() {
          _capturedShots.add(File(picked.path));
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Camera capture error: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked.isNotEmpty) {
        setState(() {
          _capturedShots.addAll(picked.map((x) => File(x.path)));
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Gallery error: $e');
    }
  }

  void _removeShot(int index) {
    setState(() => _capturedShots.removeAt(index));
  }

  Future<void> _processAllShots() async {
    if (_capturedShots.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final List<String> base64List = [];
      for (final f in _capturedShots) {
        final bytes = await f.readAsBytes();
        base64List.add(base64Encode(bytes));
      }

      final res = await ApiService.instance.scanReceipt(
        imagesBase64: base64List,
        householdId: widget.householdId,
        allowDuplicate: false,
      );

      setState(() => _isProcessing = false);

      if (mounted) {
        if (res['status'] == 'success') {
          AppSnackBar.showSuccess(
            context,
            res['message'] ?? 'Receipt stitched and saved successfully!',
            title: 'Receipt Saved',
          );
          Navigator.pop(context, true);
        } else if (res['status'] == 'error') {
          // If offline, enqueue
          await OfflineSyncService.instance.enqueue(
            endpoint: 'receipt',
            payload: {'images_base64': base64List},
            householdId: widget.householdId,
          );
          if (mounted) {
            AppSnackBar.showWarning(
              context,
              'Saved receipt shots to local offline queue. Will sync automatically once connected.',
              title: 'Queued Offline',
              icon: Icons.cloud_off_rounded,
            );
            Navigator.pop(context, true);
          }
        } else {
          setState(() {
            _errorMessage = res['message'] ?? 'Could not parse receipt shots.';
          });
        }
      }
    } catch (e) {
      // Offline fallback
      setState(() => _isProcessing = false);
      try {
        final List<String> base64List = [];
        for (final f in _capturedShots) {
          final bytes = await f.readAsBytes();
          base64List.add(base64Encode(bytes));
        }
        await OfflineSyncService.instance.enqueue(
          endpoint: 'receipt',
          payload: {'images_base64': base64List},
          householdId: widget.householdId,
        );
        if (mounted) {
          AppSnackBar.showWarning(
            context,
            'Saved receipt shots to local offline queue.',
            title: 'Queued Offline',
            icon: Icons.cloud_off_rounded,
          );
          Navigator.pop(context, true);
        }
      } catch (_) {
        setState(() => _errorMessage = 'Failed to process receipt shots: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentGuide = _capturedShots.length < _guideSteps.length
        ? _guideSteps[_capturedShots.length]
        : 'Ready to stitch and process all shots!';

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Text(
          'Continuous Long Receipt Stitcher',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF00C896)),
            tooltip: 'Scan ZATCA QR',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ZatcaQrCameraScanner()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Guided Instruction Banner
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C896).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, color: Color(0xFF00C896), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overlap Shots by ~2-3 Items',
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentGuide,
                          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ),
                  ],
                ),
              ),

            // Main Preview Area / Empty state
            Expanded(
              child: _capturedShots.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161B22),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF30363D)),
                            ),
                            child: const Icon(Icons.receipt_long_rounded, size: 54, color: Color(0xFF00C896)),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Capture Continuous Long Receipts',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 36),
                            child: Text(
                              'Take sequential overlapping photos of long grocery receipts (60+ items). Our AI stitches them and eliminates duplicate items automatically.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF8B949E), fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              _capturedShots.last,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Latest: Shot #${_capturedShots.length}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),

            // Bottom Filmstrip
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: const Color(0xFF161B22),
              child: Column(
                children: [
                  if (_capturedShots.isNotEmpty)
                    SizedBox(
                      height: 85,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _capturedShots.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (ctx, i) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  _capturedShots[i],
                                  width: 65,
                                  height: 85,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                left: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#${i + 1}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () => _removeShot(i),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.redAccent,
                                    ),
                                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF21262D),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                            label: Text(
                              _capturedShots.isEmpty ? 'Take Shot 1' : 'Take Shot #${_capturedShots.length + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: _isProcessing ? null : _captureShot,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF21262D),
                            padding: const EdgeInsets.all(14),
                          ),
                          icon: const Icon(Icons.photo_library_outlined, color: Colors.white),
                          tooltip: 'Pick from Gallery',
                          onPressed: _isProcessing ? null : _pickFromGallery,
                        ),
                        if (_capturedShots.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C896),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: _isProcessing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                    )
                                  : const Icon(Icons.check_circle_outline, size: 20),
                              label: Text(
                                _isProcessing ? 'Stitching...' : 'Process (${_capturedShots.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              onPressed: _isProcessing ? null : _processAllShots,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
