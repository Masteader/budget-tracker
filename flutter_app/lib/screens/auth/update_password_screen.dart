import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart';
import '../../widgets/app_snackbar.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';

typedef UpdatePasswordFn = Future<void> Function(String newPassword);

class UpdatePasswordScreen extends StatefulWidget {
  final UpdatePasswordFn? onUpdatePassword;
  final VoidCallback? onPasswordUpdated;
  final VoidCallback? onCancel;

  const UpdatePasswordScreen({
    super.key,
    this.onUpdatePassword,
    this.onPasswordUpdated,
    this.onCancel,
  });

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final newPassword = _passwordCtrl.text;

    try {
      if (widget.onUpdatePassword != null) {
        await widget.onUpdatePassword!(newPassword);
      } else {
        await supabase.auth.updateUser(
          UserAttributes(password: newPassword),
        );
      }

      if (!mounted) return;
      AppSnackBar.showSuccess(
        context,
        context.tr('auth_password_updated_msg'),
        title: context.tr('auth_password_updated'),
      );

      if (widget.onPasswordUpdated != null) {
        widget.onPasswordUpdated!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        e.message,
        title: context.tr('auth_error'),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        context.trArgs('auth_update_password_failed', {'error': e}),
        title: context.tr('auth_update_failed'),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleCancel() async {
    if (widget.onCancel != null) {
      widget.onCancel!();
      return;
    }
    try {
      await supabase.auth.signOut();
    } catch (_) {}
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: context.tr('nav_back'),
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.textPrimary, size: 20),
          onPressed: _handleCancel,
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: context.isDark
                ? const [VelvetBurgundyColors.canvasDark, VelvetBurgundyColors.surfaceDark]
                : const [VelvetBurgundyColors.canvasLight, VelvetBurgundyColors.rosePillLight],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppThemes.electricTeal, AppThemes.iceCyan],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppThemes.electricTeal.withValues(alpha: 0.25),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.lock_reset_rounded, color: AppThemes.brandDarkBg, size: 36),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      context.tr('auth_create_new_password_title'),
                      style: GoogleFonts.outfit(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('auth_create_new_password_desc'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.textSecondary, fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePass,
                      style: TextStyle(color: context.textPrimary),
                      decoration: InputDecoration(
                        hintText: context.tr('auth_new_password'),
                        hintStyle: TextStyle(color: context.textSecondary),
                        prefixIcon: Icon(Icons.lock_outline, color: context.textSecondary),
                        suffixIcon: IconButton(
                          tooltip: context.tr('auth_toggle_password_visibility'),
                          icon: Icon(
                            _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: context.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscurePass = !_obscurePass),
                        ),
                        filled: true,
                        fillColor: context.inputBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: context.borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: context.borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppThemes.electricTeal),
                        ),
                      ),
                      validator: (v) => v != null && v.length >= 6 ? null : context.tr('auth_min_6_chars'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordCtrl,
                      obscureText: _obscureConfirm,
                      style: TextStyle(color: context.textPrimary),
                      decoration: InputDecoration(
                        hintText: context.tr('auth_confirm_new_password'),
                        hintStyle: TextStyle(color: context.textSecondary),
                        prefixIcon: Icon(Icons.lock_outline, color: context.textSecondary),
                        suffixIcon: IconButton(
                          tooltip: context.tr('auth_toggle_password_visibility'),
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: context.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                        filled: true,
                        fillColor: context.inputBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: context.borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: context.borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppThemes.electricTeal),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v != _passwordCtrl.text) {
                          return context.tr('auth_passwords_mismatch');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _handleSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppThemes.electricTeal,
                          foregroundColor: AppThemes.brandDarkBg,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppThemes.brandDarkBg),
                              )
                            : Text(
                                context.tr('auth_set_new_password'),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _loading ? null : _handleCancel,
                      child: Text(
                        context.tr('auth_cancel_and_return'),
                        style: TextStyle(
                          color: context.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
