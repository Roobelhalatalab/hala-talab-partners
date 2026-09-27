import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> halaTalabPartnerFirebaseBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {
    // Never crash a background delivery path because Firebase initialization
    // is temporarily unavailable.
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

  static const String _installationIdPrefKey =
      'hala_talab_partner_push_installation_id_v2';

  final StreamController<PartnerPushEvent> _events =
      StreamController<PartnerPushEvent>.broadcast();

  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;

  Timer? _setupRetryTimer;
  Timer? _tokenRetryTimer;

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
        'Partner FCM skipped on ${defaultTargetPlatform.name}; '
        'Supabase in-app notifications remain enabled.',
      );
      _initialized = true;
      _initializing = false;
      return;
    }

    try {
      // Important: this runs AFTER runApp/first frame, so a Firebase/APNs issue
      // can never hold the application on the launch screen.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp().timeout(
          const Duration(seconds: 15),
        );
      }

      // The background handler is registered in main.dart before runApp.
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);

      // requestPermission() is the FlutterFire-supported Apple permission API.
      // On iOS it presents the system authorization sheet when status is
      // notDetermined. No native notification permission workaround is used.
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint(
        'Partner push permission: ${settings.authorizationStatus.name}',
      );

      if (_isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

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
      _setupRetryTimer?.cancel();
      _setupRetryTimer = null;

      unawaited(syncCurrentInstallation());
    } catch (error, stackTrace) {
      _initialized = false;
      debugPrint('Partner push initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _scheduleSetupRetry();
    } finally {
      _initializing = false;
    }
  }

  void _scheduleSetupRetry() {
    if (_setupRetryTimer?.isActive == true) return;

    _setupRetryTimer = Timer(const Duration(seconds: 20), () {
      _setupRetryTimer = null;
      unawaited(initialize());
    });
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
    if (!_supportsFcm || !_initialized || _syncInProgress) return;

    _syncInProgress = true;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        _scheduleTokenRetry();
        return;
      }

      final role = await _resolvePartnerRole(user);
      if (role == null) {
        debugPrint('Partner push sync waiting for partner role.');
        _scheduleTokenRetry();
        return;
      }

      final messaging = FirebaseMessaging.instance;

      if (_isIOS) {
        final settings = await messaging.getNotificationSettings();

        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          debugPrint('Partner push sync stopped: iOS permission denied.');
          return;
        }

        final apnsToken = await _waitForApnsToken(messaging);
        if (apnsToken == null || apnsToken.isEmpty) {
          _scheduleTokenRetry();
          return;
        }
      }

      final fcmToken = await messaging.getToken();
      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('Partner push sync waiting for FCM token.');
        _scheduleTokenRetry();
        return;
      }

      final installationId = await _installationId();
      final platform = _isIOS ? 'ios' : 'android';

      await Supabase.instance.client.rpc(
        'register_device_push_token',
        params: {
          'p_role': role,
          'p_platform': platform,
          'p_token': fcmToken,
          'p_installation_id': installationId,
        },
      );

      _tokenRetryTimer?.cancel();
      _tokenRetryTimer = null;

      debugPrint(
        'Partner push token registered: '
        'role=$role platform=$platform installation=$installationId',
      );
    } catch (error, stackTrace) {
      debugPrint('Partner push token sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _scheduleTokenRetry();
    } finally {
      _syncInProgress = false;
    }
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
        debugPrint('Partner APNs token check failed: $error');
      }

      await Future<void>.delayed(const Duration(seconds: 1));
    }

    debugPrint('Partner APNs token is unavailable after 30 seconds.');
    return null;
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

  void _scheduleTokenRetry() {
    if (_tokenRetryTimer?.isActive == true) return;

    _tokenRetryTimer = Timer(const Duration(seconds: 20), () {
      _tokenRetryTimer = null;
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
    if (!_supportsFcm || state != AppLifecycleState.resumed) return;

    if (!_initialized) {
      unawaited(initialize());
    } else {
      unawaited(syncCurrentInstallation());
    }
  }

  Future<void> dispose() async {
    if (_observerAdded) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAdded = false;
    }

    _setupRetryTimer?.cancel();
    _tokenRetryTimer?.cancel();

    await _authSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();

    await _events.close();
  }
}
