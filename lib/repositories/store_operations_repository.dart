import 'package:supabase_flutter/supabase_flutter.dart';

class StoreOperationsRepository {
  StoreOperationsRepository._();
  static final StoreOperationsRepository instance = StoreOperationsRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>?> getCurrentStore() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final data = await _client.from('stores').select().eq('owner_id', userId).maybeSingle();
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> saveOperations({
    required String address,
    required double? latitude,
    required double? longitude,
    required String locationNote,
    required bool deliveryAvailable,
    required bool pickupAvailable,
    required double deliveryFee,
    required double minimumOrder,
    required int preparationMinutes,
    required List<String> deliveryZones,
    required Map<String, dynamic> workingHours,
    required bool isOpen,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const AuthException('User is not signed in');
    }

    final response = await _client.rpc(
      'update_my_store_operations',
      params: {
        'p_address_text': address.trim(),
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_location_note': locationNote.trim().isEmpty ? null : locationNote.trim(),
        'p_delivery_available': deliveryAvailable,
        'p_pickup_available': pickupAvailable,
        'p_delivery_fee': deliveryFee,
        'p_minimum_order': minimumOrder,
        'p_preparation_minutes': preparationMinutes,
        'p_delivery_zones': deliveryZones,
        'p_working_hours': workingHours,
        'p_is_open': isOpen,
      },
    );

    if (response is List && response.isNotEmpty) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    if (response is Map) return Map<String, dynamic>.from(response);
    throw PostgrestException(message: 'Store operation settings were not returned');
  }

  // Preserve the existing store ID; resolve from the session only when missing.
  Future<String> _coverageStoreId(String? storeId) async {
    if (_client.auth.currentUser == null) throw const AuthException('User is not signed in');
    if (storeId != null && storeId.isNotEmpty) return storeId;
    final store = await getCurrentStore();
    final resolved = store?['id']?.toString();
    if (resolved == null || resolved.isEmpty) throw StateError('Store ID unavailable');
    return resolved;
  }

  // Zone coverage is additive: it does not replace the legacy operations RPC.
  Future<List<Map<String, dynamic>>> getDeliveryCoverage({required String? storeId}) async {
    final resolvedStoreId = await _coverageStoreId(storeId);
    final response = await _client.rpc('hala_get_my_delivery_coverage_v1', params: {'p_store_id': resolvedStoreId});
    return List<Map<String, dynamic>>.from(
      (response as List).map((row) => Map<String, dynamic>.from(row as Map)),
    );
  }

  Future<void> saveDeliveryCoverage({
    required String? storeId,
    required String areaId,
    required bool enabled,
    required double deliveryFee,
  }) async {
    final resolvedStoreId = await _coverageStoreId(storeId);
    if (deliveryFee < 0 || deliveryFee > 100000000 || !deliveryFee.isFinite || deliveryFee != deliveryFee.roundToDouble()) {
      throw ArgumentError.value(deliveryFee, 'deliveryFee');
    }
    if (_client.auth.currentUser == null) throw const AuthException('User is not signed in');
    try {
      await _client.rpc('hala_save_my_delivery_coverage_v1', params: {
        'p_store_id': resolvedStoreId,
        'p_area_id': areaId,
        'p_enabled': enabled,
        'p_delivery_fee': deliveryFee,
      });
    } on PostgrestException catch (error) {
      if (!error.message.contains('STORE_ACCESS_DENIED')) rethrow;
      // Read-only diagnostic; never bypass server ownership/approval checks.
      final store = await _client.from('stores')
          .select('id,owner_id,is_active,approval_status,zone_id')
          .eq('id', resolvedStoreId)
          .maybeSingle();
      final currentUserId = _client.auth.currentUser?.id;
      String reason;
      if (store == null) {
        reason = 'المتجر غير متاح لهذا الحساب أو غير موجود.';
      } else if (store['owner_id']?.toString() != currentUserId) {
        reason = 'الحساب الحالي ليس مالك هذا المتجر.';
      } else if (store['zone_id'] == null) {
        reason = 'لم يتم تحديد المنطقة الأصلية للمتجر في الإدارة.';
      } else if (store['is_active'] != true) {
        reason = 'المتجر غير مفعّل.';
      } else if (store['approval_status'] != 'approved') {
        reason = 'المتجر لم يحصل على الموافقة بعد.';
      } else {
        reason = 'رفض الخادم الحفظ رغم ظهور الشروط صحيحة؛ يلزم فحص جلسة الدخول.';
      }
      throw StateError(reason);
    }
  }

  Future<Map<String, dynamic>> saveMerchantDeliveryPreferences({
    required bool selfDelivery,
    required bool alwaysOpen,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('User is not signed in');
    final store = await getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) throw const AuthException('Store is not configured');
    return _client
        .from('stores')
        .update({'self_delivery': selfDelivery, 'always_open': alwaysOpen})
        .eq('id', storeId)
        .eq('owner_id', userId)
        .select()
        .single();
  }

  // Note 24: menu mode is independent from working hours and shift count.
  Future<void> saveMenuMode(String menuMode) async {
    if (menuMode != 'unified' && menuMode != 'different') {
      throw ArgumentError.value(menuMode, 'menuMode');
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('User is not signed in');
    final store = await getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) throw const AuthException('Store is not configured');
    final updated = await _client.from('stores')
        .update({'menu_mode': menuMode})
        .eq('id', storeId)
        .eq('owner_id', userId)
        .select('id, menu_mode');
    if (updated.isEmpty || updated.first['menu_mode'] != menuMode) {
      throw StateError('Menu mode was not saved. Check store update permissions.');
    }
  }

  Future<List<Map<String, dynamic>>> getStoreShifts() async {
    final store = await getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) return const <Map<String, dynamic>>[];
    final data = await _client
        .from('store_shifts')
        .select()
        .eq('store_id', storeId)
        .order('sort_order')
        .order('start_time');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> saveShiftConfiguration({
    required int shiftMode,
    required String morningStart,
    required String morningEnd,
    required String eveningStart,
    required String eveningEnd,
    required Map<String, dynamic> morningWeeklyHours,
    required Map<String, dynamic> eveningWeeklyHours,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('User is not signed in');
    final store = await getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) throw const AuthException('Store is not configured');

    await _client.from('stores').update({'shift_mode': shiftMode}).eq('id', storeId).eq('owner_id', userId);

    if (shiftMode == 2) {
      await _client.from('store_shifts').upsert([
        {
          'store_id': storeId,
          'shift_code': 'morning',
          'display_name': 'الصباحي',
          'start_time': morningStart,
          'end_time': morningEnd,
          'is_active': true,
          'sort_order': 1,
          'weekly_hours': morningWeeklyHours,
        },
        {
          'store_id': storeId,
          'shift_code': 'evening',
          'display_name': 'المسائي',
          'start_time': eveningStart,
          'end_time': eveningEnd,
          'is_active': true,
          'sort_order': 2,
          'weekly_hours': eveningWeeklyHours,
        },
      ], onConflict: 'store_id,shift_code');
    }
  }

}
