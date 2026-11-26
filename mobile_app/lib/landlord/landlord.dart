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
    if (_data == null || _data!.tenants.isEmpty) return;
    setState(() => _isReconciling = true);

    try {
      for (final t in _data!.tenants) {
        await ApiService.reconcileTenant(t.id);
      }
      await _loadPortfolio(silent: true);
      if (mounted) {
        showAppSnackBar(context, 'Balances reconciled.');
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

              // 2. Upgraded 3-Column Circular Action Grid
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
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
                          onComplete: () => _loadPortfolio(silent: true),
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

              // 4. Polished Residents Preview
              if (d.tenants.isNotEmpty) ...[
                _sectionHeader(
                  'Residents',
                  actionLabel: 'Manage',
                  onAction: () => _goToPropertySegment(1),
                ),
                ...d.tenants.take(3).map((t) => _buildResidentTile(t)),
              ],

              // 5. Minimal Recent Payments (Name, Unit, Amount only — tap for full receipt)
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
                ...d.transactions.take(4).map((tx) => _buildMinimalDashboardPaymentTile(tx, d.tenants)),
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
            const SizedBox(height: 6),
            Text(
              label,
              style: sans(12, color: C.textPrimary, weight: FontWeight.w500),
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

  Widget _buildResidentTile(TenantModel t) {
    final isUnassigned = t.currentUnitNumber.isEmpty;
    final avatarBg = t.hasArrears ? C.navySoftBg : C.mintBg;
    final avatarFg = t.hasArrears ? C.navy : C.mintText;

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
              'Unit ${t.currentUnitNumber}',
              style: sans(11.5, color: C.textMuted, weight: FontWeight.w500, fontFeatures: kTabularNums),
            ),
      amountPrefix: 'KES',
      amount: t.hasArrears
          ? t.effectiveBalanceDue.toLocaleString()
          : (t.hasCredit ? t.accountCredit.toLocaleString() : '0'),
      amountColor: t.hasArrears ? C.roseText : C.mintText,
      status: t.hasArrears
          ? StatusPill.amber('Due')
          : (t.hasCredit ? StatusPill.mint('Credit') : StatusPill.mint('Current')),
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
      status: tx.reconciled
          ? StatusPill.mint('Reconciled', hasDot: false)
          : StatusPill.amber(tx.statusDisplayLabel),
      onTap: () => showPaymentDetailsSheet(
        context,
        tx,
        isAdmin: true,
        tenants: tenants,
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
            preferredSize: const Size.fromHeight(50),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
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
    if (d.units.isEmpty) {
      return SliverFillRemaining(
        child: Center(child: Text('No units yet.', style: sans(12.5, color: C.textMuted))),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      sliver: SliverList.builder(
        itemCount: d.units.length,
        itemBuilder: (_, i) {
          final u = d.units[i];
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
    if (d.tenants.isEmpty) {
      return SliverFillRemaining(
        child: Center(child: Text('No residents yet.', style: sans(12.5, color: C.textMuted))),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      sliver: SliverList.builder(
        itemCount: d.tenants.length,
        itemBuilder: (_, i) => _buildResidentTile(d.tenants[i]),
      ),
    );
  }

  Widget _buildLeasesSliver(DashboardData d, List<UnitModel> vacantUnits) {
    if (d.leases.isEmpty) {
      return SliverFillRemaining(
        child: Center(child: Text('No leases yet.', style: sans(12.5, color: C.textMuted))),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      sliver: SliverList.builder(
        itemCount: d.leases.length,
        itemBuilder: (_, i) {
          final l = d.leases[i];
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

  // --- TAB 2: LEDGER (Full Non-Truncated M-Pesa Codes) ---
  Widget _buildLedgerTab(DashboardData d) {
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
                onComplete: () => _loadPortfolio(silent: true),
              ),
              child: Text('+ Collect', style: sans(12.5, color: C.navy, weight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: C.borderLight),
          ),
        ),
        if (_pagedTransactions.isEmpty)
          SliverFillRemaining(
            child: Center(child: Text('No transactions yet.', style: sans(12.5, color: C.textMuted))),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            sliver: SliverList.builder(
              itemCount: _pagedTransactions.length + (_hasMoreTx ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _pagedTransactions.length) {
                  return const Padding(
                    padding: EdgeInsets.all(14),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.navy)),
                  );
                }
                return _buildLedgerPaymentTile(_pagedTransactions[i], d.tenants);
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
