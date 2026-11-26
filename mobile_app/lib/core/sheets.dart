import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'models.dart';
import 'api.dart';
import 'icons.dart';
import 'widgets.dart';

class MaintenanceTemplate {
  final String label;
  final String status;
  final String text;
  const MaintenanceTemplate({
    required this.label,
    required this.status,
    required this.text,
  });
}

const List<MaintenanceTemplate> kMaintenanceTemplates = [
  MaintenanceTemplate(
    label: 'Technician Dispatched',
    status: 'in_progress',
    text: 'A technician has been dispatched to your unit to inspect and resolve this issue. Kindly ensure access to the suite.',
  ),
  MaintenanceTemplate(
    label: 'Inspection Scheduled',
    status: 'in_progress',
    text: 'Our maintenance team has reviewed your ticket and scheduled a quick inspection to assess the repair scope.',
  ),
  MaintenanceTemplate(
    label: 'Parts Ordered',
    status: 'in_progress',
    text: 'Replacement parts have been ordered for this repair. We will notify you as soon as installation is scheduled.',
  ),
  MaintenanceTemplate(
    label: 'Access Needed',
    status: 'in_progress',
    text: 'Our technician attempted to reach you regarding this repair. Kindly contact management to arrange unit access.',
  ),
  MaintenanceTemplate(
    label: 'Issue Resolved',
    status: 'resolved',
    text: 'The reported maintenance issue has been repaired and verified. Please let us know if anything further is needed.',
  ),
  MaintenanceTemplate(
    label: 'Checked & Normal',
    status: 'cancelled',
    text: 'We inspected the issue and confirmed everything is operating normally. Feel free to log a new ticket if it recurs.',
  ),
];

Widget _sheetHandle() {
  return Center(
    child: Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: C.border,
        borderRadius: BorderRadius.circular(99),
      ),
    ),
  );
}

