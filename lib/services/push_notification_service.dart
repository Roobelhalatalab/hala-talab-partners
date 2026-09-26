import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> halaTalabPartnerFirebaseBackgroundHandler(
  RemoteMessage message,
) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

class PartnerPushEvent {
  const PartnerPushEvent({
    required this.data,
    required this.openedByUser,
  });

  final Map<String, dynamic> data;
  final bool openedByUser;

  String get orderId => data['order_id']?.toString().trim() ?? '';
  String get notificationType =>
      data['notification_type']?.toString().trim().toLowerCase() ?? '';
}

class PushNotificationService with WidgetsBindingObserver {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const MethodChannel _nativePushChannel =
      MethodChannel('com.halatalab.partners/push_native');

  static const String _installationIdPrefKey =
      'hala_talab_partner_push_installation_id_v2';

  final StreamController<PartnerPushEvent> _events =
      StreamController<PartnerPushEvent>.broadcast();

  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;

  Timer? _retryTimer;
  PartnerPushEvent? _pendingOpenedEvent;

  bool _initialized = false;
  bool _initializing = false;
  bool _observerAdded = false;
  bool _syncInProgress = false;

  Stream<PartnerPushEvent> get events => _events.stream;

  bool get _supportsFcm =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  PartnerPushEvent? takePendingOpenedEvent() {
    final event = _pendingOpenedEvent;
    _pendingOpenedEvent = null;
    return event;
  }

  Future<void> initialize() async {
    if (_initialized || _initializing) return;
    _initializing = true;

    if (!_observerAdded) {
      WidgetsBinding.instance.addObserver(this);
      _observerAdded = true;
    }

    if (!_supportsFcm) {
      debugPrint(
        'Partner push skipped on ${defaultTargetPlatform.name}; '
        'Supabase in-app notifications stay active.',
      );
      _initialized = true;
      _initializing = false;
      return;
    }

    try {
      // main.dart initializes Firebase and registers the background handler
      // before runApp. Keep this as a defensive guard only.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);

      _foregroundSubscription ??= FirebaseMessaging.onMessage.listen(
        (message) => _emitMessage(message, openedByUser: false),
      );

      _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _emitMessage(message, openedByUser: true),
      );

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _pendingOpenedEvent = PartnerPushEvent(
          data: Map<String, dynamic>.from(initialMessage.data),
          openedByUser: true,
        );
      }

