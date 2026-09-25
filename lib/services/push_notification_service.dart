import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> halaTalabPartnerFirebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

/// Hala Talab Partners push registration.
///
/// Firebase Messaging is enabled only on Android/iOS. iPadOS is covered by iOS.
/// Windows keeps the existing in-app Supabase realtime notifications and does
/// not attempt to initialize the unsupported firebase_messaging desktop path.
class PartnerPushEvent {
  const PartnerPushEvent({required this.data, required this.openedByUser});
  final Map<String, dynamic> data;
  final bool openedByUser;

  String get orderId => data['order_id']?.toString().trim() ?? '';
  String get notificationType =>
      data['notification_type']?.toString().trim().toLowerCase() ?? '';
}

class PushNotificationService with WidgetsBindingObserver {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _tokenSub;
  Timer? _retryTimer;
  bool _initialized = false;
  final StreamController<PartnerPushEvent> _events =
      StreamController<PartnerPushEvent>.broadcast();
  PartnerPushEvent? _pendingOpenedEvent;

  Stream<PartnerPushEvent> get events => _events.stream;

  PartnerPushEvent? takePendingOpenedEvent() {
    final event = _pendingOpenedEvent;
    _pendingOpenedEvent = null;
    return event;
  }

  void _emitMessage(RemoteMessage message, {required bool openedByUser}) {
    final data = Map<String, dynamic>.from(message.data);
    if (data.isEmpty) return;
    final event = PartnerPushEvent(data: data, openedByUser: openedByUser);
    if (openedByUser) _pendingOpenedEvent = event;
    _events.add(event);
  }

  bool get _supportsFcm => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);

    // firebase_messaging does not provide native Windows push delivery.
    // Do not let that affect the Store Windows build or its in-app realtime
    // notifications.
    if (!_supportsFcm) {
      debugPrint(
        'Partner FCM skipped on ${defaultTargetPlatform.name}; '
        'in-app Supabase notifications remain enabled.',
      );
      return;
    }

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
        halaTalabPartnerFirebaseBackgroundHandler,
      );

      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // Foreground messages do not automatically display an Android system
      // banner. We still surface them instantly inside the app by emitting a
      // canonical event; the Driver home refreshes its notification badge/list.
      FirebaseMessaging.onMessage.listen((message) {
        _emitMessage(message, openedByUser: false);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _emitMessage(message, openedByUser: true);
      });
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _pendingOpenedEvent = PartnerPushEvent(
          data: Map<String, dynamic>.from(initialMessage.data),
          openedByUser: true,
        );
      }

      await _registerCurrentTokenWithRetry();
      _tokenSub = messaging.onTokenRefresh.listen((_) {
        unawaited(_registerCurrentTokenWithRetry());
      });
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (state.session == null) return;
        unawaited(_registerCurrentTokenWithRetry());
      });
    } catch (error, stack) {
      debugPrint('Partner push setup failed: $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  Future<void> _registerCurrentTokenWithRetry() async {
    _retryTimer?.cancel();
    // iOS can take several seconds after first launch / reinstall to receive
    // an APNs token. Keep retrying long enough for that handshake and for a
    // just-created partner profile to become visible, without blocking UI.
    for (var attempt = 0; attempt < 12; attempt++) {
      final registered = await _registerCurrentToken();
      if (registered) return;
      if (attempt < 11) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    // A final delayed retry also covers returning from the notification
    // permission sheet or a temporarily unavailable network connection.
    _retryTimer = Timer(const Duration(seconds: 15), () {
      unawaited(_registerCurrentToken());
    });
  }

  static const _installationIdPrefKey =
      'hala_talab_partner_push_installation_id_v1';

  Future<String> _installationId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installationIdPrefKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;

    // Stable per app installation/device. It is intentionally not derived from
    // hardware identifiers, phone number, or account data. This lets one Store
    // account keep one independent push registration per phone/tablet while
    // preserving privacy and surviving sign-out/sign-in on the same device.
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    final generated = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(_installationIdPrefKey, generated);
    return generated;
  }

  Future<bool> _registerCurrentToken() async {
    if (!_supportsFcm) return false;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return false;

      // Canonical role comes from partner_profiles. Metadata is only a safe
      // fallback during the short first-login window before the profile row is
      // visible. Only Hala Talab partner roles are accepted.
      String? role;
      try {
        final profile = await Supabase.instance.client
            .from('partner_profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();
        final profileRole = profile?['role']?.toString();
        if (profileRole == 'business' || profileRole == 'driver') {
          role = profileRole;
        }
      } catch (_) {}

      final metadataRole = user.userMetadata?['role']?.toString();
      if (role == null &&
          (metadataRole == 'business' || metadataRole == 'driver')) {
        role = metadataRole;
      }
      if (role == null) {
        debugPrint(
          'Partner push token registration waiting for canonical partner role.',
        );
        return false;
      }

      // On Apple platforms wait for APNs before asking Firebase for its token.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken == null || apnsToken.isEmpty) {
          debugPrint('Partner push token registration waiting for APNs token.');
          return false;
        }
        debugPrint('Partner APNs token is available.');
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return false;

      final installationId = await _installationId();
      final now = DateTime.now().toUtc().toIso8601String();

      // Stage 208 Fix 4: register one row per physical app installation. The
      // server RPC atomically rotates the token for THIS installation only and
      // never deletes tokens belonging to the same Store account on other
      // phones/tablets. A direct-upsert fallback keeps older backends usable
      // until the migration is applied.
      try {
        await Supabase.instance.client.rpc('register_device_push_token', params: {
          'p_role': role,
          'p_platform': defaultTargetPlatform.name,
          'p_token': token,
          'p_installation_id': installationId,
        });
      } catch (rpcError) {
        debugPrint(
          'Multi-device push RPC unavailable; using compatibility registration: '
          '$rpcError',
        );
        await Supabase.instance.client.from('device_push_tokens').upsert({
          'user_id': user.id,
          'role': role,
          'platform': defaultTargetPlatform.name,
          'token': token,
          'updated_at': now,
        }, onConflict: 'token');
      }

      debugPrint(
        'Partner push token registered: role=$role '
        'platform=${defaultTargetPlatform.name} installation=$installationId',
      );
      return true;
    } catch (error) {
      debugPrint('Partner push token registration failed: $error');
      return false;
    }
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // FCM tokens can rotate while the app is backgrounded. Re-register on
    // every resume so each physical installation remains represented in
    // device_push_tokens. This intentionally does NOT delete tokens belonging
    // to the same account on other devices: Hala Talab supports multi-device
    // Store/Driver sessions and push fan-out to every valid token.
    if (state == AppLifecycleState.resumed && _supportsFcm) {
      unawaited(_registerCurrentTokenWithRetry());
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    await _authSub?.cancel();
    await _tokenSub?.cancel();
  }
}
