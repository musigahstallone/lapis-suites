import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/icons.dart';
import '../core/widgets.dart';
import '../core/sheets.dart';
import '../core/crud_sheets.dart';
import '../core/logo.dart';
import '../auth/login_page.dart';
import 'notifications_page.dart';
import 'lease_details_page.dart';

/// Settings Hub — embedded directly inside Bottom Nav Tab (NO back button by default).
/// Each item navigates to its own clean dedicated sub-page.
class ProfileSettingsPage extends StatefulWidget {
  final bool showBackButton;
  final LeaseModel? residentLease;
  final List<TenantModel> tenants;
  final VoidCallback? onDataChanged;

  const ProfileSettingsPage({
    super.key,
    this.showBackButton = false,
    this.residentLease,
    this.tenants = const [],
    this.onDataChanged,
  });

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  PropertySettingsModel _settings = ApiService.cachedSettings;
  List<AdminAccountModel> _admins = [];
  int _unreadCount = 0;
  bool _isLoadingReminders = false;
  bool _isRevokingAll = false;
  NetworkStatus? _net;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final results = await Future.wait([
      ApiService.checkNetwork(),
      ApiService.fetchNotifications(),
      ApiService.fetchSettings(),
    ]);
    if (!mounted) return;

    final net = results[0] as NetworkStatus;
    final notifs = results[1] as List<NotificationModel>;
    final settingsRes = results[2] as Map<String, dynamic>;

