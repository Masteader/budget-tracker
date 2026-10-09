import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_snackbar.dart';

/// Live Camera QR Scanner specifically designed for Saudi ZATCA e-invoicing QR codes.
class ZatcaQrCameraScanner extends StatefulWidget {
  const ZatcaQrCameraScanner({super.key});

  @override
  State<ZatcaQrCameraScanner> createState() => _ZatcaQrCameraScannerState();
}

class _ZatcaQrCameraScannerState extends State<ZatcaQrCameraScanner>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController();
  bool _isDetected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionAndRestart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionAndRestart();
    }
  }

  Future<void> _checkPermissionAndRestart() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      try {
        await _controller.start();
        if (mounted) setState(() {});
      } catch (_) {}
    }
  }

  Future<void> _requestPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      try {
        await _controller.start();
        if (mounted) setState(() {});
      } catch (_) {}
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        AppSnackBar.showWarning(
          context,
          'Camera permission is permanently denied. Please enable it in Settings.',
          title: 'Camera Permission',
          actionLabel: 'Settings',
          onAction: () => openAppSettings(),
        );
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isDetected) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.trim().isNotEmpty) {
        _isDetected = true;
        HapticFeedback.heavyImpact();
        Navigator.pop(context, code.trim());
        break;
      }
    }
  }

  void _showManualInputDialog() {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Row(
          children: [
            const Icon(Icons.qr_code_2_rounded, color: Color(0xFF00C896)),
            const SizedBox(width: 8),
            Text(
              'Enter Invoice QR Data',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the Base64 ZATCA QR code from your tax invoice:',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              maxLines: 3,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'AQ5UYW1pbWkgTWFya2V0cw...',
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final raw = textCtrl.text.trim();
              if (raw.isNotEmpty) {
                Navigator.pop(ctx);
                Navigator.pop(context, raw);
              }
            },
            child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(MobileScannerException error) {
    final isPermissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.no_photography_rounded,
                color: Color(0xFFEF4444),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isPermissionDenied
                  ? 'Camera Access Denied'
                  : 'Camera Unavailable',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              isPermissionDenied
                  ? 'Camera access is required to scan Saudi ZATCA e-invoicing QR codes directly from receipts.\n\nPlease allow camera access in App Settings or tap Request Access.'
                  : 'Unable to start camera preview: ${error.errorDetails?.message ?? error.errorCode.name}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings_outlined, size: 20),
                label: const Text(
                  'Open App Settings',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C896),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _requestPermission,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text(
                  'Request Access Again',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF30363D)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _showManualInputDialog,
              icon: const Icon(
                Icons.keyboard_alt_outlined,
                size: 18,
                color: Color(0xFF8B949E),
              ),
              label: const Text(
                'Enter QR Text Manually',
                style: TextStyle(color: Color(0xFF8B949E), fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Scan Tax Invoice QR',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard_alt_outlined, color: Colors.white70),
            tooltip: 'Enter Manually',
            onPressed: _showManualInputDialog,
          ),
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.amber),
            tooltip: 'Flashlight',
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
            tooltip: 'Flip Camera',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _buildErrorView(error),
          ),
          // Viewfinder square targeting the QR code
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF00C896), width: 3),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00C896).withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner, color: Color(0xFF00C896), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Hold camera over the QR code on your printed receipt',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
