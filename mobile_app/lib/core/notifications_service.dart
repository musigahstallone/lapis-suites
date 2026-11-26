import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

/// Native local app notifications for payments, maintenance tickets, reconciliations, and OTP alerts.
/// Supplements SMS notifications without replacing them.
class AppNotifications {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static Timer? _pollTimer;
  static final Set<String> _seenIds = <String>{};
  static bool _primed = false;
  static const String _seenStorageKey = 'lapis_seen_notif_ids';

  static Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(android: androidInit, iOS: darwinInit);
      await _plugin.initialize(settings);

      // Request Android 13+ notification permission gracefully
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_seenStorageKey) ?? [];
      _seenIds.addAll(saved);
      _initialized = true;
    } catch (_) {
      // Gracefully no-op in unit tests or unsupported environments
    }
  }

  static Future<void> show({
    required String title,
    required String body,
    int? id,
  }) async {
    if (!_initialized) await init();
    if (!_initialized) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        'lapis_suites_alerts',
        'Lapis Suites Alerts',
        channelDescription: 'Payments, maintenance tickets, and verification alerts',
        importance: Importance.high,
        priority: Priority.high,
      );
      const darwinDetails = DarwinNotificationDetails();
      const details = NotificationDetails(android: androidDetails, iOS: darwinDetails);
      final notifId = id ?? (DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF);
      await _plugin.show(notifId, title, body, details);
    } catch (_) {}
  }

  /// Trigger an in-app system notification whenever an SMS OTP is dispatched
  static Future<void> notifyOtpSent(String purposeLabel, {String? maskedPhone}) async {
    final target = (maskedPhone != null && maskedPhone.isNotEmpty)
        ? 'Check SMS on $maskedPhone for your 6-digit code.'
        : 'Check your SMS messages for your 6-digit verification code.';
    await show(
      title: 'Lapis Suites · $purposeLabel',
      body: target,
    );
  }

  /// Poll server notifications while signed in and surface newly arrived payments & tickets
  static void startPolling() {
    _pollTimer?.cancel();
    _primed = false;
    _checkServerNotifications();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _checkServerNotifications(),
    );
  }

  static void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _primed = false;
  }

  static Future<void> _checkServerNotifications() async {
    if (ApiService.authToken == null) return;
    try {
      final list = await ApiService.fetchNotifications();
      if (list.isEmpty) {
        _primed = true;
        return;
      }

      if (!_primed && _seenIds.isEmpty) {
        // First run after install: record existing notifications without spamming historical alerts
        for (final n in list) {
          _seenIds.add(n.id);
        }
        _primed = true;
        await _saveSeenIds();
        return;
      }

      _primed = true;
      bool changed = false;
      for (final n in list.reversed) {
        if (!_seenIds.contains(n.id)) {
          _seenIds.add(n.id);
          changed = true;
          if (!n.read) {
            await show(
              id: n.id.hashCode & 0x7FFFFFFF,
              title: n.title,
              body: n.message.isNotEmpty ? n.message : 'Open Lapis Suites for details.',
            );
            ApiService.triggerRealtimeRefresh();
          }
        }
      }

      if (changed) await _saveSeenIds();
    } catch (_) {}
  }

  static Future<void> _saveSeenIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = _seenIds.length > 100
          ? _seenIds.skip(_seenIds.length - 100).toList()
          : _seenIds.toList();
      await prefs.setStringList(_seenStorageKey, trimmed);
    } catch (_) {}
  }
}
