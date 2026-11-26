import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/api.dart';
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
        showAppSnackBar(context, 'Resident balance reconciled.');
      }
    } else {
      showAppSnackBar(context, res['error']?.toString() ?? 'Reconciliation failed.', isError: true);
    }
  }

  void _openEditDialog() {
    final phoneCtrl = TextEditingController(text: extractKenyaNineDigits(_tenant.phone));
    final emailCtrl = TextEditingController(text: _tenant.email);
    bool isSaving = false;
    String? err;

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
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Update Resident Contact', style: flex(14.5, color: C.textPrimary)),
                const SizedBox(height: 12),
                if (err != null) ...[
                  InlineAlert(message: err!),
                  const SizedBox(height: 12),
                ],
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
                const SizedBox(height: 16),
                SizedBox(
                  height: 43,
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
                              phone: phoneCtrl.text.trim(),
                              email: emailCtrl.text.trim(),
                            );
                            if (!ctx.mounted) return;
                            setMState(() => isSaving = false);
                            if (res['success'] == true) {
                              Navigator.pop(ctx);
                              final up = await ApiService.fetchTenantProfile(_tenant.id);
                              if (up != null && mounted) setState(() => _tenant = up);
                              if (mounted) showAppSnackBar(context, 'Resident contact updated.');
                            } else {
                              setMState(() => err = res['error']?.toString() ?? 'Update failed.');
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                        : Text('Save Updates', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
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

    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back, size: 19, color: C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t.name, style: flex(15, color: C.textPrimary)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: C.border),
        ),
        actions: [
          IconButton(
            tooltip: 'Edit Contact',
            icon: const Icon(CupertinoIcons.pencil, size: 17, color: C.textSecondary),
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
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: C.blueBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: C.blueBorder),
                  ),
                  child: Center(
                    child: Text(t.avatarInitials, style: flex(14, color: C.blueText)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, style: flex(14, color: C.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                        '${t.currentUnitNumber.isNotEmpty ? "Unit ${t.currentUnitNumber}" : "Unassigned"} · ${t.email}',
                        style: sans(11.5, color: C.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                StatusPill.mint(formatStatusLabel(t.status)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Standing Card
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: hasArrears ? C.amberBg : (hasCredit ? C.mintBg : C.surface),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasArrears ? C.amberBorder : (hasCredit ? C.mintBorder : C.border),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACCOUNT STANDING',
                      style: sans(
                        9.5,
                        color: hasArrears ? C.amberText : (hasCredit ? C.mintText : C.textMuted),
                        weight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasArrears
                          ? 'KES ${t.effectiveBalanceDue.toLocaleString()} Due'
                          : (hasCredit ? 'KES ${t.accountCredit.toLocaleString()} Credit' : 'Settled'),
                      style: flex(15, color: C.textPrimary),
                    ),
                  ],
                ),
                SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: _isReconciling ? null : _handleReconcile,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
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
              height: 42,
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
                icon: const Icon(CupertinoIcons.money_dollar_circle, size: 15, color: C.navy),
                label: Text('Record Payment / Send STK Push', style: sans(12, color: C.navy, weight: FontWeight.w600)),
              ),
            ),
          ],

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.border),
            ),
            child: Column(
              children: [
                _field('Phone', t.phone.isNotEmpty ? t.phone : 'Not set'),
                _field('National ID', t.nationalId.isNotEmpty ? t.nationalId : 'Pending verification'),
                _field('Assigned Unit', t.currentUnitNumber.isNotEmpty ? 'Unit ${t.currentUnitNumber}' : 'Unassigned'),
                _field('Next Payment Due', formatShortDate(t.nextPaymentDueDate)),
              ],
            ),
          ),
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
          Text(value, style: sans(12, color: C.textPrimary, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}
