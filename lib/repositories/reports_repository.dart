import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

class ReportsSnapshot {
  const ReportsSnapshot({
    required this.orders,
    required this.reviews,
    required this.loadedAt,
  });

  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> reviews;
  final DateTime loadedAt;
}

/// Read-only Supabase boundary for merchant reports and analytics.
///
/// Stage 66 deliberately filters the order window at the database level instead
/// of downloading the store's full order history on every refresh.
class ReportsRepository {
  ReportsRepository._();

  static final ReportsRepository instance = ReportsRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<ReportsSnapshot> loadSnapshot({required int days}) async {
    final store = await AuthService.instance.getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) {
      return ReportsSnapshot(
        orders: const [],
        reviews: const [],
        loadedAt: DateTime.now(),
      );
    }

    final safeDays = days.clamp(1, 365);
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: safeDays - 1))
        .toUtc()
        .toIso8601String();

    final ordersFuture = _client
        .from('orders')
        .select(
          'id,status,subtotal,delivery_fee,discount_amount,total,payment_method,created_at,delivered_at,'
          'order_items(product_id,product_name,quantity,unit_price,total_price)',
        )
        .eq('store_id', storeId)
        .gte('created_at', from)
        .order('created_at', ascending: false);

    Future<List<Map<String, dynamic>>> reviewsFuture() async {
      try {
        final rows = await _client
            .from('store_reviews')
            .select('rating, created_at')
            .eq('store_id', storeId)
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(rows);
      } on PostgrestException {
        return const [];
      }
    }

    final orders = List<Map<String, dynamic>>.from(await ordersFuture);
    final reviews = await reviewsFuture();
    return ReportsSnapshot(orders: orders, reviews: reviews, loadedAt: now);
  }


  Future<List<Map<String, dynamic>>> loadMonthOrders(DateTime month) async {
    final store = await AuthService.instance.getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) return const [];

    final startLocal = DateTime(month.year, month.month, 1);
    final endLocal = DateTime(month.year, month.month + 1, 1);
    final rows = await _client
        .from('orders')
        .select('*, order_items(*)')
        .eq('store_id', storeId)
        .gte('created_at', startLocal.toUtc().toIso8601String())
        .lt('created_at', endLocal.toUtc().toIso8601String())
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> loadSalesOverview() async {
    final result = await _client.rpc('get_store_sales_overview');
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    return const <String, dynamic>{};
  }

}
