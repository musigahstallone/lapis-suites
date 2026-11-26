import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'core/theme.dart';
import 'core/api.dart';
import 'core/logo.dart';
import 'core/widgets.dart';
import 'core/notifications_service.dart';
import 'auth/login_page.dart';
import 'landlord/landlord.dart';
import 'resident/resident.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  ApiService.onSessionExpired = () {
    final nav = appNavigatorKey.currentState;
    final ctx = appNavigatorKey.currentContext;
    if (nav != null) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
      if (ctx != null && ctx.mounted) {
        showAppSnackBar(ctx, 'Session expired. Please sign in again.', isError: true);
      }
    }
  };

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: C.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const LapisSuitesApp());
}

class LapisSuitesApp extends StatefulWidget {
  const LapisSuitesApp({super.key});

  @override
  State<LapisSuitesApp> createState() => _LapisSuitesAppState();
}

class _LapisSuitesAppState extends State<LapisSuitesApp> with WidgetsBindingObserver {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppNotifications.init();
    _initDeepLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ApiService.authToken != null) {
      AppNotifications.checkNow();
      ApiService.triggerRealtimeRefresh();
    }
  }

  Future<void> _initDeepLinks() async {
    try {
      final appLinks = AppLinks();
      final initial = await appLinks.getInitialLink();
      if (initial != null) _handleIncomingUri(initial);
      _linkSub = appLinks.uriLinkStream.listen(_handleIncomingUri, onError: (_) {});
    } catch (_) {
      // Gracefully ignored in widget tests / desktop
    }
  }

  void _handleIncomingUri(Uri uri) {
    final path = uri.path.toLowerCase();
    final isPayLink = path.startsWith('/pay') || uri.host.toLowerCase() == 'pay';
    if (!isPayLink) return;

    ApiService.pendingDeepLinkPay = true;
    ApiService.triggerRealtimeRefresh();

    final ctx = appNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted && ApiService.authToken == null) {
      showAppSnackBar(ctx, 'Sign in to complete your Lapis Suites rent payment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Lapis Suites',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootDecisionGate(),
    );
  }
}

/// Restores saved session on startup so users stay signed in across app restarts
class RootDecisionGate extends StatefulWidget {
  const RootDecisionGate({super.key});

  @override
  State<RootDecisionGate> createState() => _RootDecisionGateState();
}

class _RootDecisionGateState extends State<RootDecisionGate> {
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await ApiService.restoreSession();
    if (mounted) {
      setState(() => _checkingSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return Scaffold(
        backgroundColor: C.canvas,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LapisLogo(size: 46),
              const SizedBox(height: 14),
              Text(
                'LAPIS SUITES',
                style: flex(14.5, color: C.navy, letterSpacing: 1.0),
              ),
              const SizedBox(height: 16),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: C.navy),
              ),
            ],
          ),
        ),
      );
    }

    if (ApiService.authToken == null) {
      return const LoginPage();
    }

    final role = (ApiService.currentUser?['role'] ?? '').toString().toLowerCase();
    if (role == 'landlord' || role == 'admin' || role == 'manager') {
      return const LandlordPortfolioScreen();
    }
    return const ResidentHomeScreen();
  }
}
