import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              Text('Unable to Load Data', style: flex(14, color: C.textPrimary)),
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
                  label: Text('Try Again', style: sans(12, color: C.ctaOn, weight: FontWeight.w600)),
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

/// Executive Portfolio Hero Card (Lapis Navy)
class OrbixOverviewCard extends StatelessWidget {
  final String title;
  final String period;
  final String heroLabel;
  final String heroValue;
  final List<MetricItem> metrics;
  final Widget? extraAction;

  const OrbixOverviewCard({
    super.key,
    required this.title,
    required this.period,
    required this.heroLabel,
    required this.heroValue,
    required this.metrics,
    this.extraAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [C.navy, C.navyHover],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.navyBorder),
        boxShadow: [
          BoxShadow(
            color: C.navy.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 4),
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
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
          const SizedBox(height: 12),
          Text(
            heroLabel.toUpperCase(),
            style: sans(9.5, color: const Color(0xFF94A3B8), weight: FontWeight.w600, letterSpacing: 0.6),
          ),
          const SizedBox(height: 3),
          Text(
            heroValue,
            style: flex(
              20,
              color: Colors.white,
              weight: FontWeight.w700,
              letterSpacing: -0.4,
              fontFeatures: kTabularNums,
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          Row(
            children: metrics.map((m) {
              return Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.label,
                      style: sans(10, color: const Color(0xFF94A3B8), weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.value,
                      style: flex(12, color: Colors.white, weight: FontWeight.w700, fontFeatures: kTabularNums),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class MetricItem {
  final String label;
  final String value;
  const MetricItem(this.label, this.value);
}

/// Compact, fintech-grade card-row list tile using Lucide SVG vector icons (zero `▯` glyphs)
class OrbixListTile extends StatelessWidget {
  final LapisIconName icon;
  final Color? iconColor;
  final Color? iconBg;
  final bool circularIcon;
  final String title;
  final String subtitle;
  final String amount;
  final String? amountPrefix;
  final Color? amountColor;
  final bool isMonoTitle;
  final Widget? status;
  final VoidCallback? onTap;

  const OrbixListTile({
    super.key,
    required this.icon,
    this.iconColor,
    this.iconBg,
    this.circularIcon = false,
    required this.title,
    required this.subtitle,
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
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconBg ?? C.cardSubtle,
                    shape: circularIcon ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: circularIcon ? null : BorderRadius.circular(9),
                    border: circularIcon ? null : Border.all(color: C.borderLight),
                  ),
                  child: Center(
                    child: LapisIcon(icon, size: 15, color: iconColor ?? C.textSecondary),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: isMonoTitle
                            ? mono(12, color: C.textPrimary, weight: FontWeight.w600, letterSpacing: 0.35)
                            : sans(12.5, color: C.textPrimary, weight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: sans(11, color: C.textMuted, fontFeatures: kTabularNums),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
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
                                color: C.textMuted,
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
            ),
          ),
        ),
      ),
    );
  }
}

/// Clean Minimalist Bottom Navigation Bar (NO gray pill box behind active icon!)
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
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
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
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LapisIcon(
                          item.icon,
                          size: 19,
                          color: color,
                          strokeWidth: isSelected ? 2.1 : 1.75,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
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
