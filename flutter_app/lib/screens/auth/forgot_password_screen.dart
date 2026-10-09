import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart';
import '../../widgets/app_snackbar.dart';

typedef SendResetCodeFn = Future<void> Function(String email);
typedef VerifyAndResetPasswordFn = Future<void> Function(String email, String token, String newPassword);

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;
  final SendResetCodeFn? onSendResetCode;
  final VerifyAndResetPasswordFn? onVerifyAndResetPassword;

  const ForgotPasswordScreen({
    super.key,
    this.initialEmail,
    this.onSendResetCode,
    this.onVerifyAndResetPassword,
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

  int _currentStep = 1; // 1 = Request code, 2 = Verify & Reset
  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
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
        await supabase.auth.signInWithOtp(email: email);
      }

      if (!mounted) return;
      _startCooldown();
      setState(() {
        _currentStep = 2;
      });

      AppSnackBar.showSuccess(
        context,
        'Verification code sent to $email',
        title: 'Code Sent',
        icon: Icons.mark_email_read_outlined,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        e.message,
        title: 'Authentication Error',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        'Failed to send reset code: $e',
        title: 'Request Failed',
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
            type: OtpType.email,
          );
        } catch (_) {
          await supabase.auth.verifyOTP(
            email: email,
            token: otp,
            type: OtpType.recovery,
          );
        }
        await supabase.auth.updateUser(
          UserAttributes(password: newPassword),
        );
      }

      if (!mounted) return;
      AppSnackBar.showSuccess(
        context,
        'Password updated successfully! You can now log in.',
        title: 'Password Updated',
      );

      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        e.message,
        title: 'Authentication Error',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        'Failed to update password: $e',
        title: 'Update Failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () {
            if (_currentStep == 2) {
              setState(() => _currentStep = 1);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1117), Color(0xFF0A1628)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: _currentStep == 1 ? _buildStep1() : _buildStep2(),
              ),
            ),
          ),
        ),
      ),
    );
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
                colors: [Color(0xFF00C896), Color(0xFF00A3FF)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 24),
          Text(
            'Reset Password',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter your account email address and we will send you a verification code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8B949E), fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Email address',
              hintStyle: const TextStyle(color: Color(0xFF8B949E)),
              prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF8B949E)),
              filled: true,
              fillColor: const Color(0xFF161B22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF30363D)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF30363D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF00C896)),
              ),
            ),
            validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _handleSendResetCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Send Reset Code',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C896), Color(0xFF00A3FF)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 24),
          Text(
            'Enter Verification Code',
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a verification code to ${_emailCtrl.text.trim()}. Check your inbox or spam folder.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 8,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              letterSpacing: 6,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Code',
              hintStyle: TextStyle(
                color: const Color(0xFF8B949E).withValues(alpha: 0.5),
                letterSpacing: 4,
              ),
              prefixIcon: const Icon(Icons.pin_outlined, color: Color(0xFF8B949E)),
              filled: true,
              fillColor: const Color(0xFF161B22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF30363D)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF30363D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF00C896)),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().length < 6 || v.trim().length > 8) {
                return 'Enter verification code';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePass,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'New password',
              hintStyle: const TextStyle(color: Color(0xFF8B949E)),
              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF8B949E)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: const Color(0xFF8B949E),
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
              filled: true,
              fillColor: const Color(0xFF161B22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF30363D)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF30363D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF00C896)),
              ),
            ),
            validator: (v) => v != null && v.length >= 6 ? null : 'Min 6 characters',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordCtrl,
            obscureText: _obscureConfirm,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Confirm new password',
              hintStyle: const TextStyle(color: Color(0xFF8B949E)),
              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF8B949E)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: const Color(0xFF8B949E),
                ),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              filled: true,
              fillColor: const Color(0xFF161B22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF30363D)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF30363D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF00C896)),
              ),
            ),
            validator: (v) {
              if (v == null || v != _passwordCtrl.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _handleVerifyAndResetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Set New Password',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: (_resendCooldown > 0 || _loading) ? null : _handleSendResetCode,
            child: Text(
              _resendCooldown > 0
                  ? 'Resend code in ${_resendCooldown}s'
                  : 'Didn\'t receive code? Resend',
              style: TextStyle(
                color: _resendCooldown > 0 ? const Color(0xFF8B949E) : const Color(0xFF00C896),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
