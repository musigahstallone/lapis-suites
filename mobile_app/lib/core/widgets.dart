import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_auth/smart_auth.dart';
import 'theme.dart';
import 'models.dart';
import 'icons.dart';

/// Shared tabular-nums font feature for fintech currency, dates & references
const List<FontFeature> kTabularNums = [FontFeature.tabularFigures()];

/// Show crisp floating feedback toast (success or error)
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: isError ? C.roseText : C.navy,
      content: Row(
        children: [
          LapisIcon(
            isError ? LapisIconName.alertTriangle : LapisIconName.checkCircle,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: sans(12, color: Colors.white, weight: FontWeight.w500),
            ),
          ),
        ],
      ),
      duration: Duration(seconds: isError ? 4 : 3),
    ),
  );
}

/// Compact inline alert banner (error / success / info)
class InlineAlert extends StatelessWidget {
  final String message;
  final bool isSuccess;
  final bool isInfo;

  const InlineAlert({
    super.key,
    required this.message,
    this.isSuccess = false,
    this.isInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isSuccess ? C.mintBg : (isInfo ? C.navySoftBg : C.roseBg);
    final border = isSuccess ? C.mintBorder : (isInfo ? C.navySoftBorder : C.roseBorder);
    final fg = isSuccess ? C.mintText : (isInfo ? C.navy : C.roseText);
    final icon = isSuccess
        ? LapisIconName.checkCircle
        : (isInfo ? LapisIconName.info : LapisIconName.alertTriangle);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: LapisIcon(icon, size: 14, color: fg),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: sans(11.5, color: fg, weight: FontWeight.w500, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean retryable error state panel
class ErrorStateCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorStateCard({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(color: C.roseBg, shape: BoxShape.circle),
                child: const Center(
                  child: LapisIcon(LapisIconName.wifiOff, size: 18, color: C.roseText),
                ),
              ),
              const SizedBox(height: 12),
              Text('Connection issue', style: flex(14, color: C.textPrimary)),
              const SizedBox(height: 4),
              Text(
                message,
                style: sans(11.5, color: C.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 38,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const LapisIcon(LapisIconName.refresh, size: 14, color: C.ctaOn),
                  label: Text('Retry', style: sans(12, color: C.ctaOn, weight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed +254 Kenyan Phone Input (accepts strictly 9 digits starting with 7 or 1)
class KenyaPhoneField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const KenyaPhoneField({
    super.key,
    required this.controller,
    this.hintText = '712345678',
    this.enabled = true,
    this.onChanged,
  });

  @override
  State<KenyaPhoneField> createState() => _KenyaPhoneFieldState();
}

class _KenyaPhoneFieldState extends State<KenyaPhoneField> {
  @override
  void initState() {
    super.initState();
    final cleaned = extractKenyaNineDigits(widget.controller.text);
    if (cleaned != widget.controller.text) {
      widget.controller.text = cleaned;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.enabled ? C.cardSubtle : C.borderLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
            decoration: const BoxDecoration(
              color: C.borderLight,
              borderRadius: BorderRadius.horizontal(left: Radius.circular(9)),
              border: Border(right: BorderSide(color: C.border)),
            ),
            child: Text(
              '+254',
              style: mono(12.5, color: C.textPrimary, weight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              enabled: widget.enabled,
              keyboardType: TextInputType.phone,
              style: mono(12.5, color: C.textPrimary, weight: FontWeight.w600),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: mono(12.5, color: C.textSoft, weight: FontWeight.w400),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 6-Box Segmented OTP Input with automatic Android SMS OTP Detection (Google SMS User Consent API + Autofill)
class OtpCodeInput extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final bool autoFocus;
  final bool autoListenSms;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  const OtpCodeInput({
    super.key,
    required this.controller,
    this.length = 6,
    this.autoFocus = true,
    this.autoListenSms = true,
    this.onChanged,
    this.onCompleted,
  });

  @override
  State<OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<OtpCodeInput> {
  final FocusNode _focusNode = FocusNode();
  bool _isListeningSms = false;
  bool _smsAutoFilled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChange);
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.autoListenSms) {
      _startSmsDetection();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChange);
    _focusNode.dispose();
    if (_isListeningSms) {
      try {
        SmartAuth.instance.removeUserConsentApiListener();
      } catch (_) {}
    }
    super.dispose();
  }

  void _onTextChange() {
    if (mounted) setState(() {});
  }

  Future<void> _startSmsDetection() async {
    bool isAndroid = false;
    try {
      isAndroid = Platform.isAndroid;
    } catch (_) {
      return;
    }
    if (!isAndroid) return;

    try {
      setState(() => _isListeningSms = true);
      final res = await SmartAuth.instance.getSmsWithUserConsentApi(
        matcher: r'\d{6}',
      );
      if (!mounted) return;
      setState(() => _isListeningSms = false);
      if (res.hasData && res.data?.code != null && res.data!.code!.length == widget.length) {
        final code = res.data!.code!;
        widget.controller.text = code;
        widget.controller.selection = TextSelection.collapsed(offset: code.length);
        setState(() => _smsAutoFilled = true);
        widget.onChanged?.call(code);
        widget.onCompleted?.call(code);
      }
    } catch (_) {
      if (mounted) setState(() => _isListeningSms = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Hidden native TextField supporting paste, keyboard autofillHints.oneTimeCode, and backspace
              Opacity(
                opacity: 0.0,
                child: SizedBox(
                  height: 52,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    autofocus: widget.autoFocus,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    enableSuggestions: false,
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(widget.length),
                    ],
                    onChanged: (val) {
                      widget.onChanged?.call(val);
                      if (val.length == widget.length) {
                        widget.onCompleted?.call(val);
                      }
                    },
                  ),
                ),
              ),
              // 6 Crisp Rounded OTP Boxes
              IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(widget.length, (i) {
                    final char = i < text.length ? text[i] : '';
                    final isCurrent = _focusNode.hasFocus &&
                        (i == text.length || (text.length == widget.length && i == widget.length - 1));
                    final isFilled = char.isNotEmpty;

                    return Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        height: 52,
                        margin: EdgeInsets.only(right: i == widget.length - 1 ? 0 : 8),
                        decoration: BoxDecoration(
                          color: isFilled ? C.surface : C.canvas,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? C.navy
                                : (isFilled ? C.navy.withValues(alpha: 0.35) : C.border),
                            width: isCurrent ? 1.8 : 1.1,
                          ),
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: C.navy.withValues(alpha: 0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          char,
                          style: mono(20, color: C.navy, weight: FontWeight.w700),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        if (_smsAutoFilled) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const LapisIcon(LapisIconName.checkCircle, size: 12, color: C.mintText),
              const SizedBox(width: 5),
              Text('SMS code auto-filled', style: sans(11, color: C.mintText, weight: FontWeight.w600)),
            ],
          ),
        ] else if (_isListeningSms) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const LapisIcon(LapisIconName.smartphone, size: 12, color: C.textMuted),
              const SizedBox(width: 5),
              Text('Auto-detecting SMS code...', style: sans(11, color: C.textMuted)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Executive Status Pill Badge (strict 3-color palette)
class StatusPill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final Color? border;
  final bool hasDot;
  final LapisIconName? icon;

  const StatusPill({
    super.key,
    required this.text,
    required this.bg,
    required this.fg,
    this.border,
    this.hasDot = true,
    this.icon,
  });

  factory StatusPill.mint(String text, {LapisIconName? icon, bool hasDot = true}) => StatusPill(
        text: text,
        bg: C.mintBg,
        fg: C.mintText,
        border: C.mintBorder.withValues(alpha: 0.7),
        hasDot: hasDot,
        icon: icon,
      );

  factory StatusPill.blue(String text, {LapisIconName? icon, bool hasDot = false}) => StatusPill(
        text: text,
        bg: C.navySoftBg,
        fg: C.navy,
        border: C.navySoftBorder,
        hasDot: hasDot,
        icon: icon,
      );

  factory StatusPill.amber(String text, {LapisIconName? icon, bool hasDot = true}) => StatusPill(
        text: text,
        bg: C.amberBg,
        fg: C.amberText,
        border: C.amberBorder,
        hasDot: hasDot,
        icon: icon,
      );

  factory StatusPill.rose(String text, {LapisIconName? icon, bool hasDot = true}) => StatusPill(
        text: text,
        bg: C.roseBg,
        fg: C.roseText,
        border: C.roseBorder,
        hasDot: hasDot,
        icon: icon,
      );

  factory StatusPill.slate(String text, {LapisIconName? icon, bool hasDot = false}) => StatusPill(
        text: text,
        bg: C.borderLight,
        fg: C.textSecondary,
        border: C.border,
        hasDot: hasDot,
        icon: icon,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: border ?? fg.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            LapisIcon(icon!, size: 10, color: fg),
            const SizedBox(width: 4),
          ] else if (hasDot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: sans(10.5, color: fg, weight: FontWeight.w600, height: 1.1),
          ),
        ],
      ),
    );
  }
}

/// Executive Portfolio Hero Card (Lapis Navy + Tabular Precision + Collection Progress Bar)
class OrbixOverviewCard extends StatelessWidget {
  final String title;
  final String period;
  final String heroLabel;
  final String heroValue;
  final String? heroPrefix;
  final List<MetricItem> metrics;
  final Widget? extraAction;
  final double? collectionProgress;
  final int? collectedAmount;
  final int? expectedAmount;

  const OrbixOverviewCard({
    super.key,
    required this.title,
    required this.period,
    required this.heroLabel,
    required this.heroValue,
    this.heroPrefix,
    required this.metrics,
    this.extraAction,
    this.collectionProgress,
    this.collectedAmount,
    this.expectedAmount,
  });

  @override
  Widget build(BuildContext context) {
    final pct = ((collectionProgress ?? 0) * 100).round();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [C.navy, C.navyHover],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.navyBorder),
        boxShadow: [
          BoxShadow(
            color: C.navy.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(title, style: flex(12.5, color: Colors.white, weight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      period,
                      style: sans(10, color: const Color(0xFF94A3B8), weight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              ?extraAction,
            ],
          ),
          const SizedBox(height: 14),
          Text(
            heroLabel.toUpperCase(),
            style: sans(9.5, color: const Color(0xFF94A3B8), weight: FontWeight.w600, letterSpacing: 0.65),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (heroPrefix != null) ...[
                Text(
                  heroPrefix!,
                  style: sans(
                    12.5,
                    color: Colors.white.withValues(alpha: 0.65),
                    weight: FontWeight.w500,
                    fontFeatures: kTabularNums,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                heroValue,
                style: flex(
                  24,
                  color: Colors.white,
                  weight: FontWeight.w700,
                  letterSpacing: -0.5,
                  fontFeatures: kTabularNums,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          // Responsive 2x2 metrics grid so exact unrounded KES figures never squeeze or clip on narrow phones
          Column(
            children: [
              for (int rowStart = 0; rowStart < metrics.length; rowStart += 2) ...[
                if (rowStart > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    for (int idx = rowStart; idx < rowStart + 2 && idx < metrics.length; idx++)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              metrics[idx].label,
                              style: sans(10, color: const Color(0xFF94A3B8), weight: FontWeight.w500),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                if (metrics[idx].prefix != null) ...[
                                  Text(
                                    metrics[idx].prefix!,
                                    style: sans(
                                      9.5,
                                      color: Colors.white.withValues(alpha: 0.62),
                                      weight: FontWeight.w500,
                                      fontFeatures: kTabularNums,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    metrics[idx].value,
                                    style: flex(
                                      13,
                                      color: Colors.white,
                                      weight: FontWeight.w700,
                                      fontFeatures: kTabularNums,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          if (collectionProgress != null && expectedAmount != null) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Collected KES ${(collectedAmount ?? 0).toLocaleString()} of KES ${expectedAmount!.toLocaleString()}',
                  style: sans(
                    10.5,
                    color: Colors.white.withValues(alpha: 0.72),
                    weight: FontWeight.w500,
                    fontFeatures: kTabularNums,
                  ),
                ),
                Text(
                  '$pct%',
                  style: sans(
                    10.5,
                    color: const Color(0xFF34D399),
                    weight: FontWeight.w700,
                    fontFeatures: kTabularNums,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: collectionProgress!.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MetricItem {
  final String label;
  final String value;
  final String? prefix;
  final int flex;
  const MetricItem(this.label, this.value, {this.prefix, this.flex = 1});
}

/// Compact, fintech-grade card-row list tile using Lucide SVG vector icons (zero `▯` glyphs)
class OrbixListTile extends StatelessWidget {
  final LapisIconName? icon;
  final Color? iconColor;
  final Color? iconBg;
  final bool circularIcon;
  final Widget? leadingOverride;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final String amount;
  final String? amountPrefix;
  final Color? amountColor;
  final bool isMonoTitle;
  final Widget? status;
  final VoidCallback? onTap;

  const OrbixListTile({
    super.key,
    this.icon,
    this.iconColor,
    this.iconBg,
    this.circularIcon = false,
    this.leadingOverride,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    required this.amount,
    this.amountPrefix,
    this.amountColor,
    this.isMonoTitle = false,
    this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: C.navy.withValues(alpha: 0.04),
          highlightColor: C.navy.withValues(alpha: 0.025),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.border.withValues(alpha: 0.75)),
            ),
            child: Row(
              children: [
                if (leadingOverride != null) ...[
                  leadingOverride!,
                  const SizedBox(width: 11),
                ] else if (icon != null) ...[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconBg ?? C.cardSubtle,
                      shape: circularIcon ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: circularIcon ? null : BorderRadius.circular(10),
                      border: circularIcon ? null : Border.all(color: C.borderLight),
                    ),
                    child: Center(
                      child: LapisIcon(icon!, size: 16, color: iconColor ?? C.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 11),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: isMonoTitle
                            ? mono(12, color: C.textPrimary, weight: FontWeight.w600, letterSpacing: 0.35)
                            : sans(13, color: C.textPrimary, weight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitleWidget != null) ...[
                        const SizedBox(height: 3),
                        subtitleWidget!,
                      ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: sans(11.5, color: C.textMuted, fontFeatures: kTabularNums),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (amount.isNotEmpty || status != null) ...[
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (amount.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            if (amountPrefix != null) ...[
                              Text(
                                amountPrefix!,
                                style: sans(
                                  10,
                                  color: C.textMuted.withValues(alpha: 0.8),
                                  weight: FontWeight.w500,
                                  fontFeatures: kTabularNums,
                                ),
                              ),
                              const SizedBox(width: 3),
                            ],
                            Text(
                              amount,
                              style: flex(
                                13,
                                color: amountColor ?? C.textPrimary,
                                weight: FontWeight.w700,
                                fontFeatures: kTabularNums,
                              ),
                            ),
                          ],
                        ),
                      if (status != null) ...[
                        if (amount.isNotEmpty) const SizedBox(height: 4),
                        status!,
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Clean Minimalist Bottom Navigation Bar — filled active icons, NO gray box highlight
class OrbixBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavItem> items;

  const OrbixBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        border: Border(top: BorderSide(color: C.border.withValues(alpha: 0.8), width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: items.asMap().entries.map((e) {
              final idx = e.key;
              final item = e.value;
              final isSelected = idx == currentIndex;
              final color = isSelected ? C.navy : C.textMuted;

              return Expanded(
                child: InkWell(
                  onTap: () => onTap(idx),
                  borderRadius: BorderRadius.circular(10),
                  splashColor: C.navy.withValues(alpha: 0.05),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LapisIcon(
                          item.icon,
                          size: 20,
                          color: color,
                          strokeWidth: isSelected ? 2.0 : 1.7,
                          filled: isSelected,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(
                            10.5,
                            color: color,
                            weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class BottomNavItem {
  final LapisIconName icon;
  final String label;
  const BottomNavItem(this.icon, this.label);
}

extension NumberFormatting on int {
  String toK() {
    if (this >= 1000000) return '${(this / 1000000).toStringAsFixed(1)}M';
    if (this >= 1000) return '${(this / 1000).toStringAsFixed(0)}k';
    return toString();
  }

  String toLocaleString() {
    final s = toString();
    final regExp = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(regExp, (match) => ',');
  }
}
