import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/api.dart';
import '../core/logo.dart';
import '../core/icons.dart';
import '../core/widgets.dart';
import '../landlord/landlord.dart';
import '../resident/resident.dart';
import 'otp_verification_page.dart';
import 'register_page.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please enter both your email address and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final res = await ApiService.login(email, pass);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] != true) {
      setState(() => _error = res['error']?.toString() ?? 'Sign in failed. Please try again.');
      return;
    }

    // 1. Admin 2FA SMS OTP required
    if (res['requiresOtp'] == true) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationPage(
            mode: OtpFlowMode.adminLogin,
            email: res['email']?.toString() ?? email,
            challengeToken: res['challengeToken']?.toString() ?? '',
            maskedPhone: res['maskedPhone']?.toString(),
            initialMessage: res['message']?.toString(),
            expiresInSeconds: (res['expiresInSeconds'] as num?)?.toInt() ?? 600,
          ),
        ),
      );
      return;
    }

    // 2. Pre-added resident needs SMS OTP to claim account & set password
    if (res['requiresAccountSetup'] == true) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationPage(
            mode: OtpFlowMode.passwordRecovery,
            email: res['email']?.toString() ?? email,
            initialMessage: res['message']?.toString(),
            expiresInSeconds: (res['expiresInSeconds'] as num?)?.toInt() ?? 600,
          ),
        ),
      );
      return;
    }

    // 3. Direct session established
    final role = (res['role'] ?? '').toString().toLowerCase();
    final dest = (role == 'landlord' || role == 'admin' || role == 'manager')
        ? const LandlordPortfolioScreen()
        : const ResidentHomeScreen();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => dest),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand Mark + Wordmark
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const LapisLogo(size: 38),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LAPIS SUITES',
                          style: flex(15.5, color: C.navy, weight: FontWeight.w700, letterSpacing: 0.9),
                        ),
                        Text(
                          'Urban Executive Living',
                          style: sans(10.5, color: C.textMuted, weight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Sign-In Form Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: C.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: C.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Sign in', style: flex(16, color: C.textPrimary)),
                      const SizedBox(height: 16),

                      if (_error != null) ...[
                        InlineAlert(message: _error!),
                        const SizedBox(height: 14),
                      ],

                      Text('Email Address', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        style: sans(13, color: C.textPrimary),
                        decoration: fieldDecoration(hintText: 'name@example.com'),
                      ),
                      const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Password', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ForgotPasswordPage(initialEmail: _emailCtrl.text.trim()),
                              ),
                            ),
                            child: Text(
                              'Forgot password?',
                              style: sans(11.5, color: C.blueText, weight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _handleLogin(),
                        style: sans(13, color: C.textPrimary),
                        decoration: fieldDecoration(
                          hintText: 'Enter your password',
                          suffixIcon: IconButton(
                            icon: LapisIcon(
                              _obscure ? LapisIconName.eye : LapisIconName.eyeOff,
                              size: 16,
                              color: C.textMuted,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      SizedBox(
                        height: 43,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn),
                                )
                              : Text('Sign In', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Resident Registration / Account Claim link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('New resident or added by management? ', style: sans(12, color: C.textMuted)),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RegisterPage()),
                      ),
                      child: Text(
                        'Create account',
                        style: sans(12, color: C.blueText, weight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
