import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/api.dart';
import '../core/widgets.dart';
import '../core/sheets.dart';
import '../core/icons.dart';
import '../pages/lease_details_page.dart';
import '../pages/profile_settings_page.dart';

class ResidentHomeScreen extends StatefulWidget {
  const ResidentHomeScreen({super.key});

  @override
  State<ResidentHomeScreen> createState() => _ResidentHomeScreenState();
}

class _ResidentHomeScreenState extends State<ResidentHomeScreen> {
  int _navIndex = 0;
  TenantModel? _tenant;
  LeaseModel? _lease;
  List<TransactionModel> _myTxs = [];
  List<MaintenanceTicket> _myTickets = [];
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  bool _showBreakdown = false;
  String? _error;

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
          _error = n.message ?? 'Unable to reach Lapis Suites server.';
        });
      }
      return;
    }

    try {
      final tenantId =
          (ApiService.currentUser?['tenantId'] ?? ApiService.currentUser?['userId'] ?? '').toString();

      final results = await Future.wait([
        ApiService.fetchTenantProfile(tenantId),
        ApiService.fetchTenantLease(tenantId),
        ApiService.fetchTenantTransactions(tenantId, page: 1, limit: 20),
        ApiService.fetchMaintenance(),
        ApiService.fetchSettings(),
        ApiService.fetchNotifications(),
      ]);

      final profile = results[0] as TenantModel?;
      final lease = results[1] as LeaseModel?;
      final txs = results[2] as List<TransactionModel>;
      final tickets = results[3] as List<MaintenanceTicket>;
      final notifs = results[5] as List<NotificationModel>;

      if (mounted) {
        setState(() {
          _tenant = profile;
          _lease = lease;
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

  void _openProfile() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ProfileSettingsPage()))
        .then((_) => _loadResidentScope(silent: true));
  }

  void _openNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Notifications', style: flex(15, color: C.textPrimary)),
                  if (_notifications.any((n) => !n.read))
                    GestureDetector(
                      onTap: () async {
                        for (final n in _notifications.where((x) => !x.read)) {
                          await ApiService.markNotificationRead(n.id);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadResidentScope(silent: true);
                      },
                      child: Text('Mark all read', style: sans(11.5, color: C.navy, weight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_notifications.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text('You are all caught up.', style: sans(12, color: C.textMuted)),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _notifications.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: C.borderLight),
                    itemBuilder: (_, i) {
                      final n = _notifications[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 5),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: n.read ? C.border : C.mintText,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n.title, style: sans(12.5, color: C.textPrimary, weight: FontWeight.w600)),
                                  if (n.message.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(n.message, style: sans(11.5, color: C.textSecondary)),
                                  ],
                                  const SizedBox(height: 3),
                                  Text(
                                    formatShortDate(n.timestamp),
                                    style: sans(10, color: C.textSoft, fontFeatures: kTabularNums),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
      unitNumber: t?.currentUnitNumber.isNotEmpty == true
          ? t!.currentUnitNumber
          : (l?.unitNumber ?? ApiService.currentUser?['unitNumber']?.toString() ?? ''),
      tenantId: t?.id ?? ApiService.currentUser?['tenantId']?.toString(),
      unitId: t?.currentUnitId ?? l?.unitId,
      leaseId: l?.id,
      payerName: t?.name ?? ApiService.currentUser?['name']?.toString(),
      onComplete: () => _loadResidentScope(silent: true),
    );
  }

  void _openReportIssueModal() {
    showCreateMaintenanceSheet(
      context,
      isAdmin: false,
      unitNumber: _tenant?.currentUnitNumber.isNotEmpty == true
          ? _tenant!.currentUnitNumber
          : (_lease?.unitNumber ?? ''),
      unitId: _tenant?.currentUnitId ?? _lease?.unitId,
      onCreated: () => _loadResidentScope(silent: true),
    );
  }

  String _getTitleForTab() {
    switch (_navIndex) {
      case 1:
        return 'Rent Payments';
      case 2:
        return 'Maintenance';
      default:
        return 'Resident Portal';
    }
  }

  String _getHeaderSubtitle() {
    final unitNum = _tenant?.currentUnitNumber.isNotEmpty == true
        ? _tenant!.currentUnitNumber
        : (_lease?.unitNumber ?? ApiService.currentUser?['unitNumber']?.toString() ?? '');
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

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.read).length;
    final initials = _tenant?.avatarInitials ??
        ApiService.currentUser?['avatarInitials']?.toString() ??
        'RS';

    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.surface,
        elevation: 0,
        toolbarHeight: 58,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _getTitleForTab(),
              style: flex(15.5, color: C.textPrimary, weight: FontWeight.w700),
            ),
            const SizedBox(height: 1),
            Text(
              _getHeaderSubtitle(),
              style: sans(11, color: C.textMuted, weight: FontWeight.w500),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: C.border.withValues(alpha: 0.7)),
        ),
        actions: [
          // Clean Notification Bell Button (replaces "• Live" pill)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              tooltip: 'Notifications',
              onPressed: _openNotificationsSheet,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const LapisIcon(LapisIconName.bell, size: 19, color: C.textSecondary),
                  if (unreadCount > 0)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 7.5,
                        height: 7.5,
                        decoration: BoxDecoration(
                          color: C.mintText,
                          shape: BoxShape.circle,
                          border: Border.all(color: C.surface, width: 1.4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Profile Avatar Button
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: GestureDetector(
              onTap: _openProfile,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: C.navy,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: flex(11, color: Colors.white, weight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
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
        ],
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_navIndex) {
      case 1:
        return _buildPaymentsList();
      case 2:
        return _buildSupportList();
      default:
        return _buildHomeOverview();
    }
  }

  // --- TAB 0: FINTECH HOME OVERVIEW ---
  Widget _buildHomeOverview() {
    final t = _tenant;
    final l = _lease;
    final credit = t?.accountCredit ?? 0;
    final due = t?.effectiveBalanceDue ?? 0;
    final hasCredit = credit > 0;
    final hasDue = due > 0;

    final nextDue = (t?.nextPaymentDueDate.isNotEmpty == true)
        ? formatShortDate(t!.nextPaymentDueDate)
        : (l?.nextPaymentDueDate.isNotEmpty == true
            ? formatShortDate(l!.nextPaymentDueDate)
            : 'Day ${ApiService.cachedSettings.rentDueDay}');

    final heroNumber = hasDue
        ? due.toLocaleString()
        : (hasCredit ? credit.toLocaleString() : '0');
    final heroCaption = hasDue
        ? 'Balance due · Next due $nextDue'
        : (hasCredit
            ? 'Prepaid credit · Covered until $nextDue'
            : 'Account settled · Next due $nextDue');
    final breakdownText = _buildBalanceBreakdown();

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        // 1. Clean White Fintech Hero Balance Card (Amber strictly inside the pill badge!)
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ACCOUNT STANDING',
                    style: sans(10, color: C.textMuted, weight: FontWeight.w700, letterSpacing: 0.7),
                  ),
                  hasDue
                      ? StatusPill.amber('Payment Due')
                      : (hasCredit ? StatusPill.mint('Prepaid') : StatusPill.mint('Current')),
                ],
              ),
              const SizedBox(height: 10),

              // Fintech Currency Hierarchy: small muted KES + bold tabular figure
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
                      color: C.textPrimary,
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

              // Subtle collapsible balance breakdown line
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
                            _showBreakdown ? 'Hide breakdown' : 'Balance breakdown',
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

              // Primary CTA Button: #111B35 Lapis Navy, rounded-xl (12px), h-12 (48px), crisp Lucide Smartphone icon
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

        // 2. Compact Borderless Horizontal Unit Metadata Strip (tappable for Lease Details)
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

        // 3. Recent Payments Header
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
                    'See all (${_myTxs.length})',
                    style: sans(11.5, color: C.navy, weight: FontWeight.w600, fontFeatures: kTabularNums),
                  ),
                ),
            ],
          ),
        ),

        if (_myTxs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                  Text('No payment records yet', style: sans(12.5, color: C.textMuted)),
                ],
              ),
            ),
          )
        else
          ..._myTxs.take(5).map(_buildPaymentRow),
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

  Widget _buildPaymentRow(TransactionModel tx) {
    final rec = tx.reconciled;
    return OrbixListTile(
      icon: rec ? LapisIconName.arrowDownLeft : LapisIconName.clock,
      iconColor: rec ? C.mintText : C.amberText,
      iconBg: rec ? C.mintBg : C.amberBg,
      circularIcon: true,
      title: tx.reference,
      isMonoTitle: true,
      subtitle: '${formatShortDate(tx.date)} · ${formatPaymentMethodLabel(tx.method)}',
      amountPrefix: 'KES',
      amount: tx.amount.toLocaleString(),
      amountColor: rec ? C.mintText : C.amberText,
      status: rec ? StatusPill.mint('Reconciled') : StatusPill.amber(tx.statusDisplayLabel),
      onTap: () => showPaymentDetailsSheet(context, tx),
    );
  }

  // --- TAB 1: PAYMENTS LIST ---
  Widget _buildPaymentsList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_myTxs.length} Payments',
                style: sans(11.5, color: C.textMuted, weight: FontWeight.w600, fontFeatures: kTabularNums),
              ),
              GestureDetector(
                onTap: _openPayRentSheet,
                child: StatusPill.blue('+ Make Payment', hasDot: false),
              ),
            ],
          ),
        ),
        Expanded(
          child: _myTxs.isEmpty
              ? Center(child: Text('No transactions on file yet.', style: sans(12, color: C.textMuted)))
              : ListView.builder(
                  controller: _payScrollCtrl,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _myTxs.length + (_hasMorePay ? 1 : 0),
                  itemBuilder: (context, i) {
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

  // --- TAB 2: SUPPORT / MAINTENANCE ---
  Widget _buildSupportList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _openReportIssueModal,
              style: ElevatedButton.styleFrom(
                backgroundColor: C.navy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const LapisIcon(LapisIconName.plus, size: 15, color: Colors.white),
                  const SizedBox(width: 7),
                  Text('Report Maintenance Issue', style: sans(12.5, color: Colors.white, weight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _myTickets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LapisIcon(LapisIconName.shieldCheck, size: 28, color: C.mintText),
                      const SizedBox(height: 8),
                      Text('No open maintenance tickets', style: sans(12.5, color: C.textMuted)),
                    ],
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _myTickets.length,
                  itemBuilder: (context, i) {
                    final tk = _myTickets[i];
                    final isResolved = tk.status == 'resolved';
                    final isInProgress = tk.status == 'in_progress';

                    return OrbixListTile(
                      icon: LapisIconName.wrench,
                      iconColor: isResolved ? C.mintText : (isInProgress ? C.navy : C.amberText),
                      iconBg: isResolved ? C.mintBg : (isInProgress ? C.navySoftBg : C.amberBg),
                      circularIcon: true,
                      title: tk.title,
                      subtitle: '${formatCategoryLabel(tk.category)} · ${formatShortDate(tk.createdAt)}',
                      amount: '',
                      status: isResolved
                          ? StatusPill.mint(formatStatusLabel(tk.status))
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
