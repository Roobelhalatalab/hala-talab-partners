import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService._();

  static final instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  Session? get currentSession => _client.auth.currentSession;

  static const _activeRoleKey = 'active_partner_role';
  static const _quickLockKey = 'partner_quick_lock';
  String? _activeRoleCache;
  final ValueNotifier<int> quickLockRevision = ValueNotifier<int>(0);

  void refreshAuthGate() {
    quickLockRevision.value++;
  }

  Future<void> setActivePartnerRole(String role) async {
    final normalized = role == 'driver' ? 'driver' : 'business';
    // Set memory first so an auth-state event can never beat the disk write.
    _activeRoleCache = normalized;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_activeRoleKey, normalized);
  }

  Future<String?> getActivePartnerRole() async {
    final cached = _activeRoleCache;
    if (cached == 'driver' || cached == 'business') return cached;
    final preferences = await SharedPreferences.getInstance();
    final role = preferences.getString(_activeRoleKey);
    if (role == 'driver' || role == 'business') {
      _activeRoleCache = role;
      return role;
    }
    return null;
  }

  Future<void> clearActivePartnerRole() async {
    _activeRoleCache = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_activeRoleKey);
  }




  Future<void> lockCurrentSession() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      await signOut();
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_quickLockKey, true);
    quickLockRevision.value++;
  }

  Future<void> unlockCurrentSession() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_quickLockKey, false);
    quickLockRevision.value++;
  }

  Future<bool> isQuickLocked() async {
    // Stage 193: no daily PIN/lock screen. A persisted Supabase session opens
    // the verified account automatically until the user explicitly signs out.
    final preferences = await SharedPreferences.getInstance();
    if (preferences.containsKey(_quickLockKey)) {
      await preferences.remove(_quickLockKey);
    }
    return false;
  }

  Future<void> fullSignOut() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_quickLockKey);
    quickLockRevision.value++;
    await clearActivePartnerRole();
    await _client.auth.signOut();
  }


  /// Permanently deletes the currently signed-in partner account.
  ///
  /// The server resolves the caller from the access token and verifies that
  /// the authoritative role matches [expectedRole]. The client never sends a
  /// user id, so one account cannot request deletion of another account.
  Future<void> deleteCurrentPartnerAccount({required String expectedRole}) async {
    final normalizedRole = expectedRole == 'driver' ? 'driver' : 'business';
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('partner_not_signed_in');

    final response = await _client.functions.invoke(
      'delete-partner-account',
      body: {
        'confirm': true,
        'expected_role': normalizedRole,
      },
    );
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : const <String, dynamic>{};
    if (response.status < 200 || response.status >= 300 || data['ok'] != true) {
      final code = (data['code'] ?? 'PARTNER_ACCOUNT_DELETE_FAILED').toString();
      throw StateError(code);
    }

    // Clear only this deleted partner's local authentication state. Business,
    // order, printer and notification configuration belonging to other users
    // is never touched here.
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_quickLockKey);
    await preferences.remove('partner_pin_$userId');
    await preferences.remove('pending_social_role');
    await clearActivePartnerRole();
    quickLockRevision.value++;
    try {
      await _client.auth.signOut();
    } catch (_) {
      // The auth user has already been deleted by the server. Supabase may
      // reject the remote sign-out after that point; the deletion itself has
      // already succeeded, so do not turn that into a false deletion failure.
    }
  }

  Future<String> getAccountRoleForEmail(String email) async {
    final result = await _client.rpc(
      'get_account_role_for_email',
      params: {'p_email': email.trim().toLowerCase()},
    );
    final role = result?.toString().trim().toLowerCase();
    if (role == null || role.isEmpty || role == 'null') return 'unknown';
    return role;
  }

  Future<void> ensureEmailRoleAllowed({
    required String email,
    required String requestedRole,
    bool requireExisting = false,
    bool requireNew = false,
  }) async {
    final expected = requestedRole == 'driver' ? 'driver' : 'business';
    final actual = await getAccountRoleForEmail(email);

    if (requireExisting) {
      if (actual == 'unregistered') {
        throw const AuthException('account_not_found');
      }
      if (actual == 'unknown') {
        throw const AuthException('account_role_unknown');
      }
      if (actual != expected) {
        throw AuthException('account_role_mismatch:$actual');
      }
      return;
    }

    if (requireNew) {
      if (actual == 'unregistered') return;
      if (actual == 'unknown') {
        throw const AuthException('account_role_unknown');
      }
      if (actual != expected) {
        throw AuthException('account_role_mismatch:$actual');
      }
      throw const AuthException('account_already_exists');
    }

    if (actual == 'unknown') {
      throw const AuthException('account_role_unknown');
    }
    if (actual != 'unregistered' && actual != expected) {
      throw AuthException('account_role_mismatch:$actual');
    }
  }

  Future<void> sendEmailOtp({
    required String email,
    required String fullName,
    required String phone,
    required String role,
    String? businessType,
    String? systemCategoryId,
  }) async {
    await ensureEmailRoleAllowed(
      email: email,
      requestedRole: role,
      requireNew: true,
    );
    await _client.auth.signInWithOtp(
      email: email.trim().toLowerCase(),
      shouldCreateUser: true,
      data: {
        'full_name': fullName.trim(),
        'phone': _normalizeIraqiPhone(phone),
        'role': role,
        'account_role': role,
        'business_type': businessType,
        'system_category_id': systemCategoryId,
      },
    );
  }

  Future<void> sendLoginEmailOtp(String email, {required String role}) async {
    await ensureEmailRoleAllowed(
      email: email,
      requestedRole: role,
      requireExisting: true,
    );
    await _client.auth.signInWithOtp(
      email: email.trim().toLowerCase(),
      shouldCreateUser: false,
    );
  }

  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
    required String requestedRole,
  }) async {
    final response = await _client.auth.verifyOTP(
      email: email.trim().toLowerCase(),
      token: token.trim(),
      type: OtpType.email,
    );
    await validateCurrentSessionRole(requestedRole: requestedRole);
    return response;
  }

  Future<void> saveLocalPin(String pin) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('partner_not_signed_in');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('partner_pin_$userId', pin);
  }

  Future<bool> hasLocalPin() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('partner_pin_$userId');
  }

  Future<bool> verifyLocalPin(String pin) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('partner_pin_$userId') == pin;
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String role,
    String? businessType,
  }) {
    return _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password.trim(),
      data: {
        'full_name': fullName.trim(),
        'phone': _normalizeIraqiPhone(phone),
        'role': role,
        'account_role': role,
        'business_type': businessType,
      },
    );
  }

  Future<AuthResponse> signIn({
    required String identifier,
    required String password,
  }) {
    final value = identifier.trim();
    if (value.contains('@')) {
      return _client.auth.signInWithPassword(
        email: value.toLowerCase(),
        password: password.trim(),
      );
    }
    return _client.auth.signInWithPassword(
      phone: _normalizeIraqiPhone(value),
      password: password.trim(),
    );
  }


  Future<String> getAuthoritativePartnerRole() async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('partner_not_signed_in');

    final profile = await _client
        .from('partner_profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    final role = profile?['role']?.toString();
    if (role != 'business' && role != 'driver') {
      throw const AuthException('partner_role_missing');
    }
    return role!;
  }

  Future<String> validateCurrentSessionRole({String? requestedRole}) async {
    final normalizedRequested = requestedRole == null
        ? null
        : (requestedRole == 'driver' ? 'driver' : 'business');
    late final String authoritativeRole;
    try {
      final currentRoleResult = await _client.rpc('get_current_account_role');
      final unifiedRole = currentRoleResult?.toString().trim().toLowerCase() ?? 'unknown';
      if (unifiedRole == 'unknown' || unifiedRole == 'unregistered' || unifiedRole == 'anonymous') {
        throw const AuthException('account_role_unknown');
      }
      if (unifiedRole != 'business' && unifiedRole != 'driver') {
        throw AuthException('account_role_mismatch:$unifiedRole');
      }
      authoritativeRole = await getAuthoritativePartnerRole();
      if (authoritativeRole != unifiedRole) {
        throw AuthException('account_role_mismatch:$unifiedRole');
      }
    } catch (_) {
      await clearActivePartnerRole();
      if (_client.auth.currentSession != null) {
        await _client.auth.signOut();
      }
      rethrow;
    }

    final preferences = await SharedPreferences.getInstance();
    final pendingSocialRole = preferences.getString('pending_social_role');
    final expectedRole = normalizedRequested ?? pendingSocialRole;

    if (expectedRole != null && expectedRole != authoritativeRole) {
      await preferences.remove('pending_social_role');
      await clearActivePartnerRole();
      await _client.auth.signOut();
      throw AuthException('partner_role_mismatch:$authoritativeRole');
    }

    await preferences.remove('pending_social_role');
    await setActivePartnerRole(authoritativeRole);
    return authoritativeRole;
  }

  Future<AuthResponse> signInForRole({
    required String identifier,
    required String password,
    required String role,
  }) async {
    final response = await signIn(identifier: identifier, password: password);
    await validateCurrentSessionRole(requestedRole: role);
    return response;
  }

  Future<bool> signInWithSocialProvider({
    required OAuthProvider provider,
    required String role,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('pending_social_role', role);
    return _client.auth.signInWithOAuth(provider);
  }


  Future<void> sendPasswordReset(String email) {
    return _client.auth.resetPasswordForEmail(email.trim().toLowerCase());
  }

  Future<Map<String, dynamic>?> getCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final profile = await _client
          .from('partner_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) return profile;
    } on PostgrestException catch (error) {
      // PGRST205 means the database setup SQL has not been executed yet.
      // Fall back to auth metadata so the app can still route correctly.
      if (error.code != 'PGRST205') rethrow;
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return {
      'id': user.id,
      'full_name': metadata['full_name'],
      'phone': metadata['phone'] ?? user.phone,
      'email': user.email,
      'role': metadata['role'] ?? 'business',
      'business_type': metadata['business_type'] ?? 'restaurant',
      'system_category_id': metadata['system_category_id'],
      'status': 'pending',
    };
  }

  Future<Map<String, dynamic>?> getCurrentStore() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final data = await _client.from('stores').select().eq('owner_id', userId).maybeSingle();
    if (data == null) return null;

    final store = Map<String, dynamic>.from(data);
    final storeId = store['id']?.toString();
    if (storeId == null || storeId.isEmpty) return store;

    // Admin Stage 4 stores the actual review decision in admin_store_reviews.
    // Merge that decision into the store map so the partner app always shows
    // the same approval state as the Admin dashboard.
    try {
      final review = await _client
          .from('admin_store_reviews')
          .select('review_status,notes,reviewed_at')
          .eq('store_id', storeId)
          .maybeSingle();
      if (review != null) {
        store['approval_status'] = review['review_status'] ?? store['approval_status'] ?? 'pending';
        store['admin_review_notes'] = review['notes'];
        store['admin_reviewed_at'] = review['reviewed_at'];
      }
    } on PostgrestException {
      // Keep compatibility with projects that have not run the sync policy yet.
    }

    return store;
  }

  Future<Map<String, dynamic>> createStore({
    required String name,
    required String description,
    required String phone,
    required String address,
    required bool deliveryAvailable,
    String? businessType,
    String? systemCategoryId,
    double? latitude,
    double? longitude,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('User is not signed in');
    final data = await _client.from('stores').insert({
      'owner_id': userId,
      'name': name.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
      'phone': _normalizeIraqiPhone(phone),
      'address_text': address.trim(),
      'latitude': ?latitude,
      'longitude': ?longitude,
      'business_type': businessType ?? 'general',
      'system_category_id': systemCategoryId,
      'delivery_available': deliveryAvailable,
      'pickup_available': true,
      'delivery_fee': 0,
      'minimum_order': 0,
      'preparation_minutes': 30,
      'payment_methods': const <String>['cash'],
      'approval_status': 'pending',
      'is_active': false,
      'is_open': false,
    }).select().single();
    return data;
  }

  Future<Map<String, dynamic>> updateStoreOpenStatus(bool isOpen) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('User is not signed in');

    // Stage 76: the database RPC is the single source of truth for whether a
    // store may open. Do not pre-check cached/local approval fields here; they
    // can be stale for a few moments after an Admin decision and previously
    // caused valid stores to be blocked before the request reached Supabase.
    // The RPC validates the authoritative admin review, activation and
    // lifecycle state atomically and returns the database-accepted row.

    // Use one database RPC for opening/closing. The RPC validates
    // the authoritative admin review + activation state and returns the row
    // after the database has actually accepted the change. This avoids silent
    // no-op updates caused by older approval triggers/policies.
    final response = await _client.rpc(
      'set_my_store_open_status',
      params: {'p_is_open': isOpen},
    );

    Map<String, dynamic>? updated;
    if (response is List && response.isNotEmpty && response.first is Map) {
      updated = Map<String, dynamic>.from(response.first as Map);
    } else if (response is Map) {
      updated = Map<String, dynamic>.from(response);
    }
    if (updated == null) {
      throw const AuthException('Store status update returned no data');
    }

    final actualOpen = updated['is_open'] == true;
    if (actualOpen != isOpen) {
      throw const AuthException('Database did not accept the requested store status');
    }

    // Merge the admin review fields back into the UI model.
    final refreshed = await getCurrentStore();
    return refreshed ?? updated;
  }


  Future<String> uploadStoreImage({
    required Uint8List bytes,
    required String extension,
    required String kind,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('User is not signed in');
    if (bytes.isEmpty) throw ArgumentError('Image is empty');
    if (bytes.length > 10 * 1024 * 1024) throw ArgumentError('Image must be under 10MB');

    final safeExtension = extension.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(safeExtension)) {
      throw ArgumentError('Unsupported image type');
    }
    final safeKind = kind == 'cover' ? 'cover' : 'logo';

    // Store identity images are isolated by the authenticated user's UUID.
    // Do not make the Storage INSERT policy depend on a secondary query to
    // public.stores; that cross-table RLS check was the source of the 403 seen
    // on valid signed-in partner sessions. Ownership of logo_url/cover_url is
    // still enforced separately by the stores UPDATE RLS policy.
    final contentType = switch (safeExtension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // The first path segment is always auth.currentUser.id. The bucket RLS
    // policy validates exactly this segment, making uploads owner-only without
    // relying on another table during Storage policy evaluation.
    final path = '$userId/$safeKind/$safeKind-$stamp.$safeExtension';
    await _client.storage.from('store-images').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        cacheControl: '31536000',
        upsert: false,
        contentType: contentType,
      ),
    );
    return _client.storage.from('store-images').getPublicUrl(path);
  }

  Future<String> uploadStoreDocument({
    required Uint8List bytes,
    required String extension,
    required String kind,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('User is not signed in');
    if (bytes.isEmpty) throw ArgumentError('Document is empty');
    if (bytes.length > 8 * 1024 * 1024) throw ArgumentError('Document must be under 8MB');
    final safeExtension = extension.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (!const {'pdf', 'jpg', 'jpeg', 'png', 'webp'}.contains(safeExtension)) {
      throw ArgumentError('Unsupported document type');
    }
    final safeKind = kind == 'identity-document' ? 'identity-document' : 'commercial-registration';
    final contentType = switch (safeExtension) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // Keep verification documents private and isolate every partner inside
    // their authenticated-user folder. This mirrors the working store-images
    // strategy and avoids cross-table RLS checks during Storage INSERT.
    final path = '$userId/$safeKind/$safeKind-$stamp.$safeExtension';
    await _client.storage.from('store-documents').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        cacheControl: '3600',
        upsert: false,
        contentType: contentType,
      ),
    );
    return path;
  }

  Future<String> createStoreDocumentSignedUrl(String path) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('User is not signed in');
    if (!path.startsWith('$userId/')) {
      throw const AuthException('Document does not belong to this account');
    }
    return _client.storage.from('store-documents').createSignedUrl(path, 900);
  }

  Future<Map<String, dynamic>> updateStoreProfile({
    required String name,
    required String description,
    required String phone,
    required String email,
    required String address,
    required String logoUrl,
    required String coverUrl,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('User is not signed in');
    final values = <String, dynamic>{
      'name': name.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
      'phone': _normalizeIraqiPhone(phone),
      'email': email.trim().isEmpty ? null : email.trim().toLowerCase(),
      'address_text': address.trim(),
      'logo_url': logoUrl.trim().isEmpty ? null : logoUrl.trim(),
      'cover_url': coverUrl.trim().isEmpty ? null : coverUrl.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    return _client.from('stores').update(values).eq('owner_id', userId).select().single();
  }

  Future<Map<String, dynamic>> updateStoreImages({String? logoUrl, String? coverUrl}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('User is not signed in');
    final values = <String, dynamic>{'updated_at': DateTime.now().toUtc().toIso8601String()};
    if (logoUrl != null) values['logo_url'] = logoUrl.trim().isEmpty ? null : logoUrl.trim();
    if (coverUrl != null) values['cover_url'] = coverUrl.trim().isEmpty ? null : coverUrl.trim();
    return _client.from('stores').update(values).eq('owner_id', userId).select().single();
  }

  Future<Map<String, dynamic>> updateStoreSettings({
    required String name,
    required String description,
    required String phone,
    required String email,
    required String address,
    required String logoUrl,
    required String coverUrl,
    required bool deliveryAvailable,
    required double deliveryFee,
    required double minimumOrder,
    required int preparationMinutes,
    required String openingTime,
    required String closingTime,
    required bool isOpen,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('User is not signed in');
    final values = <String, dynamic>{
      'name': name.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
      'phone': _normalizeIraqiPhone(phone),
      'email': email.trim().isEmpty ? null : email.trim().toLowerCase(),
      'address_text': address.trim(),
      'logo_url': logoUrl.trim().isEmpty ? null : logoUrl.trim(),
      'cover_url': coverUrl.trim().isEmpty ? null : coverUrl.trim(),
      'delivery_available': deliveryAvailable,
      'delivery_fee': deliveryFee,
      'minimum_order': minimumOrder,
      'preparation_minutes': preparationMinutes,
      'opening_time': openingTime.trim(),
      'closing_time': closingTime.trim(),
      'is_open': isOpen,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    return _client.from('stores').update(values).eq('owner_id', userId).select().single();
  }

  Future<Map<String, dynamic>?> getStoreOrderById(String orderId) async {
    final store = await getCurrentStore();
    final storeId = store?['id'] as String?;
    if (storeId == null) return null;
    final data = await _client
        .from('orders')
        .select('*, order_items(*)')
        .eq('id', orderId)
        .eq('store_id', storeId)
        .maybeSingle();
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> getStoreOrders() async {
    final store = await getCurrentStore();
    final storeId = store?['id'] as String?;
    if (storeId == null) return const [];
    final data = await _client
        .from('orders')
        .select('*, order_items(*)')
        .eq('store_id', storeId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    final result = await _client.rpc(
      'update_my_store_order_status',
      params: {
        'p_order_id': orderId,
        'p_new_status': status,
      },
    );

    if (result is List && result.isNotEmpty) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw const AuthException('Order update failed');
  }


  Future<List<Map<String, dynamic>>> getStoreNotifications({int limit = 100}) async {
    final store = await getCurrentStore();
    final storeId = store?['id'] as String?;
    if (storeId == null) return const [];
    final data = await _client
        .from('store_notifications')
        .select()
        .eq('store_id', storeId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<int> getUnreadNotificationCount() async {
    try {
      final result = await _client.rpc('get_my_store_unread_notification_count');
      return (result as num?)?.toInt() ?? 0;
    } on PostgrestException {
      // Fallback keeps the bell badge working if the RPC has not been refreshed yet.
      final store = await getCurrentStore();
      final storeId = store?['id'] as String?;
      if (storeId == null) return 0;
      final rows = await _client
          .from('store_notifications')
          .select('id')
          .eq('store_id', storeId)
          .eq('is_read', false);
      return (rows as List).length;
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    final store = await getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) return;
    await _client.from('store_notifications').update({
      'is_read': true,
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', notificationId).eq('store_id', storeId);
  }

  Future<void> markNotificationUnread(String notificationId) async {
    final store = await getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) return;
    await _client.from('store_notifications').update({
      'is_read': false,
      'read_at': null,
    }).eq('id', notificationId).eq('store_id', storeId);
  }

  Future<void> markAllNotificationsRead() async {
    await _client.rpc('mark_all_my_store_notifications_read');
  }

  Future<void> deleteStoreNotification(String notificationId) async {
    final store = await getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) return;
    await _client
        .from('store_notifications')
        .delete()
        .eq('id', notificationId)
        .eq('store_id', storeId);
  }

  Future<void> deleteAllStoreNotifications() async {
    final store = await getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) return;
    await _client.from('store_notifications').delete().eq('store_id', storeId);
  }


  Future<bool> isDriverBasicProfileComplete() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final row = await _client
          .from('driver_basic_profiles')
          .select('driver_id, vehicle_type')
          .eq('driver_id', userId)
          .maybeSingle();
      return row != null && (row['vehicle_type']?.toString().trim().isNotEmpty ?? false);
    } on PostgrestException {
      return false;
    }
  }

  Future<void> saveDriverBasicProfile({
    required String vehicleType,
    String plateNumber = '',
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('No signed-in user');
    await _client.from('driver_basic_profiles').upsert({
      'driver_id': userId,
      'vehicle_type': vehicleType.trim(),
      'plate_number': plateNumber.trim().isEmpty ? null : plateNumber.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'driver_id');

    // Keep the legacy local vehicle reader compatible with the simplified setup.
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('driver_vehicle_type_$userId', vehicleType.trim());
    await preferences.setString('driver_vehicle_plate_number_$userId', plateNumber.trim());
    await preferences.setBool('driver_vehicle_info_complete_$userId', true);
  }

  Future<Map<String, dynamic>> getDriverAccessState() async {
    final result = await _client.rpc('driver_access_state');
    if (result is Map) return Map<String, dynamic>.from(result);
    return <String, dynamic>{
      'approval_required': false,
      'review_status': 'approved',
      'allowed': true,
    };
  }

  Future<bool> isDriverEmailOtpVerified() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool('driver_email_otp_verified_$userId') ?? false;
  }

  Future<void> markDriverEmailOtpVerified() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('driver_email_otp_verified_$userId', true);
  }

  String getCurrentDriverEmail() {
    final email = _client.auth.currentUser?.email?.trim() ?? '';
    if (email.isEmpty) throw const AuthException('No email is linked to this account');
    return email;
  }

  Future<void> requestDriverEmailVerification() async {
    final email = getCurrentDriverEmail();
    await _client.auth.signInWithOtp(
      email: email,
      shouldCreateUser: false,
    );
  }

  Future<void> resendDriverEmailVerification() async {
    await requestDriverEmailVerification();
  }

  Future<AuthResponse> verifyDriverEmailOtp({
    required String token,
  }) async {
    final email = getCurrentDriverEmail();
    final response = await _client.auth.verifyOTP(
      type: OtpType.email,
      token: token.trim(),
      email: email,
    );
    await markDriverEmailOtpVerified();
    return response;
  }

  Future<Map<String, dynamic>?> getDriverPersonalInfo() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final preferences = await SharedPreferences.getInstance();
    final fullName = preferences.getString('driver_personal_full_name_$userId');
    if (fullName == null) return null;
    return <String, dynamic>{
      'full_name': fullName,
      'phone': preferences.getString('driver_personal_phone_$userId') ?? '',
      'birth_date': preferences.getString('driver_personal_birth_date_$userId') ?? '',
      'address': preferences.getString('driver_personal_address_$userId') ?? '',
      'gender': preferences.getString('driver_personal_gender_$userId') ?? 'male',
    };
  }

  Future<void> saveDriverPersonalInfo({
    required String fullName,
    required String phone,
    required String birthDate,
    required String address,
    required String gender,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('No signed-in user');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('driver_personal_full_name_$userId', fullName.trim());
    await preferences.setString('driver_personal_phone_$userId', _normalizeIraqiPhone(phone));
    await preferences.setString('driver_personal_birth_date_$userId', birthDate.trim());
    await preferences.setString('driver_personal_address_$userId', address.trim());
    await preferences.setString('driver_personal_gender_$userId', gender == 'female' ? 'female' : 'male');
    await preferences.setBool('driver_personal_info_complete_$userId', true);
  }

  Future<void> purgeLegacyDriverOnboardingState() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    final preferences = await SharedPreferences.getInstance();
    final obsoleteKeys = <String>[
      'driver_documents_complete_$userId',
      'driver_document_identity_$userId',
      'driver_document_license_$userId',
      'driver_document_vehicle_$userId',
      'driver_document_insurance_$userId',
      'driver_review_submitted_$userId',
      'driver_vehicle_make_model_$userId',
      'driver_vehicle_color_$userId',
      'driver_vehicle_plate_city_$userId',
      'driver_vehicle_plate_country_$userId',
      'driver_vehicle_chassis_number_$userId',
      'driver_vehicle_rear_image_$userId',
    ];
    for (final key in obsoleteKeys) {
      await preferences.remove(key);
    }
  }

  Future<Map<String, String>?> getDriverVehicleInfo() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final preferences = await SharedPreferences.getInstance();
    final type = preferences.getString('driver_vehicle_type_$userId');
    if (type == null || type.isEmpty) return null;
    return <String, String>{
      'type': type,
      'plate_number': preferences.getString('driver_vehicle_plate_number_$userId') ?? '',
    };
  }


  Future<bool> isDriverOnline() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool('driver_online_$userId') ?? false;
  }

  Future<void> setDriverOnline(bool value) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('No signed-in user');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('driver_online_$userId', value);
  }


  Future<bool> areDriverNotificationsEnabled() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return true;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool('driver_notifications_enabled_$userId') ?? true;
  }

  Future<void> setDriverNotificationsEnabled(bool value) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('No signed-in user');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('driver_notifications_enabled_$userId', value);
  }

  Future<void> signOut() => fullSignOut();

  String _normalizeIraqiPhone(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('00964')) return '+${cleaned.substring(2)}';
    if (cleaned.startsWith('964')) return '+$cleaned';
    if (cleaned.startsWith('07')) return '+964${cleaned.substring(1)}';
    return cleaned;
  }
}
