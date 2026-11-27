import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'models.dart';
import 'api.dart';
import 'icons.dart';
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
  final startCtrl = TextEditingController(
    text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
  );
  final endCtrl = TextEditingController(); // Intentionally blank unless landlord explicitly sets an end date
  final termsCtrl = TextEditingController();
  bool depositPaid = false;
  bool isSaving = false;
  String? errorMsg;

  Future<void> pickDate(BuildContext pickerCtx, TextEditingController targetCtrl, StateSetter setMState) async {
    final initial = DateTime.tryParse(targetCtrl.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: pickerCtx,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setMState(() {
        targetCtrl.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

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
                          readOnly: true,
                          onTap: () => pickDate(ctx, startCtrl, setMState),
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('End Date (Optional)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                            if (endCtrl.text.isNotEmpty)
                              GestureDetector(
                                onTap: () => setMState(() => endCtrl.clear()),
                                child: Text('Clear', style: sans(10.5, color: C.navy, weight: FontWeight.w600)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        TextField(
                          controller: endCtrl,
                          readOnly: true,
                          onTap: () => pickDate(ctx, endCtrl, setMState),
                          style: mono(12, color: C.textPrimary),
                          decoration: fieldDecoration(hintText: 'Leave blank if ongoing'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: depositPaid,
                activeThumbColor: C.navy,
                title: Text('Deposit already paid', style: sans(12.5, color: C.textPrimary, weight: FontWeight.w500)),
                onChanged: (v) => setMState(() => depositPaid = v),
              ),
              Text('Special Notes (Optional)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: termsCtrl,
                maxLines: 2,
                style: sans(12.5, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'Optional agreement notes'),
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
                          if (startCtrl.text.trim().isEmpty) {
                            setMState(() => errorMsg = 'Select a lease start date.');
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
                            depositPaid: depositPaid,
                            terms: termsCtrl.text.trim(),
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

/// 3. Amend / Edit Lease Sheet (Editable Start Date, Optional/Blank End Date, Rent, Deposit & Status)
void showAmendLeaseSheet(
  BuildContext context, {
  required LeaseModel lease,
  VoidCallback? onAmended,
}) {
  String changeType = 'rent_adjustment';
  final startCtrl = TextEditingController(text: lease.startDate);
  final rentCtrl = TextEditingController(text: lease.monthlyRent.toString());
  final depCtrl = TextEditingController(text: lease.depositAmount.toString());
  final endCtrl = TextEditingController(text: lease.endDate);
  final reasonCtrl = TextEditingController();
  bool depositPaid = lease.isDepositSettled;
  bool isSaving = false;
  String? errorMsg;

  Future<void> pickDate(BuildContext pickerCtx, TextEditingController targetCtrl, StateSetter setMState) async {
    final initial = DateTime.tryParse(targetCtrl.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: pickerCtx,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setMState(() {
        targetCtrl.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

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
                  DropdownMenuItem(value: 'renewal', child: Text('Lease Dates / Renewal')),
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
                          readOnly: true,
                          onTap: () => pickDate(ctx, startCtrl, setMState),
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('End Date (Optional)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                            if (endCtrl.text.isNotEmpty)
                              GestureDetector(
                                onTap: () => setMState(() => endCtrl.clear()),
                                child: Text('Clear', style: sans(10.5, color: C.navy, weight: FontWeight.w600)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        TextField(
                          controller: endCtrl,
                          readOnly: true,
                          onTap: () => pickDate(ctx, endCtrl, setMState),
                          style: mono(12, color: C.textPrimary),
                          decoration: fieldDecoration(hintText: 'Leave blank if ongoing'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: depositPaid,
                activeThumbColor: C.navy,
                title: Text('Deposit settled', style: sans(12.5, color: C.textPrimary, weight: FontWeight.w500)),
                onChanged: (v) => setMState(() => depositPaid = v),
              ),
              Text('Reason', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: reasonCtrl,
                style: sans(12.5, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'e.g. Updated start date or rent review'),
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
                          final trimmedEnd = endCtrl.text.trim();
                          setMState(() {
                            isSaving = true;
                            errorMsg = null;
                          });
                          final res = await ApiService.amendLease(
                            lease.id,
                            changeType: changeType,
                            newStartDate: startCtrl.text.trim(),
                            newRent: rent,
                            newDeposit: dep,
                            newEndDate: trimmedEnd,
                            clearEndDate: trimmedEnd.isEmpty,
                            depositPaid: depositPaid,
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
                      : Text('Save Changes', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
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

/// 7. Unpaid Residents ("Who Hasn't Paid") Bottom Sheet
void showUnpaidTenantsSheet(
  BuildContext context, {
  required List<TenantModel> tenants,
  void Function(TenantModel tenant)? onSelectCollect,
  void Function(TenantModel tenant)? onSelectDetails,
}) {
  final unpaid = tenants.where((t) => t.hasArrears).toList()
    ..sort((a, b) => b.effectiveBalanceDue.compareTo(a.effectiveBalanceDue));
  final totalArrears = unpaid.fold<int>(0, (sum, t) => sum + t.effectiveBalanceDue);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.78),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _handle(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Unpaid Residents', style: flex(15.5, color: C.textPrimary, weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        unpaid.isEmpty
                            ? 'Everyone is up to date'
                            : '${unpaid.length} resident${unpaid.length == 1 ? '' : 's'} with balance due',
                        style: sans(11.5, color: C.textMuted),
                      ),
                    ],
                  ),
                  if (totalArrears > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('KES', style: sans(10.5, color: C.textMuted, weight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        Text(
                          totalArrears.toLocaleString(),
                          style: flex(15, color: C.roseText, weight: FontWeight.w700, fontFeatures: kTabularNums),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: C.borderLight),
              if (unpaid.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(color: C.mintBg, shape: BoxShape.circle),
                        child: const Center(child: LapisIcon(LapisIconName.check, size: 20, color: C.mintText)),
                      ),
                      const SizedBox(height: 10),
                      Text('All rents are settled', style: flex(13.5, color: C.mintText)),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: unpaid.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: C.borderLight),
                    itemBuilder: (_, i) {
                      final t = unpaid[i];
                      return InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          if (onSelectDetails != null) {
                            onSelectDetails(t);
                          } else if (onSelectCollect != null) {
                            onSelectCollect(t);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(color: C.navySoftBg, shape: BoxShape.circle),
                                alignment: Alignment.center,
                                child: Text(t.avatarInitials, style: flex(12.5, color: C.navy, weight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.name,
                                      style: sans(13, color: C.textPrimary, weight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      t.currentUnitNumber.isNotEmpty ? 'Unit ${t.currentUnitNumber}' : 'Unassigned',
                                      style: sans(11.5, color: C.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text('KES', style: sans(10, color: C.textMuted, weight: FontWeight.w500)),
                                      const SizedBox(width: 3),
                                      Text(
                                        t.effectiveBalanceDue.toLocaleString(),
                                        style: flex(13.5, color: C.roseText, weight: FontWeight.w700, fontFeatures: kTabularNums),
                                      ),
                                    ],
                                  ),
                                  if (onSelectCollect != null) ...[
                                    const SizedBox(height: 3),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        onSelectCollect(t);
                                      },
                                      child: Text(
                                        'Collect',
                                        style: sans(11, color: C.navy, weight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
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

/// 8. Confirm-Before-Send Rent Reminders Sheet (Prevents accidental SMS blast)
void showSendRemindersConfirmSheet(
  BuildContext context, {
  required List<TenantModel> tenants,
  VoidCallback? onSent,
}) {
  final unpaid = tenants.where((t) => t.hasArrears).toList()
    ..sort((a, b) => b.effectiveBalanceDue.compareTo(a.effectiveBalanceDue));
  final totalArrears = unpaid.fold<int>(0, (sum, t) => sum + t.effectiveBalanceDue);
  bool isSending = false;
  String? errorMsg;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setMState) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.78),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _handle(),
                Text('Send Rent Reminders', style: flex(15.5, color: C.textPrimary, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  unpaid.isEmpty
                      ? 'No residents currently have unpaid rent balances.'
                      : 'Review the ${unpaid.length} resident${unpaid.length == 1 ? '' : 's'} below before dispatching SMS reminders.',
                  style: sans(12, color: C.textMuted),
                ),
                const SizedBox(height: 12),

                if (errorMsg != null) ...[
                  InlineAlert(message: errorMsg!),
                  const SizedBox(height: 10),
                ],

                if (unpaid.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: C.cardSubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: C.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Arrears (${unpaid.length})', style: sans(12, color: C.textSecondary, weight: FontWeight.w600)),
                        Text(
                          'KES ${totalArrears.toLocaleString()}',
                          style: flex(13.5, color: C.roseText, weight: FontWeight.w700, fontFeatures: kTabularNums),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: unpaid.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: C.borderLight),
                      itemBuilder: (_, i) {
                        final t = unpaid[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.name, style: sans(12.5, color: C.textPrimary, weight: FontWeight.w600)),
                                    Text(
                                      t.currentUnitNumber.isNotEmpty ? 'Unit ${t.currentUnitNumber}' : 'Unassigned',
                                      style: sans(11, color: C.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'KES ${t.effectiveBalanceDue.toLocaleString()}',
                                style: flex(12.5, color: C.roseText, weight: FontWeight.w700, fontFeatures: kTabularNums),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 43,
                        child: OutlinedButton(
                          onPressed: isSending ? null : () => Navigator.pop(ctx),
                          child: Text('Cancel', style: sans(12.5, color: C.textSecondary, weight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    if (unpaid.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 43,
                          child: ElevatedButton.icon(
                            onPressed: isSending
                                ? null
                                : () async {
                                    setMState(() {
                                      isSending = true;
                                      errorMsg = null;
                                    });
                                    final res = await ApiService.runRentReminders();
                                    if (!ctx.mounted) return;
                                    setMState(() => isSending = false);
                                    if (res['success'] == true) {
                                      Navigator.pop(ctx);
                                      showAppSnackBar(
                                        context,
                                        res['message']?.toString() ?? 'Rent reminders sent.',
                                      );
                                      onSent?.call();
                                    } else {
                                      setMState(() => errorMsg = res['error']?.toString() ?? 'Could not send reminders.');
                                    }
                                  },
                            icon: isSending
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn),
                                  )
                                : const LapisIcon(LapisIconName.send, size: 14, color: C.ctaOn),
                            label: Text(
                              isSending ? 'Sending...' : 'Confirm & Send',
                              style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 9. Post Rent Ledger Adjustment Sheet (Rent/Deposit Charge or Rent Credit/Waiver — Rent Only, NO water/utilities)
void showLedgerAdjustmentSheet(
  BuildContext context, {
  required TenantModel tenant,
  VoidCallback? onSaved,
}) {
  String type = 'charge'; // 'charge' | 'credit'
  String category = 'rent_adjustment';
  final amountCtrl = TextEditingController();
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
              Text('Rent Ledger Adjustment', style: flex(15, color: C.textPrimary, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${tenant.name} · Rent & Deposit Only', style: sans(12, color: C.textMuted)),
              const SizedBox(height: 12),

              if (errorMsg != null) ...[
                InlineAlert(message: errorMsg!),
                const SizedBox(height: 10),
              ],

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
                          type = 'charge';
                          category = 'rent_adjustment';
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: type == 'charge' ? C.navy : Colors.transparent,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Rent Charge',
                            style: sans(11.5, color: type == 'charge' ? Colors.white : C.textSecondary, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setMState(() {
                          type = 'credit';
                          category = 'waiver';
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: type == 'credit' ? C.navy : Colors.transparent,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Credit / Waiver',
                            style: sans(11.5, color: type == 'credit' ? Colors.white : C.textSecondary, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              Text('Category', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              DropdownButtonFormField<String>(
                initialValue: category,
                dropdownColor: C.surface,
                style: sans(12.5, color: C.textPrimary),
                decoration: fieldDecoration(),
                items: type == 'charge'
                    ? const [
                        DropdownMenuItem(value: 'rent_adjustment', child: Text('Rent Balance Adjustment')),
                        DropdownMenuItem(value: 'deposit_adjustment', child: Text('Security Deposit Adjustment')),
                        DropdownMenuItem(value: 'damage', child: Text('Premises Repair / Damage')),
                      ]
                    : const [
                        DropdownMenuItem(value: 'waiver', child: Text('Rent Waiver / Discount')),
                        DropdownMenuItem(value: 'credit_note', child: Text('Rent Credit Note')),
                        DropdownMenuItem(value: 'overpayment_adj', child: Text('Balance Correction')),
                      ],
                onChanged: (v) => setMState(() => category = v ?? category),
              ),
              const SizedBox(height: 12),

              Text('Amount (KES)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: flex(14.5, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'e.g. 5000', prefixText: 'KES '),
              ),
              const SizedBox(height: 12),

              Text('Reason', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: reasonCtrl,
                style: sans(12.5, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'e.g. Agreed rent balance correction'),
              ),
              const SizedBox(height: 16),

              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final amt = int.tryParse(amountCtrl.text.trim()) ?? 0;
                          final rsn = reasonCtrl.text.trim();
                          if (amt <= 0) {
                            setMState(() => errorMsg = 'Enter a valid positive amount.');
                            return;
                          }
                          if (rsn.isEmpty) {
                            setMState(() => errorMsg = 'Enter a brief reason for this adjustment.');
                            return;
                          }
                          setMState(() {
                            isSaving = true;
                            errorMsg = null;
                          });
                          final res = await ApiService.createTenantAdjustment(
                            tenant.id,
                            type: type,
                            amount: amt,
                            category: category,
                            reason: rsn,
                            leaseId: tenant.currentLeaseId,
                            unitNumber: tenant.currentUnitNumber,
                          );
                          if (!ctx.mounted) return;
                          setMState(() => isSaving = false);
                          if (res['success'] == true) {
                            Navigator.pop(ctx);
                            showAppSnackBar(
                              context,
                              type == 'charge' ? 'Charge added and balance updated.' : 'Credit applied and balance updated.',
                            );
                            onSaved?.call();
                          } else {
                            setMState(() => errorMsg = res['error']?.toString() ?? 'Could not save adjustment.');
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                      : Text(
                          type == 'charge' ? 'Post Charge' : 'Apply Credit',
                          style: sans(13, color: C.ctaOn, weight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 10. Move-Out Settlement & Lease Termination Sheet
void showMoveOutSettlementSheet(
  BuildContext context, {
  required LeaseModel lease,
  VoidCallback? onTerminated,
}) {
  final depositHeld = lease.isDepositSettled ? lease.depositAmount : 0;
  final deductionsCtrl = TextEditingController(text: '0');
  final notesCtrl = TextEditingController();
  bool isSaving = false;
  String? errorMsg;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setMState) {
        final ded = int.tryParse(deductionsCtrl.text.trim()) ?? 0;
        final netRefund = (depositHeld - ded) > 0 ? (depositHeld - ded) : 0;
        final extraOwed = (ded - depositHeld) > 0 ? (ded - depositHeld) : 0;

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
                _handle(),
                Text('Move-Out Settlement', style: flex(15, color: C.textPrimary, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Unit ${lease.unitNumber} · ${lease.tenantName}', style: sans(12, color: C.textMuted)),
                const SizedBox(height: 12),

                if (errorMsg != null) ...[
                  InlineAlert(message: errorMsg!),
                  const SizedBox(height: 10),
                ],

                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: C.cardSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: C.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Deposit Held', style: sans(12, color: C.textMuted)),
                          Text(
                            'KES ${depositHeld.toLocaleString()}',
                            style: flex(13, color: C.textPrimary, weight: FontWeight.w700, fontFeatures: kTabularNums),
                          ),
                        ],
                      ),
                      const Divider(height: 14, color: C.borderLight),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            extraOwed > 0 ? 'Balance Owed After Deposit' : 'Net Deposit Refundable',
                            style: sans(12, color: C.textSecondary, weight: FontWeight.w600),
                          ),
                          Text(
                            'KES ${(extraOwed > 0 ? extraOwed : netRefund).toLocaleString()}',
                            style: flex(
                              14,
                              color: extraOwed > 0 ? C.roseText : C.mintText,
                              weight: FontWeight.w700,
                              fontFeatures: kTabularNums,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                Text('Deposit Deductions (Rent Arrears / Repairs)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: deductionsCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setMState(() {}),
                  style: flex(14, color: C.textPrimary),
                  decoration: fieldDecoration(hintText: '0', prefixText: 'KES '),
                ),
                const SizedBox(height: 12),

                Text('Settlement Notes (Optional)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: notesCtrl,
                  style: sans(12.5, color: C.textPrimary),
                  decoration: fieldDecoration(hintText: 'e.g. Keys returned, joint move-out inspection'),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setMState(() {
                              isSaving = true;
                              errorMsg = null;
                            });
                            final res = await ApiService.terminateLease(
                              lease.id,
                              deductions: ded,
                              deductionNotes: notesCtrl.text.trim(),
                            );
                            if (!ctx.mounted) return;
                            setMState(() => isSaving = false);
                            if (res['success'] == true) {
                              Navigator.pop(ctx);
                              showAppSnackBar(
                                context,
                                'Lease terminated. Net refund: KES ${netRefund.toLocaleString()}.',
                              );
                              onTerminated?.call();
                            } else {
                              setMState(() => errorMsg = res['error']?.toString() ?? 'Could not terminate lease.');
                            }
                          },
                    style: ElevatedButton.styleFrom(backgroundColor: C.roseText, foregroundColor: Colors.white),
                    child: isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Terminate & Settle Lease', style: sans(13, color: Colors.white, weight: FontWeight.w600)),
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

/// 11. Change Password Sheet (Revokes all prior sessions across devices)
void showChangePasswordSheet(BuildContext context) {
  final currentCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
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
              Text('Change Password', style: flex(15, color: C.textPrimary, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('Other signed-in devices will be logged out automatically.', style: sans(11.5, color: C.textMuted)),
              const SizedBox(height: 12),

              if (errorMsg != null) ...[
                InlineAlert(message: errorMsg!),
                const SizedBox(height: 10),
              ],

              Text('Current Password', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: currentCtrl,
                obscureText: true,
                style: sans(13, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'Enter current password'),
              ),
              const SizedBox(height: 12),

              Text('New Password', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: newCtrl,
                obscureText: true,
                style: sans(13, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'At least 6 characters'),
              ),
              const SizedBox(height: 12),

              Text('Confirm New Password', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                style: sans(13, color: C.textPrimary),
                decoration: fieldDecoration(hintText: 'Re-enter new password'),
              ),
              const SizedBox(height: 16),

              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (currentCtrl.text.isEmpty || newCtrl.text.length < 6) {
                            setMState(() => errorMsg = 'Enter current password and a new password (min 6 chars).');
                            return;
                          }
                          if (newCtrl.text != confirmCtrl.text) {
                            setMState(() => errorMsg = 'New passwords do not match.');
                            return;
                          }
                          setMState(() {
                            isSaving = true;
                            errorMsg = null;
                          });
                          final res = await ApiService.changePassword(
                            currentPassword: currentCtrl.text,
                            newPassword: newCtrl.text,
                            confirmPassword: confirmCtrl.text,
                          );
                          if (!ctx.mounted) return;
                          setMState(() => isSaving = false);
                          if (res['success'] == true) {
                            Navigator.pop(ctx);
                            showAppSnackBar(context, 'Password updated successfully.');
                          } else {
                            setMState(() => errorMsg = res['error']?.toString() ?? 'Could not update password.');
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                      : Text('Update Password', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