    setState(() {
      _net = net;
      _unreadCount = notifs.where((n) => !n.read).length;
      if (settingsRes['success'] == true) {
        _settings = settingsRes['settings'] as PropertySettingsModel;
        _admins = (settingsRes['admins'] as List<AdminAccountModel>?) ?? [];
      }
    });
  }

  Future<void> _handleOpenRemindersConfirm() async {
    List<TenantModel> tenantsList = widget.tenants;
    if (tenantsList.isEmpty) {
      setState(() => _isLoadingReminders = true);
      try {
        final d = await ApiService.fetchDashboardStats();
        tenantsList = d.tenants;
      } catch (_) {}
      if (!mounted) return;
      setState(() => _isLoadingReminders = false);
    }

    showSendRemindersConfirmSheet(
      context,
      tenants: tenantsList,
      onSent: () => widget.onDataChanged?.call(),
    );
  }

  Future<void> _handleLogoutAllDevices() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Sign Out All Devices', style: flex(14.5, color: C.textPrimary)),
        content: Text(
          'This will revoke your session on every phone and browser immediately.',
          style: sans(12.5, color: C.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: sans(12, color: C.textMuted, weight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: C.roseText, foregroundColor: Colors.white),
            child: Text('Sign Out All', style: sans(12, color: Colors.white, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isRevokingAll = true);
    final res = await ApiService.logoutAllDevices();
    if (!mounted) return;
    setState(() => _isRevokingAll = false);
    if (res['success'] == true) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } else {
      showAppSnackBar(context, res['error']?.toString() ?? 'Could not sign out all devices.', isError: true);
    }
  }

  void _handleLogout() {
    ApiService.logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = ApiService.currentUser;
    final name = u?['name']?.toString() ?? 'User';
    final email = u?['email']?.toString() ?? '';
    final role = formatStatusLabel(u?['role']?.toString() ?? 'resident');
    final unit = u?['unitNumber']?.toString() ?? '';
    final isAdmin = ApiService.isLandlord;

    final body = RefreshIndicator(
      onRefresh: _loadMeta,
      color: C.navy,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: C.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            leading: widget.showBackButton
                ? IconButton(
                    icon: const LapisIcon(LapisIconName.chevronLeft, size: 19, color: C.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  )
                : null,
            titleSpacing: widget.showBackButton ? 0 : 16,
            title: Text('Settings', style: flex(17, color: C.textPrimary)),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, color: C.borderLight),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Compact Profile Summary
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: C.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: C.border.withValues(alpha: 0.75)),
                  ),
                  child: Row(
                    children: [
                      const LapisLogo(size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: flex(14, color: C.textPrimary)),
                            const SizedBox(height: 2),
                            Text(email, style: sans(11.5, color: C.textMuted), overflow: TextOverflow.ellipsis),
                            if (unit.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('Unit $unit', style: sans(11, color: C.mintText, weight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ),
                      StatusPill.blue(role),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                _groupLabel(isAdmin ? 'Property' : 'Account'),
                const SizedBox(height: 6),
                _settingsGroup([
                  _linkTile(
                    icon: LapisIconName.bell,
                    title: 'Notifications',
                    trailingText: _unreadCount > 0 ? '$_unreadCount unread' : null,
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const NotificationsPage()))
                        .then((_) => _loadMeta()),
                  ),
                  if (!isAdmin && widget.residentLease != null)
                    _linkTile(
                      icon: LapisIconName.fileText,
                      title: 'Lease Agreement',
                      trailingText: 'Unit ${widget.residentLease!.unitNumber}',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => LeaseDetailsPage(lease: widget.residentLease!)),
                      ),
                    ),
                  if (isAdmin) ...[
                    _linkTile(
                      icon: LapisIconName.building,
                      title: 'Property & Billing',
                      trailingText: _settings.paybillNumber,
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => PropertyBillingSettingsPage(settings: _settings)))
                          .then((_) {
                        _loadMeta();
                        widget.onDataChanged?.call();
                      }),
                    ),
                    _linkTile(
                      icon: LapisIconName.users,
                      title: 'Administrators',
                      trailingText: '${_admins.length}/2',
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => AdminsSettingsPage(admins: _admins)))
                          .then((_) => _loadMeta()),
                    ),
                    _linkTile(
                      icon: LapisIconName.layers,
                      title: 'Unit Types',
                      onTap: () => showUnitTypesSheet(
                        context,
                        onChanged: () => widget.onDataChanged?.call(),
                      ),
                    ),
                    _linkTile(
                      icon: LapisIconName.send,
                      title: _isLoadingReminders ? 'Loading Unpaid...' : 'Rent Reminders',
                      onTap: _isLoadingReminders ? null : _handleOpenRemindersConfirm,
                    ),
                  ],
                ]),

                const SizedBox(height: 18),
                _groupLabel('Security'),
                const SizedBox(height: 6),
                _settingsGroup([
                  _linkTile(
                    icon: LapisIconName.shieldCheck,
                    title: 'Change Password',
                    onTap: () => showChangePasswordSheet(context),
                  ),
                  _linkTile(
                    icon: LapisIconName.logOut,
                    title: _isRevokingAll ? 'Signing Out All...' : 'Sign Out All Devices',
                    onTap: _isRevokingAll ? null : _handleLogoutAllDevices,
                  ),
                ]),

                const SizedBox(height: 18),
                _groupLabel('App'),
                const SizedBox(height: 6),
                _settingsGroup([
                  _linkTile(
                    icon: LapisIconName.info,
                    title: 'System Status',
                    trailingText: (_net?.isOnline ?? false) ? 'Online' : 'Offline',
                    trailingColor: (_net?.isOnline ?? false) ? C.mintText : C.roseText,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => SystemStatusPage(net: _net)),
                    ),
                  ),
                ]),

                const SizedBox(height: 22),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _handleLogout,
                    icon: const LapisIcon(LapisIconName.logOut, size: 15, color: C.roseText),
                    label: Text('Sign Out', style: sans(12.5, color: C.roseText, weight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: C.surface,
                      side: const BorderSide(color: C.roseBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );

    if (widget.showBackButton) {
      return Scaffold(backgroundColor: C.canvas, body: body);
    }
    return body;
  }

  Widget _groupLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: sans(10, color: C.textMuted, weight: FontWeight.w700, letterSpacing: 0.7),
      ),
    );
  }

  Widget _settingsGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border.withValues(alpha: 0.75)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 48, color: C.borderLight),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _linkTile({
    required LapisIconName icon,
    required String title,
    String? trailingText,
    Color? trailingColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: C.canvas,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(child: LapisIcon(icon, size: 15, color: C.navy)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: sans(13, color: C.textPrimary, weight: FontWeight.w600)),
            ),
            if (trailingText != null && trailingText.isNotEmpty) ...[
              Text(
                trailingText,
                style: sans(11.5, color: trailingColor ?? C.textMuted, weight: FontWeight.w500, fontFeatures: kTabularNums),
              ),
              const SizedBox(width: 6),
            ],
            const LapisIcon(LapisIconName.chevronRight, size: 15, color: C.textSoft),
          ],
        ),
      ),
    );
  }
}

