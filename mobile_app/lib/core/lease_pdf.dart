import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'api.dart';
import 'models.dart';
import 'widgets.dart';

class LeasePdfService {
  static Future<void> shareLeaseAgreement(
    LeaseModel lease, {
    TenantModel? tenant,
  }) async {
    final doc = pw.Document();
    final settings = ApiService.cachedSettings;

    final propertyName =
        settings.propertyName.isNotEmpty ? settings.propertyName : 'Lapis Suites';
    final landlordCompany = settings.paybillRecipientName.isNotEmpty
        ? settings.paybillRecipientName
        : 'LAPIS APARTMENTS LIMITED';
    final paybill =
        settings.paybillNumber.isNotEmpty ? settings.paybillNumber : '522533';
    final accountNo =
        settings.accountNumber.isNotEmpty ? settings.accountNumber : '8107578';
    final rentDueDay = settings.rentDueDay > 0 ? settings.rentDueDay : 5;
    final contactEmail = settings.contactEmail.isNotEmpty
        ? settings.contactEmail
        : 'lapissuites@gmail.com';
    final contactPhone = settings.contactPhone.isNotEmpty
        ? settings.contactPhone
        : '+254 797 204 141';
    final address =
        settings.address.isNotEmpty ? settings.address : 'Nairobi, Kenya';

    final residentName = (tenant?.name.isNotEmpty == true)
        ? tenant!.name
        : (lease.tenantName.isNotEmpty ? lease.tenantName : 'Resident');
    final residentId =
        (tenant?.nationalId.isNotEmpty == true) ? tenant!.nationalId : 'On file';
    final residentPhone =
        (tenant?.phone.isNotEmpty == true) ? tenant!.phone : 'On file';
    final residentEmail =
        (tenant?.email.isNotEmpty == true) ? tenant!.email : 'On file';
    final unitTypeLabel = formatUnitTypeLabel(lease.unitType);
    final depositStatus =
        lease.isDepositSettled ? 'Verified Paid' : 'Pending Settlement';
    final issueDate = formatShortDate(DateTime.now().toIso8601String());

    final navy = PdfColor.fromHex('#111B35');
    final emerald = PdfColor.fromHex('#059669');
    final amber = PdfColor.fromHex('#B45309');
    final amberBg = PdfColor.fromHex('#FFFBEB');
    final amberBorder = PdfColor.fromHex('#FDE68A');
    final textDark = PdfColor.fromHex('#172033');
    final slate = PdfColor.fromHex('#64748B');
    final surface = PdfColor.fromHex('#F8FAFC');
    final border = PdfColor.fromHex('#E2E8F0');

    pw.Widget scheduleCell(String label, String value) {
      return pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8, color: slate),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 9.5,
                color: textDark,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget clauseBlock(String number, String title, String body) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '$number. $title',
              style: pw.TextStyle(
                fontSize: 9.8,
                color: navy,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              body,
              style: pw.TextStyle(
                fontSize: 8.9,
                color: textDark,
                lineSpacing: 2.2,
              ),
            ),
          ],
        ),
      );
    }

    final customTerms = lease.terms.trim();
    final governingBody = customTerms.isNotEmpty
        ? 'Special Notes on File: $customTerms\n\nThis Agreement constitutes the entire understanding between the parties regarding Unit ${lease.unitNumber} and shall be governed by and construed in accordance with the Laws of the Republic of Kenya.'
        : 'This Agreement constitutes the entire understanding between the parties regarding Unit ${lease.unitNumber} and shall be governed by and construed in accordance with the Laws of the Republic of Kenya.';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 30),
        footer: (pw.Context ctx) => pw.Column(
          children: [
            pw.Divider(color: border, thickness: 0.7),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '$propertyName · Lease ${lease.leaseNumber} · Unit ${lease.unitNumber} · Laws of Kenya',
                  style: pw.TextStyle(fontSize: 8, color: slate),
                ),
                pw.Text(
                  'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: slate),
                ),
              ],
            ),
          ],
        ),
        build: (pw.Context ctx) => [
          // 1. Branded Header
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: navy,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        propertyName.toUpperCase(),
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 15,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Managed by $landlordCompany',
                        style: pw.TextStyle(
                          color: PdfColor.fromHex('#CBD5E1'),
                          fontSize: 8.8,
                        ),
                      ),
                      pw.Text(
                        '$address · $contactEmail · $contactPhone',
                        style: pw.TextStyle(
                          color: PdfColor.fromHex('#94A3B8'),
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: emerald,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'TENANCY AGREEMENT',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Ref: ${lease.leaseNumber}',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 8,
                          font: pw.Font.courierBold(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 14),
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  'RESIDENTIAL TENANCY AGREEMENT',
                  style: pw.TextStyle(
                    fontSize: 13,
                    color: navy,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Made under the Laws of the Republic of Kenya · Issued $issueDate',
                  style: pw.TextStyle(fontSize: 8.5, color: slate),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 12),

          // 2. Landlord & Tenant Cards
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(11),
                  decoration: pw.BoxDecoration(
                    color: surface,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: border),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'THE LANDLORD',
                        style: pw.TextStyle(
                          fontSize: 7.8,
                          color: emerald,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        landlordCompany,
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: navy,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text('Property: $propertyName', style: pw.TextStyle(fontSize: 8.4, color: slate)),
                      pw.Text('Location: $address', style: pw.TextStyle(fontSize: 8.4, color: slate)),
                      pw.Text('Email: $contactEmail', style: pw.TextStyle(fontSize: 8.4, color: slate)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(11),
                  decoration: pw.BoxDecoration(
                    color: surface,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: border),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'THE TENANT (RESIDENT)',
                        style: pw.TextStyle(
                          fontSize: 7.8,
                          color: emerald,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        residentName,
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: navy,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text('ID / Passport: $residentId', style: pw.TextStyle(fontSize: 8.4, color: slate)),
                      pw.Text('Phone: $residentPhone', style: pw.TextStyle(fontSize: 8.4, color: slate)),
                      pw.Text('Email: $residentEmail', style: pw.TextStyle(fontSize: 8.4, color: slate)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 12),

          // 3. Schedule of Tenancy Particulars
          pw.Container(
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: border),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: navy,
                    borderRadius: const pw.BorderRadius.only(
                      topLeft: pw.Radius.circular(5),
                      topRight: pw.Radius.circular(5),
                    ),
                  ),
                  child: pw.Text(
                    'SCHEDULE OF TENANCY PARTICULARS',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 8.2,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(11),
                  child: pw.Column(
                    children: [
                      pw.Row(
                        children: [
                          scheduleCell('Demised Premises', 'Unit ${lease.unitNumber} ($unitTypeLabel)'),
                          scheduleCell('Agreement Reference', lease.leaseNumber),
                        ],
                      ),
                      pw.SizedBox(height: 8),
                      pw.Row(
                        children: [
                          scheduleCell('Commencement Date', formatShortDate(lease.startDate)),
                          scheduleCell('Expiry Date', formatShortDate(lease.endDate)),
                        ],
                      ),
                      pw.SizedBox(height: 8),
                      pw.Row(
                        children: [
                          scheduleCell('Monthly Rent', 'KES ${lease.monthlyRent.toLocaleString()} / month'),
                          scheduleCell('Rent Due Day', 'Day $rentDueDay of each month'),
                        ],
                      ),
                      pw.SizedBox(height: 8),
                      pw.Row(
                        children: [
                          scheduleCell('Security Deposit', 'KES ${lease.depositAmount.toLocaleString()}'),
                          scheduleCell('Deposit Status', depositStatus),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 11),

          // 4. Official Payment Details & Anti-Fraud Box
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: amberBg,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: amberBorder),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'OFFICIAL PAYMENT CHANNEL: M-PESA PAY BILL $paybill | ACCOUNT NO: $accountNo ($landlordCompany)',
                  style: pw.TextStyle(fontSize: 8.4, color: navy, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'You will receive a confirmation message that you sent payment to $landlordCompany.',
                  style: pw.TextStyle(fontSize: 8.1, color: textDark),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'NB: To avoid fraud and losing money, DO NOT pay rent to any other account or to any personal numbers.',
                  style: pw.TextStyle(fontSize: 8.1, color: amber, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 14),

          // 5. Legal Clauses
          clauseBlock(
            '1',
            'DEMISED PREMISES & PERMITTED USE',
            'The Landlord lets and the Tenant takes residential Unit ${lease.unitNumber} ($unitTypeLabel) situated at $propertyName, $address, together with standard fixtures and fittings. The premises shall be used strictly as a private residential dwelling. The Tenant shall not sublet, assign, part with possession, or carry on any commercial or unlawful business without the Landlord\'s prior written consent.',
          ),
          clauseBlock(
            '2',
            'TERM & RENEWAL',
            'This Tenancy commences on ${formatShortDate(lease.startDate)} and expires on ${formatShortDate(lease.endDate)}, unless earlier terminated under Clause 7. Any holding over with the Landlord\'s consent shall renew month-to-month on the same terms, subject to at least thirty (30) days written notice for any rent review.',
          ),
          clauseBlock(
            '3',
            'RENT & PAYMENT TERMS',
            'The agreed monthly rent is KES ${lease.monthlyRent.toLocaleString()}, payable strictly in advance on or before Day $rentDueDay of each calendar month exclusively via M-Pesa Pay Bill $paybill, Account Number $accountNo ($landlordCompany), or via verified STK Push in the $propertyName App. Payments are reconciled strictly to Lease ${lease.leaseNumber} (Unit ${lease.unitNumber}).',
          ),
          clauseBlock(
            '4',
            'SECURITY DEPOSIT',
            'The Tenant shall maintain a refundable Security Deposit of KES ${lease.depositAmount.toLocaleString()} ($depositStatus) held against unpaid rent, utility arrears, lost keys/access cards, or damage beyond fair wear and tear. The deposit may NOT be offset against the final month\'s rent without written consent. The balance is refunded within thirty (30) days after vacant possession and joint move-out inspection.',
          ),
          clauseBlock(
            '5',
            'UTILITIES, REPAIRS & MAINTENANCE',
            'The Tenant shall punctually settle all separately metered utilities (electricity, water, internet) and keep the interior clean and tenantable. The Landlord shall maintain the building structure and common areas. Any defect shall be reported promptly through the $propertyName Resident Portal.',
          ),
          clauseBlock(
            '6',
            'HOUSE RULES & QUIET ENJOYMENT',
            'The Tenant covenants to comply with the $propertyName Resident Handbook, including quiet hours (10:00 PM – 6:00 AM), proper waste disposal, authorized parking, and refraining from structural alterations or nuisance. Subject to punctual payment of rent and compliance, the Landlord guarantees peaceful enjoyment of Unit ${lease.unitNumber}.',
          ),
          clauseBlock(
            '7',
            'TERMINATION & NOTICE PERIOD',
            'Either party may terminate this Agreement by giving at least one (1) full calendar month\'s written notice prior to the intended vacate date. Failure to give requisite notice renders one month\'s rent in lieu of notice recoverable. Persistent arrears beyond fourteen (14) days or uncured material breach entitles the Landlord to pursue lawful termination and re-entry under Kenyan law.',
          ),
          clauseBlock('8', 'SPECIAL COVENANTS & GOVERNING LAW', governingBody),

          pw.SizedBox(height: 10),
          pw.Divider(color: navy, thickness: 1),
          pw.SizedBox(height: 6),
          pw.Text(
            'IN WITNESS WHEREOF the parties have executed this Residential Tenancy Agreement:',
            style: pw.TextStyle(fontSize: 9, color: navy, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),

          // 6. Execution Block
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: surface,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: border),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FOR & ON BEHALF OF LANDLORD',
                        style: pw.TextStyle(fontSize: 8, color: navy, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(landlordCompany, style: pw.TextStyle(fontSize: 8.5, color: textDark)),
                      pw.SizedBox(height: 14),
                      pw.Text('Sign: ___________________________', style: pw.TextStyle(fontSize: 8.2, color: slate)),
                      pw.SizedBox(height: 8),
                      pw.Text('Name / Title: ___________________', style: pw.TextStyle(fontSize: 8.2, color: slate)),
                      pw.SizedBox(height: 8),
                      pw.Text('Date & Stamp: __________________', style: pw.TextStyle(fontSize: 8.2, color: slate)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: surface,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: border),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'SIGNED BY THE TENANT (RESIDENT)',
                        style: pw.TextStyle(fontSize: 8, color: navy, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text('$residentName (ID: $residentId)', style: pw.TextStyle(fontSize: 8.5, color: textDark)),
                      pw.SizedBox(height: 14),
                      pw.Text('Sign: ___________________________', style: pw.TextStyle(fontSize: 8.2, color: slate)),
                      pw.SizedBox(height: 8),
                      pw.Text('Witness: ________________________', style: pw.TextStyle(fontSize: 8.2, color: slate)),
                      pw.SizedBox(height: 8),
                      pw.Text('Date: ___________________________', style: pw.TextStyle(fontSize: 8.2, color: slate)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final safeRef = lease.leaseNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final safeUnit = lease.unitNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final file = File(
      '${dir.path}/Lapis_Suites_Tenancy_Agreement_Unit_${safeUnit}_${safeRef.isNotEmpty ? safeRef : lease.id}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Lapis Suites Tenancy Agreement - Unit ${lease.unitNumber} (${lease.leaseNumber})',
        text: 'Residential Tenancy Agreement for $residentName — Unit ${lease.unitNumber} (${lease.leaseNumber}).',
      ),
    );
  }
}
