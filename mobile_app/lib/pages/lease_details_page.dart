import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/api.dart';
import '../core/icons.dart';
import '../core/widgets.dart';
import '../core/crud_sheets.dart';

class LeaseDetailsPage extends StatefulWidget {
  final LeaseModel lease;
  final List<UnitModel> vacantUnits;

  const LeaseDetailsPage({
    super.key,
    required this.lease,
    this.vacantUnits = const [],
  });

  @override
  State<LeaseDetailsPage> createState() => _LeaseDetailsPageState();
}

class _LeaseDetailsPageState extends State<LeaseDetailsPage> {
  late LeaseModel _lease;
  bool _isTerminating = false;

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

  Future<void> _handleTerminate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Terminate Lease', style: flex(14.5, color: C.textPrimary)),
        content: Text(
          'End lease ${_lease.leaseNumber} for Unit ${_lease.unitNumber}?',
          style: sans(12.5, color: C.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: sans(12, color: C.textMuted, weight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: C.roseText, foregroundColor: Colors.white),
            child: Text('Terminate', style: sans(12, color: Colors.white, weight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isTerminating = true);
    final res = await ApiService.terminateLease(_lease.id);
    if (!mounted) return;
    setState(() => _isTerminating = false);

    if (res['success'] == true) {
      showAppSnackBar(context, 'Lease terminated.');
      Navigator.pop(context, true);
    } else {
      showAppSnackBar(context, res['error']?.toString() ?? 'Could not terminate lease.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _lease;
    final isAdmin = ApiService.isLandlord;

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
                _item('Resident', l.tenantName),
                _item('Unit', 'Unit ${l.unitNumber} · ${formatUnitTypeLabel(l.unitType)}'),
                _item('Monthly Rent', 'KES ${l.monthlyRent.toLocaleString()}'),
                _item(
                  'Deposit',
                  'KES ${l.depositAmount.toLocaleString()} · ${l.isDepositSettled ? "Paid" : "Pending"}',
                ),
                _item('Term', '${formatShortDate(l.startDate)} – ${formatShortDate(l.endDate)}'),
                _item('Next Due', formatShortDate(l.nextPaymentDueDate)),
              ],
            ),
          ),

          if (l.terms.isNotEmpty) ...[
            const SizedBox(height: 12),
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
                  Text('Terms', style: flex(13, color: C.textPrimary)),
                  const SizedBox(height: 6),
                  Text(l.terms, style: sans(12, color: C.textSecondary, height: 1.45)),
                ],
              ),
            ),
          ],

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
                onPressed: _isTerminating ? null : _handleTerminate,
                style: OutlinedButton.styleFrom(side: const BorderSide(color: C.roseBorder)),
                child: _isTerminating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.roseText))
                    : Text('Terminate Lease', style: sans(12.5, color: C.roseText, weight: FontWeight.w600)),
              ),
            ),
          ],
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
