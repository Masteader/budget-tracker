/// Login & Signup screen.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../supabase_config.dart';
import '../../widgets/app_snackbar.dart';
import '../../theme/app_themes.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _formKey      = GlobalKey<FormState>();

  bool _isLogin  = true;
  bool _loading  = false;
  bool _obscure  = true;

  late final AnimationController _anim;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      } else {
        await supabase.auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          emailRedirectTo: authRedirectUrl,
          data: {'display_name': _nameCtrl.text.trim()},
        );
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            context.tr('auth_account_created'),
            title: context.tr('auth_welcome'),
            icon: Icons.mark_email_read_outlined,
          );
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          e.message,
          title: context.tr('auth_failed'),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          e.toString().replaceAll('Exception: ', ''),
          title: context.tr('auth_error'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: context.isDark
                ? const [AppThemes.brandDarkBg, Color(0xFF091C31)]
                : const [Color(0xFFF8FAFC), Color(0xFFEFF6FF)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppThemes.electricTeal, AppThemes.iceCyan],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppThemes.electricTeal.withValues(alpha: 0.25),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded,
                          color: AppThemes.brandDarkBg, size: 40),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      context.tr('app_title'),
                      style: GoogleFonts.outfit(
                        fontSize: 30, fontWeight: FontWeight.w700, color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isLogin ? context.tr('auth_welcome_back') : context.tr('auth_create_your_account'),
                      style: TextStyle(color: context.textSecondary, fontSize: 15),
                    ),
                    const SizedBox(height: 40),

                    // Form
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (!_isLogin) ...[
                            TextFormField(
                              controller: _nameCtrl,
                              decoration: InputDecoration(
                                hintText: context.tr('auth_display_name'),
                                prefixIcon: const Icon(Icons.person_outline),
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? context.tr('auth_enter_your_name') : null,
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              hintText: context.tr('auth_email_address'),
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                            validator: (v) =>
                                v != null && v.contains('@') ? null : context.tr('auth_enter_valid_email'),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              hintText: context.tr('auth_password'),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: context.tr('auth_toggle_password_visibility'),
                                icon: Icon(_obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) =>
                                v != null && v.length >= 6 ? null : context.tr('auth_min_6_chars'),
                          ),
                          if (_isLogin) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ForgotPasswordScreen(
                                        initialEmail: _emailCtrl.text.trim(),
                                      ),
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: const Size(48, 48),
                                ),
                                child: Text(
                                  context.tr('auth_forgot_password'),
                                  style: TextStyle(
                                    color: context.accentText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),

                          // Submit button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppThemes.electricTeal,
                                foregroundColor: AppThemes.brandDarkBg,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: AppThemes.brandDarkBg),
                                    )
                                  : Text(
                                      _isLogin ? context.tr('auth_sign_in') : context.tr('auth_create_account'),
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w700),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Toggle
                          TextButton(
                            onPressed: () => setState(() => _isLogin = !_isLogin),
                            child: Text(
                              _isLogin
                                  ? context.tr('auth_no_account_sign_up')
                                  : context.tr('auth_have_account_sign_in'),
                              style: TextStyle(
                                color: context.accentText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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
