import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'models.dart';
import 'api.dart';
import 'widgets.dart';

Widget _handle() {
  return Center(
    child: Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(99)),
    ),
  );
}

/// 1. Create Resident / Tenant Sheet (POST /api/tenants)
void showCreateTenantSheet(BuildContext context, {VoidCallback? onCreated}) {
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final idCtrl = TextEditingController();
  bool isSaving = false;
  String? errorMsg;

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
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _handle(),
              Text('Add Resident', style: flex(15.5, color: C.textPrimary)),
              const SizedBox(height: 12),
              if (errorMsg != null) ...[
                InlineAlert(message: errorMsg!),
                const SizedBox(height: 12),
              ],
              Text('Full Name', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: sans(13, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'e.g. Samuel Mwangi'),
              ),
              const SizedBox(height: 12),
              Text('Email', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: sans(13, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'name@example.com'),
              ),
              const SizedBox(height: 12),
              Text('Mobile Number', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              KenyaPhoneField(controller: phoneCtrl),
              const SizedBox(height: 12),
              Text('National ID (optional)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: idCtrl,
                keyboardType: TextInputType.number,
                style: mono(13, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'e.g. 34567890'),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 45,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final email = emailCtrl.text.trim();
                          final phone = phoneCtrl.text.trim();
                          if (name.isEmpty) {
                            setMState(() => errorMsg = 'Enter resident full name.');
                            return;
                          }
                          if (email.isEmpty || !email.contains('@')) {
                            setMState(() => errorMsg = 'Enter a valid email address.');
                            return;
                          }
                          if (phone.length != 9) {
                            setMState(() => errorMsg = 'Enter a valid 9-digit mobile number.');
                            return;
                          }
                          setMState(() {
                            isSaving = true;
                            errorMsg = null;
                          });
                          final res = await ApiService.createTenant(
                            name: name,
                            email: email,
                            phone: phone,
                            nationalId: idCtrl.text.trim(),
                          );
                          if (!ctx.mounted) return;
                          setMState(() => isSaving = false);
                          if (res['success'] == true) {
                            Navigator.pop(ctx);
                            showAppSnackBar(context, '$name added.');
                            onCreated?.call();
                          } else {
                            setMState(() => errorMsg = res['error']?.toString() ?? 'Could not add resident.');
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                      : Text('Save Resident', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 2. Create / Assign Lease Sheet (Select Vacant Unit + Resident)
void showCreateLeaseSheet(
  BuildContext context, {
  required List<UnitModel> units,
  required List<TenantModel> tenants,
  UnitModel? initialUnit,
  TenantModel? initialTenant,
  VoidCallback? onCreated,
}) {
  final vacantUnits = units.where((u) => !u.isOccupied).toList();
  if (vacantUnits.isEmpty) {
    showAppSnackBar(context, 'No vacant units available.', isError: true);
    return;
  }
  if (tenants.isEmpty) {
    showAppSnackBar(context, 'Add a resident first before creating a lease.', isError: true);
    return;
  }

  UnitModel selectedUnit = initialUnit != null && !initialUnit.isOccupied
      ? initialUnit
      : vacantUnits.first;
  TenantModel selectedTenant = initialTenant ??
      tenants.firstWhere((t) => t.currentUnitNumber.isEmpty, orElse: () => tenants.first);

  final rentCtrl = TextEditingController(text: selectedUnit.monthlyRent.toString());
  final depCtrl = TextEditingController(text: selectedUnit.monthlyRent.toString());
  final now = DateTime.now();
  final nextYear = DateTime(now.year + 1, now.month, now.day);
  final startCtrl = TextEditingController(
    text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
  );
  final endCtrl = TextEditingController(
    text: '${nextYear.year}-${nextYear.month.toString().padLeft(2, '0')}-${nextYear.day.toString().padLeft(2, '0')}',
  );
  bool isSaving = false;
  String? errorMsg;

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
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _handle(),
              Text('New Lease', style: flex(15.5, color: C.textPrimary)),
              const SizedBox(height: 12),
              if (errorMsg != null) ...[
                InlineAlert(message: errorMsg!),
                const SizedBox(height: 12),
              ],
              Text('Vacant Unit', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              DropdownButtonFormField<String>(
                initialValue: selectedUnit.id,
                dropdownColor: C.surface,
                isExpanded: true,
                style: sans(12.5, color: C.textPrimary),
                decoration: fieldDecoration(),
                items: vacantUnits
                    .map((u) => DropdownMenuItem(
                          value: u.id,
                          child: Text(
                            'Unit ${u.unitNumber} · ${formatUnitTypeLabel(u.type)} (KES ${u.monthlyRent.toLocaleString()})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (id) {
                  final u = vacantUnits.firstWhere((x) => x.id == id, orElse: () => selectedUnit);
                  setMState(() {
                    selectedUnit = u;
                    rentCtrl.text = u.monthlyRent.toString();
                    depCtrl.text = u.monthlyRent.toString();
                  });
                },
              ),
              const SizedBox(height: 12),
              Text('Resident', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
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
                          child: Text(
                            '${t.name}${t.currentUnitNumber.isNotEmpty ? " · Unit ${t.currentUnitNumber}" : " · Unassigned"}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (id) {
                  setMState(() {
                    selectedTenant = tenants.firstWhere((x) => x.id == id, orElse: () => selectedTenant);
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
                          style: sans(13, color: C.textPrimary, weight: FontWeight.w600, fontFeatures: kTabularNums),
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
                        Text('Deposit', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                        const SizedBox(height: 5),
                        TextField(
                          controller: depCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: sans(13, color: C.textPrimary, weight: FontWeight.w600, fontFeatures: kTabularNums),
                          decoration: fieldDecoration(prefixText: 'KES '),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Start Date', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                        const SizedBox(height: 5),
                        TextField(
                          controller: startCtrl,
                          style: mono(12, color: C.textPrimary),
                          decoration: fieldDecoration(hintText: 'YYYY-MM-DD'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('End Date', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                        const SizedBox(height: 5),
                        TextField(
                          controller: endCtrl,
                          style: mono(12, color: C.textPrimary),
                          decoration: fieldDecoration(hintText: 'YYYY-MM-DD'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 45,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final rent = int.tryParse(rentCtrl.text.trim()) ?? 0;
                          final dep = int.tryParse(depCtrl.text.trim()) ?? 0;
                          if (rent <= 0) {
                            setMState(() => errorMsg = 'Enter a valid monthly rent.');
                            return;
                          }
                          setMState(() {
                            isSaving = true;
                            errorMsg = null;
                          });
                          final res = await ApiService.createLease(
                            tenantId: selectedTenant.id,
                            unitId: selectedUnit.id,
                            unitNumber: selectedUnit.unitNumber,
                            monthlyRent: rent,
                            depositAmount: dep,
                            startDate: startCtrl.text.trim(),
                            endDate: endCtrl.text.trim(),
                          );
                          if (!ctx.mounted) return;
                          setMState(() => isSaving = false);
                          if (res['success'] == true) {
                            Navigator.pop(ctx);
                            showAppSnackBar(context, 'Lease created for Unit ${selectedUnit.unitNumber}.');
                            onCreated?.call();
                          } else {
                            setMState(() => errorMsg = res['error']?.toString() ?? 'Could not create lease.');
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                      : Text('Create Lease', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 3. Amend / Edit Lease Sheet (POST /api/leases/:id/amend)
void showAmendLeaseSheet(
  BuildContext context, {
  required LeaseModel lease,
  VoidCallback? onAmended,
}) {
  String changeType = 'rent_adjustment';
  final rentCtrl = TextEditingController(text: lease.monthlyRent.toString());
  final depCtrl = TextEditingController(text: lease.depositAmount.toString());
  final endCtrl = TextEditingController(text: lease.endDate);
  final reasonCtrl = TextEditingController();
  bool isSaving = false;
  String? errorMsg;

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
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _handle(),
              Text('Edit Lease · Unit ${lease.unitNumber}', style: flex(15, color: C.textPrimary)),
              const SizedBox(height: 12),
              if (errorMsg != null) ...[
                InlineAlert(message: errorMsg!),
                const SizedBox(height: 12),
              ],
              Text('Change Type', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              DropdownButtonFormField<String>(
                initialValue: changeType,
                dropdownColor: C.surface,
                style: sans(12.5, color: C.textPrimary),
                decoration: fieldDecoration(),
                items: const [
                  DropdownMenuItem(value: 'rent_adjustment', child: Text('Rent Adjustment')),
                  DropdownMenuItem(value: 'renewal', child: Text('Lease Renewal / Extension')),
                  DropdownMenuItem(value: 'deposit_update', child: Text('Deposit Adjustment')),
                  DropdownMenuItem(value: 'terms_update', child: Text('Terms Update')),
                ],
                onChanged: (v) => setMState(() => changeType = v ?? 'rent_adjustment'),
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
                          style: sans(13, color: C.textPrimary, weight: FontWeight.w600, fontFeatures: kTabularNums),
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
                        Text('Deposit', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                        const SizedBox(height: 5),
                        TextField(
                          controller: depCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: sans(13, color: C.textPrimary, weight: FontWeight.w600, fontFeatures: kTabularNums),
                          decoration: fieldDecoration(prefixText: 'KES '),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('End Date', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: endCtrl,
                style: mono(12.5, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'YYYY-MM-DD'),
              ),
              const SizedBox(height: 12),
              Text('Reason', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: reasonCtrl,
                style: sans(12.5, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'e.g. Annual lease renewal'),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 45,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final rent = int.tryParse(rentCtrl.text.trim()) ?? lease.monthlyRent;
                          final dep = int.tryParse(depCtrl.text.trim()) ?? lease.depositAmount;
                          setMState(() {
                            isSaving = true;
                            errorMsg = null;
                          });
                          final res = await ApiService.amendLease(
                            lease.id,
                            changeType: changeType,
                            newRent: rent,
                            newDeposit: dep,
                            newEndDate: endCtrl.text.trim(),
                            reason: reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : formatStatusLabel(changeType),
                          );
                          if (!ctx.mounted) return;
                          setMState(() => isSaving = false);
                          if (res['success'] == true) {
                            Navigator.pop(ctx);
                            showAppSnackBar(context, 'Lease updated & resident notified.');
                            onAmended?.call();
                          } else {
                            setMState(() => errorMsg = res['error']?.toString() ?? 'Could not update lease.');
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                      : Text('Save Amendment', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 4. Transfer Lease to Another Vacant Unit Sheet (POST /api/leases/transfer)
void showTransferLeaseSheet(
  BuildContext context, {
  required LeaseModel lease,
  required List<UnitModel> vacantUnits,
  VoidCallback? onTransferred,
}) {
  if (vacantUnits.isEmpty) {
    showAppSnackBar(context, 'No vacant units available for transfer.', isError: true);
    return;
  }

  UnitModel targetUnit = vacantUnits.first;
  final rentCtrl = TextEditingController(text: targetUnit.monthlyRent.toString());
  bool rollOverDeposit = true;
  bool isSaving = false;
  String? errorMsg;

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
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _handle(),
              Text('Transfer Unit · ${lease.tenantName}', style: flex(15, color: C.textPrimary)),
              const SizedBox(height: 12),
              if (errorMsg != null) ...[
                InlineAlert(message: errorMsg!),
                const SizedBox(height: 12),
              ],
              Text('Destination Unit', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              DropdownButtonFormField<String>(
                initialValue: targetUnit.id,
                dropdownColor: C.surface,
                isExpanded: true,
                style: sans(12.5, color: C.textPrimary),
                decoration: fieldDecoration(),
                items: vacantUnits
                    .map((u) => DropdownMenuItem(
                          value: u.id,
                          child: Text(
                            'Unit ${u.unitNumber} · ${formatUnitTypeLabel(u.type)} (KES ${u.monthlyRent.toLocaleString()})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (id) {
                  final u = vacantUnits.firstWhere((x) => x.id == id, orElse: () => targetUnit);
                  setMState(() {
                    targetUnit = u;
                    rentCtrl.text = u.monthlyRent.toString();
                  });
                },
              ),
              const SizedBox(height: 12),
              Text('New Monthly Rent', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: rentCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: sans(13, color: C.textPrimary, weight: FontWeight.w600, fontFeatures: kTabularNums),
                decoration: fieldDecoration(prefixText: 'KES '),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: rollOverDeposit,
                activeThumbColor: C.navy,
                title: Text('Roll over security deposit', style: sans(12.5, color: C.textPrimary, weight: FontWeight.w500)),
                onChanged: (v) => setMState(() => rollOverDeposit = v),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 45,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final rent = int.tryParse(rentCtrl.text.trim()) ?? targetUnit.monthlyRent;
                          setMState(() {
                            isSaving = true;
                            errorMsg = null;
                          });
                          final res = await ApiService.transferLease(
                            tenantId: lease.tenantId,
                            currentUnitId: lease.unitId,
                            newUnitId: targetUnit.id,
                            newRent: rent,
                            depositRollOver: rollOverDeposit,
                          );
                          if (!ctx.mounted) return;
                          setMState(() => isSaving = false);
                          if (res['success'] == true) {
                            Navigator.pop(ctx);
                            showAppSnackBar(context, 'Transferred to Unit ${targetUnit.unitNumber}.');
                            onTransferred?.call();
                          } else {
                            setMState(() => errorMsg = res['error']?.toString() ?? 'Transfer failed.');
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                      : Text('Confirm Transfer', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
