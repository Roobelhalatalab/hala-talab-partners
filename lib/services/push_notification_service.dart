import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  static const MethodChannel _iosPushChannel =
      MethodChannel('com.halatalab.partners/ios_push');

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _tokenSub;
  Timer? _retryTimer;
  Timer? _iosSetupRetryTimer;
  bool _initialized = false;
  bool _initializing = false;
  bool _messagingListenersAttached = false;
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

  Future<void> _requestIosPermissionAndRegisterApns() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    try {
      await _iosPushChannel.invokeMethod<bool>(
        'requestPermissionAndRegister',
      );
    } on PlatformException catch (error) {
      debugPrint(
        'Partner native iOS push registration failed: '
        '${error.code} ${error.message}',
      );
      rethrow;
    }
  }

  Future<void> initialize() async {
    if (_initialized || _initializing) return;

    // Build 16 is deliberately iOS-only. Android keeps the Build 15 flow.
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      await _initializeExistingPlatform();
      return;
    }

    _initializing = true;
    WidgetsBinding.instance.addObserver(this);

    try {
      // FlutterFire may already have a default app. Initialize only if needed.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      FirebaseMessaging.onBackgroundMessage(
        halaTalabPartnerFirebaseBackgroundHandler,
      );

      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);

      // Critical iOS order:
      // 1) Firebase is initialized.
      // 2) Firebase Messaging auto-init is enabled.
      // 3) Native iOS asks permission and registers with APNs.
      // This restores the system permission dialog on first install while
      // preventing APNs registration from racing Firebase startup.
      await _requestIosPermissionAndRegisterApns();

      // Read/confirm the authorization state through FlutterFire too. If the
      // user already answered the native prompt, this is idempotent.
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint(
        'Partner iOS push permission: ${settings.authorizationStatus.name}',
      );

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      if (!_messagingListenersAttached) {
        FirebaseMessaging.onMessage.listen((message) {
          _emitMessage(message, openedByUser: false);
        });
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          _emitMessage(message, openedByUser: true);
        });
        _tokenSub = messaging.onTokenRefresh.listen((_) {
          unawaited(_registerCurrentTokenWithRetry());
        });
        _authSub =
            Supabase.instance.client.auth.onAuthStateChange.listen((state) {
          if (state.session == null) return;
          unawaited(_registerCurrentTokenWithRetry());
        });
        _messagingListenersAttached = true;
      }

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _pendingOpenedEvent = PartnerPushEvent(
          data: Map<String, dynamic>.from(initialMessage.data),
          openedByUser: true,
        );
      }

      // Mark initialized only after Firebase + permission setup actually
      // completed. Build 15 marked it before the try block, which could make a
      // one-time startup failure permanent until the next app launch.
      _initialized = true;
      _iosSetupRetryTimer?.cancel();
      _iosSetupRetryTimer = null;

      if (settings.authorizationStatus != AuthorizationStatus.denied) {
        await _waitForApplePushRegistration(messaging);
        unawaited(_registerCurrentTokenWithRetry());
      }
    } catch (error, stack) {
      _initialized = false;
      debugPrint('Partner iOS push setup failed: $error');
      debugPrintStack(stackTrace: stack);
      _scheduleIosSetupRetry();
    } finally {
      _initializing = false;
    }
  }

  Future<void> _initializeExistingPlatform() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);

    if (!_supportsFcm) {
      debugPrint(
        'Partner FCM skipped on ${defaultTargetPlatform.name}; '
        'in-app Supabase notifications remain enabled.',
      );
      return;
    }

    // This is the existing Build 15 Android path, kept unchanged.
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
        halaTalabPartnerFirebaseBackgroundHandler,
      );

      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint(
        'Partner push permission: ${settings.authorizationStatus.name}',
      );

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

      unawaited(_registerCurrentTokenWithRetry());
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

  void _scheduleIosSetupRetry() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    if (_iosSetupRetryTimer?.isActive == true) return;

    _iosSetupRetryTimer =
        Timer.periodic(const Duration(seconds: 8), (timer) {
      if (_initialized) {
        timer.cancel();
        if (identical(_iosSetupRetryTimer, timer)) {
          _iosSetupRetryTimer = null;
        }
        return;
      }
      unawaited(initialize());
    });
  }

  Future<void> _waitForApplePushRegistration(
    FirebaseMessaging messaging,
  ) async {
    // A real iPhone may need a few seconds before APNs exposes its device token.
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 5),
      Duration(seconds: 8),
    ];

    for (final delay in delays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      try {
        final apnsToken = await messaging.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) {
          debugPrint('Partner APNs registration ready.');
          return;
        }
      } catch (error) {
        debugPrint('Partner APNs token check waiting: $error');
      }
    }

    debugPrint(
      'Partner APNs token not ready yet; background retry will continue.',
    );
  }

  Future<void> _registerCurrentTokenWithRetry() async {
    _retryTimer?.cancel();

    // Real iPhones can take several seconds to expose the APNs token after a
    // cold start, first install, permission change, or network handover. Keep
    // retrying long enough to cover that window without blocking app startup.
    const retryDelays = <Duration>[
      Duration.zero,
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
    ];

    for (var attempt = 0; attempt < retryDelays.length; attempt++) {
      final delay = retryDelays[attempt];
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final registered = await _registerCurrentToken();
      if (registered) return;
    }

    // A final delayed attempt also covers first-login flows where
    // partner_profiles is committed after the auth event or APNs becomes
    // available unusually late. Resume/token-refresh/auth events also trigger
    // registration independently.
    _retryTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      unawaited(() async {
        final registered = await _registerCurrentToken();
        if (registered) {
          timer.cancel();
          if (identical(_retryTimer, timer)) _retryTimer = null;
        }
      }());
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
        final settings =
            await FirebaseMessaging.instance.getNotificationSettings();
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          debugPrint(
            'Partner push token registration blocked: iOS notifications are denied.',
          );
          return false;
        }

        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken == null || apnsToken.isEmpty) {
          debugPrint('Partner push token registration waiting for APNs token.');
          try {
            await _requestIosPermissionAndRegisterApns();
          } catch (_) {}
          return false;
        }
        debugPrint('Partner APNs token is available.');
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return false;

      final installationId = await _installationId();
      final now = DateTime.now().toUtc().toIso8601String();
      final platform = defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : defaultTargetPlatform.name.toLowerCase();

      // Stage 208 Fix 4: register one row per physical app installation. The
      // server RPC atomically rotates the token for THIS installation only and
      // never deletes tokens belonging to the same Store account on other
      // phones/tablets. A direct-upsert fallback keeps older backends usable
      // until the migration is applied.
      try {
        await Supabase.instance.client.rpc('register_device_push_token', params: {
          'p_role': role,
          'p_platform': platform,
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
          'platform': platform,
          'token': token,
          'updated_at': now,
        }, onConflict: 'token');
      }

      debugPrint(
        'Partner push token registered: role=$role '
        'platform=$platform installation=$installationId',
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
      if (defaultTargetPlatform == TargetPlatform.iOS && !_initialized) {
        unawaited(initialize());
      } else {
        unawaited(_registerCurrentTokenWithRetry());
      }
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _iosSetupRetryTimer?.cancel();
    await _authSub?.cancel();
    await _tokenSub?.cancel();
  }
}
