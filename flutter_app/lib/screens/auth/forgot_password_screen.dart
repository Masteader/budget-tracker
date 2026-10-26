import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart';
import '../../supabase_config.dart';
import '../../widgets/app_snackbar.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';

typedef SendResetCodeFn = Future<void> Function(String email);
typedef VerifyAndResetPasswordFn = Future<void> Function(String email, String token, String newPassword);
typedef UpdatePasswordDirectFn = Future<void> Function(String newPassword);

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;
  final SendResetCodeFn? onSendResetCode;
  final VerifyAndResetPasswordFn? onVerifyAndResetPassword;
  final UpdatePasswordDirectFn? onUpdatePassword;
  final Stream<AuthState>? authStates;

  const ForgotPasswordScreen({
    super.key,
    this.initialEmail,
    this.onSendResetCode,
    this.onVerifyAndResetPassword,
    this.onUpdatePassword,
    this.authStates,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailCtrl;
  final _otpCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();
  final _step3FormKey = GlobalKey<FormState>();

  int _currentStep = 1; // 1 = Request, 2 = Check Email & Verify, 3 = Direct Set New Password
  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
    _initAuthListener();
  }

  void _initAuthListener() {
    if (widget.authStates != null) {
      _authSub = widget.authStates!.listen(_onAuthStateChanged);
      return;
    }
    try {
      _authSub = supabase.auth.onAuthStateChange.listen(_onAuthStateChanged);
    } catch (_) {
      // Supabase is not initialized in pure widget test environments.
    }
  }

  void _onAuthStateChanged(AuthState data) {
    if (!mounted) return;
    if (data.event == AuthChangeEvent.passwordRecovery) {
      setState(() {
        _currentStep = 3;
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _cooldownTimer?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _handleSendResetCode() async {
    if (!_step1FormKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final email = _emailCtrl.text.trim();
    try {
      if (widget.onSendResetCode != null) {
        await widget.onSendResetCode!(email);
      } else {
        try {
          await supabase.auth.resetPasswordForEmail(
            email,
            redirectTo: authResetRedirectUrl,
          );
        } catch (_) {
          await supabase.auth.signInWithOtp(
            email: email,
            emailRedirectTo: authResetRedirectUrl,
          );
        }
      }

      if (!mounted) return;
      _startCooldown();
      setState(() {
        _currentStep = 2;
      });

      AppSnackBar.showSuccess(
        context,
        context.trArgs('auth_code_sent_to', {'email': email}),
        title: context.tr('auth_code_sent'),
        icon: Icons.mark_email_read_outlined,
      );
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
        context.trArgs('auth_send_code_failed', {'error': e}),
        title: context.tr('auth_request_failed'),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleVerifyAndResetPassword() async {
    if (!_step2FormKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final email = _emailCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    final newPassword = _passwordCtrl.text;

    try {
      if (widget.onVerifyAndResetPassword != null) {
        await widget.onVerifyAndResetPassword!(email, otp, newPassword);
      } else {
        try {
          await supabase.auth.verifyOTP(
            email: email,
            token: otp,
            type: OtpType.recovery,
          );
        } catch (_) {
          await supabase.auth.verifyOTP(
            email: email,
            token: otp,
            type: OtpType.email,
          );
        }
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

      Navigator.of(context).pop();
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

  Future<void> _handleUpdateDirectPassword() async {
    if (!_step3FormKey.currentState!.validate()) return;
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

      Navigator.of(context).pop();
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
          onPressed: () {
            if (_currentStep == 2) {
              setState(() => _currentStep = 1);
            } else if (_currentStep == 3) {
              setState(() => _currentStep = 2);
            } else {
              Navigator.of(context).pop();
            }
          },
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: _buildCurrentStepWidget(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStepWidget() {
    switch (_currentStep) {
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
      default:
        return _buildStep3();
    }
  }

  Widget _buildStep1() {
    return Form(
      key: _step1FormKey,
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
            context.tr('auth_reset_password'),
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('auth_reset_password_desc'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.textSecondary, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              hintText: context.tr('auth_email_address'),
              hintStyle: TextStyle(color: context.textSecondary),
              prefixIcon: Icon(Icons.email_outlined, color: context.textSecondary),
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
            validator: (v) => v != null && v.contains('@') ? null : context.tr('auth_enter_valid_email'),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _handleSendResetCode,
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
                      context.tr('auth_send_reset_code'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Form(
      key: _step2FormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppThemes.electricTeal, AppThemes.iceCyan],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppThemes.electricTeal.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.mark_email_read_rounded, color: AppThemes.brandDarkBg, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('auth_enter_verification_code_title'),
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            context.trArgs('auth_code_sent_check_inbox', {'email': _emailCtrl.text.trim()}),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 12),
          // Deep-link helper card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppThemes.electricTeal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppThemes.electricTeal.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.touch_app_outlined, color: AppThemes.electricTeal, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('auth_reset_link_instruction'),
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 8,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 18,
              letterSpacing: 6,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: context.tr('auth_code_hint'),
              hintStyle: TextStyle(
                color: context.textSecondary.withValues(alpha: 0.5),
                letterSpacing: 4,
              ),
              prefixIcon: Icon(Icons.pin_outlined, color: context.textSecondary, size: 20),
              filled: true,
              fillColor: context.inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppThemes.electricTeal),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().length < 6 || v.trim().length > 8) {
                return context.tr('auth_enter_verification_code');
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePass,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: context.tr('auth_new_password'),
              hintStyle: TextStyle(color: context.textSecondary),
              prefixIcon: Icon(Icons.lock_outline, color: context.textSecondary, size: 20),
              suffixIcon: IconButton(
                tooltip: context.tr('auth_toggle_password_visibility'),
                icon: Icon(
                  _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: context.textSecondary,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
              filled: true,
              fillColor: context.inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppThemes.electricTeal),
              ),
            ),
            validator: (v) => v != null && v.length >= 6 ? null : context.tr('auth_min_6_chars'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmPasswordCtrl,
            obscureText: _obscureConfirm,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: context.tr('auth_confirm_new_password'),
              hintStyle: TextStyle(color: context.textSecondary),
              prefixIcon: Icon(Icons.lock_outline, color: context.textSecondary, size: 20),
              suffixIcon: IconButton(
                tooltip: context.tr('auth_toggle_password_visibility'),
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: context.textSecondary,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              filled: true,
              fillColor: context.inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _handleVerifyAndResetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemes.electricTeal,
                foregroundColor: AppThemes.brandDarkBg,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppThemes.brandDarkBg),
                    )
                  : Text(
                      context.tr('auth_set_new_password'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: (_resendCooldown > 0 || _loading) ? null : _handleSendResetCode,
            child: Text(
              _resendCooldown > 0
                  ? context.trArgs('auth_resend_in', {'seconds': _resendCooldown})
                  : context.tr('auth_resend_code'),
              style: TextStyle(
                color: _resendCooldown > 0 ? context.textSecondary : context.accentText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return Form(
      key: _step3FormKey,
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
            child: const Icon(Icons.check_circle_outline_rounded, color: AppThemes.brandDarkBg, size: 36),
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
              onPressed: _loading ? null : _handleUpdateDirectPassword,
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
        ],
      ),
    );
  }
}
