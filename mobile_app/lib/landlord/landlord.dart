import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/api.dart';
import '../core/icons.dart';
import '../core/widgets.dart';
import '../core/sheets.dart';
import '../core/crud_sheets.dart';
import '../pages/unit_details_page.dart';
import '../pages/tenant_details_page.dart';
import '../pages/lease_details_page.dart';
import '../pages/notifications_page.dart';
import '../pages/profile_settings_page.dart';

class LandlordPortfolioScreen extends StatefulWidget {
  const LandlordPortfolioScreen({super.key});

  @override
  State<LandlordPortfolioScreen> createState() => _LandlordPortfolioScreenState();
}

class _LandlordPortfolioScreenState extends State<LandlordPortfolioScreen> {
  int _currentNavIndex = 0; // 0: Home, 1: Property (Units/Tenants/Leases), 2: Ledger, 3: Tickets, 4: Settings
  int _propertySegment = 0; // 0: Units, 1: Tenants, 2: Leases

  DashboardData? _data;
  List<TransactionModel> _pagedTransactions = [];
  List<MaintenanceTicket> _tickets = [];
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  String? _error;
  bool _isReconciling = false;

  final ScrollController _ledgerScrollCtrl = ScrollController();
  final TextEditingController _propertySearchCtrl = TextEditingController();
  final TextEditingController _ledgerSearchCtrl = TextEditingController();
  String _propertySearch = '';
  String _ledgerSearch = '';
  int _ledgerPage = 1;
  bool _isLoadingMoreTx = false;
  bool _hasMoreTx = true;

  @override
  void initState() {
    super.initState();
    ApiService.realtimeUpdateNotifier.addListener(_onRealtimeUpdate);
    _ledgerScrollCtrl.addListener(_onScroll);
    _loadPortfolio();
  }

  @override
  void dispose() {
    ApiService.realtimeUpdateNotifier.removeListener(_onRealtimeUpdate);
    _ledgerScrollCtrl.dispose();
    _propertySearchCtrl.dispose();
    _ledgerSearchCtrl.dispose();
    super.dispose();
  }

  void _onRealtimeUpdate() {
    if (mounted) _loadPortfolio(silent: true);
  }

  void _onScroll() {
    if (!_ledgerScrollCtrl.hasClients) return;
    if (_ledgerScrollCtrl.position.pixels >= _ledgerScrollCtrl.position.maxScrollExtent - 100) {
      if (!_isLoadingMoreTx && _hasMoreTx) {
        _loadMoreTransactions();
      }
    }
  }

