import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

/// Data access for store promotions and coupons.
///
/// Stage 51 keeps the existing table names and payloads unchanged while moving
/// offer/coupon queries out of authentication and dashboard UI code.
class OffersRepository {
  OffersRepository._();

  static final OffersRepository instance = OffersRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<String?> _storeId() async => (await AuthService.instance.getCurrentStore())?['id']?.toString();

  Future<String> _requireStoreId() async {
    final storeId = await _storeId();
    if (storeId == null || storeId.isEmpty) {
      throw const AuthException('Store is not configured');
    }
    return storeId;
  }

  void _validateDiscount(String type, double value) {
    if (!const {'percentage', 'fixed'}.contains(type)) {
      throw const FormatException('Invalid discount type');
    }
    if (value <= 0 || (type == 'percentage' && value > 100)) {
      throw const FormatException('Invalid discount value');
    }
  }

  Future<List<Map<String, dynamic>>> getPromotions() async {
    final storeId = await _storeId();
    if (storeId == null || storeId.isEmpty) return const [];
    final data = await _client
        .from('store_promotions')
        .select()
        .eq('store_id', storeId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data)
        .where((row) => (row['source']?.toString().toLowerCase() ?? 'store') != 'admin')
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> savePromotion({
    String? promotionId,
    required String title,
    required String description,
    required String discountType,
    required double discountValue,
    required double minimumOrder,
    int? perCustomerLimit,
    required DateTime startAt,
    required DateTime endAt,
    required bool isActive,
  }) async {
    final storeId = await _storeId();
    if (storeId == null || storeId.isEmpty) {
      throw const AuthException('Store is not configured');
    }
    _validateDiscount(discountType, discountValue);
    if (title.trim().isEmpty || minimumOrder < 0 ||
        (perCustomerLimit != null && perCustomerLimit <= 0) ||
        !endAt.isAfter(startAt)) {
      throw const FormatException('Invalid promotion data');
    }
    final values = <String, dynamic>{
      'store_id': storeId,
      'title': title.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
      'discount_type': discountType,
      'discount_value': discountValue,
      'minimum_order': minimumOrder,
      // Null = the offer can be used again until it expires. A positive value
      // limits how many times one customer can benefit from this offer.
      'per_customer_limit': perCustomerLimit,
      'start_at': startAt.toUtc().toIso8601String(),
      'end_at': endAt.toUtc().toIso8601String(),
      'is_active': isActive,
    };
    if (promotionId == null) {
      return _client.from('store_promotions').insert(values).select().single();
    }
    return _client.from('store_promotions').update(values).eq('id', promotionId).eq('store_id', storeId).select().single();
  }

  Future<Map<String, dynamic>> updatePromotionActive(String id, bool value) async {
    final storeId = await _requireStoreId();
    return _client.from('store_promotions').update({'is_active': value}).eq('id', id).eq('store_id', storeId).select().single();
  }

  Future<void> deletePromotion(String id) async {
    final storeId = await _requireStoreId();
    await _client.from('store_promotions').delete().eq('id', id).eq('store_id', storeId);
  }

  Future<List<Map<String, dynamic>>> getCoupons() async {
    final storeId = await _storeId();
    if (storeId == null || storeId.isEmpty) return const [];
    final data = await _client
        .from('coupons')
        .select()
        .eq('store_id', storeId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data)
        .where((row) => row['platform_campaign_id'] == null)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> saveCoupon({
    String? couponId,
    required String code,
    required String title,
    required String discountType,
    required double discountValue,
    required double minimumOrder,
    double? maxDiscount,
    int? usageLimit,
    required DateTime startAt,
    required DateTime endAt,
    required bool isActive,
  }) async {
    final storeId = await _requireStoreId();
    _validateDiscount(discountType, discountValue);
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.length < 3 || title.trim().isEmpty || minimumOrder < 0 ||
        (maxDiscount != null && maxDiscount <= 0) ||
        (usageLimit != null && usageLimit <= 0) || !endAt.isAfter(startAt)) {
      throw const FormatException('Invalid coupon data');
    }
    final values = <String, dynamic>{
      'store_id': storeId,
      'code': normalizedCode,
      'title': title.trim(),
      'discount_type': discountType,
      'discount_value': discountValue,
      'minimum_order': minimumOrder,
      'max_discount': maxDiscount,
      'usage_limit': usageLimit,
      // Hala Talab final rule: every coupon is single-use per customer.
      // The database trigger from client Stage 107 enforces this as well.
      'per_customer_limit': 1,
      'start_at': startAt.toUtc().toIso8601String(),
      'end_at': endAt.toUtc().toIso8601String(),
      'is_active': isActive,
    };
    if (couponId == null) {
      return _client.from('coupons').insert(values).select().single();
    }
    return _client.from('coupons').update(values).eq('id', couponId).eq('store_id', storeId).select().single();
  }

  Future<Map<String, dynamic>> updateCouponActive(String id, bool value) async {
    final storeId = await _requireStoreId();
    return _client.from('coupons').update({'is_active': value}).eq('id', id).eq('store_id', storeId).select().single();
  }

  Future<void> deleteCoupon(String id) async {
    final storeId = await _requireStoreId();
    await _client.from('coupons').delete().eq('id', id).eq('store_id', storeId);
  }

  Future<Map<String, dynamic>> quoteDiscount({
    required double subtotal,
    String? couponCode,
  }) async {
    final storeId = await _requireStoreId();
    final result = await _client.rpc('quote_store_discount_v5', params: {
      'p_store_id': storeId,
      'p_subtotal': subtotal,
      'p_coupon_code': couponCode?.trim().toUpperCase(),
    });
    return Map<String, dynamic>.from(result as Map);
  }
}
