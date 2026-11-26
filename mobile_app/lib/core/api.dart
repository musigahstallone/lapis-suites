import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'notifications_service.dart';

class NetworkStatus {
  final bool isOnline;
  final bool isDbConnected;
  final String? message;
  final int? latencyMs;

  const NetworkStatus({
    required this.isOnline,
    required this.isDbConnected,
    this.message,
    this.latencyMs,
  });
}

/// Safe API Exception with clean user-facing message (never leaks HTML/stack traces)
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  static const String baseUrl = 'https://rmsapi.qmusglobal.com';

  static String? authToken;
  static Map<String, dynamic>? currentUser;
  static PropertySettingsModel cachedSettings = const PropertySettingsModel();
  static bool pendingDeepLinkPay = false;

  static const String _tokenKey = 'lapis_auth_token';
  static const String _userKey = 'lapis_auth_user';

  /// Triggered automatically when an authenticated request gets HTTP 401
  static VoidCallback? onSessionExpired;
  static bool _handlingSessionExpiry = false;

  // Global realtime trigger to refresh UI anywhere an update or callback lands
  static final ValueNotifier<int> realtimeUpdateNotifier = ValueNotifier<int>(0);

  static void triggerRealtimeRefresh() {
    realtimeUpdateNotifier.value++;
  }

  /// Persist JWT & user profile across app restarts
  static Future<void> _saveSession(String token, Map<String, dynamic> user) async {
    authToken = token;
    currentUser = user;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userKey, jsonEncode(user));
    } catch (_) {}
    AppNotifications.startPolling();
  }

  /// Restore saved session on app launch (validates via /api/auth/me when online)
  static Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(_tokenKey);
      final savedUserJson = prefs.getString(_userKey);
      if (savedToken == null || savedToken.isEmpty || savedUserJson == null) {
        return false;
      }

      authToken = savedToken;
      currentUser = Map<String, dynamic>.from(jsonDecode(savedUserJson));

      // Verify token with server if reachable (keep cached session gracefully if offline)
      try {
        final res = await http
            .get(Uri.parse('$baseUrl/api/auth/me'), headers: _headers)
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = _safeDecode(res);
          if (data is Map<String, dynamic> && data['user'] is Map<String, dynamic>) {
            currentUser = Map<String, dynamic>.from(data['user']);
            await prefs.setString(_userKey, jsonEncode(currentUser));
          }
        } else if (res.statusCode == 401 || res.statusCode == 403) {
          await logout();
          return false;
        }
      } catch (_) {
        // Offline — keep saved session so user isn't forced to re-login
      }

      fetchSettings();
      AppNotifications.startPolling();
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _handleUnauthorizedIfNeeded(http.Response res) {
    if (res.statusCode == 401 && authToken != null && !_handlingSessionExpiry) {
      _handlingSessionExpiry = true;
      logout();
      onSessionExpired?.call();
      Future.delayed(const Duration(seconds: 2), () {
        _handlingSessionExpiry = false;
      });
    }
  }

  static bool get isLandlord {
    final role = (currentUser?['role'] ?? '').toString().toLowerCase();
    return role == 'landlord' || role == 'admin' || role == 'manager';
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  /// Safely decode JSON without crashing on HTML gateway/502 error pages
  static dynamic _safeDecode(http.Response res) {
    final body = res.body.trim();
    if (body.isEmpty) return <String, dynamic>{};

    final lower = body.toLowerCase();
    if (lower.startsWith('<!doctype') || lower.startsWith('<html')) {
      throw const ApiException(
        'Server is temporarily unreachable. Please check your connection and try again.',
      );
    }

    try {
      return jsonDecode(body);
    } catch (_) {
      throw const ApiException(
        'Received an unexpected response from the server. Please try again shortly.',
      );
    }
  }

  static String _extractError(http.Response res, dynamic decoded, String fallback) {
    _handleUnauthorizedIfNeeded(res);
    if (res.statusCode == 429) {
      final retryAfter = int.tryParse(res.headers['retry-after'] ?? '');
      if (retryAfter != null && retryAfter > 0) {
        final mins = (retryAfter / 60).ceil();
        return mins > 1
            ? 'Too many attempts. Please wait $mins minutes and try again.'
            : 'Too many attempts. Please wait $retryAfter seconds and try again.';
      }
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString().trim();
      }
      return 'Too many requests. Please wait a moment before trying again.';
    }
    if (decoded is Map) {
      final err = decoded['error'] ?? decoded['message'];
      if (err != null && err.toString().trim().isNotEmpty) {
        return err.toString().trim();
      }
    }
    if (res.statusCode == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    if (res.statusCode == 403) {
      return 'You do not have permission to perform this action.';
    }
    if (res.statusCode >= 500) {
      return 'Server is temporarily unavailable. Please try again in a moment.';
    }
    return fallback;
  }

  static String friendlyError(Object e) {
    if (e is ApiException) return e.message;
    if (e is SocketException) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (e is TimeoutException) {
      return 'Connection timed out. Please check your internet and try again.';
    }
    if (e is HandshakeException) {
      return 'Secure connection could not be established. Please retry.';
    }
    final raw = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (raw.toLowerCase().contains('clientexception') ||
        raw.toLowerCase().contains('failed host lookup') ||
        raw.toLowerCase().contains('connection refused') ||
        raw.toLowerCase().contains('network is unreachable')) {
      return 'Unable to reach Lapis Suites server. Check your internet connection.';
    }
    if (raw.toLowerCase().contains('formatexception') ||
        raw.toLowerCase().contains('unexpected character')) {
      return 'Server returned an incomplete response. Please try again shortly.';
    }
    return raw.isNotEmpty ? raw : 'Something went wrong. Please try again.';
  }

  // --- HEALTH / CONNECTIVITY ---

  static Future<NetworkStatus> checkNetwork() async {
    final sw = Stopwatch()..start();
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/health'), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));
      sw.stop();

      if (res.statusCode == 200) {
        final data = _safeDecode(res);
        return NetworkStatus(
          isOnline: true,
          isDbConnected: data is Map && data['database'] == 'connected',
          message: 'Connected',
          latencyMs: sw.elapsedMilliseconds,
        );
      }
      return NetworkStatus(
        isOnline: false,
        isDbConnected: false,
        message: 'Server returned ${res.statusCode}',
      );
    } catch (e) {
      return NetworkStatus(
        isOnline: false,
        isDbConnected: false,
        message: friendlyError(e),
      );
    }
  }

  // --- AUTHENTICATION & OTP FLOWS ---

  /// Sign in with email + password.
  /// Handles:
  ///   1. Direct tenant login (token + user)
  ///   2. Admin 2FA SMS OTP (requiresOtp + challengeToken + maskedPhone)
  ///   3. Pre-added resident account setup via SMS OTP (requiresAccountSetup + email)
  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 12));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        if (data['requiresOtp'] == true) {
          final masked = data['maskedPhone']?.toString() ?? '';
          AppNotifications.notifyOtpSent('Admin Login OTP', maskedPhone: masked);
          return {
            'success': true,
            'requiresOtp': true,
            'challengeToken': data['challengeToken']?.toString() ?? '',
            'maskedPhone': masked,
            'email': data['email']?.toString() ?? email.trim().toLowerCase(),
            'expiresInSeconds': (data['expiresInSeconds'] as num?)?.toInt() ?? 600,
            'message': data['message']?.toString() ??
                'Enter the 6-digit SMS verification code sent to your admin phone.',
          };
        }

        if (data['requiresAccountSetup'] == true) {
          AppNotifications.notifyOtpSent('Account Setup OTP');
          return {
            'success': true,
            'requiresAccountSetup': true,
            'email': data['email']?.toString() ?? email.trim().toLowerCase(),
            'expiresInSeconds': (data['expiresInSeconds'] as num?)?.toInt() ?? 600,
            'message': data['message']?.toString() ??
                'Enter the 6-digit SMS code sent to your phone to set your password.',
          };
        }

        if (data['token'] != null) {
          await _saveSession(
            data['token'].toString(),
            Map<String, dynamic>.from(data['user'] ?? {}),
          );
          fetchSettings();
          return {
            'success': true,
            'user': currentUser,
            'role': currentUser?['role'] ?? 'tenant',
            'needsAdminPhoneSetup': data['needsAdminPhoneSetup'] == true,
          };
        }
      }

      return {
        'success': false,
        'error': _extractError(res, data, 'Invalid email or password.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Complete Admin 2FA login with 6-digit SMS OTP
  static Future<Map<String, dynamic>> verifyLoginOtp({
    required String challengeToken,
    required String code,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/auth/verify-login-otp'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'challengeToken': challengeToken,
              'code': code.replaceAll(RegExp(r'\D'), ''),
            }),
          )
          .timeout(const Duration(seconds: 12));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic> && data['token'] != null) {
        await _saveSession(
          data['token'].toString(),
          Map<String, dynamic>.from(data['user'] ?? {}),
        );
        fetchSettings();
        return {
          'success': true,
          'user': currentUser,
          'role': currentUser?['role'] ?? 'landlord',
        };
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'Invalid verification code.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Resend Admin 2FA login SMS OTP
  static Future<Map<String, dynamic>> resendLoginOtp(String challengeToken) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/auth/resend-login-otp'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'challengeToken': challengeToken}),
          )
          .timeout(const Duration(seconds: 12));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        final masked = data['maskedPhone']?.toString() ?? '';
        AppNotifications.notifyOtpSent('Admin Login OTP', maskedPhone: masked);
        return {
          'success': true,
          'challengeToken': data['challengeToken']?.toString() ?? challengeToken,
          'maskedPhone': masked,
          'expiresInSeconds': (data['expiresInSeconds'] as num?)?.toInt() ?? 600,
          'message': data['message']?.toString() ?? 'A new OTP has been sent via SMS.',
        };
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'Could not resend verification code.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Resident Sign Up / Account Claim Step 1: Request SMS OTP
  static Future<Map<String, dynamic>> requestRegisterOtp({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/auth/register/request-otp'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'password': password,
              'name': name.trim(),
              'phone': toCanonicalKenyaPhone(phone),
            }),
          )
          .timeout(const Duration(seconds: 14));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        AppNotifications.notifyOtpSent('Account Verification OTP');
        return {
          'success': true,
          'mode': data['mode']?.toString() ?? 'new',
          'challengeToken': data['challengeToken']?.toString() ?? '',
          'email': data['email']?.toString() ?? email.trim().toLowerCase(),
          'expiresInSeconds': (data['expiresInSeconds'] as num?)?.toInt() ?? 600,
          'message': data['message']?.toString() ?? 'SMS verification code sent.',
        };
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'Could not send verification code.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Resident Sign Up / Account Claim Step 2: Verify SMS OTP & activate account
  static Future<Map<String, dynamic>> verifyRegisterOtp({
    required String challengeToken,
    required String code,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/auth/register/verify-otp'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'challengeToken': challengeToken,
              'code': code.replaceAll(RegExp(r'\D'), ''),
            }),
          )
          .timeout(const Duration(seconds: 12));

      final data = _safeDecode(res);
      if ((res.statusCode == 200 || res.statusCode == 201) &&
          data is Map<String, dynamic> &&
          data['token'] != null) {
        await _saveSession(
          data['token'].toString(),
          Map<String, dynamic>.from(data['user'] ?? {}),
        );
        fetchSettings();
        return {
          'success': true,
          'user': currentUser,
          'role': currentUser?['role'] ?? 'tenant',
        };
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'Verification failed.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Forgot Password Step 1: Send 6-digit SMS OTP
  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/auth/forgot-password'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'email': email.trim().toLowerCase()}),
          )
          .timeout(const Duration(seconds: 12));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        final masked = data['maskedPhone']?.toString() ?? '';
        AppNotifications.notifyOtpSent('Password Reset OTP', maskedPhone: masked);
        return {
          'success': true,
          'email': data['email']?.toString() ?? email.trim().toLowerCase(),
          'maskedPhone': masked,
          'expiresInSeconds': (data['expiresInSeconds'] as num?)?.toInt() ?? 600,
          'message': data['message']?.toString() ?? 'Verification code sent via SMS.',
        };
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'Could not send reset code.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Forgot Password Step 2: Verify 6-digit SMS OTP
  static Future<Map<String, dynamic>> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/auth/verify-code'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'code': code.replaceAll(RegExp(r'\D'), ''),
            }),
          )
          .timeout(const Duration(seconds: 12));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return {
          'success': true,
          'resetToken': data['resetToken']?.toString() ?? '',
          'email': data['email']?.toString() ?? email.trim().toLowerCase(),
          'message': data['message']?.toString() ?? 'Code verified.',
        };
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'Invalid verification code.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Forgot Password Step 3: Set new password using verified resetToken
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String resetToken,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/auth/reset-password'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'resetToken': resetToken,
              'password': password,
              'confirmPassword': confirmPassword,
            }),
          )
          .timeout(const Duration(seconds: 12));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return {
          'success': true,
          'message': data['message']?.toString() ?? 'Password updated successfully.',
        };
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'Failed to reset password.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<void> logout() async {
    authToken = null;
    currentUser = null;
    AppNotifications.stopPolling();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    } catch (_) {}
  }

  // --- UNIT TYPES CRUD (With Occupied-Unit Integrity Guard) ---

  static Future<Map<String, dynamic>> fetchUnitTypes() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/unit-types'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final decoded = _safeDecode(res);
      if (res.statusCode == 200 && decoded is List) {
        final items = decoded
            .whereType<Map<String, dynamic>>()
            .map((e) => UnitTypeModel.fromJson(e))
            .toList();
        return {'success': true, 'unitTypes': items};
      }
      return {'success': false, 'error': _extractError(res, decoded, 'Failed to load unit types.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> saveUnitType({
    String? id,
    String? key,
    required String name,
    required int baseRent,
    int depositMultiplier = 1,
    String description = '',
    List<String> features = const [],
  }) async {
    try {
      final isUpdate = id != null && id.isNotEmpty;
      final uri = isUpdate
          ? Uri.parse('$baseUrl/api/unit-types/$id')
          : Uri.parse('$baseUrl/api/unit-types');
      final body = jsonEncode({
        if (isUpdate) 'id': id,
        if (key != null && key.isNotEmpty) 'key': key,
        'name': name.trim(),
        'baseRent': baseRent,
        'depositMultiplier': depositMultiplier,
        'description': description.trim(),
        'features': features,
      });

      final res = isUpdate
          ? await http.put(uri, headers: _headers, body: body).timeout(const Duration(seconds: 12))
          : await http.post(uri, headers: _headers, body: body).timeout(const Duration(seconds: 12));

      final data = _safeDecode(res);
      if (res.statusCode == 200 || res.statusCode == 201) {
        triggerRealtimeRefresh();
        return {'success': true, 'unitType': data};
      }
      return {'success': false, 'error': _extractError(res, data, 'Failed to save unit type.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> deleteUnitType(String id) async {
    try {
      final res = await http
          .delete(Uri.parse('$baseUrl/api/unit-types/$id'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final data = _safeDecode(res);
      if (res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true};
      }
      return {'success': false, 'error': _extractError(res, data, 'Could not delete unit type.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  // --- SETTINGS & REMINDERS ---

  static Future<Map<String, dynamic>> fetchSettings() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/settings'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        final settingsJson = data['settings'];
        if (settingsJson is Map<String, dynamic>) {
          cachedSettings = PropertySettingsModel.fromJson(settingsJson);
        }
        final rawAdmins = (data['admins'] as List?) ?? [];
        final admins = rawAdmins
            .whereType<Map<String, dynamic>>()
            .map((a) => AdminAccountModel.fromJson(a))
            .toList();
        return {
          'success': true,
          'settings': cachedSettings,
          'admins': admins,
        };
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'Could not load settings.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> updateSettings({
    Map<String, dynamic>? settings,
    List<Map<String, dynamic>>? admins,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (settings != null) body['settings'] = settings;
      if (admins != null) body['admins'] = admins;

      final res = await http
          .put(
            Uri.parse('$baseUrl/api/settings'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        if (data['settings'] is Map<String, dynamic>) {
          cachedSettings = PropertySettingsModel.fromJson(data['settings']);
        }
        triggerRealtimeRefresh();
        return {'success': true, 'data': data};
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'Failed to save settings.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> runRentReminders() async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/reminders/run'),
            headers: _headers,
            body: jsonEncode({'force': true}),
          )
          .timeout(const Duration(seconds: 20));
      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return {
          'success': true,
          'sent': data['sent'] ?? 0,
          'message': data['message']?.toString() ?? 'Rent reminders processed.',
        };
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'Could not run rent reminders.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  // --- TENANT-SPECIFIC LOADERS ---

  static Future<TenantModel?> fetchTenantProfile(String tenantId) async {
    if (tenantId.isEmpty) return null;
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/tenants/$tenantId'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = _safeDecode(res);
        if (data is Map<String, dynamic>) return TenantModel.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  static Future<LeaseModel?> fetchTenantLease(String tenantId) async {
    if (tenantId.isEmpty) return null;
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/leases?tenantId=$tenantId'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = _safeDecode(res);
        if (list is List && list.isNotEmpty) {
          final active = list.cast<Map<String, dynamic>>().firstWhere(
                (l) => l['status'] == 'active' || l['status'] == 'pending_deposit',
                orElse: () => list.first as Map<String, dynamic>,
              );
          return LeaseModel.fromJson(active);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<List<TransactionModel>> fetchTenantTransactions(
    String tenantId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/api/transactions?tenantId=$tenantId&page=$page&limit=$limit'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final decoded = _safeDecode(res);
      if (res.statusCode == 200 && decoded is List) {
        final txs = decoded
            .whereType<Map<String, dynamic>>()
            .map((t) => TransactionModel.fromJson(t))
            .toList();
        txs.sort((a, b) => b.date.compareTo(a.date));
        return txs;
      }
      throw ApiException(_extractError(res, decoded, 'Failed to load payment records.'));
    } catch (e) {
      throw ApiException(friendlyError(e));
    }
  }

  // --- LANDLORD / ADMIN LOADERS ---

  static Future<DashboardData> fetchDashboardStats() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/dashboard/stats'), headers: _headers)
          .timeout(const Duration(seconds: 12));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        final unitTypes = ((data['unitTypes'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map((t) => UnitTypeModel.fromJson(t))
            .toList();
        final units = ((data['units'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map((u) => UnitModel.fromJson(u, unitTypes))
            .toList();
        final tenants = ((data['tenants'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map((t) => TenantModel.fromJson(t))
            .toList();
        final leases = ((data['leases'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map((l) => LeaseModel.fromJson(l))
            .toList();
        final transactions = ((data['transactions'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map((t) => TransactionModel.fromJson(t))
            .toList();
        transactions.sort((a, b) => b.date.compareTo(a.date));

        return DashboardData(
          units: units,
          tenants: tenants,
          leases: leases,
          transactions: transactions,
          unitTypes: unitTypes,
        );
      }
      throw ApiException(_extractError(res, data, 'Failed to load portfolio data.'));
    } catch (e) {
      throw ApiException(friendlyError(e));
    }
  }

  static Future<List<TransactionModel>> fetchTransactions({
    String? tenantId,
    String? unitNumber,
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (tenantId != null && tenantId.isNotEmpty) params['tenantId'] = tenantId;
      if (unitNumber != null && unitNumber.isNotEmpty) params['unitNumber'] = unitNumber;

      final uri = Uri.parse('$baseUrl/api/transactions').replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      final decoded = _safeDecode(res);
      if (res.statusCode == 200 && decoded is List) {
        final txs = decoded
            .whereType<Map<String, dynamic>>()
            .map((t) => TransactionModel.fromJson(t))
            .toList();
        txs.sort((a, b) => b.date.compareTo(a.date));
        return txs;
      }
      throw ApiException(_extractError(res, decoded, 'Failed to load financial ledger.'));
    } catch (e) {
      throw ApiException(friendlyError(e));
    }
  }

  // --- CRUD FUNCTIONS ---

  static Future<Map<String, dynamic>> createUnit({
    required String unitNumber,
    required String type,
    String status = 'vacant',
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/units'),
            headers: _headers,
            body: jsonEncode({
              'unitNumber': unitNumber.trim().toUpperCase(),
              'type': type,
              'status': status,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = _safeDecode(res);
      if (res.statusCode == 201 || res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true, 'unit': data};
      }
      return {'success': false, 'error': _extractError(res, data, 'Failed to create unit.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> updateUnit(
    String id, {
    String? type,
    String? status,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (type != null) body['type'] = type;
      if (status != null) body['status'] = status;

      final res = await http
          .put(
            Uri.parse('$baseUrl/api/units/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      final data = _safeDecode(res);
      if (res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true};
      }
      return {'success': false, 'error': _extractError(res, data, 'Could not update unit.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> createLease({
    required String tenantId,
    required String unitId,
    required String unitNumber,
    required int monthlyRent,
    required int depositAmount,
    required String startDate,
    required String endDate,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/leases'),
            headers: _headers,
            body: jsonEncode({
              'tenantId': tenantId,
              'unitId': unitId,
              'unitNumber': unitNumber,
              'monthlyRent': monthlyRent,
              'depositAmount': depositAmount,
              'startDate': startDate,
              'endDate': endDate,
            }),
          )
          .timeout(const Duration(seconds: 12));
      final data = _safeDecode(res);
      if (res.statusCode == 201 || res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true, 'lease': data};
      }
      return {'success': false, 'error': _extractError(res, data, 'Failed to assign lease.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> terminateLease(String leaseId, {String? reason}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/leases/$leaseId/terminate'),
            headers: _headers,
            body: jsonEncode({'reason': reason ?? 'Normal lease conclusion'}),
          )
          .timeout(const Duration(seconds: 10));
      final data = _safeDecode(res);
      if (res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true};
      }
      return {'success': false, 'error': _extractError(res, data, 'Failed to terminate lease.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<LeaseModel?> fetchLeaseById(String id) async {
    if (id.isEmpty) return null;
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/leases/$id'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = _safeDecode(res);
        if (data is Map<String, dynamic>) return LeaseModel.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>> amendLease(
    String leaseId, {
    String changeType = 'rent_adjustment',
    String? effectiveDate,
    int? newRent,
    int? newDeposit,
    String? newEndDate,
    String? reason,
    String? notes,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/leases/$leaseId/amend'),
            headers: _headers,
            body: jsonEncode({
              'changeType': changeType,
              if (effectiveDate != null && effectiveDate.isNotEmpty) 'effectiveDate': effectiveDate,
              if (newRent != null && newRent > 0) 'newRent': newRent,
              if (newDeposit != null && newDeposit >= 0) 'newDeposit': newDeposit,
              if (newEndDate != null && newEndDate.isNotEmpty) 'newEndDate': newEndDate,
              'reason': (reason ?? '').trim().isNotEmpty ? reason!.trim() : 'Lease update',
              if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
            }),
          )
          .timeout(const Duration(seconds: 12));
      final data = _safeDecode(res);
      if (res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true, 'data': data};
      }
      return {'success': false, 'error': _extractError(res, data, 'Could not update lease.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> transferLease({
    required String tenantId,
    String? currentUnitId,
    required String newUnitId,
    required int newRent,
    bool depositRollOver = true,
    String? transferDate,
    String? transferNotes,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/leases/transfer'),
            headers: _headers,
            body: jsonEncode({
              'tenantId': tenantId,
              if (currentUnitId != null && currentUnitId.isNotEmpty) 'currentUnitId': currentUnitId,
              'newUnitId': newUnitId,
              'newRent': newRent,
              'depositRollOver': depositRollOver,
              if (transferDate != null && transferDate.isNotEmpty) 'transferDate': transferDate,
              if (transferNotes != null && transferNotes.trim().isNotEmpty) 'transferNotes': transferNotes.trim(),
            }),
          )
          .timeout(const Duration(seconds: 12));
      final data = _safeDecode(res);
      if (res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true, 'data': data};
      }
      return {'success': false, 'error': _extractError(res, data, 'Could not transfer lease.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> createTenant({
    required String name,
    required String email,
    required String phone,
    String? nationalId,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/tenants'),
            headers: _headers,
            body: jsonEncode({
              'name': name.trim(),
              'email': email.trim().toLowerCase(),
              'phone': toCanonicalKenyaPhone(phone),
              if (nationalId != null && nationalId.trim().isNotEmpty) 'nationalId': nationalId.trim(),
            }),
          )
          .timeout(const Duration(seconds: 12));
      final data = _safeDecode(res);
      if (res.statusCode == 201 || res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true, 'tenant': data};
      }
      return {'success': false, 'error': _extractError(res, data, 'Could not add resident.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> updateTenant(
    String id, {
    String? name,
    String? phone,
    String? email,
    String? nationalId,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null && name.trim().isNotEmpty) body['name'] = name.trim();
      if (phone != null) body['phone'] = toCanonicalKenyaPhone(phone);
      if (email != null) body['email'] = email.trim().toLowerCase();
      if (nationalId != null) body['nationalId'] = nationalId.trim();

      final res = await http
          .put(
            Uri.parse('$baseUrl/api/tenants/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      final data = _safeDecode(res);
      if (res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true};
      }
      return {'success': false, 'error': _extractError(res, data, 'Could not update resident.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> deleteTenant(String id) async {
    try {
      final res = await http
          .delete(Uri.parse('$baseUrl/api/tenants/$id'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final data = _safeDecode(res);
      if (res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true};
      }
      return {'success': false, 'error': _extractError(res, data, 'Could not remove resident.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  // --- MAINTENANCE & NOTIFICATIONS ---

  static Future<List<MaintenanceTicket>> fetchMaintenance() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/maintenance'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final decoded = _safeDecode(res);
      if (res.statusCode == 200 && decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((m) => MaintenanceTicket.fromJson(m))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>> createMaintenanceTicket({
    required String title,
    required String description,
    required String category,
    required String priority,
    String? tenantId,
    String? unitNumber,
    String? unitId,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/maintenance'),
            headers: _headers,
            body: jsonEncode({
              'title': title.trim(),
              'description': description.trim(),
              'category': category,
              'priority': priority,
              if (tenantId != null && tenantId.isNotEmpty) 'tenantId': tenantId,
              if (unitNumber != null && unitNumber.isNotEmpty) 'unitNumber': unitNumber,
              if (unitId != null && unitId.isNotEmpty) 'unitId': unitId,
            }),
          )
          .timeout(const Duration(seconds: 12));
      final data = _safeDecode(res);
      if (res.statusCode == 200 || res.statusCode == 201) {
        triggerRealtimeRefresh();
        return {'success': true, 'ticket': data};
      }
      return {'success': false, 'error': _extractError(res, data, 'Failed to submit ticket.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Landlord: Update maintenance ticket status, technician, and resident update/template message
  static Future<Map<String, dynamic>> updateMaintenanceTicket(
    String id, {
    required String status,
    String? assignedTo,
    String? resolutionNotes,
  }) async {
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/api/maintenance/$id'),
            headers: _headers,
            body: jsonEncode({
              'status': status,
              'assignedTo': assignedTo?.trim() ?? '',
              'resolutionNotes': resolutionNotes?.trim() ?? '',
            }),
          )
          .timeout(const Duration(seconds: 12));
      final data = _safeDecode(res);
      if (res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true, 'ticket': data};
      }
      return {'success': false, 'error': _extractError(res, data, 'Failed to update ticket.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  static Future<List<NotificationModel>> fetchNotifications() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/notifications'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      final decoded = _safeDecode(res);
      if (res.statusCode == 200 && decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((n) => NotificationModel.fromJson(n))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> markNotificationRead(String id) async {
    try {
      await http
          .post(Uri.parse('$baseUrl/api/notifications/$id/read'), headers: _headers)
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  // --- PAYMENTS, MANUAL PAYBILL, STK PUSH & LIVE KCB RECOVERY ---

  /// Record a manual M-Pesa Paybill / direct payment (Tenant portal OR Admin ledger)
  static Future<Map<String, dynamic>> recordManualPayment({
    String? tenantId,
    String? unitId,
    String? leaseId,
    String? unitNumber,
    required int amount,
    required String reference,
    String? notes,
    String? phoneNumber,
    String? payerName,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/transactions'),
            headers: _headers,
            body: jsonEncode({
              if (tenantId != null && tenantId.isNotEmpty) 'tenantId': tenantId,
              if (unitId != null && unitId.isNotEmpty) 'unitId': unitId,
              if (leaseId != null && leaseId.isNotEmpty) 'leaseId': leaseId,
              if (unitNumber != null && unitNumber.isNotEmpty) 'unitNumber': unitNumber,
              'amount': amount,
              'method': 'mpesa_paybill',
              'reference': reference.trim().toUpperCase(),
              'notes': (notes ?? '').trim().isNotEmpty
                  ? notes!.trim()
                  : 'M-Pesa Paybill payment for Unit ${unitNumber ?? "Suite"}',
              if (phoneNumber != null && phoneNumber.isNotEmpty)
                'phoneNumber': toCanonicalKenyaPhone(phoneNumber),
              if (payerName != null && payerName.isNotEmpty) 'payerName': payerName,
              'source': 'manual',
            }),
          )
          .timeout(const Duration(seconds: 12));

      final data = _safeDecode(res);
      if (res.statusCode == 200 || res.statusCode == 201) {
        triggerRealtimeRefresh();
        final pendingVerif = data is Map &&
            (data['pendingVerification'] == true || data['status'] == 'pending_verification');
        return {
          'success': true,
          'transaction': data,
          'pendingVerification': pendingVerif,
        };
      }
      return {'success': false, 'error': _extractError(res, data, 'Failed to record payment.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Landlord only: Approve & reconcile a pending_verification or unassigned payment
  static Future<Map<String, dynamic>> reconcileTransaction({
    required String transactionId,
    required String tenantId,
    String? unitId,
    String? notes,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/transactions/reconcile'),
            headers: _headers,
            body: jsonEncode({
              'transactionId': transactionId,
              'tenantId': tenantId,
              if (unitId != null && unitId.isNotEmpty) 'unitId': unitId,
              if (notes != null && notes.isNotEmpty) 'notes': notes,
            }),
          )
          .timeout(const Duration(seconds: 12));
      final data = _safeDecode(res);
      if (res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true, 'transaction': data};
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'Failed to verify and reconcile payment.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Resident STK Push initiation
  static Future<Map<String, dynamic>> initiateStkPush({
    required String phoneNumber,
    required int amount,
    String? unitNumber,
    String? tenantId,
    String? description,
  }) async {
    try {
      final canonicalPhone = toCanonicalKenyaPhone(phoneNumber);
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/kcb/stkpush'),
            headers: _headers,
            body: jsonEncode({
              'phoneNumber': canonicalPhone,
              'amount': amount,
              'invoiceNumber': 'LAPIS-${unitNumber ?? "RENT"}',
              'unitNumber': unitNumber ?? '',
              'tenantId': tenantId,
              'description': description ?? 'Rent Payment',
              'callerName': currentUser?['name'] ?? 'Resident',
              'callerEmail': currentUser?['email'] ?? 'resident@lapissuites.com',
            }),
          )
          .timeout(const Duration(seconds: 18));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return {
          'success': true,
          'message': data['message'] ?? 'STK prompt dispatched to your phone.',
          'checkoutRequestId':
              data['checkoutRequestId'] ?? data['data']?['CheckoutRequestID'] ?? '',
          'merchantRequestId':
              data['merchantRequestId'] ?? data['data']?['MerchantRequestID'] ?? '',
        };
      }
      return {'success': false, 'error': _extractError(res, data, 'STK push failed.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Admin STK Push Step 1: Request SMS OTP to logged-in admin's configured phone
  static Future<Map<String, dynamic>> requestAdminStkOtp({
    required int amount,
    String? unitNumber,
    String? tenantName,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/kcb/admin-stk/request-otp'),
            headers: _headers,
            body: jsonEncode({
              'amount': amount,
              'unitNumber': unitNumber ?? '',
              'tenantName': tenantName ?? 'Resident',
            }),
          )
          .timeout(const Duration(seconds: 14));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return {
          'success': true,
          'challengeToken': data['challengeToken']?.toString() ?? '',
          'maskedPhone': data['maskedPhone']?.toString() ?? '',
          'message': data['message']?.toString() ?? 'Admin confirmation OTP sent.',
        };
      }
      return {'success': false, 'error': _extractError(res, data, 'Could not send admin OTP.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Admin STK Push Step 2: Verify Admin SMS OTP & send STK push to resident
  static Future<Map<String, dynamic>> verifyAndSendAdminStk({
    required String challengeToken,
    required String code,
    required String phoneNumber,
    required int amount,
    String? unitNumber,
    String? tenantId,
    String? description,
  }) async {
    try {
      final canonicalPhone = toCanonicalKenyaPhone(phoneNumber);
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/kcb/admin-stk/verify-and-push'),
            headers: _headers,
            body: jsonEncode({
              'challengeToken': challengeToken,
              'code': code.replaceAll(RegExp(r'\D'), ''),
              'phoneNumber': canonicalPhone,
              'amount': amount,
              'invoiceNumber': 'LAPIS-${unitNumber ?? "RENT"}',
              'unitNumber': unitNumber ?? '',
              'tenantId': tenantId,
              'description': description ?? 'Rent Payment',
            }),
          )
          .timeout(const Duration(seconds: 18));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return {
          'success': true,
          'checkoutRequestId':
              data['checkoutRequestId'] ?? data['data']?['CheckoutRequestID'] ?? '',
          'merchantRequestId':
              data['merchantRequestId'] ?? data['data']?['MerchantRequestID'] ?? '',
          'message': data['message'] ?? 'STK push dispatched to resident.',
        };
      }
      return {
        'success': false,
        'error': _extractError(res, data, 'OTP verification or STK dispatch failed.'),
      };
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }

  /// Wait for STK Callback from gateway (up to 45s)
  static Future<Map<String, dynamic>> waitForStkCallback(String checkoutRequestId) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/kcb/wait-callback'),
            headers: _headers,
            body: jsonEncode({
              'checkoutRequestId': checkoutRequestId,
              'timeout': 45000,
            }),
          )
          .timeout(const Duration(seconds: 50));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        triggerRealtimeRefresh();
        final isSuccess = data['resultCode'] == 0 ||
            data['resultCode'] == '0' ||
            data['status'] == 'Success';
        final isPending = data['status'] == 'Pending' || data['timedOut'] == true;
        return {
          'success': isSuccess,
          'pending': isPending && !isSuccess,
          'resultCode': data['resultCode'],
          'resultDesc': data['resultDesc'] ??
              data['statusDescription'] ??
              (isSuccess
                  ? 'Payment received and reconciled.'
                  : 'Still awaiting confirmation. Tap "Check Status" to verify with M-Pesa.'),
          'receipt': data['mpesaReceiptNumber'],
          'amount': data['amount'],
        };
      }
      return {
        'success': false,
        'pending': true,
        'error': _extractError(res, data, 'Awaiting payment confirmation.'),
      };
    } catch (e) {
      return {'success': false, 'pending': true, 'error': friendlyError(e)};
    }
  }

  /// Live KCB Buni status query (gracefully recovers missed callbacks!)
  static Future<Map<String, dynamic>> queryKcbStatus({
    String? checkoutRequestId,
    String? merchantRequestId,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/kcb/query'),
            headers: _headers,
            body: jsonEncode({
              if (checkoutRequestId != null && checkoutRequestId.isNotEmpty)
                'checkoutRequestId': checkoutRequestId,
              if (merchantRequestId != null && merchantRequestId.isNotEmpty)
                'merchantRequestId': merchantRequestId,
              'syncLive': true,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = _safeDecode(res);
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        final status = (data['status'] ?? 'Pending').toString();
        if (status == 'Success') triggerRealtimeRefresh();
        return {
          'success': status == 'Success',
          'failed': status == 'Failed',
          'pending': status == 'Pending',
          'status': status,
          'receipt': data['mpesaReceiptNumber'],
          'resultDesc': data['resultDesc'] ?? data['statusDescription'] ?? data['liveNote'] ?? '',
        };
      }
      return {
        'success': false,
        'pending': true,
        'error': _extractError(res, data, 'Could not check payment status.'),
      };
    } catch (e) {
      return {'success': false, 'pending': true, 'error': friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> reconcileTenant(String tenantId) async {
    try {
      final res = await http
          .post(Uri.parse('$baseUrl/api/tenants/$tenantId/reconcile'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      final data = _safeDecode(res);
      if (res.statusCode == 200) {
        triggerRealtimeRefresh();
        return {'success': true, 'data': data};
      }
      return {'success': false, 'error': _extractError(res, data, 'Reconciliation failed.')};
    } catch (e) {
      return {'success': false, 'error': friendlyError(e)};
    }
  }
}