  Future<void> _loadPortfolio({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final n = await ApiService.checkNetwork();
    if (!n.isOnline) {
      if (!silent && mounted) {
        setState(() {
          _isLoading = false;
          _error = n.message ?? 'Unable to reach server.';
        });
      }
      return;
    }

    try {
      final results = await Future.wait([
        ApiService.fetchDashboardStats(),
        ApiService.fetchMaintenance(),
        ApiService.fetchNotifications(),
      ]);
      final d = results[0] as DashboardData;
      final tks = results[1] as List<MaintenanceTicket>;
      final notifs = results[2] as List<NotificationModel>;

      if (mounted) {
        setState(() {
          _data = d;
          _tickets = tks;
          _notifications = notifs;
          _pagedTransactions = List.from(d.transactions);
          _ledgerPage = 1;
          _hasMoreTx = d.transactions.length >= 30;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          _isLoading = false;
          _error = ApiService.friendlyError(e);
        });
      }
    }
  }

  Future<void> _loadMoreTransactions() async {
    setState(() => _isLoadingMoreTx = true);
    try {
      final nextPage = _ledgerPage + 1;
      final more = await ApiService.fetchTransactions(page: nextPage, limit: 20);
      if (mounted) {
        setState(() {
          if (more.isEmpty) {
            _hasMoreTx = false;
          } else {
            _ledgerPage = nextPage;
            _pagedTransactions.addAll(more);
          }
          _isLoadingMoreTx = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMoreTx = false);
    }
  }

  Future<void> _handleReconcile() async {
    if (_data == null) return;
    setState(() => _isReconciling = true);

    try {
      final res = await ApiService.reconcileAllTenants();
      await _loadPortfolio(silent: true);
      if (mounted) {
        if (res['success'] == true) {
          final count = res['reconciledCount'] ?? _data!.tenants.length;
          showAppSnackBar(context, 'Reconciled $count resident ledger${count == 1 ? '' : 's'}.');
        } else {
          showAppSnackBar(context, res['error']?.toString() ?? 'Reconciliation failed.', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, ApiService.friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isReconciling = false);
    }
  }

  void _openNotificationsPage() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NotificationsPage()))
        .then((_) => _loadPortfolio(silent: true));
  }

  void _goToPropertySegment(int segment) {
    setState(() {
      _currentNavIndex = 1;
      _propertySegment = segment;
    });
  }

  Widget _bellButton() {
    final unread = _notifications.where((n) => !n.read).length;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        tooltip: 'Notifications',
        onPressed: _openNotificationsPage,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const LapisIcon(LapisIconName.bell, size: 20, color: C.textPrimary),
            if (unread > 0)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: C.amberText,
                    shape: BoxShape.circle,
                    border: Border.all(color: C.surface, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.canvas,
      body: _currentNavIndex == 4
          ? ProfileSettingsPage(
              showBackButton: false,
              tenants: _data?.tenants ?? const [],
              onDataChanged: () => _loadPortfolio(silent: true),
            )
          : _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.2, color: C.navy))
              : _error != null
                  ? ErrorStateCard(message: _error!, onRetry: () => _loadPortfolio())
                  : RefreshIndicator(
                      onRefresh: _loadPortfolio,
                      color: C.navy,
                      backgroundColor: C.surface,
                      child: _buildCurrentTab(),
                    ),
      bottomNavigationBar: OrbixBottomNav(
        currentIndex: _currentNavIndex,
        onTap: (idx) => setState(() => _currentNavIndex = idx),
        items: const [
          BottomNavItem(LapisIconName.home, 'Home'),
          BottomNavItem(LapisIconName.building, 'Property'),
          BottomNavItem(LapisIconName.creditCard, 'Ledger'),
          BottomNavItem(LapisIconName.wrench, 'Tickets'),
          BottomNavItem(LapisIconName.settings, 'Settings'),
        ],
      ),
    );
  }

  Widget _buildCurrentTab() {
    final d = _data!;
    switch (_currentNavIndex) {
      case 1:
        return _buildPropertyHub(d);
      case 2:
        return _buildLedgerTab(d);
      case 3:
        return _buildTicketsTab(d);
      default:
        return _buildHomeSliver(d);
    }
  }

