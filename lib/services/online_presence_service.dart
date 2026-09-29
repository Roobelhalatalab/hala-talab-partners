import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks an authenticated partner as online while the app is in foreground.
///
/// The shared channel name is also used by the customer app so the admin panel
/// can calculate one live total and split it by role (customer/business/driver).
/// No notification, order, printer, or map code is touched here.
class OnlinePresenceService with WidgetsBindingObserver {
  OnlinePresenceService._();

  static final OnlinePresenceService instance = OnlinePresenceService._();

  static const String channelName = 'hala_online_users';

  SupabaseClient get _client => Supabase.instance.client;

  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSubscription;
  bool _initialized = false;
  bool _foreground = true;
  int _syncGeneration = 0;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);
    _authSubscription = _client.auth.onAuthStateChange.listen((_) {
      unawaited(_syncPresence());
    });

    await _syncPresence();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        unawaited(_syncPresence());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _foreground = false;
        unawaited(_disconnect());
        break;
    }
  }

  Future<void> _syncPresence() async {
    final generation = ++_syncGeneration;

    if (!_foreground) {
      await _disconnect();
      return;
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      await _disconnect();
      return;
    }

    String? role;
    try {
      final row = await _client
          .from('partner_profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      role = row?['role']?.toString().trim().toLowerCase();
    } catch (error, stackTrace) {
      debugPrint('Presence role lookup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }

    if (generation != _syncGeneration || !_foreground) return;
    if (role != 'business' && role != 'driver') {
      await _disconnect();
      return;
    }

    await _connect(userId: user.id, role: role!);
  }

  Future<void> _connect({
    required String userId,
    required String role,
  }) async {
    await _disconnect(invalidateSync: false);

    if (!_foreground || _client.auth.currentUser?.id != userId) return;

    final channel = _client.channel(channelName);
    _channel = channel;

    channel.subscribe((status, error) async {
      if (_channel != channel || !_foreground) return;

      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          await channel.track({
            'user_id': userId,
            'role': role,
            'platform': 'ios',
            'online_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (trackError, stackTrace) {
          debugPrint('Presence track failed: $trackError');
          debugPrintStack(stackTrace: stackTrace);
        }
      } else if (error != null) {
        debugPrint('Presence subscribe error: $error');
      }
    });
  }

  Future<void> _disconnect({bool invalidateSync = true}) async {
    if (invalidateSync) _syncGeneration++;

    final channel = _channel;
    _channel = null;
    if (channel == null) return;

    try {
      await channel.untrack();
    } catch (_) {
      // Removing the channel below is enough to clear Presence server-side.
    }

    try {
      await _client.removeChannel(channel);
    } catch (_) {
      // Best effort during lifecycle transitions / sign-out.
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _authSubscription?.cancel();
    _authSubscription = null;
    await _disconnect();
    _initialized = false;
  }
}
