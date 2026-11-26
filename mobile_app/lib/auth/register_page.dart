import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../core/theme.dart';
import '../core/api.dart';
import '../core/logo.dart';
import '../core/widgets.dart';
import 'otp_verification_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSendOtp() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (phone.length != 9 || !(phone.startsWith('7') || phone.startsWith('1'))) {
      setState(() => _error = 'Enter your 9-digit mobile number starting with 7 or 1.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters long.');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final res = await ApiService.requestRegisterOtp(
      email: email,
      password: pass,
      name: name,
      phone: phone,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] != true) {
      setState(() => _error = res['error']?.toString() ?? 'Could not send verification code.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpVerificationPage(
          mode: OtpFlowMode.registerOrClaim,
          email: res['email']?.toString() ?? email,
          challengeToken: res['challengeToken']?.toString() ?? '',
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
        title: Text('Resident Account', style: flex(14.5, color: C.textPrimary)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(alignment: Alignment.centerLeft, child: LapisLogo(size: 38)),
              const SizedBox(height: 12),
              Text('Create or Activate Account', style: flex(17.5, color: C.textPrimary)),
              const SizedBox(height: 4),
              Text(
                'Already added by management? Use the same email to claim your profile and set your password via SMS OTP.',
                style: sans(12, color: C.textMuted),
              ),
              const SizedBox(height: 16),

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

                    Text('Full Name', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      style: sans(13, color: C.textPrimary),
                      decoration: fieldDecoration(hintText: 'e.g. Jane Wanjiku'),
                    ),
                    const SizedBox(height: 12),

                    Text('Email Address', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: sans(13, color: C.textPrimary),
                      decoration: fieldDecoration(hintText: 'name@example.com'),
                    ),
                    const SizedBox(height: 12),

                    Text('Mobile Number (for SMS OTP)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    KenyaPhoneField(controller: _phoneCtrl),
                    const SizedBox(height: 12),

                    Text('Secure Password', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      style: sans(13, color: C.textPrimary),
                      decoration: fieldDecoration(
                        hintText: 'At least 6 characters',
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

                    Text('Confirm Password', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: _confirmCtrl,
                      obscureText: _obscure,
                      style: sans(13, color: C.textPrimary),
                      decoration: fieldDecoration(hintText: 'Re-enter password'),
                    ),
                    const SizedBox(height: 18),

                    SizedBox(
                      height: 43,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleSendOtp,
                        child: _isLoading
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn),
                              )
                            : Text('Send SMS Verification Code', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
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
