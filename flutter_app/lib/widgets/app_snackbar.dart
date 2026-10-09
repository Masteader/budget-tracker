import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized, premium dark-mode SnackBar design system.
/// Implements floating toasts with custom iconography, curated color accents,
/// modern Outfit typography, subtle glowing borders, and interactive action/undo pills.
class AppSnackBar {
  AppSnackBar._();

  /// Shows a successful operation toast (Emerald theme).
  static void showSuccess(
    BuildContext context,
    String message, {
    String? title,
    IconData icon = Icons.check_circle_rounded,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message: message,
      title: title,
      accentColor: const Color(0xFF00C896),
      icon: icon,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Shows an item deletion / removal toast with high-contrast UNDO callback (Coral/Rose theme).
  static void showDelete(
    BuildContext context,
    String message, {
    String? title,
    VoidCallback? onUndo,
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(
      context,
      message: message,
      title: title,
      accentColor: const Color(0xFFFF7B72),
      icon: Icons.delete_outline_rounded,
      duration: duration,
      undoCallback: onUndo,
    );
  }

  /// Shows an error / failure toast (Crimson theme).
  static void showError(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message: message,
      title: title,
      accentColor: const Color(0xFFF85149),
      icon: Icons.error_outline_rounded,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Shows a warning / offline alert toast (Amber/Gold theme).
  static void showWarning(
    BuildContext context,
    String message, {
    String? title,
    IconData icon = Icons.warning_amber_rounded,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message: message,
      title: title,
      accentColor: const Color(0xFFFFA657),
      icon: icon,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Shows an informational / copy toast (Cyan/Sky theme).
  static void showInfo(
    BuildContext context,
    String message, {
    String? title,
    IconData icon = Icons.info_outline_rounded,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message: message,
      title: title,
      accentColor: const Color(0xFF79C0FF),
      icon: icon,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    String? title,
    required Color accentColor,
    required IconData icon,
    required Duration duration,
    VoidCallback? undoCallback,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        elevation: 8,
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF161B22),
        duration: duration,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: accentColor.withValues(alpha: 0.38), width: 1.2),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Semantic Icon Badge
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.28),
                  width: 0.8,
                ),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 12),

            // Text column (Title + Message)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null && title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        title,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  Text(
                    message,
                    style: GoogleFonts.outfit(
                      color: const Color(0xFFC9D1D9),
                      fontSize: 12.5,
                      fontWeight: title != null ? FontWeight.w400 : FontWeight.w500,
                      height: 1.25,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Undo Button (If present)
            if (undoCallback != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  undoCallback();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF00C896).withValues(alpha: 0.6),
                      width: 1.1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.undo_rounded, size: 14, color: Color(0xFF00C896)),
                      const SizedBox(width: 4),
                      Text(
                        'UNDO',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF00C896),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  onAction();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.6),
                      width: 1.1,
                    ),
                  ),
                  child: Text(
                    actionLabel,
                    style: GoogleFonts.outfit(
                      color: accentColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
