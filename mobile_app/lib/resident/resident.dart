import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/api.dart';
import '../core/widgets.dart';
import '../core/sheets.dart';
import '../core/icons.dart';
import '../pages/lease_details_page.dart';
import '../pages/notifications_page.dart';
import '../pages/profile_settings_page.dart';

class ResidentHomeScreen extends StatefulWidget {
  const ResidentHomeScreen({super.key});

  @override
  State<ResidentHomeScreen> createState() => _ResidentHomeScreenState();
}

class _ResidentHomeScreenState extends State<ResidentHomeScreen> {
  int _navIndex = 0; // 0: Home, 1: Payments, 2: Support, 3: Settings
  TenantModel? _tenant;
  List<LeaseModel> _myLeases = [];
  String? _selectedLeaseId;
  List<TransactionModel> _myTxs = [];
  List<MaintenanceTicket> _myTickets = [];
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  bool _showBreakdown = false;
  String? _error;

  List<LeaseModel> get _activeLeases => _myLeases.where((l) => l.isActive).toList();

  LeaseModel? get _lease {
    final active = _activeLeases;
    if (active.isNotEmpty) {
      if (_selectedLeaseId != null) {
        final match = active.where((l) => l.id == _selectedLeaseId).toList();
        if (match.isNotEmpty) return match.first;
      }
      return active.first;
    }
    return _myLeases.isNotEmpty ? _myLeases.first : null;
  }

  final ScrollController _payScrollCtrl = ScrollController();
  int _payPage = 1;
  bool _isLoadingMorePay = false;
  bool _hasMorePay = true;

  @override
  void initState() {
    super.initState();
    ApiService.realtimeUpdateNotifier.addListener(_onRealtimeUpdate);
    _payScrollCtrl.addListener(_onPayScroll);
    _loadResidentScope();
  }

  @override
  void dispose() {
    ApiService.realtimeUpdateNotifier.removeListener(_onRealtimeUpdate);
    _payScrollCtrl.dispose();
    super.dispose();
  }

