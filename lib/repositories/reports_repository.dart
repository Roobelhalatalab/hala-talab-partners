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

  /// Counts each order once in the merchant's selected calendar year.
  /// The half-open local-month range is converted to UTC for created_at queries.
  /// Pages avoid silently truncating stores with more than 1000 orders.
  Future<List<Map<String, dynamic>>> loadMonthlyOrderCounts({required int year}) async {
    final store = await AuthService.instance.getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) {
      throw StateError('STORE_NOT_FOUND');
    }
    final from = DateTime(year, 1, 1).toUtc().toIso8601String();
    final until = DateTime(year + 1, 1, 1).toUtc().toIso8601String();
    const pageSize = 500;
    final months = List.generate(12, (index) => <String, dynamic>{
      'month': index + 1,
      'total': 0,
      'completed': 0,
      'cancelled': 0,
      'incomplete': 0,
    });
    for (var offset = 0; ; offset += pageSize) {
      final page = List<Map<String, dynamic>>.from(await _client
          .from('orders')
          .select('id,status,created_at')
          .eq('store_id', storeId)
          .gte('created_at', from)
          .lt('created_at', until)
          .order('created_at', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + pageSize - 1));
      for (final order in page) {
        final created = DateTime.tryParse(order['created_at']?.toString() ?? '')?.toLocal();
        if (created == null || created.year != year) continue;
        final month = months[created.month - 1];
        month['total'] = (month['total'] as int) + 1;
        final status = order['status']?.toString().trim().toLowerCase() ?? '';
        final group = status == 'delivered' || status == 'completed'
            ? 'completed'
            : const {'cancelled', 'canceled', 'rejected'}.contains(status)
                ? 'cancelled'
                : 'incomplete';
        month[group] = (month[group] as int) + 1;
      }
      if (page.length < pageSize) break;
    }
    return months;
  }

  Future<Map<String, dynamic>> loadSalesOverview() async {
    final result = await _client.rpc('get_store_sales_overview');
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    return const <String, dynamic>{};
  }

}
