import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/api.dart';
import '../core/icons.dart';
import '../core/widgets.dart';

/// Dedicated Notifications Page — minimal rows (title + date), full details shown on tap.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<NotificationModel> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ApiService.fetchNotifications();
    if (!mounted) return;
    setState(() {
      _items = list;
      _isLoading = false;
    });
  }

  Future<void> _markAllRead() async {
    for (final n in _items.where((x) => !x.read)) {
      await ApiService.markNotificationRead(n.id);
    }
    _load();
  }

  void _openItemDetail(NotificationModel n) async {
    if (!n.read) {
      ApiService.markNotificationRead(n.id).then((_) => _load());
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
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
                  StatusPill.blue(formatStatusLabel(n.type)),
                  Text(
                    formatShortDate(n.timestamp),
                    style: sans(11, color: C.textMuted, fontFeatures: kTabularNums),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(n.title, style: flex(15, color: C.textPrimary)),
              if (n.message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(n.message, style: sans(13, color: C.textSecondary, height: 1.45)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 42,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Close', style: sans(12.5, color: C.textSecondary, weight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => !n.read);

    return Scaffold(
      backgroundColor: C.canvas,
      appBar: AppBar(
        backgroundColor: C.surface,
        elevation: 0,
        leading: IconButton(
          icon: const LapisIcon(LapisIconName.chevronLeft, size: 19, color: C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Notifications', style: flex(15.5, color: C.textPrimary)),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read', style: sans(12, color: C.navy, weight: FontWeight.w600)),
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: C.borderLight),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.navy))
          : RefreshIndicator(
              onRefresh: _load,
              color: C.navy,
              child: _items.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        const Center(child: LapisIcon(LapisIconName.bell, size: 28, color: C.textSoft)),
                        const SizedBox(height: 10),
                        Center(child: Text('No notifications', style: sans(13, color: C.textMuted))),
                      ],
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final n = _items[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3.5),
                          child: Material(
                            color: C.surface,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => _openItemDetail(n),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: n.read ? C.border.withValues(alpha: 0.7) : C.navy.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: n.read ? C.border : C.navy,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            n.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: sans(
                                              13,
                                              color: C.textPrimary,
                                              weight: n.read ? FontWeight.w500 : FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            formatShortDate(n.timestamp),
                                            style: sans(11, color: C.textMuted, fontFeatures: kTabularNums),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const LapisIcon(LapisIconName.chevronRight, size: 15, color: C.textSoft),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
