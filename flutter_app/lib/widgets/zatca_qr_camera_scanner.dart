import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_snackbar.dart';
import 'dispose_on_unmount.dart';
import '../theme/app_themes.dart';
import '../l10n/app_localizations.dart';

/// Live Camera QR Scanner specifically designed for Saudi ZATCA e-invoicing QR codes.
class ZatcaQrCameraScanner extends StatefulWidget {
  const ZatcaQrCameraScanner({super.key});

  @override
  State<ZatcaQrCameraScanner> createState() => _ZatcaQrCameraScannerState();
}

class _ZatcaQrCameraScannerState extends State<ZatcaQrCameraScanner>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController();
  late final AnimationController _laserController;
  late final Animation<double> _laserAnimation;
  bool _isDetected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _laserAnimation = Tween<double>(begin: 0.08, end: 0.92).animate(
      CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
    );
    _checkPermissionAndRestart();
  }

  @override
  void dispose() {
    _laserController.dispose();
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
          context.tr('zq_perm_permanent'),
          title: context.tr('zq_perm_title'),
          actionLabel: context.tr('nav_settings'),
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
      builder: (ctx) => DisposeOnUnmount(
        disposables: [textCtrl],
        child: AlertDialog(
        backgroundColor: context.cardBg,
        title: Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E)),
            const SizedBox(width: 8),
            Text(
              context.tr('zq_manual_title'),
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('zq_manual_desc'),
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              maxLines: 3,
              style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: context.textPrimary),
              decoration: InputDecoration(
                hintText: 'AQ5UYW1pbWkgTWFya2V0cw...',
                hintStyle: TextStyle(color: context.textSecondary.withValues(alpha: 0.6), fontSize: 11),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderColor)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.isDark ? const Color(0xFF5E1327) : const Color(0xFF4A0E1E),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final raw = textCtrl.text.trim();
              if (raw.isNotEmpty) {
                Navigator.pop(ctx);
                Navigator.pop(context, raw);
              }
            },
            child: Text(context.tr('zq_apply'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
                  ? context.tr('zq_access_denied')
                  : context.tr('zq_unavailable'),
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
                  ? context.tr('zq_access_required_desc')
                  : context.trArgs('zq_preview_error', {'error': error.errorDetails?.message ?? error.errorCode.name}),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.textSecondary,
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
                label: Text(
                  context.tr('set_open_app_settings'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.isDark ? const Color(0xFF5E1327) : const Color(0xFF4A0E1E),
                  foregroundColor: Colors.white,
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
                label: Text(
                  context.tr('zq_request_again'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.textPrimary,
                  side: BorderSide(color: context.borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _showManualInputDialog,
              icon: Icon(
                Icons.keyboard_alt_outlined,
                size: 18,
                color: context.textSecondary,
              ),
              label: Text(
                context.tr('zq_enter_manually_long'),
                style: TextStyle(color: context.textSecondary, fontSize: 14),
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
          context.tr('zq_title'),
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: context.textPrimary),
        ),
        backgroundColor: context.cardBg,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.keyboard_alt_outlined, color: context.textSecondary),
            tooltip: context.tr('zq_enter_manually'),
            onPressed: _showManualInputDialog,
          ),
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.amber),
            tooltip: context.tr('zq_flashlight'),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: Icon(Icons.cameraswitch_outlined, color: context.textPrimary),
            tooltip: context.tr('zq_flip_camera'),
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
          // Viewfinder square with Holographic Laser sweep
          Center(
            child: SizedBox(
              width: 270,
              height: 270,
              child: Stack(
                children: [
                  Container(
                    width: 270,
                    height: 270,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFE598B0).withValues(alpha: 0.85),
                        width: 2.5,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4A0E1E).withValues(alpha: 0.35),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  // Top HUD Badge
                  Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E0B12).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE598B0).withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          context.tr('zq_target'),
                          style: GoogleFonts.outfit(
                            color: const Color(0xFFE598B0),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Animated Holographic Laser Line
                  AnimatedBuilder(
                    animation: _laserAnimation,
                    builder: (context, child) {
                      return Positioned(
                        top: 270 * _laserAnimation.value,
                        left: 12,
                        right: 12,
                        child: Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Colors.transparent,
                                Color(0xFFFF4D6D),
                                Color(0xFFE598B0),
                                Color(0xFFFF4D6D),
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF4D6D).withValues(alpha: 0.85),
                                blurRadius: 10,
                                spreadRadius: 1.5,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
                color: const Color(0xFF1E0B12).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE598B0).withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner, color: Color(0xFFF0A3BC), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('zq_hold_camera'),
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
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
