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
