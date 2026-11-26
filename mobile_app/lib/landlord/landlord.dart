import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/api.dart';
import '../core/widgets.dart';
import '../core/sheets.dart';
import '../pages/unit_details_page.dart';
import '../pages/tenant_details_page.dart';
import '../pages/lease_details_page.dart';
import '../pages/profile_settings_page.dart';

class LandlordPortfolioScreen extends StatefulWidget {
  const LandlordPortfolioScreen({super.key});

  @override
  State<LandlordPortfolioScreen> createState() => _LandlordPortfolioScreenState();
}

class _LandlordPortfolioScreenState extends State<LandlordPortfolioScreen> {
  int _currentNavIndex = 0;
  DashboardData? _data;
  List<TransactionModel> _pagedTransactions = [];
  List<MaintenanceTicket> _tickets = [];
  bool _isLoading = true;
  String? _error;
  NetworkStatus? _net;
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
    if (mounted) setState(() => _net = n);

    if (!n.isOnline) {
      if (!silent && mounted) {
        setState(() {
          _isLoading = false;
          _error = n.message ?? 'Unable to reach Lapis Suites server.';
        });
      }
      return;
    }

    try {
      final results = await Future.wait([
        ApiService.fetchDashboardStats(),
        ApiService.fetchMaintenance(),
      ]);
      final d = results[0] as DashboardData;
      final tks = results[1] as List<MaintenanceTicket>;

      if (mounted) {
        setState(() {
          _data = d;
          _tickets = tks;
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
        showAppSnackBar(context, 'All resident balances reconciled.');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, ApiService.friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isReconciling = false);
    }
  }

  void _openProfile() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ProfileSettingsPage()))
        .then((_) => _loadPortfolio(silent: true));
  }

  String _getTitleForTab() {
    switch (_currentNavIndex) {
      case 1:
        return 'Units';
      case 2:
        return 'Leases';
      case 3:
        return 'Rent Payments';
      case 4:
        return 'Maintenance';
      default:
        return 'Dashboard';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.surface,
        elevation: 0,
        titleSpacing: 16,
        title: Text(
          _getTitleForTab(),
          style: flex(15.5, color: C.textPrimary, weight: FontWeight.w700),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: C.border),
        ),
        actions: [
          Center(
            child: (_net?.isOnline ?? false)
                ? StatusPill.mint('Live')
                : StatusPill.rose('Offline'),
          ),
          IconButton(
            tooltip: 'Account & Settings',
            icon: const Icon(CupertinoIcons.person_crop_circle, size: 20, color: C.textSecondary),
            onPressed: _openProfile,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.2, color: C.blueText))
          : _error != null
              ? ErrorStateCard(message: _error!, onRetry: () => _loadPortfolio())
              : RefreshIndicator(
                  onRefresh: _loadPortfolio,
                  color: C.blueText,
                  backgroundColor: C.surface,
                  child: _buildCurrentTab(),
                ),
      bottomNavigationBar: OrbixBottomNav(
        currentIndex: _currentNavIndex,
        onTap: (idx) => setState(() => _currentNavIndex = idx),
        items: const [
          BottomNavItem(CupertinoIcons.house_fill, 'Home'),
          BottomNavItem(CupertinoIcons.building_2_fill, 'Units'),
          BottomNavItem(CupertinoIcons.doc_text_fill, 'Leases'),
          BottomNavItem(CupertinoIcons.creditcard_fill, 'Ledger'),
          BottomNavItem(CupertinoIcons.wrench_fill, 'Tickets'),
        ],
      ),
    );
  }

  Widget _buildCurrentTab() {
    final d = _data!;
    switch (_currentNavIndex) {
      case 1:
        return _buildUnitsView(d);
      case 2:
        return _buildLeasesView(d);
      case 3:
        return _buildLedgerView(d);
      case 4:
        return _buildMaintenanceView(d);
      default:
        return _buildHomeOverview(d);
    }
  }

  // --- TAB 0: DASHBOARD OVERVIEW ---
  Widget _buildHomeOverview(DashboardData d) {
    final openTickets = _tickets.where((t) => t.status != 'resolved' && t.status != 'cancelled').length;
    final pendingApprovals = d.transactions.where((tx) => tx.needsApproval).toList();

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (pendingApprovals.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: GestureDetector(
              onTap: () => setState(() => _currentNavIndex = 3),
              child: InlineAlert(
                message:
                    '${pendingApprovals.length} payment${pendingApprovals.length == 1 ? '' : 's'} awaiting verification/reconciliation. Tap to review in Ledger.',
                isInfo: false,
              ),
            ),
          ),

        OrbixOverviewCard(
          title: 'Portfolio',
          period: currentMonthYearLabel(),
          heroLabel: 'Monthly Recurring Revenue',
          heroValue: 'KES ${d.totalRentRoll.toLocaleString()}',
          extraAction: GestureDetector(
            onTap: _isReconciling ? null : _handleReconcile,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.arrow_2_circlepath, size: 11, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    _isReconciling ? 'Syncing...' : 'Reconcile',
                    style: sans(10, color: Colors.white, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          metrics: [
            MetricItem('Occupancy', '${d.occupancyRate.toStringAsFixed(0)}%'),
            MetricItem('Units', '${d.occupiedUnits}/${d.units.length}'),
            MetricItem('Arrears', 'KES ${d.totalArrears.toK()}'),
            MetricItem('Tickets', '$openTickets open'),
          ],
        ),

        // Quick Admin Action Strip
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: _quickActionBtn(
                  icon: CupertinoIcons.money_dollar_circle,
                  label: 'Collect Pay',
                  color: C.mintText,
                  bg: C.mintBg,
                  onTap: () => showAdminCollectPaymentSheet(
                    context,
                    tenants: d.tenants,
                    onComplete: () => _loadPortfolio(silent: true),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _quickActionBtn(
                  icon: CupertinoIcons.plus_square,
                  label: 'Add Unit',
                  color: C.blueText,
                  bg: C.blueBg,
                  onTap: () => showCreateUnitSheet(context, onCreated: () => _loadPortfolio(silent: true)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _quickActionBtn(
                  icon: CupertinoIcons.wrench,
                  label: 'New Ticket',
                  color: C.amberText,
                  bg: C.amberBg,
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

        // Residents Quick Access
        if (d.tenants.isNotEmpty) ...[
          _sectionHeader(
            'Residents (${d.tenants.length})',
            actionLabel: 'Units',
            onAction: () => setState(() => _currentNavIndex = 1),
          ),
          ...d.tenants.take(3).map((t) {
            return OrbixListTile(
              icon: CupertinoIcons.person_fill,
              iconColor: t.hasArrears ? C.amberText : C.blueText,
              iconBg: t.hasArrears ? C.amberBg : C.blueBg,
              title: t.name,
              subtitle:
                  '${t.currentUnitNumber.isNotEmpty ? "Unit ${t.currentUnitNumber}" : "Unassigned"} · ${t.phone.isNotEmpty ? t.phone : t.email}',
              amount: t.hasArrears
                  ? 'KES ${t.effectiveBalanceDue.toLocaleString()}'
                  : (t.hasCredit ? 'Credit ${t.accountCredit.toK()}' : 'Settled'),
              amountColor: t.hasArrears ? C.roseText : C.mintText,
              status: t.hasArrears ? StatusPill.amber('Due') : StatusPill.mint('Current'),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => TenantDetailsPage(tenant: t)))
                  .then((_) => _loadPortfolio(silent: true)),
            );
          }),
        ],

        // Recent Transactions
        _sectionHeader(
          'Recent Payments',
          actionLabel: 'View all',
          onAction: () => setState(() => _currentNavIndex = 3),
        ),
        if (d.transactions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No transactions recorded yet.', style: sans(12, color: C.textMuted)),
          )
        else
          ...d.transactions.take(5).map((tx) {
            return OrbixListTile(
              icon: tx.isMpesa ? CupertinoIcons.device_phone_portrait : CupertinoIcons.creditcard,
              iconColor: tx.reconciled ? C.mintText : C.amberText,
              iconBg: tx.reconciled ? C.mintBg : C.amberBg,
              title: tx.tenantName?.isNotEmpty == true ? tx.tenantName! : tx.reference,
              subtitle:
                  '${tx.unitNumber?.isNotEmpty == true ? "Unit ${tx.unitNumber} · " : ""}${formatShortDate(tx.date)} · ${tx.reference}',
              amount: 'KES ${tx.amount.toLocaleString()}',
              amountColor: tx.reconciled ? C.mintText : C.amberText,
              status: tx.reconciled
                  ? StatusPill.mint('Reconciled')
                  : StatusPill.amber(tx.statusDisplayLabel),
              onTap: () => showPaymentDetailsSheet(
                context,
                tx,
                isAdmin: true,
                tenants: d.tenants,
                onReconciled: () => _loadPortfolio(silent: true),
              ),
            );
          }),
      ],
    );
  }

  Widget _quickActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return Material(
      color: C.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: C.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
                child: Icon(icon, size: 13, color: color),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: sans(11.5, color: C.textPrimary, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {String? actionLabel, VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: flex(13, color: C.textPrimary)),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(actionLabel, style: sans(11.5, color: C.blueText, weight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  // --- TAB 1: UNITS ---
  Widget _buildUnitsView(DashboardData d) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${d.occupiedUnits} Occupied · ${d.units.length - d.occupiedUnits} Vacant',
                style: sans(11.5, color: C.textMuted, weight: FontWeight.w600),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => showUnitTypesSheet(
                      context,
                      onChanged: () => _loadPortfolio(silent: true),
                    ),
                    child: StatusPill.slate('Unit Types'),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => showCreateUnitSheet(context, onCreated: () => _loadPortfolio(silent: true)),
                    child: StatusPill.blue('+ Add Unit', hasDot: false),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: d.units.isEmpty
              ? Center(child: Text('No units configured yet.', style: sans(12, color: C.textMuted)))
              : ListView.builder(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: d.units.length,
                  itemBuilder: (context, i) {
                    final u = d.units[i];
                    final occ = u.isOccupied;
                    return OrbixListTile(
                      icon: CupertinoIcons.building_2_fill,
                      iconColor: occ ? C.mintText : C.amberText,
                      iconBg: occ ? C.mintBg : C.amberBg,
                      title: 'Unit ${u.unitNumber}',
                      subtitle:
                          '${formatUnitTypeLabel(u.type)} · ${occ ? (u.currentTenantName ?? "Occupied") : "Vacant"}',
                      amount: 'KES ${u.monthlyRent.toLocaleString()}',
                      status: occ ? StatusPill.mint('Occupied') : StatusPill.amber('Vacant'),
                      onTap: () => Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => UnitDetailsPage(unit: u, allTenants: d.tenants),
                            ),
                          )
                          .then((_) => _loadPortfolio(silent: true)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- TAB 2: LEASES ---
  Widget _buildLeasesView(DashboardData d) {
    if (d.leases.isEmpty) {
      return Center(child: Text('No leases on record.', style: sans(12, color: C.textMuted)));
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: d.leases.length,
      itemBuilder: (context, i) {
        final l = d.leases[i];
        return OrbixListTile(
          icon: CupertinoIcons.doc_text_fill,
          iconColor: C.blueText,
          iconBg: C.blueBg,
          title: 'Unit ${l.unitNumber} · ${l.tenantName}',
          subtitle: '${l.leaseNumber} · Due ${formatShortDate(l.nextPaymentDueDate)}',
          amount: 'KES ${l.monthlyRent.toLocaleString()}',
          status: l.isActive
              ? (l.isDepositSettled ? StatusPill.mint('Active') : StatusPill.amber('Deposit Pending'))
              : StatusPill.slate(formatStatusLabel(l.status)),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => LeaseDetailsPage(lease: l)))
              .then((_) => _loadPortfolio(silent: true)),
        );
      },
    );
  }

  // --- TAB 3: LEDGER ---
  Widget _buildLedgerView(DashboardData d) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_pagedTransactions.length} Transactions',
                style: sans(11.5, color: C.textMuted, weight: FontWeight.w600),
              ),
              GestureDetector(
                onTap: () => showAdminCollectPaymentSheet(
                  context,
                  tenants: d.tenants,
                  onComplete: () => _loadPortfolio(silent: true),
                ),
                child: StatusPill.mint('+ Record / STK Push', hasDot: false),
              ),
            ],
          ),
        ),
        Expanded(
          child: _pagedTransactions.isEmpty
              ? Center(child: Text('No transactions recorded yet.', style: sans(12, color: C.textMuted)))
              : ListView.builder(
                  controller: _ledgerScrollCtrl,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: _pagedTransactions.length + (_hasMoreTx ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _pagedTransactions.length) {
                      return const Padding(
                        padding: EdgeInsets.all(14),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.blueText)),
                      );
                    }
                    final tx = _pagedTransactions[i];
                    return OrbixListTile(
                      icon: tx.isMpesa ? CupertinoIcons.device_phone_portrait : CupertinoIcons.creditcard,
                      iconColor: tx.reconciled ? C.mintText : C.amberText,
                      iconBg: tx.reconciled ? C.mintBg : C.amberBg,
                      title: tx.tenantName?.isNotEmpty == true ? tx.tenantName! : tx.reference,
                      subtitle:
                          '${tx.unitNumber?.isNotEmpty == true ? "Unit ${tx.unitNumber} · " : ""}${formatShortDate(tx.date)} · ${tx.reference}',
                      amount: 'KES ${tx.amount.toLocaleString()}',
                      amountColor: tx.reconciled ? C.mintText : C.amberText,
                      status: tx.reconciled
                          ? StatusPill.mint('Reconciled')
                          : StatusPill.amber(tx.statusDisplayLabel),
                      onTap: () => showPaymentDetailsSheet(
                        context,
                        tx,
                        isAdmin: true,
                        tenants: d.tenants,
                        onReconciled: () => _loadPortfolio(silent: true),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- TAB 4: MAINTENANCE TICKETS (Admin Management + Quick SMS Templates) ---
  Widget _buildMaintenanceView(DashboardData d) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_tickets.length} Total Requests',
                style: sans(11.5, color: C.textMuted, weight: FontWeight.w600),
              ),
              GestureDetector(
                onTap: () => showCreateMaintenanceSheet(
                  context,
                  isAdmin: true,
                  tenants: d.tenants,
                  onCreated: () => _loadPortfolio(silent: true),
                ),
                child: StatusPill.blue('+ New Ticket', hasDot: false),
              ),
            ],
          ),
        ),
        Expanded(
          child: _tickets.isEmpty
              ? Center(child: Text('No maintenance tickets yet.', style: sans(12, color: C.textMuted)))
              : ListView.builder(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: _tickets.length,
                  itemBuilder: (context, i) {
                    final tk = _tickets[i];
                    final isResolved = tk.status == 'resolved';
                    final isInProgress = tk.status == 'in_progress';

                    return OrbixListTile(
                      icon: CupertinoIcons.wrench_fill,
                      iconColor: isResolved ? C.mintText : (isInProgress ? C.blueText : C.amberText),
                      iconBg: isResolved ? C.mintBg : (isInProgress ? C.blueBg : C.amberBg),
                      title: tk.title,
                      subtitle:
                          'Unit ${tk.unitNumber.isNotEmpty ? tk.unitNumber : "Suite"} · ${tk.tenantName} · ${formatCategoryLabel(tk.category)}',
                      amount: '',
                      status: isResolved
                          ? StatusPill.mint(formatStatusLabel(tk.status))
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
