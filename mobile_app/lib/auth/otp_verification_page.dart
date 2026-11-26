import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api.dart';
import '../core/logo.dart';
import '../core/widgets.dart';
import '../landlord/landlord.dart';
import '../resident/resident.dart';
import 'forgot_password_page.dart';

enum OtpFlowMode {
  adminLogin,
  registerOrClaim,
  passwordRecovery,
}

class OtpVerificationPage extends StatefulWidget {
  final OtpFlowMode mode;
  final String email;
  final String? challengeToken;
  final String? maskedPhone;
  final String? initialMessage;
  final int expiresInSeconds;

  const OtpVerificationPage({
    super.key,
    required this.mode,
    required this.email,
    this.challengeToken,
    this.maskedPhone,
    this.initialMessage,
    this.expiresInSeconds = 600,
  });

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final _codeCtrl = TextEditingController();
  late String _challengeToken;
  String? _maskedPhone;
  late int _secondsRemaining;
  Timer? _timer;
  bool _isVerifying = false;
  bool _isResending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _challengeToken = widget.challengeToken ?? '';
    _maskedPhone = widget.maskedPhone;
    _secondsRemaining = widget.expiresInSeconds;
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        t.cancel();
      }
    });
  }

  String get _formattedTimer {
    final m = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _title {
    switch (widget.mode) {
      case OtpFlowMode.adminLogin:
        return 'Admin Verification';
      case OtpFlowMode.registerOrClaim:
        return 'Verify Your Phone';
      case OtpFlowMode.passwordRecovery:
        return 'Enter Reset Code';
    }
  }

  /// Single clean instruction line (no duplicate OTP notices)
  String get _singleSubtitle {
    if (_maskedPhone != null && _maskedPhone!.isNotEmpty) {
      return 'Enter the 6-digit SMS code sent to $_maskedPhone.';
    }
    return 'Enter the 6-digit SMS code sent to your mobile number.';
  }

  Future<void> _handleVerify() async {
    final code = _codeCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _error = 'Enter all 6 digits from your SMS.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    Map<String, dynamic> res;
    switch (widget.mode) {
      case OtpFlowMode.adminLogin:
        res = await ApiService.verifyLoginOtp(
          challengeToken: _challengeToken,
          code: code,
        );
        break;
      case OtpFlowMode.registerOrClaim:
        res = await ApiService.verifyRegisterOtp(
          challengeToken: _challengeToken,
          code: code,
        );
        break;
      case OtpFlowMode.passwordRecovery:
        res = await ApiService.verifyRecoveryCode(
          email: widget.email,
          code: code,
        );
        break;
    }

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (res['success'] != true) {
      setState(() => _error = res['error']?.toString() ?? 'Verification failed.');
      return;
    }

    if (widget.mode == OtpFlowMode.passwordRecovery) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResetPasswordPage(
            email: widget.email,
            resetToken: res['resetToken']?.toString() ?? '',
          ),
        ),
      );
      return;
    }

    final role = (res['role'] ?? ApiService.currentUser?['role'] ?? 'tenant')
        .toString()
        .toLowerCase();
    final dest = (role == 'landlord' || role == 'admin' || role == 'manager')
        ? const LandlordPortfolioScreen()
        : const ResidentHomeScreen();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => dest),
      (route) => false,
    );
  }

  Future<void> _handleResend() async {
    setState(() {
      _isResending = true;
      _error = null;
    });

    Map<String, dynamic> res;
    if (widget.mode == OtpFlowMode.adminLogin) {
      res = await ApiService.resendLoginOtp(_challengeToken);
    } else if (widget.mode == OtpFlowMode.passwordRecovery) {
      res = await ApiService.forgotPassword(widget.email);
    } else {
      setState(() {
        _isResending = false;
        _error = 'Go back and tap Send Code to request a fresh OTP.';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _isResending = false);

    if (res['success'] == true) {
      setState(() {
        if (res['challengeToken'] != null && res['challengeToken'].toString().isNotEmpty) {
          _challengeToken = res['challengeToken'].toString();
        }
        if (res['maskedPhone'] != null && res['maskedPhone'].toString().isNotEmpty) {
          _maskedPhone = res['maskedPhone'].toString();
        }
        _secondsRemaining = (res['expiresInSeconds'] as num?)?.toInt() ?? 600;
      });
      _startCountdown();
      showAppSnackBar(context, 'New verification code sent.');
    } else {
      setState(() => _error = res['error']?.toString() ?? 'Could not resend code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = widget.mode != OtpFlowMode.registerOrClaim;

    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.canvas,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back, size: 19, color: C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(alignment: Alignment.centerLeft, child: LapisLogo(size: 38)),
              const SizedBox(height: 14),
              Text(_title, style: flex(17.5, color: C.textPrimary)),
              const SizedBox(height: 4),
              Text(_singleSubtitle, style: sans(12.5, color: C.textMuted)),
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

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('6-Digit Code', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                        Text(
                          _secondsRemaining > 0 ? _formattedTimer : 'Expired',
                          style: mono(
                            11.5,
                            color: _secondsRemaining > 0 ? C.textMuted : C.roseText,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      autofocus: true,
                      style: mono(20, color: C.navy, weight: FontWeight.w700, letterSpacing: 8),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onSubmitted: (_) => _handleVerify(),
                      decoration: fieldDecoration(hintText: '••••••').copyWith(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      height: 43,
                      child: ElevatedButton(
                        onPressed: _isVerifying ? null : _handleVerify,
                        child: _isVerifying
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn),
                              )
                            : Text('Verify & Continue', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
                      ),
                    ),

                    if (canResend) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: _isResending ? null : _handleResend,
                          child: Text(
                            _isResending ? 'Sending...' : 'Resend SMS code',
                            style: sans(12, color: C.navy, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
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