  void _onRealtimeUpdate() {
    if (!mounted) return;
    if (ApiService.pendingDeepLinkPay) {
      ApiService.pendingDeepLinkPay = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPayRentSheet();
      });
    }
    _loadResidentScope(silent: true);
  }

  void _onPayScroll() {
    if (!_payScrollCtrl.hasClients) return;
    if (_payScrollCtrl.position.pixels >= _payScrollCtrl.position.maxScrollExtent - 100) {
      if (!_isLoadingMorePay && _hasMorePay && _tenant != null) {
        _loadMorePayments();
      }
    }
  }

  Future<void> _loadResidentScope({bool silent = false}) async {
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
      final tenantId =
          (ApiService.currentUser?['tenantId'] ?? ApiService.currentUser?['userId'] ?? '').toString();

      final results = await Future.wait([
        ApiService.fetchTenantProfile(tenantId),
        ApiService.fetchTenantLeases(tenantId),
        ApiService.fetchTenantTransactions(tenantId, page: 1, limit: 20),
        ApiService.fetchMaintenance(),
        ApiService.fetchSettings(),
        ApiService.fetchNotifications(),
      ]);

      final profile = results[0] as TenantModel?;
      final leases = results[1] as List<LeaseModel>;
      final txs = results[2] as List<TransactionModel>;
      final tickets = results[3] as List<MaintenanceTicket>;
      final notifs = results[5] as List<NotificationModel>;

      if (mounted) {
        setState(() {
          _tenant = profile;
          _myLeases = leases;
          final active = leases.where((l) => l.isActive).toList();
          if (active.isNotEmpty && (_selectedLeaseId == null || !active.any((l) => l.id == _selectedLeaseId))) {
            _selectedLeaseId = active.first.id;
          }
          _myTxs = txs;
          _myTickets = tickets;
          _notifications = notifs;
          _payPage = 1;
          _hasMorePay = txs.length >= 20;
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

  Future<void> _loadMorePayments() async {
    if (_tenant == null) return;
    setState(() => _isLoadingMorePay = true);
    try {
      final nextPage = _payPage + 1;
      final more = await ApiService.fetchTenantTransactions(_tenant!.id, page: nextPage, limit: 20);
      if (mounted) {
        setState(() {
          if (more.isEmpty) {
            _hasMorePay = false;
          } else {
            _payPage = nextPage;
            _myTxs.addAll(more);
          }
          _isLoadingMorePay = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMorePay = false);
    }
  }

  void _openNotificationsPage() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NotificationsPage()))
        .then((_) => _loadResidentScope(silent: true));
  }

  void _openPayRentSheet() {
    final t = _tenant;
    final l = _lease;
    final defaultAmt = (t != null && t.effectiveBalanceDue > 0)
        ? t.effectiveBalanceDue
        : (l?.monthlyRent ?? 0);

    showStkPushSheet(
      context,
      defaultPhone: t?.phone ?? ApiService.currentUser?['phone']?.toString() ?? '',
      defaultAmount: defaultAmt,
      unitNumber: l?.unitNumber.isNotEmpty == true
          ? l!.unitNumber
          : (t?.currentUnitNumber.isNotEmpty == true
              ? t!.currentUnitNumber
              : ApiService.currentUser?['unitNumber']?.toString() ?? ''),
      tenantId: t?.id ?? ApiService.currentUser?['tenantId']?.toString(),
      unitId: l?.unitId ?? t?.currentUnitId,
      leaseId: l?.id,
      payerName: t?.name ?? ApiService.currentUser?['name']?.toString(),
      onComplete: () => _loadResidentScope(silent: true),
    );
  }

  void _openReportIssueModal() {
    showCreateMaintenanceSheet(
      context,
      isAdmin: false,
      unitNumber: _lease?.unitNumber.isNotEmpty == true
          ? _lease!.unitNumber
          : (_tenant?.currentUnitNumber ?? ''),
      unitId: _lease?.unitId ?? _tenant?.currentUnitId,
      onCreated: () => _loadResidentScope(silent: true),
    );
  }

  String _getHeaderSubtitle() {
    final unitNum = _lease?.unitNumber.isNotEmpty == true
        ? _lease!.unitNumber
        : (_tenant?.currentUnitNumber.isNotEmpty == true
            ? _tenant!.currentUnitNumber
            : ApiService.currentUser?['unitNumber']?.toString() ?? '');
    final unitType = _lease?.unitType.isNotEmpty == true ? formatUnitTypeLabel(_lease!.unitType) : '';

    if (unitNum.isNotEmpty && unitType.isNotEmpty) return 'Unit $unitNum · $unitType';
    if (unitNum.isNotEmpty) return 'Unit $unitNum';
    return 'Lapis Suites';
  }

  String _buildBalanceBreakdown() {
    final l = _lease;
    final totalPaid = _myTxs
        .where((tx) => tx.reconciled)
        .fold<int>(0, (sum, tx) => sum + tx.amount);

    final parts = <String>[];
    if (l != null && l.monthlyRent > 0) {
      parts.add('Rent KES ${l.monthlyRent.toLocaleString()}');
    }
    if (l != null && !l.isDepositSettled && l.depositAmount > 0) {
      parts.add('Deposit KES ${l.depositAmount.toLocaleString()}');
    }
    if (totalPaid > 0) {
      final prefix = parts.isNotEmpty ? '− ' : '';
      return '${parts.join(' + ')}${parts.isNotEmpty ? ' ' : ''}${prefix}Paid KES ${totalPaid.toLocaleString()}';
    }
    return parts.join(' + ');
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
                    color: C.mintText,
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
      body: _navIndex == 3
          ? ProfileSettingsPage(
              showBackButton: false,
              residentLease: _lease,
              onDataChanged: () => _loadResidentScope(silent: true),
            )
          : _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.navy))
              : _error != null
                  ? ErrorStateCard(message: _error!, onRetry: () => _loadResidentScope())
                  : RefreshIndicator(
                      onRefresh: _loadResidentScope,
                      color: C.navy,
                      backgroundColor: C.surface,
                      child: _buildCurrentView(),
                    ),
      bottomNavigationBar: OrbixBottomNav(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
        items: const [
          BottomNavItem(LapisIconName.home, 'Home'),
          BottomNavItem(LapisIconName.creditCard, 'Payments'),
          BottomNavItem(LapisIconName.wrench, 'Support'),
          BottomNavItem(LapisIconName.settings, 'Settings'),
        ],
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_navIndex) {
      case 1:
        return _buildPaymentsSliver();
      case 2:
        return _buildSupportSliver();
      default:
        return _buildHomeSliver();
    }
  }

  // --- TAB 0: FINTECH HOME OVERVIEW WITH SLIVER APP BAR ---
  Widget _buildHomeSliver() {
    final t = _tenant;
    final l = _lease;
    final credit = t?.accountCredit ?? 0;
    final due = t?.effectiveBalanceDue ?? 0;
    final hasCredit = credit > 0;
    final hasDue = due > 0;

    final firstName = firstNameFrom(
      t?.name ?? ApiService.currentUser?['name']?.toString(),
      fallback: 'Resident',
    );

    final nextDue = (t?.nextPaymentDueDate.isNotEmpty == true)
        ? formatShortDate(t!.nextPaymentDueDate)
        : (l?.nextPaymentDueDate.isNotEmpty == true
            ? formatShortDate(l!.nextPaymentDueDate)
            : 'Day ${ApiService.cachedSettings.rentDueDay}');

    final heroNumber = hasDue
        ? due.toLocaleString()
        : (hasCredit ? credit.toLocaleString() : '0');
    final heroCaption = hasDue
        ? 'Next due $nextDue'
        : (hasCredit ? 'Prepaid · Covered until $nextDue' : 'Settled · Next due $nextDue');
    final breakdownText = _buildBalanceBreakdown();

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
                _getHeaderSubtitle(),
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
              // Conditional Multi-Unit Switcher (ONLY shown when resident holds 2+ active units)
              if (_activeLeases.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _activeLeases.map((leaseItem) {
                        final selected = leaseItem.id == l?.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedLeaseId = leaseItem.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                              decoration: BoxDecoration(
                                color: selected ? C.navy : C.surface,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: selected ? C.navy : C.border),
                              ),
                              child: Text(
                                'Unit ${leaseItem.unitNumber}',
                                style: sans(
                                  12,
                                  color: selected ? Colors.white : C.textSecondary,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              // 1. Clean White Fintech Hero Balance Card (color-coded balance text, no status pill badge)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: C.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: C.border.withValues(alpha: 0.7)),
                  boxShadow: [
                    BoxShadow(
                      color: C.navy.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasDue ? 'BALANCE DUE' : (hasCredit ? 'ACCOUNT CREDIT' : 'ACCOUNT STANDING'),
                      style: sans(10, color: C.textMuted, weight: FontWeight.w700, letterSpacing: 0.7),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'KES',
                          style: sans(
                            13.5,
                            color: C.textMuted,
                            weight: FontWeight.w500,
                            fontFeatures: kTabularNums,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          heroNumber,
                          style: flex(
                            28,
                            color: hasDue ? C.roseText : (hasCredit ? C.mintText : C.navy),
                            weight: FontWeight.w700,
                            letterSpacing: -0.7,
                            height: 1.08,
                            fontFeatures: kTabularNums,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      heroCaption,
                      style: sans(12, color: C.textMuted, fontFeatures: kTabularNums),
                    ),

                    if (breakdownText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => setState(() => _showBreakdown = !_showBreakdown),
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _showBreakdown ? 'Hide breakdown' : 'Breakdown',
                                  style: sans(11, color: C.textSecondary, weight: FontWeight.w600),
                                ),
                                const SizedBox(width: 4),
                                LapisIcon(
                                  _showBreakdown ? LapisIconName.chevronUp : LapisIconName.chevronDown,
                                  size: 12,
                                  color: C.textSecondary,
                                ),
                              ],
                            ),
                            if (_showBreakdown) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: C.canvas,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  breakdownText,
                                  style: sans(11, color: C.textSecondary, fontFeatures: kTabularNums),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _openPayRentSheet,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: C.navy,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const LapisIcon(LapisIconName.smartphone, size: 17, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              'Pay Rent via M-Pesa',
                              style: sans(13, color: Colors.white, weight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Compact Borderless Horizontal Unit Metadata Strip
              GestureDetector(
                onTap: l != null
                    ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeaseDetailsPage(lease: l)))
                    : null,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: C.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _stripMetric(
                          'Monthly Rent',
                          l != null ? 'KES ${l.monthlyRent.toLocaleString()}' : '—',
                        ),
                      ),
                      Container(width: 1, height: 26, color: C.borderLight),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: _stripMetric(
                            'Deposit',
                            l != null ? (l.isDepositSettled ? 'Paid' : 'Pending') : '—',
                            valueColor: l != null && !l.isDepositSettled ? C.amberText : C.textPrimary,
                          ),
                        ),
                      ),
                      Container(width: 1, height: 26, color: C.borderLight),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: _stripMetric('Next Due', nextDue),
                        ),
                      ),
                      if (l != null)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: LapisIcon(LapisIconName.chevronRight, size: 14, color: C.textSoft),
                        ),
                    ],
                  ),
                ),
              ),

              // 3. Recent Payments
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Payments', style: flex(13.5, color: C.textPrimary)),
                    if (_myTxs.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _navIndex = 1),
                        child: Text(
                          'See all',
                          style: sans(12, color: C.navy, weight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),

              if (_myTxs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: C.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.border.withValues(alpha: 0.7)),
                    ),
                    child: Column(
                      children: [
                        const LapisIcon(LapisIconName.receipt, size: 22, color: C.textSoft),
                        const SizedBox(height: 8),
                        Text('No payments yet', style: sans(12.5, color: C.textMuted)),
                      ],
                    ),
                  ),
                )
              else
                ..._myTxs.take(4).map(_buildPaymentRow),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _stripMetric(String label, String val, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: sans(10, color: C.textMuted, weight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(
          val,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: flex(12, color: valueColor ?? C.textPrimary, fontFeatures: kTabularNums),
        ),
      ],
    );
  }

  /// Resident payment row: full non-truncated M-Pesa confirmation code in monospace (no Reconciled badge)
  Widget _buildPaymentRow(TransactionModel tx) {
    final rec = tx.reconciled;
    final matchingLease = _myLeases.where((l) => l.unitNumber == tx.unitNumber).toList();
    final unitType = matchingLease.isNotEmpty ? matchingLease.first.unitType : (_lease?.unitType ?? '');
    return OrbixListTile(
      icon: rec ? LapisIconName.arrowDownLeft : LapisIconName.clock,
      iconColor: rec ? C.mintText : C.amberText,
      iconBg: rec ? C.mintBg : C.amberBg,
      circularIcon: true,
      title: formatShortDate(tx.date),
      subtitleWidget: Text(
        tx.reference,
        softWrap: false,
        style: mono(11.5, color: C.textSecondary, weight: FontWeight.w600, letterSpacing: 0.3),
      ),
      amountPrefix: 'KES',
      amount: tx.amount.toLocaleString(),
      amountColor: rec ? C.mintText : C.amberText,
      status: rec ? null : StatusPill.amber(tx.statusDisplayLabel),
      onTap: () => showPaymentDetailsSheet(context, tx, unitTypeLabel: unitType),
    );
  }

  // --- TAB 1: PAYMENTS ---
  Widget _buildPaymentsSliver() {
    return CustomScrollView(
      controller: _payScrollCtrl,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: C.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 16,
          title: Text('Payments', style: flex(17, color: C.textPrimary)),
          actions: [
            TextButton(
              onPressed: _openPayRentSheet,
              child: Text('+ Pay', style: sans(12.5, color: C.navy, weight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: C.borderLight),
          ),
        ),
        if (_myTxs.isEmpty)
          SliverFillRemaining(
            child: Center(child: Text('No payments yet.', style: sans(12.5, color: C.textMuted))),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            sliver: SliverList.builder(
              itemCount: _myTxs.length + (_hasMorePay ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _myTxs.length) {
                  return const Padding(
                    padding: EdgeInsets.all(14),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.navy)),
                  );
                }
                return _buildPaymentRow(_myTxs[i]);
              },
            ),
          ),
      ],
    );
  }

  // --- TAB 2: SUPPORT ---
  Widget _buildSupportSliver() {
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
              onPressed: _openReportIssueModal,
              child: Text('+ Report', style: sans(12.5, color: C.navy, weight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: C.borderLight),
          ),
        ),
        if (_myTickets.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LapisIcon(LapisIconName.shieldCheck, size: 28, color: C.mintText),
                  const SizedBox(height: 8),
                  Text('No open tickets', style: sans(12.5, color: C.textMuted)),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            sliver: SliverList.builder(
              itemCount: _myTickets.length,
              itemBuilder: (_, i) {
                final tk = _myTickets[i];
                final isResolved = tk.status == 'resolved';
                final isInProgress = tk.status == 'in_progress';
                return OrbixListTile(
                  icon: LapisIconName.wrench,
                  iconColor: isResolved ? C.mintText : (isInProgress ? C.navy : C.amberText),
                  iconBg: isResolved ? C.mintBg : (isInProgress ? C.navySoftBg : C.amberBg),
                  circularIcon: true,
                  title: tk.title,
                  subtitle: formatShortDate(tk.createdAt),
                  amount: '',
                  status: isResolved
                      ? StatusPill.mint(formatStatusLabel(tk.status), hasDot: false)
                      : (isInProgress
                          ? StatusPill.blue(formatStatusLabel(tk.status), hasDot: true)
                          : StatusPill.amber(formatStatusLabel(tk.status))),
                  onTap: () => showMaintenanceDetailSheet(context, tk, isAdmin: false),
                );
              },
            ),
          ),
      ],
    );
  }
}