/// Dedicated Sub-page: Property & Billing Settings
class PropertyBillingSettingsPage extends StatefulWidget {
  final PropertySettingsModel settings;
  const PropertyBillingSettingsPage({super.key, required this.settings});

  @override
  State<PropertyBillingSettingsPage> createState() => _PropertyBillingSettingsPageState();
}

class _PropertyBillingSettingsPageState extends State<PropertyBillingSettingsPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _paybillCtrl;
  late final TextEditingController _dueDayCtrl;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.settings.propertyName);
    _paybillCtrl = TextEditingController(text: widget.settings.paybillNumber);
    _dueDayCtrl = TextEditingController(text: widget.settings.rentDueDay.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _paybillCtrl.dispose();
    _dueDayCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final day = int.tryParse(_dueDayCtrl.text.trim()) ?? 5;
    if (day < 1 || day > 28) {
      setState(() => _error = 'Due day must be between 1 and 28.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    final res = await ApiService.updateSettings(
      settings: {
        'propertyName': _nameCtrl.text.trim(),
        'paybillNumber': _paybillCtrl.text.trim(),
        'rentDueDay': day,
      },
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (res['success'] == true) {
      showAppSnackBar(context, 'Property settings saved.');
      Navigator.pop(context, true);
    } else {
      setState(() => _error = res['error']?.toString() ?? 'Could not save settings.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.surface,
        elevation: 0,
        leading: IconButton(
          icon: const LapisIcon(LapisIconName.chevronLeft, size: 19, color: C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Property & Billing', style: flex(15.5, color: C.textPrimary)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: C.borderLight),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.border.withValues(alpha: 0.75)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  InlineAlert(message: _error!),
                  const SizedBox(height: 12),
                ],
                Text('Property Name', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(controller: _nameCtrl, style: sans(13, color: C.textPrimary), decoration: fieldDecoration()),
                const SizedBox(height: 12),
                Text('M-Pesa Paybill', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: _paybillCtrl,
                  keyboardType: TextInputType.number,
                  style: mono(13, color: C.textPrimary),
                  decoration: fieldDecoration(),
                ),
                const SizedBox(height: 12),
                Text('Monthly Rent Due Day (1–28)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: _dueDayCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: sans(13, color: C.textPrimary, fontFeatures: kTabularNums),
                  decoration: fieldDecoration(hintText: '5'),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                        : Text('Save Changes', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dedicated Sub-page: Authorized Administrators
class AdminsSettingsPage extends StatefulWidget {
  final List<AdminAccountModel> admins;
  const AdminsSettingsPage({super.key, required this.admins});

  @override
  State<AdminsSettingsPage> createState() => _AdminsSettingsPageState();
}

class _AdminsSettingsPageState extends State<AdminsSettingsPage> {
  late List<AdminAccountModel> _admins;

  @override
  void initState() {
    super.initState();
    _admins = List.from(widget.admins);
  }

  Future<void> _reload() async {
    final res = await ApiService.fetchSettings();
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() => _admins = (res['admins'] as List<AdminAccountModel>?) ?? _admins);
    }
  }

  void _editAdmin(AdminAccountModel admin) {
    final nameCtrl = TextEditingController(text: admin.name);
    final emailCtrl = TextEditingController(text: admin.email);
    final phoneCtrl = TextEditingController(text: extractKenyaNineDigits(admin.phone));
    bool isSaving = false;
    String? err;

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
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit Administrator', style: flex(15, color: C.textPrimary)),
                const SizedBox(height: 12),
                if (err != null) ...[
                  InlineAlert(message: err!),
                  const SizedBox(height: 12),
                ],
                Text('Name', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(controller: nameCtrl, style: sans(13, color: C.textPrimary), decoration: fieldDecoration()),
                const SizedBox(height: 12),
                Text('Email', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: sans(13, color: C.textPrimary),
                  decoration: fieldDecoration(),
                ),
                const SizedBox(height: 12),
                Text('OTP Mobile Number', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                KenyaPhoneField(controller: phoneCtrl),
                const SizedBox(height: 16),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setMState(() {
                              isSaving = true;
                              err = null;
                            });
                            final updated = _admins.map((a) {
                              if (a.id == admin.id) {
                                return {
                                  'id': a.id,
                                  'name': nameCtrl.text.trim(),
                                  'email': emailCtrl.text.trim().toLowerCase(),
                                  'phone': phoneCtrl.text.trim().isNotEmpty
                                      ? toCanonicalKenyaPhone(phoneCtrl.text.trim())
                                      : '',
                                };
                              }
                              return {'id': a.id, 'name': a.name, 'email': a.email, 'phone': a.phone};
                            }).toList();
                            final res = await ApiService.updateSettings(admins: updated);
                            if (!ctx.mounted) return;
                            setMState(() => isSaving = false);
                            if (res['success'] == true) {
                              Navigator.pop(ctx);
                              if (mounted) {
                                showAppSnackBar(context, 'Administrator updated.');
                              }
                              _reload();
                            } else {
                              setMState(() => err = res['error']?.toString() ?? 'Could not save.');
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                        : Text('Save', style: sans(13, color: C.ctaOn, weight: FontWeight.w600)),
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
    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.surface,
        elevation: 0,
        leading: IconButton(
          icon: const LapisIcon(LapisIconName.chevronLeft, size: 19, color: C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Administrators', style: flex(15.5, color: C.textPrimary)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: C.borderLight),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: _admins.length,
        itemBuilder: (_, i) {
          final a = _admins[i];
          return OrbixListTile(
            icon: LapisIconName.shieldCheck,
            iconColor: C.navy,
            iconBg: C.navySoftBg,
            circularIcon: true,
            title: a.name,
            subtitle: a.phone.isNotEmpty ? formatKenyanPhoneDisplay(a.phone) : a.email,
            amount: '',
            status: const LapisIcon(LapisIconName.pencil, size: 15, color: C.textMuted),
            onTap: () => _editAdmin(a),
          );
        },
      ),
    );
  }
}

/// Dedicated Sub-page: System Status
class SystemStatusPage extends StatelessWidget {
  final NetworkStatus? net;
  const SystemStatusPage({super.key, this.net});

  @override
  Widget build(BuildContext context) {
    final online = net?.isOnline ?? false;
    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.surface,
        elevation: 0,
        leading: IconButton(
          icon: const LapisIcon(LapisIconName.chevronLeft, size: 19, color: C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('System Status', style: flex(15.5, color: C.textPrimary)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: C.borderLight),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.border.withValues(alpha: 0.75)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row('Server', 'suites.qmusglobal.com'),
              const Divider(height: 18, color: C.borderLight),
              _row('Status', online ? 'Online' : 'Offline', color: online ? C.mintText : C.roseText),
              const Divider(height: 18, color: C.borderLight),
              _row('Database', (net?.isDbConnected ?? false) ? 'Synced' : 'Unavailable'),
              const Divider(height: 18, color: C.borderLight),
              _row('Version', 'v2.2.0'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: sans(12.5, color: C.textMuted)),
        Text(value, style: sans(12.5, color: color ?? C.textPrimary, weight: FontWeight.w600, fontFeatures: kTabularNums)),
      ],
    );
  }
}
