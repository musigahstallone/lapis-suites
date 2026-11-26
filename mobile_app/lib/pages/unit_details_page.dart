import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/icons.dart';
import '../core/widgets.dart';
import '../core/sheets.dart';

class UnitDetailsPage extends StatelessWidget {
  final UnitModel unit;
  final List<TenantModel> allTenants;

  const UnitDetailsPage({
    super.key,
    required this.unit,
    this.allTenants = const [],
  });

  @override
  Widget build(BuildContext context) {
    final occ = unit.isOccupied;

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

          if (!occ && allTenants.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 43,
              child: ElevatedButton.icon(
                onPressed: () => showAssignLeaseSheet(
                  context,
                  unit: unit,
                  tenants: allTenants,
                  onAssigned: () => Navigator.pop(context, true),
                ),
                icon: const LapisIcon(LapisIconName.userPlus, size: 15, color: C.ctaOn),
                label: Text('Assign Lease', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
              ),
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
