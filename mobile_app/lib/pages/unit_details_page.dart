import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/api.dart';
import '../core/icons.dart';
import '../core/widgets.dart';
import '../core/sheets.dart';

class UnitDetailsPage extends StatefulWidget {
  final UnitModel unit;
  final List<TenantModel> allTenants;
  final List<UnitTypeModel> unitTypes;

  const UnitDetailsPage({
    super.key,
    required this.unit,
    this.allTenants = const [],
    this.unitTypes = const [],
  });

  @override
  State<UnitDetailsPage> createState() => _UnitDetailsPageState();
}

class _UnitDetailsPageState extends State<UnitDetailsPage> {
  bool _isDeleting = false;

  Future<void> _confirmDelete() async {
    final u = widget.unit;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text('Delete Unit ${u.unitNumber}?', style: flex(15, color: C.textPrimary)),
        content: Text(
          'This removes Unit ${u.unitNumber} permanently. Units with active or historical lease/payment records are protected and cannot be deleted.',
          style: sans(12.5, color: C.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: sans(12.5, color: C.textSecondary, weight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: sans(12.5, color: C.roseText, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isDeleting = true);
    final res = await ApiService.deleteUnit(u.id);
    if (!mounted) return;
    setState(() => _isDeleting = false);
    if (res['success'] == true) {
      showAppSnackBar(context, 'Unit ${u.unitNumber} deleted.');
      Navigator.pop(context, true);
    } else {
      showAppSnackBar(context, res['error']?.toString() ?? 'Could not delete unit.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final occ = unit.isOccupied;
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
        title: Text('Unit ${unit.unitNumber}', style: flex(15, color: C.textPrimary)),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Edit Unit',
              icon: const LapisIcon(LapisIconName.pencil, size: 17, color: C.textSecondary),
              onPressed: () => showEditUnitSheet(
                context,
                unit: unit,
                unitTypes: widget.unitTypes,
                onUpdated: () => Navigator.pop(context, true),
              ),
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: C.border),
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
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatUnitTypeLabel(unit.type), style: flex(14, color: C.textPrimary)),
                    occ ? StatusPill.mint('Occupied') : StatusPill.amber('Vacant'),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: C.borderLight),
                const SizedBox(height: 8),
                _field('Monthly Rent', 'KES ${unit.monthlyRent.toLocaleString()}'),
                _field(
                  'Resident',
                  occ ? (unit.currentTenantName ?? 'Active Resident') : 'None',
                ),
                const SizedBox(height: 6),
                Text(
                  'Occupancy status is updated automatically through leases.',
                  style: sans(11, color: C.textMuted),
                ),
              ],
            ),
          ),

          if (!occ && widget.allTenants.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 43,
              child: ElevatedButton.icon(
                onPressed: () => showAssignLeaseSheet(
                  context,
                  unit: unit,
                  tenants: widget.allTenants,
                  onAssigned: () => Navigator.pop(context, true),
                ),
                icon: const LapisIcon(LapisIconName.userPlus, size: 15, color: C.ctaOn),
                label: Text('Assign Lease', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
              ),
            ),
          ],

          if (isAdmin && !occ) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: () => showEditUnitSheet(
                        context,
                        unit: unit,
                        unitTypes: widget.unitTypes,
                        onUpdated: () => Navigator.pop(context, true),
                      ),
                      icon: const LapisIcon(LapisIconName.pencil, size: 14, color: C.navy),
                      label: Text('Edit Unit', style: sans(12.5, color: C.navy, weight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: _isDeleting ? null : _confirmDelete,
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: C.roseBorder)),
                      icon: const LapisIcon(LapisIconName.trash, size: 14, color: C.roseText),
                      label: Text(
                        _isDeleting ? 'Deleting...' : 'Delete Unit',
                        style: sans(12.5, color: C.roseText, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (unit.features.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Amenities', style: flex(13, color: C.textPrimary)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: unit.features.map((f) => StatusPill.slate(f)).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: sans(12, color: C.textMuted)),
          Text(
            value,
            style: sans(12, color: C.textPrimary, weight: FontWeight.w600).copyWith(fontFeatures: kTabularNums),
          ),
        ],
      ),
    );
  }
}
