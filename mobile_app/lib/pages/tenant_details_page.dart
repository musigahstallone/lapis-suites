import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/api.dart';
import '../core/icons.dart';
import '../core/widgets.dart';
import '../core/sheets.dart';

class TenantDetailsPage extends StatefulWidget {
  final TenantModel tenant;
  const TenantDetailsPage({super.key, required this.tenant});

  @override
  State<TenantDetailsPage> createState() => _TenantDetailsPageState();
}

class _TenantDetailsPageState extends State<TenantDetailsPage> {
  late TenantModel _tenant;
  bool _isReconciling = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _tenant = widget.tenant;
  }

  Future<void> _handleReconcile() async {
    setState(() => _isReconciling = true);
    final res = await ApiService.reconcileTenant(_tenant.id);
    if (!mounted) return;
    setState(() => _isReconciling = false);

    if (res['success'] == true) {
      final updated = await ApiService.fetchTenantProfile(_tenant.id);
      if (updated != null && mounted) setState(() => _tenant = updated);
      if (mounted) {
        showAppSnackBar(context, 'Balance reconciled.');
      }
    } else {
      showAppSnackBar(context, res['error']?.toString() ?? 'Reconciliation failed.', isError: true);
    }
  }

  Future<void> _handleDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Remove Resident', style: flex(14.5, color: C.textPrimary)),
        content: Text('Delete ${_tenant.name}?', style: sans(12.5, color: C.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: sans(12, color: C.textMuted, weight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: C.roseText, foregroundColor: Colors.white),
            child: Text('Delete', style: sans(12, color: Colors.white, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isDeleting = true);
    final res = await ApiService.deleteTenant(_tenant.id);
    if (!mounted) return;
    setState(() => _isDeleting = false);

    if (res['success'] == true) {
      showAppSnackBar(context, '${_tenant.name} removed.');
      Navigator.pop(context, true);
    } else {
      showAppSnackBar(context, res['error']?.toString() ?? 'Could not remove resident.', isError: true);
    }
  }

  void _openEditDialog() {
    final nameCtrl = TextEditingController(text: _tenant.name);
    final phoneCtrl = TextEditingController(text: extractKenyaNineDigits(_tenant.phone));
    final emailCtrl = TextEditingController(text: _tenant.email);
    final idCtrl = TextEditingController(text: _tenant.nationalId);
    bool isSaving = false;
    String? err;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit Resident', style: flex(15, color: C.textPrimary)),
                const SizedBox(height: 12),
                if (err != null) ...[
                  InlineAlert(message: err!),
                  const SizedBox(height: 12),
                ],
                Text('Full Name', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(controller: nameCtrl, style: sans(13, color: C.textPrimary), decoration: fieldDecoration()),
                const SizedBox(height: 12),
                Text('Mobile Number', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                KenyaPhoneField(controller: phoneCtrl),
                const SizedBox(height: 12),
                Text('Email', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: sans(13, color: C.textPrimary),
                  decoration: fieldDecoration(),
                ),
                const SizedBox(height: 12),
                Text('National ID', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(controller: idCtrl, style: mono(13, color: C.textPrimary), decoration: fieldDecoration()),
                const SizedBox(height: 16),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setMState(() {
                              isSaving = true;
                              err = null;
                            });
                            final res = await ApiService.updateTenant(
                              _tenant.id,
                              name: nameCtrl.text.trim(),
                              phone: phoneCtrl.text.trim(),
                              email: emailCtrl.text.trim(),
                              nationalId: idCtrl.text.trim(),
                            );
                            if (!ctx.mounted) return;
                            setMState(() => isSaving = false);
                            if (res['success'] == true) {
                              Navigator.pop(ctx);
                              final up = await ApiService.fetchTenantProfile(_tenant.id);
                              if (up != null && mounted) setState(() => _tenant = up);
                              if (mounted) showAppSnackBar(context, 'Resident updated.');
                            } else {
                              setMState(() => err = res['error']?.toString() ?? 'Update failed.');
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                        : Text('Save', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _tenant;
    final hasCredit = t.accountCredit > 0;
    final hasArrears = t.hasArrears;
    final isUnassigned = t.currentUnitNumber.isEmpty;

    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.surface,
        elevation: 0,
        leading: IconButton(
          icon: const LapisIcon(LapisIconName.chevronLeft, size: 19, color: C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t.name, style: flex(15, color: C.textPrimary)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: C.borderLight),
        ),
        actions: [
          IconButton(
            tooltip: 'Edit Resident',
            icon: const LapisIcon(LapisIconName.pencil, size: 17, color: C.textSecondary),
            onPressed: _openEditDialog,
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Identity Card
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.border.withValues(alpha: 0.75)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: hasArrears ? C.blueBg : C.mintBg,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      t.avatarInitials,
                      style: flex(14, color: hasArrears ? C.navy : C.mintText),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, style: flex(14, color: C.textPrimary)),
                      const SizedBox(height: 2),
                      Text(t.email, style: sans(11.5, color: C.textMuted), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                isUnassigned
                    ? StatusPill.amber('Unassigned', hasDot: false)
                    : StatusPill.mint('Unit ${t.currentUnitNumber}', hasDot: false),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Standing Card
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.border.withValues(alpha: 0.75)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('STANDING', style: sans(9.5, color: C.textMuted, weight: FontWeight.w700, letterSpacing: 0.6)),
                        const SizedBox(width: 8),
                        if (hasArrears)
                          StatusPill.amber('Due')
                        else if (hasCredit)
                          StatusPill.mint('Credit')
                        else
                          StatusPill.mint('Settled'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('KES', style: sans(11, color: C.textMuted, weight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        Text(
                          hasArrears
                              ? t.effectiveBalanceDue.toLocaleString()
                              : (hasCredit ? t.accountCredit.toLocaleString() : '0'),
                          style: flex(18, color: C.textPrimary, fontFeatures: kTabularNums),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: _isReconciling ? null : _handleReconcile,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: _isReconciling
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                        : Text('Reconcile', style: sans(11.5, color: C.ctaOn, weight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),

          if (ApiService.isLandlord) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () => showAdminCollectPaymentSheet(
                  context,
                  tenants: [t],
                  initialTenant: t,
                  onComplete: () async {
                    final up = await ApiService.fetchTenantProfile(t.id);
                    if (up != null && mounted) setState(() => _tenant = up);
                  },
                ),
                icon: const LapisIcon(LapisIconName.wallet, size: 15, color: C.navy),
                label: Text('Collect Payment', style: sans(12.5, color: C.navy, weight: FontWeight.w600)),
              ),
            ),
          ],

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.border.withValues(alpha: 0.75)),
            ),
            child: Column(
              children: [
                _field('Phone', t.phone.isNotEmpty ? formatKenyanPhoneDisplay(t.phone) : '—'),
                _field('National ID', t.nationalId.isNotEmpty ? t.nationalId : '—'),
                _field('Unit', isUnassigned ? 'Unassigned' : 'Unit ${t.currentUnitNumber}'),
                _field('Next Due', formatShortDate(t.nextPaymentDueDate)),
              ],
            ),
          ),

          if (ApiService.isLandlord && isUnassigned) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 43,
              child: OutlinedButton.icon(
                onPressed: _isDeleting ? null : _handleDelete,
                style: OutlinedButton.styleFrom(side: const BorderSide(color: C.roseBorder)),
                icon: _isDeleting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: C.roseText))
                    : const LapisIcon(LapisIconName.trash, size: 15, color: C.roseText),
                label: Text('Remove Resident', style: sans(12.5, color: C.roseText, weight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: sans(12, color: C.textMuted)),
          Text(
            value,
            style: sans(12, color: C.textPrimary, weight: FontWeight.w600, fontFeatures: kTabularNums),
          ),
        ],
      ),
    );
  }
}
