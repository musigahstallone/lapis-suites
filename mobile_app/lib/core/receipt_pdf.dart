import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'api.dart';
import 'models.dart';
import 'widgets.dart';

class ReceiptPdfService {
  static Future<void> sharePaymentReceipt(
    TransactionModel tx, {
    String? unitTypeLabel,
  }) async {
    final doc = pw.Document();
    final settings = ApiService.cachedSettings;
    final paybill = settings.paybillNumber.isNotEmpty ? settings.paybillNumber : '522533';
    final accountNo = settings.accountNumber.isNotEmpty ? settings.accountNumber : '8107578';
    final recipientName = settings.paybillRecipientName.isNotEmpty
        ? settings.paybillRecipientName
        : 'LAPIS APARTMENTS LIMITED';
    final propertyName = settings.propertyName.isNotEmpty ? settings.propertyName : 'Lapis Suites';

    final residentName = (tx.tenantName != null && tx.tenantName!.trim().isNotEmpty)
        ? tx.tenantName!.trim()
        : ((tx.payerName != null && tx.payerName!.trim().isNotEmpty) ? tx.payerName!.trim() : 'Resident');

    final rawUnit = (tx.unitNumber ?? '').trim();
    final cleanType = (unitTypeLabel ?? '').trim();
    final unitRef = rawUnit.isNotEmpty
        ? (cleanType.isNotEmpty ? 'Unit $rawUnit - ${formatUnitTypeLabel(cleanType)}' : 'Unit $rawUnit')
        : 'General';

    final dateTimeLabel = formatDateTimeDisplay(tx.timestamp.isNotEmpty ? tx.timestamp : tx.date);
    final channelLabel = formatPaymentMethodLabel(tx.method);
    final navy = PdfColor.fromHex('#111B35');
    final slate = PdfColor.fromHex('#64748B');
    final border = PdfColor.fromHex('#E2E8F0');
    final surface = PdfColor.fromHex('#F8FAFC');
    final emerald = PdfColor.fromHex('#059669');
    final amber = PdfColor.fromHex('#B45309');

    pw.Widget rowItem(String label, String value, {bool isMono = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 7),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 10.5, color: slate)),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Text(
                value,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 11,
                  color: navy,
                  fontWeight: pw.FontWeight.bold,
                  font: isMono ? pw.Font.courierBold() : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Branded Navy Header
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: navy,
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          propertyName.toUpperCase(),
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Official Rent Payment Receipt',
                          style: pw.TextStyle(
                            color: PdfColor.fromHex('#CBD5E1'),
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'AMOUNT PAID',
                          style: pw.TextStyle(
                            color: PdfColor.fromHex('#94A3B8'),
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'KES ${tx.amount.toLocaleString()}',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Resident Name Banner
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('RESIDENT', style: pw.TextStyle(fontSize: 8.5, color: slate, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text(residentName, style: pw.TextStyle(fontSize: 13.5, color: navy, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Text(
                    tx.reconciled ? 'VERIFIED' : 'PENDING REVIEW',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: tx.reconciled ? emerald : amber,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),

              // Core Details Card
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: surface,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: border),
                ),
                child: pw.Column(
                  children: [
                    rowItem('M-Pesa Receipt', tx.reference, isMono: true),
                    pw.Divider(height: 1, color: border),
                    rowItem('Date & Time', dateTimeLabel),
                    pw.Divider(height: 1, color: border),
                    rowItem('Payment Channel', channelLabel),
                    pw.Divider(height: 1, color: border),
                    rowItem('Unit Reference', unitRef),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Official Payment Account & Anti-Fraud Footer
              pw.Container(
                padding: const pw.EdgeInsets.all(11),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#FFFBEB'),
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColor.fromHex('#FDE68A')),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'OFFICIAL PAYMENT DETAILS: PAY BILL $paybill | ACCOUNT NO: $accountNo ($recipientName)',
                      style: pw.TextStyle(fontSize: 8.5, color: navy, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'NB: To avoid fraud and losing money, DO NOT pay rent to any other account or to any personal numbers.',
                      style: pw.TextStyle(fontSize: 8.5, color: amber, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Divider(color: border),
              pw.SizedBox(height: 4),
              pw.Text(
                'Generated electronically by $propertyName Property Management System.',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8.5, color: slate),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final safeRef = tx.reference.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final file = File('${dir.path}/Lapis_Receipt_${safeRef.isNotEmpty ? safeRef : tx.id}.pdf');
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Lapis Suites Receipt - ${tx.reference}',
        text: 'Official Lapis Suites rent receipt for $residentName (KES ${tx.amount.toLocaleString()}, Ref: ${tx.reference}).',
      ),
    );
  }
}
