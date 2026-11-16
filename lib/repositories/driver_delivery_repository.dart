
import 'package:supabase_flutter/supabase_flutter.dart';

/// Driver delivery-offer data access for Stage 07.
///
/// The SQL functions are SECURITY DEFINER and return only the minimum fields
/// required by the driver offer card. No demo order data is used.
class DriverDeliveryRepository {
  DriverDeliveryRepository._();

  static final DriverDeliveryRepository instance = DriverDeliveryRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<bool> isHalaDriver() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;
    final row = await _client.from('driver_delivery_scope')
        .select('driver_type').eq('driver_id', uid).maybeSingle();
    return row?['driver_type'] == 'hala';
  }

  // Hala Talab directed dispatch (separate from legacy delivery offers).
  // Requires the Stage 12 RPCs to be safely deployed before these are called.
  Future<List<String>> getEligibleHalaDrivers(String orderId) async {
    final result = await _client.rpc(
      'hala_store_eligible_directed_drivers_v1',
      params: {'p_order_id': orderId},
    );
    if (result is! List) return const <String>[];
    return result.whereType<Map>().map((row) => row['driver_id']?.toString())
        .whereType<String>().toList();
  }

  Future<List<Map<String, dynamic>>> getNamedEligibleHalaDrivers(String orderId) async {
    final result = await _client.rpc('hala_store_eligible_directed_drivers_named_v1',
        params: {'p_order_id': orderId});
    if (result is! List) return const [];
    return result.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>?> getHalaDirectedOfferStatus(String orderId) async {
    final result = await _client.rpc('hala_store_directed_offer_status_v1',
        params: {'p_order_id': orderId});
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    return null;
  }

  Future<String> sendHalaDirectedOffer({
    required String orderId,
    required String driverId,
  }) async {
    final result = await _client.rpc(
      'hala_store_send_directed_offer_v1',
      params: {'p_order_id': orderId, 'p_driver_id': driverId},
    );
    if (result == null) throw const AuthException('Directed offer was not created');
    return result.toString();
  }

  Future<int> broadcastHalaDirectedOffer(String orderId) async {
    final result = await _client.rpc('hala_store_broadcast_directed_offer_v1',
        params: {'p_order_id': orderId});
    return (result as num).toInt();
  }

  Future<List<Map<String, dynamic>>> getMyHalaDirectedOffers() async {
    final result = await _client.rpc('hala_driver_directed_offer_details_v1');
    if (result is! List) return const <Map<String, dynamic>>[];
    return result.whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<String> decideHalaDirectedOffer({
    required String offerId,
    required bool accept,
  }) async {
    final result = await _client.rpc(
      'hala_driver_decide_directed_offer_v1',
      params: {'p_offer_id': offerId, 'p_accept': accept},
    );
    if (result == null) throw const AuthException('Directed offer decision failed');
    return result.toString();
  }

  Future<Map<String, dynamic>?> getNextAvailableOffer() async {
    final result = await _client.rpc('get_available_driver_delivery_offer');
    if (result is List && result.isNotEmpty) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return null;
  }

  Future<Map<String, dynamic>> claimOffer(String orderId) async {
    final result = await _client.rpc(
      'claim_driver_delivery_offer',
      params: {'p_order_id': orderId},
    );
    if (result is List && result.isNotEmpty) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw const AuthException('Delivery offer is no longer available');
  }


  Future<Map<String, dynamic>?> getCurrentAssignedOrder() async {
    final result = await _client.rpc('get_current_driver_assigned_order');
    if (result == null) return null;
    if (result is Map) return Map<String, dynamic>.from(result);
    return null;
  }

  Future<List<Map<String, dynamic>>> getActiveAssignedOrders() async {
    final result = await _client.rpc('get_driver_active_orders');
    if (result is List) {
      return result
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> confirmPickup(String orderId) async {
    final result = await _client.rpc(
      'driver_confirm_order_pickup',
      params: {'p_order_id': orderId},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw const AuthException('Unable to confirm order pickup');
  }

  Future<Map<String, dynamic>> notifyCustomerArrival(String orderId) async {
    final result = await _client.rpc(
      'driver_notify_customer_arrival',
      params: {'p_order_id': orderId},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw const AuthException('Unable to notify customer arrival');
  }

  Future<Map<String, dynamic>> confirmDelivery({required String orderId}) async {
    final result = await _client.rpc(
      'driver_complete_order_one_tap',
      params: {'p_order_id': orderId},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw const AuthException('Unable to confirm delivery');
  }

  Future<Map<String, dynamic>> getDeliveryHistory() async {
    final result = await _client.rpc('get_driver_delivery_history');
    if (result is Map) return Map<String, dynamic>.from(result);
    throw const AuthException('Unable to load driver delivery history');
  }

  Future<Map<String, dynamic>> getEarningsWallet() async {
    final result = await _client.rpc('get_driver_dues_summary');
    if (result is Map) return Map<String, dynamic>.from(result);
    throw const AuthException('Unable to load driver dues');
  }

  Future<void> rejectOffer(String orderId) async {
    await _client.rpc(
      'reject_driver_delivery_offer',
      params: {'p_order_id': orderId},
    );
  }
  Future<List<Map<String, dynamic>>> getDriverNotifications({int limit = 100}) async {
    final data = await _client
        .from('driver_notifications')
        .select()
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<int> getUnreadDriverNotificationCount() async {
    final data = await _client
        .from('driver_notifications')
        .select('id')
        .eq('is_read', false);
    return (data as List).length;
  }

  Future<void> setDriverNotificationRead(String id, bool isRead) async {
    await _client.from('driver_notifications').update({
      'is_read': isRead,
      'read_at': isRead ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('id', id);
  }

  Future<void> markAllDriverNotificationsRead() async {
    await _client.rpc('mark_all_my_driver_notifications_read');
  }

  Future<void> deleteDriverNotification(String id) async {
    await _client.from('driver_notifications').delete().eq('id', id);
  }

  Future<void> deleteAllDriverNotifications() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Authentication required');
    await _client.from('driver_notifications').delete().eq('driver_id', userId);
  }

  Future<List<Map<String, dynamic>>> getDriverRatings({int limit = 100}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Authentication required');
    final data = await _client
        .from('driver_reviews')
        .select('id, driver_id, customer_id, rating, comment, order_id, created_at')
        .eq('driver_id', userId)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data);
  }

}
