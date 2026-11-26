import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Crisp Lucide-style 24x24 vector SVG icons drawn natively with CustomPainter.
/// Immune to Flutter icon-font tree-shaking and missing-glyph (`▯`) bugs across all Android/iOS builds.
enum LapisIconName {
  smartphone,
  wallet,
  arrowDownLeft,
  receipt,
  bell,
  user,
  home,
  creditCard,
  wrench,
  plus,
  chevronRight,
  chevronLeft,
  chevronDown,
  chevronUp,
  check,
  checkCircle,
  clock,
  alertTriangle,
  info,
  refresh,
  shieldCheck,
  building,
  fileText,
  logOut,
  pencil,
  trash,
  eye,
  eyeOff,
  wifiOff,
  send,
  userPlus,
}

class LapisIcon extends StatelessWidget {
  final LapisIconName name;
  final double size;
  final Color color;
  final double strokeWidth;

  const LapisIcon(
    this.name, {
    super.key,
    this.size = 18,
    this.color = const Color(0xFF172033),
    this.strokeWidth = 1.85,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LucidePainter(
          name: name,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _LucidePainter extends CustomPainter {
  final LapisIconName name;
  final Color color;
  final double strokeWidth;

  const _LucidePainter({
    required this.name,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;
    canvas.save();
    canvas.scale(sx, sy);

    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (name) {
      case LapisIconName.smartphone:
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(5, 2, 14, 20), const Radius.circular(2.5)),
          p,
        );
        canvas.drawLine(const Offset(12, 18), const Offset(12.01, 18), p..strokeWidth = 2.2);
        break;

      case LapisIconName.wallet:
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(3, 6, 18, 14), const Radius.circular(2.5)),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(5, 6)
            ..lineTo(17, 3)
            ..lineTo(18, 6),
          p,
        );
        canvas.drawCircle(const Offset(16.5, 13), 1.3, fill);
        break;

      case LapisIconName.arrowDownLeft:
        canvas.drawLine(const Offset(17, 7), const Offset(7, 17), p);
        canvas.drawPath(
          Path()
            ..moveTo(16, 17)
            ..lineTo(7, 17)
            ..lineTo(7, 8),
          p,
        );
        break;

      case LapisIconName.receipt:
        canvas.drawPath(
          Path()
            ..moveTo(4, 3)
            ..lineTo(20, 3)
            ..lineTo(20, 21)
            ..lineTo(17, 19)
            ..lineTo(14, 21)
            ..lineTo(12, 19)
            ..lineTo(10, 21)
            ..lineTo(7, 19)
            ..lineTo(4, 21)
            ..close(),
          p,
        );
        canvas.drawLine(const Offset(8, 8), const Offset(16, 8), p);
        canvas.drawLine(const Offset(8, 12), const Offset(16, 12), p);
        canvas.drawLine(const Offset(8, 16), const Offset(12, 16), p);
        break;

      case LapisIconName.bell:
        canvas.drawPath(
          Path()
            ..moveTo(6, 8)
            ..arcToPoint(const Offset(18, 8), radius: const Radius.circular(6))
            ..cubicTo(18, 14.5, 20, 16, 21, 17)
            ..lineTo(3, 17)
            ..cubicTo(4, 16, 6, 14.5, 6, 8),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(10.3, 21)
            ..arcToPoint(const Offset(13.7, 21), radius: const Radius.circular(2), clockwise: false),
          p,
        );
        break;

      case LapisIconName.user:
        canvas.drawCircle(const Offset(12, 8), 4, p);
        canvas.drawPath(
          Path()
            ..moveTo(5, 20)
            ..arcToPoint(const Offset(19, 20), radius: const Radius.circular(7)),
          p,
        );
        break;

      case LapisIconName.home:
        canvas.drawPath(
          Path()
            ..moveTo(3, 10.5)
            ..lineTo(12, 3)
            ..lineTo(21, 10.5)
            ..lineTo(21, 20)
            ..quadraticBezierTo(21, 21, 20, 21)
            ..lineTo(4, 21)
            ..quadraticBezierTo(3, 21, 3, 20)
            ..close(),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(9, 21)
            ..lineTo(9, 13)
            ..lineTo(15, 13)
            ..lineTo(15, 21),
          p,
        );
        break;

      case LapisIconName.creditCard:
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(2.5, 5, 19, 14), const Radius.circular(2.5)),
          p,
        );
        canvas.drawLine(const Offset(2.5, 10), const Offset(21.5, 10), p);
        canvas.drawLine(const Offset(6, 15), const Offset(10, 15), p);
        break;

      case LapisIconName.wrench:
        canvas.drawPath(
          Path()
            ..moveTo(14.7, 6.3)
            ..arcToPoint(const Offset(17.7, 9.3), radius: const Radius.circular(4.2), largeArc: true, clockwise: false)
            ..lineTo(8.2, 18.8)
            ..arcToPoint(const Offset(5.2, 15.8), radius: const Radius.circular(2.1))
            ..close(),
          p,
        );
        break;

      case LapisIconName.plus:
        canvas.drawLine(const Offset(12, 5), const Offset(12, 19), p);
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), p);
        break;

      case LapisIconName.chevronRight:
        canvas.drawPath(Path()..moveTo(9, 6)..lineTo(15, 12)..lineTo(9, 18), p);
        break;

      case LapisIconName.chevronLeft:
        canvas.drawPath(Path()..moveTo(15, 6)..lineTo(9, 12)..lineTo(15, 18), p);
        break;

      case LapisIconName.chevronDown:
        canvas.drawPath(Path()..moveTo(6, 9)..lineTo(12, 15)..lineTo(18, 9), p);
        break;

      case LapisIconName.chevronUp:
        canvas.drawPath(Path()..moveTo(6, 15)..lineTo(12, 9)..lineTo(18, 15), p);
        break;

      case LapisIconName.check:
        canvas.drawPath(Path()..moveTo(5, 13)..lineTo(9.5, 17.5)..lineTo(19, 7.5), p);
        break;

      case LapisIconName.checkCircle:
        canvas.drawCircle(const Offset(12, 12), 9, p);
        canvas.drawPath(Path()..moveTo(8.5, 12.2)..lineTo(11, 14.8)..lineTo(15.8, 9.5), p);
        break;

      case LapisIconName.clock:
        canvas.drawCircle(const Offset(12, 12), 9, p);
        canvas.drawPath(Path()..moveTo(12, 7)..lineTo(12, 12)..lineTo(15.5, 14), p);
        break;

      case LapisIconName.alertTriangle:
        canvas.drawPath(
          Path()
            ..moveTo(10.3, 4.2)
            ..lineTo(2.6, 17.8)
            ..quadraticBezierTo(1.8, 19.3, 3.4, 20)
            ..lineTo(20.6, 20)
            ..quadraticBezierTo(22.2, 19.3, 21.4, 17.8)
            ..lineTo(13.7, 4.2)
            ..quadraticBezierTo(12, 2.5, 10.3, 4.2),
          p,
        );
        canvas.drawLine(const Offset(12, 9.5), const Offset(12, 13.5), p);
        canvas.drawCircle(const Offset(12, 16.7), 1.0, fill);
        break;

      case LapisIconName.info:
        canvas.drawCircle(const Offset(12, 12), 9, p);
        canvas.drawLine(const Offset(12, 11.5), const Offset(12, 16), p);
        canvas.drawCircle(const Offset(12, 8.2), 1.0, fill);
        break;

      case LapisIconName.refresh:
        canvas.drawArc(const Rect.fromLTWH(4, 4, 16, 16), -math.pi * 0.25, math.pi * 1.5, false, p);
        canvas.drawPath(Path()..moveTo(17, 4)..lineTo(20, 7)..lineTo(16.5, 8.5), p);
        break;

      case LapisIconName.shieldCheck:
        canvas.drawPath(
          Path()
            ..moveTo(12, 2.5)
            ..lineTo(19.5, 5.8)
            ..lineTo(19.5, 11.5)
            ..cubicTo(19.5, 16.5, 16.2, 19.8, 12, 21.5)
            ..cubicTo(7.8, 19.8, 4.5, 16.5, 4.5, 11.5)
            ..lineTo(4.5, 5.8)
            ..close(),
          p,
        );
        canvas.drawPath(Path()..moveTo(9, 12.2)..lineTo(11.2, 14.4)..lineTo(15.5, 9.8), p);
        break;

      case LapisIconName.building:
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(4, 3, 16, 18), const Radius.circular(2)),
          p,
        );
        canvas.drawLine(const Offset(9, 7), const Offset(9.01, 7), p..strokeWidth = 2.2);
        canvas.drawLine(const Offset(15, 7), const Offset(15.01, 7), p..strokeWidth = 2.2);
        canvas.drawLine(const Offset(9, 11.5), const Offset(9.01, 11.5), p..strokeWidth = 2.2);
        canvas.drawLine(const Offset(15, 11.5), const Offset(15.01, 11.5), p..strokeWidth = 2.2);
        p.strokeWidth = strokeWidth;
        canvas.drawPath(Path()..moveTo(9.5, 21)..lineTo(9.5, 16.5)..lineTo(14.5, 16.5)..lineTo(14.5, 21), p);
        break;

      case LapisIconName.fileText:
        canvas.drawPath(
          Path()
            ..moveTo(6, 3)
            ..lineTo(14, 3)
            ..lineTo(19, 8)
            ..lineTo(19, 21)
            ..lineTo(6, 21)
            ..close(),
          p,
        );
        canvas.drawPath(Path()..moveTo(14, 3)..lineTo(14, 8)..lineTo(19, 8), p);
        canvas.drawLine(const Offset(9, 12.5), const Offset(15.5, 12.5), p);
        canvas.drawLine(const Offset(9, 16), const Offset(15.5, 16), p);
        break;

      case LapisIconName.logOut:
        canvas.drawPath(
          Path()
            ..moveTo(9, 21)
            ..lineTo(5, 21)
            ..quadraticBezierTo(4, 21, 4, 20)
            ..lineTo(4, 4)
            ..quadraticBezierTo(4, 3, 5, 3)
            ..lineTo(9, 3),
          p,
        );
        canvas.drawPath(Path()..moveTo(16, 17)..lineTo(21, 12)..lineTo(16, 7), p);
        canvas.drawLine(const Offset(21, 12), const Offset(9, 12), p);
        break;

      case LapisIconName.pencil:
        canvas.drawPath(
          Path()
            ..moveTo(16.5, 3.5)
            ..lineTo(20.5, 7.5)
            ..lineTo(8, 20)
            ..lineTo(4, 20)
            ..lineTo(4, 16)
            ..close(),
          p,
        );
        break;

      case LapisIconName.trash:
        canvas.drawLine(const Offset(3, 6), const Offset(21, 6), p);
        canvas.drawPath(Path()..moveTo(8, 6)..lineTo(9, 3.5)..lineTo(15, 3.5)..lineTo(16, 6), p);
        canvas.drawPath(
          Path()
            ..moveTo(5.5, 6)
            ..lineTo(6.5, 20)
            ..quadraticBezierTo(6.6, 21, 7.6, 21)
            ..lineTo(16.4, 21)
            ..quadraticBezierTo(17.4, 21, 17.5, 20)
            ..lineTo(18.5, 6),
          p,
        );
        break;

      case LapisIconName.eye:
        canvas.drawPath(
          Path()
            ..moveTo(2, 12)
            ..cubicTo(5, 6.5, 19, 6.5, 22, 12)
            ..cubicTo(19, 17.5, 5, 17.5, 2, 12)
            ..close(),
          p,
        );
        canvas.drawCircle(const Offset(12, 12), 2.8, p);
        break;

      case LapisIconName.eyeOff:
        canvas.drawPath(
          Path()
            ..moveTo(3, 12)
            ..cubicTo(6, 7.2, 18, 7.2, 21, 12)
            ..cubicTo(18, 16.8, 6, 16.8, 3, 12),
          p,
        );
        canvas.drawLine(const Offset(3, 3), const Offset(21, 21), p);
        break;

      case LapisIconName.wifiOff:
        canvas.drawArc(const Rect.fromLTWH(3, 6, 18, 14), -math.pi * 0.8, math.pi * 0.6, false, p);
        canvas.drawArc(const Rect.fromLTWH(7, 10, 10, 8), -math.pi * 0.8, math.pi * 0.6, false, p);
        canvas.drawCircle(const Offset(12, 18.5), 1.1, fill);
        canvas.drawLine(const Offset(3, 3), const Offset(21, 21), p);
        break;

      case LapisIconName.send:
        canvas.drawPath(
          Path()
            ..moveTo(21, 3)
            ..lineTo(10, 14)
            ..moveTo(21, 3)
            ..lineTo(14.5, 21)
            ..lineTo(10, 14)
            ..lineTo(3, 9.5)
            ..close(),
          p,
        );
        break;

      case LapisIconName.userPlus:
        canvas.drawCircle(const Offset(9.5, 8), 3.6, p);
        canvas.drawPath(
          Path()
            ..moveTo(3.5, 20)
            ..arcToPoint(const Offset(15.5, 20), radius: const Radius.circular(6)),
          p,
        );
        canvas.drawLine(const Offset(19, 8), const Offset(19, 14), p);
        canvas.drawLine(const Offset(16, 11), const Offset(22, 11), p);
        break;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LucidePainter oldDelegate) =>
      oldDelegate.name != name ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