      if (_isIOS) {
        await _configureIOS(messaging);
      } else {
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      _tokenSubscription ??= messaging.onTokenRefresh.listen((_) {
        unawaited(syncCurrentInstallation());
      });

      _authSubscription ??=
          Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (state.session != null) {
          unawaited(syncCurrentInstallation());
        }
      });

      _initialized = true;
      unawaited(syncCurrentInstallation());
    } catch (error, stackTrace) {
      _initialized = false;
      debugPrint('Partner push initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _scheduleInitializationRetry();
    } finally {
      _initializing = false;
    }
  }

  void _scheduleInitializationRetry() {
    if (_retryTimer?.isActive == true) return;

    _retryTimer = Timer(const Duration(seconds: 15), () {
      _retryTimer = null;
      unawaited(initialize());
    });
  }

  Future<void> _configureIOS(FirebaseMessaging messaging) async {
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );

    debugPrint(
      'Partner iOS notification permission: '
      '${settings.authorizationStatus.name}',
    );

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Partner iOS notifications are denied by the user.');
      return;
    }

    // Apple requires explicit APNs registration after permission.
    // Keep this tiny native call separate from Firebase initialization.
    try {
      await _nativePushChannel.invokeMethod<bool>(
        'registerForRemoteNotifications',
      );
    } catch (error) {
      // Do not abort Firebase Messaging if the native helper is unavailable.
      // firebase_messaging 16.4.3 + auto-init still has its own APNs
      // registration path; the helper is an additional deterministic request.
      debugPrint('Partner APNs native registration call failed: $error');
    }

    // Never request an FCM token until APNs is actually available.
    await _waitForApnsToken(messaging);
  }

  Future<String?> _waitForApnsToken(
    FirebaseMessaging messaging, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        final token = await messaging.getAPNSToken();
        if (token != null && token.isNotEmpty) {
          debugPrint('Partner APNs token is available.');
          return token;
        }
      } catch (error) {
        debugPrint('Partner APNs token check: $error');
      }

      await Future<void>.delayed(const Duration(seconds: 1));
    }

    debugPrint('Partner APNs token is still unavailable after 30 seconds.');
    return null;
  }

  void _emitMessage(
    RemoteMessage message, {
    required bool openedByUser,
  }) {
    final data = Map<String, dynamic>.from(message.data);
    if (data.isEmpty) return;

    final event = PartnerPushEvent(
      data: data,
      openedByUser: openedByUser,
    );

    if (openedByUser) {
      _pendingOpenedEvent = event;
    }

    _events.add(event);
  }

  Future<void> syncCurrentInstallation() async {
    if (!_supportsFcm || _syncInProgress) return;

    _syncInProgress = true;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        _scheduleRetry();
        return;
      }

      final role = await _resolvePartnerRole(user);
      if (role == null) {
        debugPrint('Partner push sync waiting for partner role.');
        _scheduleRetry();
        return;
      }

      final messaging = FirebaseMessaging.instance;

      if (_isIOS) {
        final settings = await messaging.getNotificationSettings();

        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          debugPrint('Partner push sync stopped: iOS permission denied.');
          return;
        }

        var apnsToken = await messaging.getAPNSToken();
        if (apnsToken == null || apnsToken.isEmpty) {
          // Re-register with APNs in case the app resumed after the permission
          // sheet or the first registration happened before the network was ready.
          try {
            await _nativePushChannel.invokeMethod<bool>(
              'registerForRemoteNotifications',
            );
          } catch (_) {}

          apnsToken = await _waitForApnsToken(
            messaging,
            timeout: const Duration(seconds: 15),
          );
        }

        if (apnsToken == null || apnsToken.isEmpty) {
          _scheduleRetry();
          return;
        }
      }

      final fcmToken = await messaging.getToken();
      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('Partner push sync waiting for FCM token.');
        _scheduleRetry();
        return;
      }

      final installationId = await _installationId();
      final platform = _isIOS ? 'ios' : 'android';

      await _saveToken(
        role: role,
        platform: platform,
        token: fcmToken,
        installationId: installationId,
      );

      _retryTimer?.cancel();
      _retryTimer = null;

      debugPrint(
        'Partner push token registered: '
        'role=$role platform=$platform installation=$installationId',
      );
    } catch (error, stackTrace) {
      debugPrint('Partner push token sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _scheduleRetry();
    } finally {
      _syncInProgress = false;
    }
  }

  Future<String?> _resolvePartnerRole(User user) async {
    try {
      final profile = await Supabase.instance.client
          .from('partner_profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final role = profile?['role']?.toString().trim();
      if (role == 'business' || role == 'driver') {
        return role;
      }
    } catch (error) {
      debugPrint('Partner push role lookup failed: $error');
    }

    final metadataRole = user.userMetadata?['role']?.toString().trim();
    if (metadataRole == 'business' || metadataRole == 'driver') {
      return metadataRole;
    }

    return null;
  }

  Future<void> _saveToken({
    required String role,
    required String platform,
    required String token,
    required String installationId,
  }) async {
    await Supabase.instance.client.rpc(
      'register_device_push_token',
      params: {
        'p_role': role,
        'p_platform': platform,
        'p_token': token,
        'p_installation_id': installationId,
      },
    );
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive == true) return;

    _retryTimer = Timer(const Duration(seconds: 20), () {
      _retryTimer = null;
      unawaited(syncCurrentInstallation());
    });
  }

  Future<String> _installationId() async {
    final preferences = await SharedPreferences.getInstance();

    final existing =
        preferences.getString(_installationIdPrefKey)?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(
      18,
      (_) => random.nextInt(256),
    );

    final generated = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    await preferences.setString(
      _installationIdPrefKey,
      generated,
    );

    return generated;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_supportsFcm) return;

    if (state == AppLifecycleState.resumed) {
      if (!_initialized) {
        unawaited(initialize());
      } else {
        unawaited(syncCurrentInstallation());
      }
    }
  }

  Future<void> dispose() async {
    if (_observerAdded) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAdded = false;
    }
    _retryTimer?.cancel();
    await _authSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _events.close();
  }
}
