import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/api.dart';
import '../core/icons.dart';
import '../core/widgets.dart';
import '../core/crud_sheets.dart';
import '../core/lease_pdf.dart';

class LeaseDetailsPage extends StatefulWidget {
  final LeaseModel lease;
  final TenantModel? tenant;
  final List<UnitModel> vacantUnits;

  const LeaseDetailsPage({
    super.key,
    required this.lease,
    this.tenant,
    this.vacantUnits = const [],
  });

  @override
  State<LeaseDetailsPage> createState() => _LeaseDetailsPageState();
}

class _LeaseDetailsPageState extends State<LeaseDetailsPage> {
  late LeaseModel _lease;
  bool _generatingPdf = false;

  @override
  void initState() {
    super.initState();
    _lease = widget.lease;
  }

  Future<void> _reloadLease() async {
    final fresh = await ApiService.fetchLeaseById(_lease.id);
    if (fresh != null && mounted) {
      setState(() => _lease = fresh);
    }
  }

  Future<void> _downloadAgreementPdf() async {
    if (_generatingPdf) return;
    setState(() => _generatingPdf = true);
    try {
      await LeasePdfService.shareLeaseAgreement(_lease, tenant: widget.tenant);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not prepare agreement PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _handleTerminate() async {
    showMoveOutSettlementSheet(
      context,
      lease: _lease,
      onTerminated: () {
        if (mounted) Navigator.pop(context, true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = _lease;
    final isAdmin = ApiService.isLandlord;
    final settings = ApiService.cachedSettings;
    final paybill = settings.paybillNumber.isNotEmpty ? settings.paybillNumber : '522533';
    final accountNo = settings.accountNumber.isNotEmpty ? settings.accountNumber : '8107578';
    final recipient = settings.paybillRecipientName.isNotEmpty
        ? settings.paybillRecipientName
        : 'LAPIS APARTMENTS LIMITED';
    final dueDay = settings.rentDueDay > 0 ? settings.rentDueDay : 5;

    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.surface,
        elevation: 0,
        leading: IconButton(
          icon: const LapisIcon(LapisIconName.chevronLeft, size: 19, color: C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Lease · Unit ${l.unitNumber}', style: flex(15, color: C.textPrimary)),
        actions: [
          if (l.isActive && isAdmin)
            IconButton(
              tooltip: 'Edit Lease',
              icon: const LapisIcon(LapisIconName.pencil, size: 17, color: C.textSecondary),
              onPressed: () => showAmendLeaseSheet(
                context,
                lease: l,
                onAmended: _reloadLease,
              ),
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: C.borderLight),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.border.withValues(alpha: 0.75)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l.leaseNumber, style: mono(13.5, color: C.textPrimary, weight: FontWeight.w700)),
                    l.isActive
                        ? StatusPill.mint(formatStatusLabel(l.status))
                        : StatusPill.slate(formatStatusLabel(l.status)),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: C.borderLight),
                const SizedBox(height: 8),
                _item('Landlord', recipient),
                _item('Resident', l.tenantName),
                _item('Unit', 'Unit ${l.unitNumber} · ${formatUnitTypeLabel(l.unitType)}'),
                _item('Monthly Rent', 'KES ${l.monthlyRent.toLocaleString()}'),
                _item(
                  'Deposit',
                  'KES ${l.depositAmount.toLocaleString()} · ${l.isDepositSettled ? "Paid" : "Pending"}',
                ),
                _item(
                  'Term',
                  l.endDate.trim().isNotEmpty
                      ? '${formatShortDate(l.startDate)} – ${formatShortDate(l.endDate)}'
                      : 'From ${formatShortDate(l.startDate)} · Ongoing',
                ),
                _item('Next Due', formatShortDate(l.nextPaymentDueDate)),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Prominent Formal Tenancy Agreement PDF Download / Share Action
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _generatingPdf ? null : _downloadAgreementPdf,
              style: ElevatedButton.styleFrom(
                backgroundColor: C.navy,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _generatingPdf
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const LapisIcon(LapisIconName.fileText, size: 16, color: Colors.white),
              label: Text(
                _generatingPdf ? 'Preparing Agreement PDF...' : 'Download / Share Tenancy Agreement PDF',
                style: sans(12.5, color: Colors.white, weight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Formal Tenancy Clauses Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.border.withValues(alpha: 0.75)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Key Tenancy Clauses', style: flex(13.5, color: C.textPrimary)),
                const SizedBox(height: 10),
                _clause(
                  '1. Rent Only & Official Payment Channel',
                  'KES ${l.monthlyRent.toLocaleString()} payable in advance on or before Day $dueDay of each month strictly via M-Pesa Pay Bill $paybill, Account $accountNo ($recipient). Landlord collects rent & security deposit only — water and electricity are settled directly by the resident with utility providers.',
                ),
                _clause(
                  '2. Refundable Security Deposit',
                  'KES ${l.depositAmount.toLocaleString()} (${l.isDepositSettled ? "Verified Paid" : "Pending"}) held against unpaid rent or damages beyond fair wear and tear; refunded within 30 days after move-out inspection.',
                ),
                _clause(
                  '3. Notice Period & Conduct',
                  'Minimum 1 full calendar month written notice required prior to vacating. Strictly private residential occupation; no unauthorized subletting; quiet hours 10:00 PM – 6:00 AM.',
                ),
                _clause(
                  '4. Governing Law',
                  'Governed by the Laws of the Republic of Kenya. Download the full PDF above for all 8 clauses and formal execution signatures.',
                ),
                if (l.terms.isNotEmpty)
                  _clause('Special Notes on File', l.terms),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: C.amberBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: C.amberBorder),
                  ),
                  child: Text(
                    'NB: To avoid fraud and losing money, DO NOT pay rent to any other account or to any personal numbers.',
                    style: sans(11, color: C.amberText, weight: FontWeight.w600, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          if (l.isActive && isAdmin) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 43,
                    child: OutlinedButton.icon(
                      onPressed: () => showAmendLeaseSheet(
                        context,
                        lease: l,
                        onAmended: _reloadLease,
                      ),
                      icon: const LapisIcon(LapisIconName.pencil, size: 14, color: C.navy),
                      label: Text('Amend', style: sans(12.5, color: C.navy, weight: FontWeight.w600)),
                    ),
                  ),
                ),
                if (widget.vacantUnits.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 43,
                      child: OutlinedButton.icon(
                        onPressed: () => showTransferLeaseSheet(
                          context,
                          lease: l,
                          vacantUnits: widget.vacantUnits,
                          onTransferred: () => Navigator.pop(context, true),
                        ),
                        icon: const LapisIcon(LapisIconName.arrowLeftRight, size: 14, color: C.navy),
                        label: Text('Transfer', style: sans(12.5, color: C.navy, weight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 43,
              child: OutlinedButton(
                onPressed: _handleTerminate,
                style: OutlinedButton.styleFrom(side: const BorderSide(color: C.roseBorder)),
                child: Text('Terminate & Settle Lease', style: sans(12.5, color: C.roseText, weight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _clause(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: sans(12, color: C.textPrimary, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(body, style: sans(11.8, color: C.textSecondary, height: 1.45)),
        ],
      ),
    );
  }

  Widget _item(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: sans(12, color: C.textMuted)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              val,
              textAlign: TextAlign.right,
              style: sans(12, color: C.textPrimary, weight: FontWeight.w600, fontFeatures: kTabularNums),
            ),
          ),
        ],
      ),
    );
  }
}