Widget _detailRow(String label, String value, {bool isMono = false, Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: sans(11.5, color: C.textMuted)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: isMono
                ? mono(11.5, color: valueColor ?? C.textPrimary, weight: FontWeight.w600)
                : sans(12, color: valueColor ?? C.textPrimary, weight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// 1. Payment Receipt Details Sheet (Landlords can also Approve & Reconcile pending Paybill claims)
void showPaymentDetailsSheet(
  BuildContext context,
  TransactionModel tx, {
  bool isAdmin = false,
  List<TenantModel> tenants = const [],
  VoidCallback? onReconciled,
}) {
  TenantModel? selectedTenant;
  if (tenants.isNotEmpty) {
    selectedTenant = tenants.firstWhere(
      (t) => t.id == tx.tenantId || (tx.unitNumber != null && t.currentUnitNumber == tx.unitNumber),
      orElse: () => tenants.first,
    );
  }
  bool isApproving = false;
  String? errorMsg;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setMState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHandle(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Payment Receipt', style: flex(14.5, color: C.textPrimary)),
                  tx.reconciled
                      ? StatusPill.mint('Reconciled')
                      : StatusPill.amber(tx.statusDisplayLabel),
                ],
              ),
              const SizedBox(height: 14),
              if (tx.isPendingVerification && !isAdmin) ...[
                const InlineAlert(
                  message: 'Awaiting management verification. Your balance will update as soon as approved.',
                  isInfo: true,
                ),
                const SizedBox(height: 12),
              ],
              if (errorMsg != null) ...[
                InlineAlert(message: errorMsg!),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: C.cardSubtle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: C.border),
                ),
                child: Column(
                  children: [
                    _detailRow('Reference', tx.reference, isMono: true),
                    _detailRow(
                      'Amount',
                      'KES ${tx.amount.toLocaleString()}',
                      valueColor: tx.reconciled ? C.mintText : C.amberText,
                    ),
                    if (tx.tenantName != null && tx.tenantName!.isNotEmpty)
                      _detailRow('Resident', tx.tenantName!),
                    if (tx.unitNumber != null && tx.unitNumber!.isNotEmpty)
                      _detailRow('Unit', 'Unit ${tx.unitNumber}'),
                    _detailRow('Channel', formatPaymentMethodLabel(tx.method)),
                    _detailRow('Date', formatShortDate(tx.timestamp.isNotEmpty ? tx.timestamp : tx.date)),
                    if (tx.notes.isNotEmpty) _detailRow('Notes', tx.notes),
                  ],
                ),
              ),

              // Landlord Approval & Reconciliation for pending_verification / unassigned claims
              if (isAdmin && tx.needsApproval && tenants.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Credit To Resident', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  initialValue: selectedTenant?.id,
                  dropdownColor: C.surface,
                  isExpanded: true,
                  style: sans(12.5, color: C.textPrimary),
                  decoration: fieldDecoration(),
                  items: tenants
                      .map((t) => DropdownMenuItem(
                            value: t.id,
                            child: Text(
                              '${t.name}${t.currentUnitNumber.isNotEmpty ? " · Unit ${t.currentUnitNumber}" : ""}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (id) {
                    setMState(() {
                      selectedTenant = tenants.firstWhere((t) => t.id == id, orElse: () => tenants.first);
                    });
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 43,
                  child: ElevatedButton.icon(
                    onPressed: isApproving || selectedTenant == null
                        ? null
                        : () async {
                            setMState(() {
                              isApproving = true;
                              errorMsg = null;
                            });
                            final res = await ApiService.reconcileTransaction(
                              transactionId: tx.id,
                              tenantId: selectedTenant!.id,
                              unitId: selectedTenant!.currentUnitId,
                              notes: 'Verified & approved by management via mobile app',
                            );
                            if (!ctx.mounted) return;
                            setMState(() => isApproving = false);
                            if (res['success'] == true) {
                              Navigator.pop(ctx);
                              showAppSnackBar(
                                context,
                                'Payment ${tx.reference} verified & credited to ${selectedTenant!.name}.',
                              );
                              onReconciled?.call();
                            } else {
                              setMState(() => errorMsg = res['error']?.toString() ?? 'Verification failed.');
                            }
                          },
                    style: ElevatedButton.styleFrom(backgroundColor: C.mintText),
                    icon: isApproving
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const LapisIcon(LapisIconName.shieldCheck, size: 15, color: Colors.white),
                    label: Text(
                      isApproving ? 'Verifying...' : 'Approve & Reconcile Payment',
                      style: sans(12.5, color: Colors.white, weight: FontWeight.w600),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),
              SizedBox(
                height: 41,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Close', style: sans(12.5, color: C.textSecondary, weight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 2. Dual-Mode Resident Pay Rent Sheet (M-Pesa STK Push with Live Status Check + Paybill Manual)
void showStkPushSheet(
  BuildContext context, {
  required String defaultPhone,
  required int defaultAmount,
  required String unitNumber,
  String? tenantId,
  String? unitId,
  String? leaseId,
  String? payerName,
  VoidCallback? onComplete,
}) {
  final phoneCtrl = TextEditingController(text: extractKenyaNineDigits(defaultPhone));
  final amountCtrl = TextEditingController(
    text: defaultAmount > 0 ? defaultAmount.toString() : '',
  );
  final refCtrl = TextEditingController();
  final notesCtrl = TextEditingController(text: 'Monthly Rent Payment');

  String mode = 'stk'; // 'stk' | 'manual'
  int step = 0; // 0 = input, 1 = sending, 2 = awaiting PIN, 3 = confirmed
  bool isChecking = false;
  bool isSubmittingManual = false;
  bool isPendingVerification = false;
  String? errorMessage;
  String? infoMessage;
  String? receiptNumber;
  String checkoutId = '';
  String merchantId = '';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final paybill = ApiService.cachedSettings.paybillNumber.isNotEmpty
            ? ApiService.cachedSettings.paybillNumber
            : '542910';
        final acct = 'LAPIS-${unitNumber.isNotEmpty ? unitNumber : "UNIT"}';

        Future<void> handleCheckStatus() async {
          if (checkoutId.isEmpty && merchantId.isEmpty) return;
          setSheetState(() {
            isChecking = true;
            errorMessage = null;
          });
          final q = await ApiService.queryKcbStatus(
            checkoutRequestId: checkoutId,
            merchantRequestId: merchantId,
          );
          if (!ctx.mounted) return;
          setSheetState(() {
            isChecking = false;
            if (q['success'] == true) {
              step = 3;
              receiptNumber = q['receipt']?.toString();
              onComplete?.call();
            } else if (q['failed'] == true) {
              step = 0;
              errorMessage = q['resultDesc']?.toString().isNotEmpty == true
                  ? q['resultDesc'].toString()
                  : 'Transaction was cancelled or failed.';
            } else {
              infoMessage =
                  'Still waiting for M-Pesa confirmation. If you entered your PIN, tap Check Status again in a moment.';
            }
          });
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sheetHandle(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pay Rent', style: flex(15, color: C.textPrimary)),
                    StatusPill.blue(unitNumber.isNotEmpty ? 'Unit $unitNumber' : 'Resident'),
                  ],
                ),
                const SizedBox(height: 12),

                if (step == 0) ...[
                  // Mode switcher: STK Push vs Manual Paybill
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: C.borderLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: C.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setSheetState(() {
                              mode = 'stk';
                              errorMessage = null;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: mode == 'stk' ? C.navy : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'M-Pesa STK Push',
                                style: sans(
                                  11.5,
                                  color: mode == 'stk' ? Colors.white : C.textSecondary,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setSheetState(() {
                              mode = 'manual';
                              errorMessage = null;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: mode == 'manual' ? C.navy : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Paybill Manual',
                                style: sans(
                                  11.5,
                                  color: mode == 'manual' ? Colors.white : C.textSecondary,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (errorMessage != null) ...[
                    InlineAlert(message: errorMessage!),
                    const SizedBox(height: 12),
                  ],

                  if (mode == 'stk') ...[
                    Text('M-Pesa Number', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    KenyaPhoneField(controller: phoneCtrl),
                    const SizedBox(height: 12),

                    Text('Amount (KES)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: flex(15, color: C.textPrimary),
                      decoration: fieldDecoration(
                        hintText: 'Amount in KES',
                        prefixText: 'KES ',
                        prefixStyle: flex(14, color: C.mintText),
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      height: 43,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final nine = phoneCtrl.text.trim();
                          final amt = int.tryParse(amountCtrl.text.trim()) ?? 0;
                          if (nine.length != 9 || !(nine.startsWith('7') || nine.startsWith('1'))) {
                            setSheetState(() => errorMessage = 'Enter a valid 9-digit mobile number starting with 7 or 1.');
                            return;
                          }
                          if (amt <= 0) {
                            setSheetState(() => errorMessage = 'Enter a valid amount greater than 0.');
                            return;
                          }

                          setSheetState(() {
                            step = 1;
                            errorMessage = null;
                            infoMessage = null;
                          });

                          final res = await ApiService.initiateStkPush(
                            phoneNumber: nine,
                            amount: amt,
                            unitNumber: unitNumber,
                            tenantId: tenantId,
                            description: notesCtrl.text.trim(),
                          );

                          if (!ctx.mounted) return;
                          if (res['success'] == true) {
                            checkoutId = res['checkoutRequestId']?.toString() ?? '';
                            merchantId = res['merchantRequestId']?.toString() ?? '';
                            setSheetState(() => step = 2);

                            if (checkoutId.isNotEmpty) {
                              ApiService.waitForStkCallback(checkoutId).then((cb) {
                                if (!ctx.mounted) return;
                                setSheetState(() {
                                  if (cb['success'] == true) {
                                    step = 3;
                                    receiptNumber = cb['receipt']?.toString();
                                    onComplete?.call();
                                  } else if (cb['pending'] == true) {
                                    infoMessage = cb['resultDesc']?.toString() ??
                                        'Callback delayed. Tap "Check Status Now" to verify with M-Pesa.';
                                  } else {
                                    errorMessage = cb['resultDesc']?.toString() ??
                                        cb['error']?.toString() ??
                                        'Payment was cancelled or declined.';
                                    step = 0;
                                  }
                                });
                              });
                            }
                          } else {
                            setSheetState(() {
                              step = 0;
                              errorMessage = res['error']?.toString() ?? 'Could not send STK prompt.';
                            });
                          }
                        },
                        icon: const LapisIcon(LapisIconName.smartphone, size: 15, color: C.ctaOn),
                        label: Text('Send M-Pesa Prompt', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                      ),
                    ),
                  ] else ...[
                    // Paybill Instructions Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: C.blueBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: C.blueBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('PAYBILL NO.', style: sans(9.5, color: C.blueText, weight: FontWeight.w700, letterSpacing: 0.5)),
                                const SizedBox(height: 2),
                                Text(paybill, style: mono(14.5, color: C.navy, weight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ACCOUNT NO.', style: sans(9.5, color: C.blueText, weight: FontWeight.w700, letterSpacing: 0.5)),
                                const SizedBox(height: 2),
                                Text(acct, style: mono(14, color: C.navy, weight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    Text('Amount Paid (KES)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: flex(14.5, color: C.textPrimary),
                      decoration: fieldDecoration(
                        hintText: 'Amount in KES',
                        prefixText: 'KES ',
                        prefixStyle: flex(13.5, color: C.mintText),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Text('M-Pesa Transaction Code', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: refCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: mono(13, color: C.textPrimary, weight: FontWeight.w600),
                      decoration: fieldDecoration(hintText: 'e.g. QA12BC34DE'),
                    ),
                    const SizedBox(height: 12),

                    Text('Description', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: notesCtrl,
                      style: sans(12.5, color: C.textPrimary),
                      decoration: fieldDecoration(hintText: 'Monthly Rent Payment'),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      height: 43,
                      child: ElevatedButton.icon(
                        onPressed: isSubmittingManual
                            ? null
                            : () async {
                                final amt = int.tryParse(amountCtrl.text.trim()) ?? 0;
                                final ref = refCtrl.text.trim().toUpperCase();
                                if (amt <= 0) {
                                  setSheetState(() => errorMessage = 'Enter a valid amount greater than 0.');
                                  return;
                                }
                                if (ref.length < 5) {
                                  setSheetState(() => errorMessage = 'Enter a valid M-Pesa confirmation code.');
                                  return;
                                }

                                setSheetState(() {
                                  isSubmittingManual = true;
                                  errorMessage = null;
                                });

                                final res = await ApiService.recordManualPayment(
                                  tenantId: tenantId,
                                  unitId: unitId,
                                  leaseId: leaseId,
                                  unitNumber: unitNumber,
                                  amount: amt,
                                  reference: ref,
                                  notes: notesCtrl.text.trim(),
                                  phoneNumber: phoneCtrl.text.trim(),
                                  payerName: payerName,
                                );

                                if (!ctx.mounted) return;
                                setSheetState(() => isSubmittingManual = false);

                    if (res['success'] == true) {
                      setSheetState(() {
                        receiptNumber = ref;
                        isPendingVerification = res['pendingVerification'] == true;
                        step = 3;
                      });
                      onComplete?.call();
                    } else {
                      setSheetState(() => errorMessage = res['error']?.toString() ?? 'Could not record payment.');
                    }
                  },
                  icon: isSubmittingManual
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn),
                        )
                      : const LapisIcon(LapisIconName.shieldCheck, size: 15, color: C.ctaOn),
                  label: Text(
                    isSubmittingManual ? 'Submitting...' : 'Submit for Verification',
                    style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Manual Paybill codes are verified by management before crediting your rent balance.',
                textAlign: TextAlign.center,
                style: sans(10.5, color: C.textMuted),
              ),
            ],
          ] else if (step == 1) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  const CircularProgressIndicator(strokeWidth: 2.2, color: C.blueText),
                  const SizedBox(height: 14),
                  Text('Sending M-Pesa Prompt...', style: flex(13.5, color: C.textPrimary)),
                  const SizedBox(height: 4),
                  Text('Contacting KCB Buni payment gateway', style: sans(11.5, color: C.textMuted)),
                ],
              ),
            ),
          ] else if (step == 2) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(color: C.blueBg, shape: BoxShape.circle),
                      child: const Center(child: LapisIcon(LapisIconName.smartphone, size: 22, color: C.blueText)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enter M-Pesa PIN on +254${phoneCtrl.text}',
                    textAlign: TextAlign.center,
                    style: flex(14, color: C.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    infoMessage ?? 'Waiting for Safaricom callback confirmation...',
                    textAlign: TextAlign.center,
                    style: sans(11.5, color: C.textMuted),
                  ),
                  const SizedBox(height: 14),
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(99)),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      color: C.blueText,
                      backgroundColor: C.blueBg,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSheetState(() => step = 0),
                          child: Text('Back', style: sans(12, color: C.textSecondary, weight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: isChecking ? null : handleCheckStatus,
                          child: isChecking
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn),
                                )
                              : Text('Check Status Now', style: sans(12, color: C.ctaOn, weight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (step == 3) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isPendingVerification ? C.amberBg : C.mintBg,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: LapisIcon(
                          isPendingVerification ? LapisIconName.clock : LapisIconName.check,
                          size: 24,
                          color: isPendingVerification ? C.amberText : C.mintText,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isPendingVerification ? 'Submitted for Verification' : 'Payment Recorded & Reconciled',
                    textAlign: TextAlign.center,
                    style: flex(14.5, color: isPendingVerification ? C.amberText : C.mintText),
                  ),
                  if (isPendingVerification) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Management will verify your M-Pesa code and credit your balance shortly. You will be notified by SMS.',
                      textAlign: TextAlign.center,
                      style: sans(11.5, color: C.textMuted),
                    ),
                  ],
                  if (receiptNumber != null && receiptNumber!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: C.cardSubtle,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: C.border),
                        ),
                        child: Text('Ref: $receiptNumber', style: mono(12, color: C.textPrimary)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onComplete?.call();
                      },
                      child: Text('Done', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 3. Admin Collect Payment Sheet (Manual Record OR Admin OTP-Verified STK Push)
void showAdminCollectPaymentSheet(
  BuildContext context, {
  required List<TenantModel> tenants,
  TenantModel? initialTenant,
  VoidCallback? onComplete,
}) {
  if (tenants.isEmpty) {
    showAppSnackBar(context, 'No residents available to record payment for.', isError: true);
    return;
  }

  TenantModel selected = initialTenant ?? tenants.first;
  String mode = 'manual'; // 'manual' | 'admin_stk'
  final amountCtrl = TextEditingController(
    text: selected.effectiveBalanceDue > 0 ? selected.effectiveBalanceDue.toString() : '',
  );
  final phoneCtrl = TextEditingController(text: extractKenyaNineDigits(selected.phone));
  final refCtrl = TextEditingController();
  final notesCtrl = TextEditingController(text: 'Rent Payment');
  final otpCtrl = TextEditingController();

  bool otpSent = false;
  String challengeToken = '';
  String maskedAdminPhone = '';
  bool isLoading = false;
  String? errorMessage;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setMState) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sheetHandle(),
                Text('Collect / Record Payment', style: flex(15, color: C.textPrimary)),
                const SizedBox(height: 12),

                // Mode switcher
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: C.borderLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: C.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setMState(() {
                            mode = 'manual';
                            errorMessage = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: mode == 'manual' ? C.navy : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Record Payment',
                              style: sans(11.5, color: mode == 'manual' ? Colors.white : C.textSecondary, weight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setMState(() {
                            mode = 'admin_stk';
                            errorMessage = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: mode == 'admin_stk' ? C.navy : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Send STK Push (OTP)',
                              style: sans(11.5, color: mode == 'admin_stk' ? Colors.white : C.textSecondary, weight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (errorMessage != null) ...[
                  InlineAlert(message: errorMessage!),
                  const SizedBox(height: 12),
                ],

                Text('Resident', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  initialValue: selected.id,
                  dropdownColor: C.surface,
                  isExpanded: true,
                  style: sans(12.5, color: C.textPrimary),
                  decoration: fieldDecoration(),
                  items: tenants
                      .map((t) => DropdownMenuItem(
                            value: t.id,
                            child: Text(
                              '${t.name}${t.currentUnitNumber.isNotEmpty ? " · Unit ${t.currentUnitNumber}" : ""}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: otpSent
                      ? null
                      : (id) {
                          final found = tenants.firstWhere((t) => t.id == id, orElse: () => selected);
                          setMState(() {
                            selected = found;
                            phoneCtrl.text = extractKenyaNineDigits(found.phone);
                            if (found.effectiveBalanceDue > 0) {
                              amountCtrl.text = found.effectiveBalanceDue.toString();
                            }
                          });
                        },
                ),
                const SizedBox(height: 12),

                Text('Amount (KES)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: amountCtrl,
                  enabled: !otpSent,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: flex(14.5, color: C.textPrimary),
                  decoration: fieldDecoration(
                    hintText: 'Amount in KES',
                    prefixText: 'KES ',
                    prefixStyle: flex(13.5, color: C.mintText),
                  ),
                ),
                const SizedBox(height: 12),

                if (mode == 'manual') ...[
                  Text('M-Pesa / Receipt Reference', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  TextField(
                    controller: refCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: mono(12.5, color: C.textPrimary),
                    decoration: fieldDecoration(hintText: 'e.g. QK45XY89Z1'),
                  ),
                  const SizedBox(height: 12),

                  Text('Notes', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  TextField(
                    controller: notesCtrl,
                    style: sans(12.5, color: C.textPrimary),
                    decoration: fieldDecoration(hintText: 'Monthly rent payment'),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    height: 43,
                    child: ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : () async {
                              final amt = int.tryParse(amountCtrl.text.trim()) ?? 0;
                              if (amt <= 0) {
                                setMState(() => errorMessage = 'Enter a valid payment amount.');
                                return;
                              }
                              setMState(() {
                                isLoading = true;
                                errorMessage = null;
                              });
                              final res = await ApiService.recordManualPayment(
                                tenantId: selected.id,
                                unitId: selected.currentUnitId,
                                leaseId: selected.currentLeaseId,
                                unitNumber: selected.currentUnitNumber,
                                amount: amt,
                                reference: refCtrl.text.trim().isNotEmpty
                                    ? refCtrl.text.trim()
                                    : 'MP-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                                notes: notesCtrl.text.trim(),
                                phoneNumber: selected.phone,
                                payerName: selected.name,
                              );
                              if (!ctx.mounted) return;
                              setMState(() => isLoading = false);
                              if (res['success'] == true) {
                                Navigator.pop(ctx);
                                showAppSnackBar(context, 'Payment recorded & tenant notified via SMS.');
                                onComplete?.call();
                              } else {
                                setMState(() => errorMessage = res['error']?.toString() ?? 'Failed to record payment.');
                              }
                            },
                      child: isLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                          : Text('Save Payment', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                    ),
                  ),
                ] else ...[
                  Text('Resident M-Pesa Number', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  KenyaPhoneField(controller: phoneCtrl, enabled: !otpSent),
                  const SizedBox(height: 12),

                  if (!otpSent) ...[
                    const InlineAlert(
                      message: 'For security, a 6-digit SMS confirmation OTP will first be sent to your Admin phone number.',
                      isInfo: true,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 43,
                      child: ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                                final amt = int.tryParse(amountCtrl.text.trim()) ?? 0;
                                final nine = phoneCtrl.text.trim();
                                if (amt <= 0) {
                                  setMState(() => errorMessage = 'Enter a valid amount.');
                                  return;
                                }
                                if (nine.length != 9) {
                                  setMState(() => errorMessage = 'Enter a valid 9-digit resident phone number.');
                                  return;
                                }
                                setMState(() {
                                  isLoading = true;
                                  errorMessage = null;
                                });
                                final r = await ApiService.requestAdminStkOtp(
                                  amount: amt,
                                  unitNumber: selected.currentUnitNumber,
                                  tenantName: selected.name,
                                );
                                if (!ctx.mounted) return;
                                setMState(() {
                                  isLoading = false;
                                  if (r['success'] == true) {
                                    otpSent = true;
                                    challengeToken = r['challengeToken']?.toString() ?? '';
                                    maskedAdminPhone = r['maskedPhone']?.toString() ?? '';
                                  } else {
                                    errorMessage = r['error']?.toString() ?? 'Could not send admin OTP.';
                                  }
                                });
                              },
                        child: isLoading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                            : Text('Request Admin SMS OTP', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                      ),
                    ),
                  ] else ...[
                    InlineAlert(
                      message: 'Code sent to $maskedAdminPhone',
                      isSuccess: true,
                    ),
                    const SizedBox(height: 12),
                    Text('Admin OTP', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    OtpCodeInput(
                      controller: otpCtrl,
                      autoFocus: true,
                      autoListenSms: true,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 43,
                      child: ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                                final code = otpCtrl.text.trim();
                                final amt = int.tryParse(amountCtrl.text.trim()) ?? 0;
                                if (code.length != 6) {
                                  setMState(() => errorMessage = 'Enter the 6-digit OTP code.');
                                  return;
                                }
                                setMState(() {
                                  isLoading = true;
                                  errorMessage = null;
                                });
                                final r = await ApiService.verifyAndSendAdminStk(
                                  challengeToken: challengeToken,
                                  code: code,
                                  phoneNumber: phoneCtrl.text.trim(),
                                  amount: amt,
                                  unitNumber: selected.currentUnitNumber,
                                  tenantId: selected.id,
                                );
                                if (!ctx.mounted) return;
                                setMState(() => isLoading = false);
                                if (r['success'] == true) {
                                  Navigator.pop(ctx);
                                  showAppSnackBar(context, 'OTP verified! M-Pesa prompt sent to ${selected.name}.');
                                  onComplete?.call();
                                } else {
                                  setMState(() => errorMessage = r['error']?.toString() ?? 'OTP verification failed.');
                                }
                              },
                        child: isLoading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                            : Text('Verify OTP & Send STK Push', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 4. Maintenance Details & Admin Manage Sheet (with Quick SMS Templates for Landlords!)
void showMaintenanceDetailSheet(
  BuildContext context,
  MaintenanceTicket ticket, {
  bool isAdmin = false,
  VoidCallback? onUpdated,
}) {
  String status = ticket.status;
  final techCtrl = TextEditingController(text: ticket.assignedTo ?? '');
  final notesCtrl = TextEditingController(text: ticket.resolutionNotes ?? '');
  bool isSaving = false;
  String? errorMessage;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setMState) {
        final isResolved = ticket.status == 'resolved';
        final isInProgress = ticket.status == 'in_progress';

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sheetHandle(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ticket.title, style: flex(14.5, color: C.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                            'Ref #${ticket.id.length >= 6 ? ticket.id.substring(ticket.id.length - 6).toUpperCase() : ticket.id} · Unit ${ticket.unitNumber.isNotEmpty ? ticket.unitNumber : "Suite"}',
                            style: sans(11, color: C.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    isResolved
                        ? StatusPill.mint(formatStatusLabel(ticket.status))
                        : (isInProgress
                            ? StatusPill.blue(formatStatusLabel(ticket.status), hasDot: true)
                            : StatusPill.amber(formatStatusLabel(ticket.status))),
                  ],
                ),
                const SizedBox(height: 12),

                // Issue Description Card
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: C.cardSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: C.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ISSUE DESCRIPTION',
                        style: sans(9.5, color: C.textMuted, weight: FontWeight.w700, letterSpacing: 0.6),
                      ),
                      const SizedBox(height: 4),
                      Text(ticket.description, style: sans(12.5, color: C.textSecondary, height: 1.45)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          StatusPill.slate(formatCategoryLabel(ticket.category)),
                          ticket.priority == 'emergency'
                              ? StatusPill.rose('${formatPriorityLabel(ticket.priority)} Priority', hasDot: false)
                              : StatusPill.slate('${formatPriorityLabel(ticket.priority)} Priority'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Metadata Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: C.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: C.border),
                  ),
                  child: Column(
                    children: [
                      if (isAdmin) _detailRow('Resident', ticket.tenantName),
                      _detailRow('Reported On', formatShortDate(ticket.createdAt)),
                      _detailRow(
                        'Assigned Technician',
                        (ticket.assignedTo ?? '').isNotEmpty ? ticket.assignedTo! : 'Pending assignment',
                        valueColor: (ticket.assignedTo ?? '').isNotEmpty ? C.textPrimary : C.textMuted,
                      ),
                    ],
                  ),
                ),

                // Resident view: Management Update / Resolution Notes
                if (!isAdmin && (ticket.resolutionNotes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: isResolved ? C.mintBg : C.blueBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isResolved ? C.mintBorder : C.blueBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isResolved ? 'RESOLUTION NOTES' : 'LATEST UPDATE FROM MANAGEMENT',
                          style: sans(
                            9.5,
                            color: isResolved ? C.mintText : C.blueText,
                            weight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(ticket.resolutionNotes!, style: sans(12.5, color: C.textPrimary, height: 1.45)),
                      ],
                    ),
                  ),
                ],

                // Admin Management Controls + Quick SMS Templates (LOCKED once resolved!)
                if (isAdmin && isResolved) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: C.mintBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: C.mintBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RESOLVED & LOCKED',
                          style: sans(9.5, color: C.mintText, weight: FontWeight.w700, letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (ticket.resolutionNotes ?? '').isNotEmpty
                              ? ticket.resolutionNotes!
                              : 'This ticket is completed and locked from further changes.',
                          style: sans(12, color: C.textPrimary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 41,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Close', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                    ),
                  ),
                ] else if (isAdmin) ...[
                  const SizedBox(height: 14),
                  if (errorMessage != null) ...[
                    InlineAlert(message: errorMessage!),
                    const SizedBox(height: 12),
                  ],

                  Text('Ticket Status', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    dropdownColor: C.surface,
                    style: sans(12.5, color: C.textPrimary),
                    decoration: fieldDecoration(),
                    items: const [
                      DropdownMenuItem(value: 'pending', child: Text('Pending — Awaiting Dispatch')),
                      DropdownMenuItem(value: 'in_progress', child: Text('In Progress — Work Started (Sends SMS)')),
                      DropdownMenuItem(value: 'resolved', child: Text('Resolved — Done & Lock (Sends SMS)')),
                      DropdownMenuItem(value: 'cancelled', child: Text('Cancelled — Closed')),
                    ],
                    onChanged: (v) => setMState(() => status = v ?? 'pending'),
                  ),
                  const SizedBox(height: 12),

                  Text('Assigned Technician', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  TextField(
                    controller: techCtrl,
                    style: sans(12.5, color: C.textPrimary),
                    decoration: fieldDecoration(hintText: 'e.g. John Kamau Plumbing'),
                  ),
                  const SizedBox(height: 12),

                  Text('Quick Templates', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: kMaintenanceTemplates.map((tpl) {
                      final active = notesCtrl.text.trim() == tpl.text;
                      return GestureDetector(
                        onTap: () => setMState(() {
                          status = tpl.status;
                          notesCtrl.text = tpl.text;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: active ? C.navy : C.cardSubtle,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: active ? C.navy : C.border),
                          ),
                          child: Text(
                            tpl.label,
                            style: sans(11, color: active ? Colors.white : C.textSecondary, weight: FontWeight.w600),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  Text('Notes', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    style: sans(12.5, color: C.textPrimary),
                    decoration: fieldDecoration(hintText: 'Update note for resident...'),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    height: 43,
                    child: ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              setMState(() {
                                isSaving = true;
                                errorMessage = null;
                              });
                              final res = await ApiService.updateMaintenanceTicket(
                                ticket.id,
                                status: status,
                                assignedTo: techCtrl.text,
                                resolutionNotes: notesCtrl.text,
                              );
                              if (!ctx.mounted) return;
                              setMState(() => isSaving = false);
                              if (res['success'] == true) {
                                Navigator.pop(ctx);
                                showAppSnackBar(
                                  context,
                                  status == 'resolved'
                                      ? 'Ticket resolved, locked & SMS sent.'
                                      : 'Ticket updated.',
                                );
                                onUpdated?.call();
                              } else {
                                setMState(() => errorMessage = res['error']?.toString() ?? 'Update failed.');
                              }
                            },
                      child: isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                          : Text('Save Update', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 41,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Close', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 5. Create Maintenance Ticket Sheet (Works for BOTH Resident & Admin!)
void showCreateMaintenanceSheet(
  BuildContext context, {
  bool isAdmin = false,
  List<TenantModel> tenants = const [],
  String? unitNumber,
  String? unitId,
  VoidCallback? onCreated,
}) {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  String category = 'plumbing';
  String priority = 'medium';
  TenantModel? selectedTenant = tenants.isNotEmpty ? tenants.first : null;
  bool isSaving = false;
  String? errorMessage;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setMState) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sheetHandle(),
                Text(
                  isAdmin ? 'Log Maintenance Ticket' : 'Report Maintenance Issue',
                  style: flex(15, color: C.textPrimary),
                ),
                const SizedBox(height: 12),

                if (errorMessage != null) ...[
                  InlineAlert(message: errorMessage!),
                  const SizedBox(height: 12),
                ],

                if (isAdmin && tenants.isNotEmpty) ...[
                  Text('Resident / Unit', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTenant?.id,
                    dropdownColor: C.surface,
                    isExpanded: true,
                    style: sans(12.5, color: C.textPrimary),
                    decoration: fieldDecoration(),
                    items: tenants
                        .map((t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(
                                '${t.name}${t.currentUnitNumber.isNotEmpty ? " · Unit ${t.currentUnitNumber}" : ""}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (id) {
                      setMState(() {
                        selectedTenant = tenants.firstWhere((t) => t.id == id, orElse: () => tenants.first);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Category', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                          const SizedBox(height: 5),
                          DropdownButtonFormField<String>(
                            initialValue: category,
                            dropdownColor: C.surface,
                            isExpanded: true,
                            style: sans(12, color: C.textPrimary),
                            decoration: fieldDecoration(),
                            items: const [
                              DropdownMenuItem(value: 'plumbing', child: Text('Plumbing')),
                              DropdownMenuItem(value: 'electrical', child: Text('Electrical')),
                              DropdownMenuItem(value: 'hvac', child: Text('HVAC / AC')),
                              DropdownMenuItem(value: 'appliance', child: Text('Appliances')),
                              DropdownMenuItem(value: 'carpentry', child: Text('Carpentry')),
                              DropdownMenuItem(value: 'internet', child: Text('Internet')),
                              DropdownMenuItem(value: 'general', child: Text('General')),
                            ],
                            onChanged: (v) => setMState(() => category = v ?? 'general'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Priority', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                          const SizedBox(height: 5),
                          DropdownButtonFormField<String>(
                            initialValue: priority,
                            dropdownColor: C.surface,
                            isExpanded: true,
                            style: sans(12, color: C.textPrimary),
                            decoration: fieldDecoration(),
                            items: const [
                              DropdownMenuItem(value: 'low', child: Text('Low')),
                              DropdownMenuItem(value: 'medium', child: Text('Medium')),
                              DropdownMenuItem(value: 'high', child: Text('High')),
                              DropdownMenuItem(value: 'emergency', child: Text('Emergency')),
                            ],
                            onChanged: (v) => setMState(() => priority = v ?? 'medium'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Text('Issue Title', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: titleCtrl,
                  style: sans(12.5, color: C.textPrimary),
                  decoration: fieldDecoration(hintText: 'e.g. Kitchen sink tap leaking'),
                ),
                const SizedBox(height: 12),

                Text('Detailed Description', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  style: sans(12.5, color: C.textPrimary),
                  decoration: fieldDecoration(hintText: 'Describe the location and details...'),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  height: 43,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final title = titleCtrl.text.trim();
                            final desc = descCtrl.text.trim();
                            if (title.isEmpty) {
                              setMState(() => errorMessage = 'Please enter an issue title.');
                              return;
                            }
                            setMState(() {
                              isSaving = true;
                              errorMessage = null;
                            });
                            final res = await ApiService.createMaintenanceTicket(
                              title: title,
                              description: desc.isNotEmpty ? desc : title,
                              category: category,
                              priority: priority,
                              tenantId: isAdmin ? selectedTenant?.id : null,
                              unitNumber: isAdmin ? selectedTenant?.currentUnitNumber : unitNumber,
                              unitId: isAdmin ? selectedTenant?.currentUnitId : unitId,
                            );
                            if (!ctx.mounted) return;
                            setMState(() => isSaving = false);
                            if (res['success'] == true) {
                              Navigator.pop(ctx);
                              showAppSnackBar(
                                context,
                                isAdmin
                                    ? 'Ticket logged & resident notified via SMS.'
                                    : 'Maintenance request submitted.',
                              );
                              onCreated?.call();
                            } else {
                              setMState(() => errorMessage = res['error']?.toString() ?? 'Could not submit ticket.');
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                        : Text('Submit Ticket', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 6. Quick Create Unit Sheet (with proper validation & error reporting)
void showCreateUnitSheet(BuildContext context, {VoidCallback? onCreated}) {
  final unitCtrl = TextEditingController();
  String type = 'studio';
  bool isSaving = false;
  String? errorMessage;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setMState) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sheetHandle(),
                Text('Add New Unit', style: flex(15, color: C.textPrimary)),
                const SizedBox(height: 12),

                if (errorMessage != null) ...[
                  InlineAlert(message: errorMessage!),
                  const SizedBox(height: 12),
                ],

                Text('Unit Number', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: unitCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: mono(13, color: C.textPrimary),
                  decoration: fieldDecoration(hintText: 'e.g. 402B'),
                ),
                const SizedBox(height: 12),

                Text('Suite Type', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  dropdownColor: C.surface,
                  style: sans(12.5, color: C.textPrimary),
                  decoration: fieldDecoration(),
                  items: const [
                    DropdownMenuItem(value: 'studio', child: Text('Studio Suite')),
                    DropdownMenuItem(value: 'one-bedroom', child: Text('One-Bedroom')),
                    DropdownMenuItem(value: 'two-bedroom', child: Text('Two-Bedroom')),
                    DropdownMenuItem(value: 'penthouse-suite', child: Text('Penthouse Suite')),
                  ],
                  onChanged: (v) => setMState(() => type = v ?? 'studio'),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  height: 43,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final no = unitCtrl.text.trim();
                            if (no.isEmpty) {
                              setMState(() => errorMessage = 'Enter a unit number.');
                              return;
                            }
                            setMState(() {
                              isSaving = true;
                              errorMessage = null;
                            });
                            final res = await ApiService.createUnit(unitNumber: no, type: type);
                            if (!ctx.mounted) return;
                            setMState(() => isSaving = false);
                            if (res['success'] == true) {
                              Navigator.pop(ctx);
                              showAppSnackBar(context, 'Unit ${no.toUpperCase()} added.');
                              onCreated?.call();
                            } else {
                              setMState(() => errorMessage = res['error']?.toString() ?? 'Could not create unit.');
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                        : Text('Save Unit', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 7. Assign Lease to Vacant Unit Sheet
void showAssignLeaseSheet(
  BuildContext context, {
  required UnitModel unit,
  required List<TenantModel> tenants,
  VoidCallback? onAssigned,
}) {
  if (tenants.isEmpty) {
    showAppSnackBar(context, 'No residents available to assign.', isError: true);
    return;
  }

  TenantModel selectedTenant = tenants.first;
  final rentCtrl = TextEditingController(text: unit.monthlyRent.toString());
  final depCtrl = TextEditingController(text: unit.monthlyRent.toString());
  final now = DateTime.now();
  final nextYear = DateTime(now.year + 1, now.month, now.day);
  final startStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final endStr = '${nextYear.year}-${nextYear.month.toString().padLeft(2, '0')}-${nextYear.day.toString().padLeft(2, '0')}';
  bool isSaving = false;
  String? errorMessage;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setMState) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHandle(),
              Text('Assign Lease · Unit ${unit.unitNumber}', style: flex(15, color: C.textPrimary)),
              const SizedBox(height: 12),

              if (errorMessage != null) ...[
                InlineAlert(message: errorMessage!),
                const SizedBox(height: 12),
              ],

              Text('Select Resident', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              DropdownButtonFormField<String>(
                initialValue: selectedTenant.id,
                dropdownColor: C.surface,
                isExpanded: true,
                style: sans(12.5, color: C.textPrimary),
                decoration: fieldDecoration(),
                items: tenants
                    .map((t) => DropdownMenuItem(
                          value: t.id,
                          child: Text('${t.name} (${t.email})', overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (id) {
                  setMState(() {
                    selectedTenant = tenants.firstWhere((t) => t.id == id, orElse: () => tenants.first);
                  });
                },
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Monthly Rent', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                        const SizedBox(height: 5),
                        TextField(
                          controller: rentCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: sans(13, color: C.textPrimary, weight: FontWeight.w600),
                          decoration: fieldDecoration(prefixText: 'KES '),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Security Deposit', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                        const SizedBox(height: 5),
                        TextField(
                          controller: depCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: sans(13, color: C.textPrimary, weight: FontWeight.w600),
                          decoration: fieldDecoration(prefixText: 'KES '),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '12-month term: $startStr to $endStr',
                style: sans(11, color: C.textMuted),
              ),
              const SizedBox(height: 16),

              SizedBox(
                height: 43,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final rent = int.tryParse(rentCtrl.text.trim()) ?? 0;
                          final dep = int.tryParse(depCtrl.text.trim()) ?? 0;
                          if (rent <= 0) {
                            setMState(() => errorMessage = 'Enter a valid monthly rent.');
                            return;
                          }
                          setMState(() {
                            isSaving = true;
                            errorMessage = null;
                          });
                          final res = await ApiService.createLease(
                            tenantId: selectedTenant.id,
                            unitId: unit.id,
                            unitNumber: unit.unitNumber,
                            monthlyRent: rent,
                            depositAmount: dep,
                            startDate: startStr,
                            endDate: endStr,
                          );
                          if (!ctx.mounted) return;
                          setMState(() => isSaving = false);
                          if (res['success'] == true) {
                            Navigator.pop(ctx);
                            showAppSnackBar(context, 'Lease assigned to ${selectedTenant.name}.');
                            onAssigned?.call();
                          } else {
                            setMState(() => errorMessage = res['error']?.toString() ?? 'Could not assign lease.');
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                      : Text('Assign Lease', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 8. Unit Types CRUD Sheet (Protects occupied units from key / rent / delete DB corruption)
void showUnitTypesSheet(BuildContext context, {VoidCallback? onChanged}) {
  List<UnitTypeModel> types = [];
  bool isLoading = true;
  String? errorMsg;

  Future<void> load(StateSetter setMState) async {
    setMState(() {
      isLoading = true;
      errorMsg = null;
    });
    final res = await ApiService.fetchUnitTypes();
    setMState(() {
      isLoading = false;
      if (res['success'] == true) {
        types = (res['unitTypes'] as List<UnitTypeModel>?) ?? [];
      } else {
        errorMsg = res['error']?.toString() ?? 'Could not load unit types.';
      }
    });
  }

  void openEditor(BuildContext parentCtx, StateSetter setParentState, {UnitTypeModel? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final rentCtrl = TextEditingController(text: existing != null ? existing.baseRent.toString() : '');
    final depCtrl = TextEditingController(text: (existing?.depositMultiplier ?? 1).toString());
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final featuresCtrl = TextEditingController(text: (existing?.features ?? []).join(', '));
    final hasOccupied = existing?.hasOccupiedUnits ?? false;
    bool isSaving = false;
    String? err;

    showModalBottomSheet(
      context: parentCtx,
      isScrollControlled: true,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sheetHandle(),
                Text(existing == null ? 'New Unit Type' : 'Edit ${existing.name}', style: flex(15, color: C.textPrimary)),
                const SizedBox(height: 10),

                if (hasOccupied) ...[
                  InlineAlert(
                    message:
                        '${existing!.occupiedCount} unit(s) are occupied. Rent & deposit are locked to protect active leases.',
                    isInfo: true,
                  ),
                  const SizedBox(height: 10),
                ],
                if (err != null) ...[
                  InlineAlert(message: err!),
                  const SizedBox(height: 10),
                ],

                Text('Display Name', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: nameCtrl,
                  style: sans(12.5, color: C.textPrimary),
                  decoration: fieldDecoration(hintText: 'e.g. Executive Studio'),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Base Rent (KES)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                          const SizedBox(height: 5),
                          TextField(
                            controller: rentCtrl,
                            enabled: !hasOccupied,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: sans(12.5, color: hasOccupied ? C.textMuted : C.textPrimary, weight: FontWeight.w600),
                            decoration: fieldDecoration(hintText: '35000'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Deposit ×', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                          const SizedBox(height: 5),
                          TextField(
                            controller: depCtrl,
                            enabled: !hasOccupied,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: sans(12.5, color: hasOccupied ? C.textMuted : C.textPrimary, weight: FontWeight.w600),
                            decoration: fieldDecoration(hintText: '1'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Text('Description', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  style: sans(12.5, color: C.textPrimary),
                  decoration: fieldDecoration(hintText: 'Brief summary of this suite type'),
                ),
                const SizedBox(height: 12),

                Text('Features (comma separated)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: featuresCtrl,
                  style: sans(12.5, color: C.textPrimary),
                  decoration: fieldDecoration(hintText: 'Fibre Wi-Fi, Balcony, Parking'),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  height: 43,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            final rent = int.tryParse(rentCtrl.text.trim()) ?? 0;
                            final dep = int.tryParse(depCtrl.text.trim()) ?? 1;
                            if (name.isEmpty) {
                              setEState(() => err = 'Enter a display name.');
                              return;
                            }
                            if (rent <= 0) {
                              setEState(() => err = 'Enter a valid base monthly rent.');
                              return;
                            }
                            setEState(() {
                              isSaving = true;
                              err = null;
                            });
                            final res = await ApiService.saveUnitType(
                              id: existing?.id,
                              key: existing?.key,
                              name: name,
                              baseRent: rent,
                              depositMultiplier: dep,
                              description: descCtrl.text.trim(),
                              features: featuresCtrl.text
                                  .split(',')
                                  .map((e) => e.trim())
                                  .where((e) => e.isNotEmpty)
                                  .toList(),
                            );
                            if (!ctx.mounted) return;
                            setEState(() => isSaving = false);
                            if (res['success'] == true) {
                              Navigator.pop(ctx);
                              load(setParentState);
                              onChanged?.call();
                            } else {
                              setEState(() => err = res['error']?.toString() ?? 'Could not save unit type.');
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                        : Text(existing == null ? 'Create Type' : 'Save Changes', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool initialized = false;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setMState) {
        if (!initialized) {
          initialized = true;
          load(setMState);
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sheetHandle(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Unit Types', style: flex(15, color: C.textPrimary)),
                    GestureDetector(
                      onTap: () => openEditor(ctx, setMState),
                      child: StatusPill.blue('+ New Type', hasDot: false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (errorMsg != null) ...[
                  InlineAlert(message: errorMsg!),
                  const SizedBox(height: 10),
                ],

                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.navy)),
                  )
                else if (types.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No unit types configured.', style: sans(12, color: C.textMuted))),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: types.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final ut = types[i];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: C.cardSubtle,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: C.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            ut.name,
                                            style: sans(12.5, color: C.textPrimary, weight: FontWeight.w700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (ut.hasOccupiedUnits) ...[
                                          const SizedBox(width: 6),
                                          StatusPill.mint('${ut.occupiedCount} occupied', hasDot: false),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'KES ${ut.baseRent.toLocaleString()}/mo · ${ut.unitCount} unit${ut.unitCount == 1 ? '' : 's'}',
                                      style: sans(11, color: C.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit',
                                icon: const LapisIcon(LapisIconName.pencil, size: 16, color: C.navy),
                                onPressed: () => openEditor(ctx, setMState, existing: ut),
                              ),
                              if (!ut.hasAnyUnits)
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const LapisIcon(LapisIconName.trash, size: 16, color: C.roseText),
                                  onPressed: () async {
                                    final res = await ApiService.deleteUnitType(ut.id);
                                    if (!ctx.mounted) return;
                                    if (res['success'] == true) {
                                      load(setMState);
                                      onChanged?.call();
                                    } else {
                                      setMState(() => errorMsg = res['error']?.toString() ?? 'Could not delete.');
                                    }
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
