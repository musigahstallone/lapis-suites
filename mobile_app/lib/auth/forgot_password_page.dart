import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../core/theme.dart';
import '../core/api.dart';
import '../core/logo.dart';
import '../core/widgets.dart';
import 'otp_verification_page.dart';
import 'login_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordPage({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  late final TextEditingController _emailCtrl;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid account email address.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final res = await ApiService.forgotPassword(email);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] != true) {
      setState(() => _error = res['error']?.toString() ?? 'Could not send recovery code.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpVerificationPage(
          mode: OtpFlowMode.passwordRecovery,
          email: res['email']?.toString() ?? email,
          maskedPhone: res['maskedPhone']?.toString(),
          initialMessage: res['message']?.toString(),
          expiresInSeconds: (res['expiresInSeconds'] as num?)?.toInt() ?? 600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.canvas,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back, size: 19, color: C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Password Recovery', style: flex(14.5, color: C.textPrimary)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(alignment: Alignment.centerLeft, child: LapisLogo(size: 38)),
              const SizedBox(height: 14),
              Text('Forgot your password?', style: flex(17.5, color: C.textPrimary)),
              const SizedBox(height: 4),
              Text(
                'Enter your registered email address and we will send a 6-digit SMS OTP to your linked phone number.',
                style: sans(12, color: C.textMuted),
              ),
              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: C.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      InlineAlert(message: _error!),
                      const SizedBox(height: 14),
                    ],
                    Text('Account Email', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      onSubmitted: (_) => _handleSendCode(),
                      style: sans(13, color: C.textPrimary),
                      decoration: fieldDecoration(hintText: 'name@example.com'),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 43,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleSendCode,
                        child: _isLoading
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn),
                              )
                            : Text('Send SMS Reset Code', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ResetPasswordPage extends StatefulWidget {
  final String email;
  final String resetToken;

  const ResetPasswordPage({
    super.key,
    required this.email,
    required this.resetToken,
  });

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleReset() async {
    final p = _passCtrl.text;
    final c = _confirmCtrl.text;

    if (p.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters long.');
      return;
    }
    if (p != c) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final res = await ApiService.resetPassword(
      email: widget.email,
      resetToken: widget.resetToken,
      password: p,
      confirmPassword: c,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res['success'] != true) {
      setState(() => _error = res['error']?.toString() ?? 'Password reset failed.');
      return;
    }

    showAppSnackBar(context, 'Password updated! Sign in with your new password.');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.canvas,
        elevation: 0,
        title: Text('Set New Password', style: flex(14.5, color: C.textPrimary)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(alignment: Alignment.centerLeft, child: LapisLogo(size: 38)),
              const SizedBox(height: 14),
              Text('Create a new password', style: flex(17.5, color: C.textPrimary)),
              const SizedBox(height: 4),
              Text(
                'Choose a strong password for ${widget.email}.',
                style: sans(12, color: C.textMuted),
              ),
              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: C.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      InlineAlert(message: _error!),
                      const SizedBox(height: 14),
                    ],
                    Text('New Password', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      style: sans(13, color: C.textPrimary),
                      decoration: fieldDecoration(
                        hintText: 'Minimum 6 characters',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                            size: 16,
                            color: C.textMuted,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Confirm New Password', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _confirmCtrl,
                      obscureText: _obscure,
                      onSubmitted: (_) => _handleReset(),
                      style: sans(13, color: C.textPrimary),
                      decoration: fieldDecoration(hintText: 'Re-enter new password'),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 43,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _handleReset,
                        child: _isSaving
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn),
                              )
                            : Text('Update Password', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
