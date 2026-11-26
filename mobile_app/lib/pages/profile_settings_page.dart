import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/widgets.dart';
import '../core/logo.dart';
import '../auth/login_page.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  List<NotificationModel> _notifications = [];
  PropertySettingsModel _settings = ApiService.cachedSettings;
  List<AdminAccountModel> _admins = [];
  bool _isLoading = true;
  bool _isRunningReminders = false;
  NetworkStatus? _net;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
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
      _notifications = notifs;
      if (settingsRes['success'] == true) {
        _settings = settingsRes['settings'] as PropertySettingsModel;
        _admins = (settingsRes['admins'] as List<AdminAccountModel>?) ?? [];
      }
      _isLoading = false;
    });
  }

  Future<void> _markAllRead() async {
    for (final n in _notifications.where((x) => !x.read)) {
      await ApiService.markNotificationRead(n.id);
    }
    _loadData();
  }

  Future<void> _handleRunReminders() async {
    setState(() => _isRunningReminders = true);
    final res = await ApiService.runRentReminders();
    if (!mounted) return;
    setState(() => _isRunningReminders = false);

    if (res['success'] == true) {
      showAppSnackBar(context, res['message']?.toString() ?? 'Rent reminders dispatched.');
    } else {
      showAppSnackBar(context, res['error']?.toString() ?? 'Could not send reminders.', isError: true);
    }
  }

  void _openEditPropertySheet() {
    final nameCtrl = TextEditingController(text: _settings.propertyName);
    final paybillCtrl = TextEditingController(text: _settings.paybillNumber);
    final dueDayCtrl = TextEditingController(text: _settings.rentDueDay.toString());
    bool isSaving = false;
    String? err;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
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
                Text('Property & Billing Settings', style: flex(15, color: C.textPrimary)),
                const SizedBox(height: 12),
                if (err != null) ...[
                  InlineAlert(message: err!),
                  const SizedBox(height: 12),
                ],
                Text('Property Name', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(controller: nameCtrl, style: sans(13, color: C.textPrimary), decoration: fieldDecoration()),
                const SizedBox(height: 12),
                Text('M-Pesa Paybill Number', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: paybillCtrl,
                  keyboardType: TextInputType.number,
                  style: mono(13, color: C.textPrimary),
                  decoration: fieldDecoration(),
                ),
                const SizedBox(height: 12),
                Text('Monthly Rent Due Day (1–28)', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                TextField(
                  controller: dueDayCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: sans(13, color: C.textPrimary),
                  decoration: fieldDecoration(hintText: 'e.g. 5'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 43,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final day = int.tryParse(dueDayCtrl.text.trim()) ?? 5;
                            if (day < 1 || day > 28) {
                              setMState(() => err = 'Due day must be between 1 and 28.');
                              return;
                            }
                            setMState(() {
                              isSaving = true;
                              err = null;
                            });
                            final res = await ApiService.updateSettings(
                              settings: {
                                'propertyName': nameCtrl.text.trim(),
                                'paybillNumber': paybillCtrl.text.trim(),
                                'rentDueDay': day,
                              },
                            );
                            if (!ctx.mounted) return;
                            setMState(() => isSaving = false);
                            if (res['success'] == true) {
                              Navigator.pop(ctx);
                              if (mounted) {
                                showAppSnackBar(context, 'Property settings saved.');
                              }
                              _loadData();
                            } else {
                              setMState(() => err = res['error']?.toString() ?? 'Could not save settings.');
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                        : Text('Save Settings', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openEditAdminSheet(AdminAccountModel admin) {
    final nameCtrl = TextEditingController(text: admin.name);
    final emailCtrl = TextEditingController(text: admin.email);
    final phoneCtrl = TextEditingController(text: extractKenyaNineDigits(admin.phone));
    bool isSaving = false;
    String? err;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
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
                Text('Admin OTP Mobile Number', style: sans(11.5, color: C.textSecondary, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                KenyaPhoneField(controller: phoneCtrl),
                const SizedBox(height: 16),
                SizedBox(
                  height: 43,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setMState(() {
                              isSaving = true;
                              err = null;
                            });
                            final updatedList = _admins.map((a) {
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
                              return {
                                'id': a.id,
                                'name': a.name,
                                'email': a.email,
                                'phone': a.phone,
                              };
                            }).toList();

                            final res = await ApiService.updateSettings(admins: updatedList);
                            if (!ctx.mounted) return;
                            setMState(() => isSaving = false);
                            if (res['success'] == true) {
                              Navigator.pop(ctx);
                              if (mounted) {
                                showAppSnackBar(context, 'Administrator details updated.');
                              }
                              _loadData();
                            } else {
                              setMState(() => err = res['error']?.toString() ?? 'Could not save admin.');
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ctaOn))
                        : Text('Save Changes', style: sans(12.5, color: C.ctaOn, weight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back, size: 19, color: C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Account & Settings', style: flex(15, color: C.textPrimary)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: C.border),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: C.blueText,
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.all(16),
          children: [
            // Profile Card
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.border),
              ),
              child: Row(
                children: [
                  const LapisLogo(size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: flex(14, color: C.textPrimary)),
                        const SizedBox(height: 2),
                        Text(email, style: sans(11.5, color: C.textMuted)),
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

            // Admin Property & Authorized Admins Settings
            if (isAdmin) ...[
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Property Settings', style: flex(13, color: C.textPrimary)),
                  GestureDetector(
                    onTap: _openEditPropertySheet,
                    child: Text('Edit', style: sans(12, color: C.blueText, weight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: C.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: C.border),
                ),
                child: Column(
                  children: [
                    _row('Property Name', _settings.propertyName),
                    _row('M-Pesa Paybill', _settings.paybillNumber, isMono: true),
                    _row('Rent Due Day', 'Day ${_settings.rentDueDay} of every month'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _isRunningReminders ? null : _handleRunReminders,
                  icon: _isRunningReminders
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: C.blueText))
                      : const Icon(CupertinoIcons.paperplane, size: 14, color: C.blueText),
                  label: Text(
                    _isRunningReminders ? 'Dispatching Reminders...' : 'Send Rent Reminders Now',
                    style: sans(12, color: C.blueText, weight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: C.blueBorder)),
                ),
              ),

              if (_admins.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Authorized Administrators (${_admins.length}/2)', style: flex(13, color: C.textPrimary)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: C.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.border),
                  ),
                  child: Column(
                    children: _admins.map((a) {
                      return ListTile(
                        dense: true,
                        title: Text(a.name, style: sans(12.5, color: C.textPrimary, weight: FontWeight.w600)),
                        subtitle: Text(
                          '${a.email}${a.phone.isNotEmpty ? " · +${a.phone}" : " · No OTP phone"}',
                          style: sans(11, color: C.textMuted),
                        ),
                        trailing: const Icon(CupertinoIcons.pencil, size: 15, color: C.blueText),
                        onTap: () => _openEditAdminSheet(a),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],

            // Notifications Section
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Notifications', style: flex(13, color: C.textPrimary)),
                if (_notifications.any((n) => !n.read))
                  GestureDetector(
                    onTap: _markAllRead,
                    child: Text('Mark all read', style: sans(11.5, color: C.blueText, weight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.border),
              ),
              child: _isLoading
                  ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: C.blueText)))
                  : _notifications.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text('No notifications right now.', style: sans(12, color: C.textMuted)),
                          ),
                        )
                      : Column(
                          children: _notifications.take(6).map((n) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 5),
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: n.read ? C.border : C.blueText,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(n.title, style: sans(12, color: C.textPrimary, weight: FontWeight.w600)),
                                        if (n.message.isNotEmpty)
                                          Text(n.message, style: sans(11.5, color: C.textSecondary)),
                                        Text(formatShortDate(n.timestamp), style: sans(10, color: C.textSoft)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
            ),

            // System Connectivity
            const SizedBox(height: 18),
            Text('System', style: flex(13, color: C.textPrimary)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.border),
              ),
              child: Column(
                children: [
                  _row('Server', 'rmsapi.qmusglobal.com'),
                  _row('Status', (_net?.isOnline ?? false) ? 'Online & Synced' : 'Offline'),
                  _row('Version', 'v2.0.0'),
                ],
              ),
            ),

            const SizedBox(height: 20),
            SizedBox(
              height: 43,
              child: OutlinedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(CupertinoIcons.square_arrow_right, size: 15, color: C.roseText),
                label: Text('Sign Out', style: sans(12.5, color: C.roseText, weight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: C.roseBorder)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool isMono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: sans(12, color: C.textMuted)),
          Text(
            value,
            style: isMono
                ? mono(12, color: C.textPrimary, weight: FontWeight.w600)
                : sans(12, color: C.textPrimary, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