  // --- TAB 0: HOME DASHBOARD (SliverAppBar + Precision Hero + 3-Col Circular Actions + Clean Minimal Lists) ---
  Widget _buildHomeSliver(DashboardData d) {
    final openTickets = _tickets.where((t) => t.status != 'resolved' && t.status != 'cancelled').length;
    final pendingApprovals = d.transactions.where((tx) => tx.needsApproval).length;
    final firstName = firstNameFrom(ApiService.currentUser?['name']?.toString(), fallback: 'Admin');

    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: C.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 62,
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${greetingForTimeOfDay()}, $firstName',
                style: flex(16.5, color: C.textPrimary, weight: FontWeight.w700),
              ),
              const SizedBox(height: 1),
              Text(
                'Lapis Suites',
                style: sans(11.5, color: C.textMuted, weight: FontWeight.w500),
              ),
            ],
          ),
          actions: [_bellButton()],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: C.borderLight),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (pendingApprovals > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: GestureDetector(
                    onTap: () => setState(() => _currentNavIndex = 2),
                    child: InlineAlert(
                      message: '$pendingApprovals payment${pendingApprovals == 1 ? '' : 's'} pending review',
                      isInfo: false,
                    ),
                  ),
                ),

              // 1. Dark Navy Hero Card with Exact Unrounded Arrears + Collection Progress Bar
              OrbixOverviewCard(
                title: 'Monthly Roll',
                period: currentMonthYearLabel(),
                heroLabel: 'Expected Rent',
                heroPrefix: 'KES',
                heroValue: d.totalRentRoll.toLocaleString(),
                collectionProgress: d.collectionProgress,
                collectedAmount: d.collectedThisMonth,
                expectedAmount: d.totalRentRoll,
                extraAction: GestureDetector(
                  onTap: _isReconciling ? null : _handleReconcile,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LapisIcon(LapisIconName.refresh, size: 11, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(
                          _isReconciling ? 'Syncing' : 'Reconcile',
                          style: sans(10.5, color: Colors.white, weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                metrics: [
                  MetricItem('Occupancy', '${d.occupancyRate.toStringAsFixed(0)}%'),
                  MetricItem('Units', '${d.occupiedUnits}/${d.units.length}'),
                  MetricItem(
                    'Arrears',
                    d.totalArrears.toLocaleString(),
                    prefix: 'KES',
                    flex: 2,
                  ),
                  MetricItem('Tickets', '$openTickets'),
                ],
              ),

              // 2. Upgraded 4-Column Circular Action Grid (Collect Pay, Unpaid List, Add Unit, New Ticket)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: _circularQuickAction(
                        icon: LapisIconName.wallet,
                        label: 'Collect Pay',
                        isPrimary: true,
                        onTap: () => showAdminCollectPaymentSheet(
                          context,
                          tenants: d.tenants,
                          leases: d.leases,
                          onComplete: () => _loadPortfolio(silent: true),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _circularQuickAction(
                        icon: LapisIconName.alertTriangle,
                        label: 'Unpaid',
                        badgeCount: d.tenants.where((t) => t.hasArrears).length,
                        onTap: () => showUnpaidTenantsSheet(
                          context,
                          tenants: d.tenants,
                          onSelectCollect: (t) => showAdminCollectPaymentSheet(
                            context,
                            tenants: d.tenants,
                            leases: d.leases,
                            initialTenant: t,
                            onComplete: () => _loadPortfolio(silent: true),
                          ),
                          onSelectDetails: (t) => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => TenantDetailsPage(tenant: t)))
                              .then((_) => _loadPortfolio(silent: true)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _circularQuickAction(
                        icon: LapisIconName.plus,
                        label: 'Add Unit',
                        onTap: () => showCreateUnitSheet(
                          context,
                          onCreated: () => _loadPortfolio(silent: true),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _circularQuickAction(
                        icon: LapisIconName.wrench,
                        label: 'New Ticket',
                        onTap: () => showCreateMaintenanceSheet(
                          context,
                          isAdmin: true,
                          tenants: d.tenants,
                          onCreated: () => _loadPortfolio(silent: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Compact Property Quick Links (Units · Tenants · Leases)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _directoryChip('Units', '${d.units.length}', () => _goToPropertySegment(0)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _directoryChip('Tenants', '${d.tenants.length}', () => _goToPropertySegment(1)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _directoryChip('Leases', '${d.leases.length}', () => _goToPropertySegment(2)),
                    ),
                  ],
                ),
              ),

              // 4. Recent Payments Only (Minimal Dashboard — Residents managed in Property tab / Unpaid sheet)
              _sectionHeader(
                'Recent Payments',
                actionLabel: 'View all',
                onAction: () => setState(() => _currentNavIndex = 2),
              ),
              if (d.transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text('No payments yet.', style: sans(12, color: C.textMuted)),
                )
              else
                ...d.transactions.take(6).map((tx) => _buildMinimalDashboardPaymentTile(tx, d.tenants)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _circularQuickAction({
    required LapisIconName icon,
    required String label,
    bool isPrimary = false,
    int badgeCount = 0,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isPrimary ? C.navy : C.surface,
                    shape: BoxShape.circle,
                    border: isPrimary ? null : Border.all(color: C.border),
                    boxShadow: isPrimary
                        ? [
                            BoxShadow(
                              color: C.navy.withValues(alpha: 0.16),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: LapisIcon(
                      icon,
                      size: 17,
                      color: isPrimary ? Colors.white : C.textSecondary,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: C.roseText,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: C.canvas, width: 1.5),
                      ),
                      child: Text(
                        '$badgeCount',
                        style: sans(9, color: Colors.white, weight: FontWeight.w700, fontFeatures: kTabularNums),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: sans(11.5, color: C.textPrimary, weight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _directoryChip(String label, String count, VoidCallback onTap) {
    return Material(
      color: C.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: C.border.withValues(alpha: 0.75)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: sans(12, color: C.textSecondary, weight: FontWeight.w600)),
              Text(
                count,
                style: flex(12, color: C.navy, weight: FontWeight.w700, fontFeatures: kTabularNums),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _unitTypeFor(String? unitNumber) {
    if (unitNumber == null || unitNumber.isEmpty || _data == null) return '';
    for (final u in _data!.units) {
      if (u.unitNumber == unitNumber) return u.type;
    }
    for (final l in _data!.leases) {
      if (l.unitNumber == unitNumber && l.unitType.isNotEmpty) return l.unitType;
    }
    return '';
  }

  Widget _buildResidentTile(TenantModel t) {
    final isUnassigned = t.currentUnitNumber.isEmpty;
    final avatarBg = t.hasArrears ? C.navySoftBg : C.mintBg;
    final avatarFg = t.hasArrears ? C.navy : C.mintText;

    // Color-coded balance text (NO Due/Credit/Current pill badges):
    // Arrears -> Red, 0 -> Navy/Blue, Credit -> Emerald Green
    final amountColor = t.hasArrears
        ? C.roseText
        : (t.hasCredit ? C.mintText : C.navy);

    final activeUnitCount = _data?.leases.where((l) => l.tenantId == t.id && l.isActive).length ?? 0;

    return OrbixListTile(
      leadingOverride: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: avatarBg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          t.avatarInitials,
          style: flex(13, color: avatarFg, weight: FontWeight.w700),
        ),
      ),
      title: t.name,
      subtitleWidget: isUnassigned
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: C.amberBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: C.amberBorder.withValues(alpha: 0.7)),
              ),
              child: Text(
                'Unassigned',
                style: sans(10.5, color: C.amberText, weight: FontWeight.w600),
              ),
            )
          : Text(
              activeUnitCount > 1
                  ? 'Unit ${t.currentUnitNumber} +${activeUnitCount - 1} more'
                  : 'Unit ${t.currentUnitNumber}',
              style: sans(11.5, color: C.textMuted, weight: FontWeight.w500, fontFeatures: kTabularNums),
            ),
      amountPrefix: 'KES',
      amount: t.hasArrears
          ? t.effectiveBalanceDue.toLocaleString()
          : (t.hasCredit ? t.accountCredit.toLocaleString() : '0'),
      amountColor: amountColor,
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => TenantDetailsPage(tenant: t)))
          .then((_) => _loadPortfolio(silent: true)),
    );
  }

  /// Home dashboard recent payment row: ultra-clean (Name + Unit + Amount only!)
  Widget _buildMinimalDashboardPaymentTile(TransactionModel tx, List<TenantModel> tenants) {
    final unitText = tx.unitNumber?.isNotEmpty == true ? 'Unit ${tx.unitNumber}' : 'General';
    return OrbixListTile(
      icon: tx.reconciled ? LapisIconName.arrowDownLeft : LapisIconName.clock,
      iconColor: tx.reconciled ? C.mintText : C.amberText,
      iconBg: tx.reconciled ? C.mintBg : C.amberBg,
      circularIcon: true,
      title: tx.tenantName?.isNotEmpty == true ? tx.tenantName! : tx.reference,
      subtitle: unitText,
      amountPrefix: 'KES',
      amount: tx.amount.toLocaleString(),
      amountColor: tx.reconciled ? C.textPrimary : C.amberText,
      onTap: () => showPaymentDetailsSheet(
        context,
        tx,
        isAdmin: true,
        tenants: tenants,
        unitTypeLabel: _unitTypeFor(tx.unitNumber),
        onReconciled: () => _loadPortfolio(silent: true),
      ),
    );
  }

  /// Full Ledger payment row: displays FULL non-truncated M-Pesa confirmation code in monospace!
  Widget _buildLedgerPaymentTile(TransactionModel tx, List<TenantModel> tenants) {
    final unitPrefix = tx.unitNumber?.isNotEmpty == true ? 'Unit ${tx.unitNumber} · ' : '';
    return OrbixListTile(
      icon: tx.reconciled ? LapisIconName.arrowDownLeft : LapisIconName.clock,
      iconColor: tx.reconciled ? C.mintText : C.amberText,
      iconBg: tx.reconciled ? C.mintBg : C.amberBg,
      circularIcon: true,
      title: tx.tenantName?.isNotEmpty == true ? tx.tenantName! : 'Resident',
      subtitleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$unitPrefix${formatShortDate(tx.date)}',
            style: sans(11, color: C.textMuted, fontFeatures: kTabularNums),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            tx.reference,
            softWrap: false,
            style: mono(11.5, color: C.textSecondary, weight: FontWeight.w600, letterSpacing: 0.3),
          ),
        ],
      ),
      amountPrefix: 'KES',
      amount: tx.amount.toLocaleString(),
      amountColor: tx.reconciled ? C.textPrimary : C.amberText,
      status: tx.reconciled ? null : StatusPill.amber(tx.statusDisplayLabel),
      onTap: () => showPaymentDetailsSheet(
        context,
        tx,
        isAdmin: true,
        tenants: tenants,
        unitTypeLabel: _unitTypeFor(tx.unitNumber),
        onReconciled: () => _loadPortfolio(silent: true),
      ),
    );
  }

  Widget _sectionHeader(String title, {String? actionLabel, VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: flex(13.5, color: C.textPrimary)),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(actionLabel, style: sans(12, color: C.navy, weight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  // --- TAB 1: UNIFIED PROPERTY HUB (Units | Tenants | Leases) ---
  Widget _buildPropertyHub(DashboardData d) {
    final vacantUnits = d.units.where((u) => !u.isOccupied).toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: C.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 16,
          title: Text('Property', style: flex(17, color: C.textPrimary)),
          actions: [
            if (_propertySegment == 0) ...[
              TextButton(
                onPressed: () => showUnitTypesSheet(context, onChanged: () => _loadPortfolio(silent: true)),
                child: Text('Types', style: sans(12, color: C.textSecondary, weight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () => showCreateUnitSheet(context, onCreated: () => _loadPortfolio(silent: true)),
                child: Text('+ Unit', style: sans(12, color: C.navy, weight: FontWeight.w700)),
              ),
            ] else if (_propertySegment == 1) ...[
              TextButton(
                onPressed: () => showCreateTenantSheet(context, onCreated: () => _loadPortfolio(silent: true)),
                child: Text('+ Resident', style: sans(12, color: C.navy, weight: FontWeight.w700)),
              ),
            ] else ...[
              TextButton(
                onPressed: () => showCreateLeaseSheet(
                  context,
                  units: d.units,
                  tenants: d.tenants,
                  onCreated: () => _loadPortfolio(silent: true),
                ),
                child: Text('+ Lease', style: sans(12, color: C.navy, weight: FontWeight.w700)),
              ),
            ],
            const SizedBox(width: 4),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(96),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: C.canvas,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: C.border),
                    ),
                    child: Row(
                      children: [
                        _segTab('Units (${d.units.length})', 0),
                        _segTab('Tenants (${d.tenants.length})', 1),
                        _segTab('Leases (${d.leases.length})', 2),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _compactSearchField(
                    controller: _propertySearchCtrl,
                    hint: _propertySegment == 0
                        ? 'Search unit number or type...'
                        : (_propertySegment == 1 ? 'Search resident name, phone, unit...' : 'Search lease, resident, unit...'),
                    value: _propertySearch,
                    onChanged: (v) => setState(() => _propertySearch = v.trim().toLowerCase()),
                  ),
                ),
                const Divider(height: 1, color: C.borderLight),
              ],
            ),
          ),
        ),
        if (_propertySegment == 0)
          _buildUnitsSliver(d)
        else if (_propertySegment == 1)
          _buildTenantsSliver(d)
        else
          _buildLeasesSliver(d, vacantUnits),
      ],
    );
  }

  Widget _compactSearchField({
    required TextEditingController controller,
    required String hint,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: sans(12.5, color: C.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: sans(12, color: C.textMuted),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 10, right: 6),
            child: LapisIcon(LapisIconName.search, size: 15, color: C.textMuted),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          suffixIcon: value.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    controller.clear();
                    onChanged('');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Center(
                      widthFactor: 1,
                      child: Text('Clear', style: sans(11, color: C.navy, weight: FontWeight.w600)),
                    ),
                  ),
                )
              : null,
          filled: true,
          fillColor: C.canvas,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: C.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: C.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: C.navy, width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _segTab(String label, int index) {
    final active = _propertySegment == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _propertySegment = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? C.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: sans(
              11.5,
              color: active ? Colors.white : C.textSecondary,
              weight: FontWeight.w600,
              fontFeatures: kTabularNums,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnitsSliver(DashboardData d) {
    final q = _propertySearch;
    final items = q.isEmpty
        ? d.units
        : d.units.where((u) {
            return u.unitNumber.toLowerCase().contains(q) ||
                u.type.toLowerCase().contains(q) ||
                formatUnitTypeLabel(u.type).toLowerCase().contains(q) ||
                (u.isOccupied ? 'occupied' : 'vacant').contains(q);
          }).toList();

    if (items.isEmpty) {
      return SliverFillRemaining(
        child: Center(child: Text(q.isEmpty ? 'No units yet.' : 'No matching units.', style: sans(12.5, color: C.textMuted))),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      sliver: SliverList.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final u = items[i];
          final occ = u.isOccupied;
          return OrbixListTile(
            icon: LapisIconName.building,
            iconColor: occ ? C.mintText : C.amberText,
            iconBg: occ ? C.mintBg : C.amberBg,
            title: 'Unit ${u.unitNumber}',
            subtitle: formatUnitTypeLabel(u.type),
            amountPrefix: 'KES',
            amount: u.monthlyRent.toLocaleString(),
            status: occ ? StatusPill.mint('Occupied', hasDot: false) : StatusPill.amber('Vacant', hasDot: false),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => UnitDetailsPage(unit: u, allTenants: d.tenants)))
                .then((_) => _loadPortfolio(silent: true)),
          );
        },
      ),
    );
  }

  Widget _buildTenantsSliver(DashboardData d) {
    final q = _propertySearch;
    final items = q.isEmpty
        ? d.tenants
        : d.tenants.where((t) {
            return t.name.toLowerCase().contains(q) ||
                t.email.toLowerCase().contains(q) ||
                t.phone.toLowerCase().contains(q) ||
                t.currentUnitNumber.toLowerCase().contains(q);
          }).toList();

    if (items.isEmpty) {
      return SliverFillRemaining(
        child: Center(child: Text(q.isEmpty ? 'No residents yet.' : 'No matching residents.', style: sans(12.5, color: C.textMuted))),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      sliver: SliverList.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => _buildResidentTile(items[i]),
      ),
    );
  }

  Widget _buildLeasesSliver(DashboardData d, List<UnitModel> vacantUnits) {
    final q = _propertySearch;
    final items = q.isEmpty
        ? d.leases
        : d.leases.where((l) {
            return l.unitNumber.toLowerCase().contains(q) ||
                l.tenantName.toLowerCase().contains(q) ||
                l.leaseNumber.toLowerCase().contains(q) ||
                l.status.toLowerCase().contains(q);
          }).toList();

    if (items.isEmpty) {
      return SliverFillRemaining(
        child: Center(child: Text(q.isEmpty ? 'No leases yet.' : 'No matching leases.', style: sans(12.5, color: C.textMuted))),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      sliver: SliverList.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final l = items[i];
          return OrbixListTile(
            icon: LapisIconName.fileText,
            iconColor: C.navy,
            iconBg: C.navySoftBg,
            title: 'Unit ${l.unitNumber} · ${l.tenantName}',
            subtitle: 'Due ${formatShortDate(l.nextPaymentDueDate)}',
            amountPrefix: 'KES',
            amount: l.monthlyRent.toLocaleString(),
            status: l.isActive
                ? (l.isDepositSettled ? StatusPill.mint('Active', hasDot: false) : StatusPill.amber('Deposit'))
                : StatusPill.slate(formatStatusLabel(l.status)),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => LeaseDetailsPage(lease: l, vacantUnits: vacantUnits)))
                .then((_) => _loadPortfolio(silent: true)),
          );
        },
      ),
    );
  }

  // --- TAB 2: LEDGER (Full Non-Truncated M-Pesa Codes + Live Search) ---
  Widget _buildLedgerTab(DashboardData d) {
    final q = _ledgerSearch;
    final filteredTx = q.isEmpty
        ? _pagedTransactions
        : _pagedTransactions.where((tx) {
            return tx.reference.toLowerCase().contains(q) ||
                (tx.tenantName ?? '').toLowerCase().contains(q) ||
                (tx.unitNumber ?? '').toLowerCase().contains(q) ||
                tx.amount.toString().contains(q);
          }).toList();

    return CustomScrollView(
      controller: _ledgerScrollCtrl,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: C.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 16,
          title: Text('Ledger', style: flex(17, color: C.textPrimary)),
          actions: [
            TextButton(
              onPressed: () => showAdminCollectPaymentSheet(
                context,
                tenants: d.tenants,
                leases: d.leases,
                onComplete: () => _loadPortfolio(silent: true),
              ),
              child: Text('+ Collect', style: sans(12.5, color: C.navy, weight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _compactSearchField(
                    controller: _ledgerSearchCtrl,
                    hint: 'Search resident, unit or M-Pesa code...',
                    value: _ledgerSearch,
                    onChanged: (v) => setState(() => _ledgerSearch = v.trim().toLowerCase()),
                  ),
                ),
                const Divider(height: 1, color: C.borderLight),
              ],
            ),
          ),
        ),
        if (filteredTx.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Text(
                q.isEmpty ? 'No transactions yet.' : 'No matching transactions.',
                style: sans(12.5, color: C.textMuted),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            sliver: SliverList.builder(
              itemCount: filteredTx.length + (q.isEmpty && _hasMoreTx ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == filteredTx.length) {
                  return const Padding(
                    padding: EdgeInsets.all(14),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.navy)),
                  );
                }
                return _buildLedgerPaymentTile(filteredTx[i], d.tenants);
              },
            ),
          ),
      ],
    );
  }

  // --- TAB 3: MAINTENANCE TICKETS ---
  Widget _buildTicketsTab(DashboardData d) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: C.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 16,
          title: Text('Maintenance', style: flex(17, color: C.textPrimary)),
          actions: [
            TextButton(
              onPressed: () => showCreateMaintenanceSheet(
                context,
                isAdmin: true,
                tenants: d.tenants,
                onCreated: () => _loadPortfolio(silent: true),
              ),
              child: Text('+ Ticket', style: sans(12.5, color: C.navy, weight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: C.borderLight),
          ),
        ),
        if (_tickets.isEmpty)
          SliverFillRemaining(
            child: Center(child: Text('No tickets yet.', style: sans(12.5, color: C.textMuted))),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            sliver: SliverList.builder(
              itemCount: _tickets.length,
              itemBuilder: (_, i) {
                final tk = _tickets[i];
                final isResolved = tk.status == 'resolved';
                final isInProgress = tk.status == 'in_progress';
                return OrbixListTile(
                  icon: LapisIconName.wrench,
                  iconColor: isResolved ? C.mintText : (isInProgress ? C.navy : C.amberText),
                  iconBg: isResolved ? C.mintBg : (isInProgress ? C.navySoftBg : C.amberBg),
                  title: tk.title,
                  subtitle: 'Unit ${tk.unitNumber.isNotEmpty ? tk.unitNumber : "Suite"} · ${tk.tenantName}',
                  amount: '',
                  status: isResolved
                      ? StatusPill.mint(formatStatusLabel(tk.status), hasDot: false)
                      : (isInProgress
                          ? StatusPill.blue(formatStatusLabel(tk.status), hasDot: true)
                          : StatusPill.amber(formatStatusLabel(tk.status))),
                  onTap: () => showMaintenanceDetailSheet(
                    context,
                    tk,
                    isAdmin: true,
                    onUpdated: () => _loadPortfolio(silent: true),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
