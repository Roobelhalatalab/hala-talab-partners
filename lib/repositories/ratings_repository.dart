import 'package:supabase_flutter/supabase_flutter.dart';

class RatingsSnapshot {
  const RatingsSnapshot({
    required this.storeReviews,
    required this.productReviews,
  });

  final List<Map<String, dynamic>> storeReviews;
  final List<Map<String, dynamic>> productReviews;
}

class RatingsRepository {
  RatingsRepository._();
  static final RatingsRepository instance = RatingsRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<String> _requireOwnedStoreId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Not authenticated');
    final row = await _client
        .from('stores')
        .select('id')
        .eq('owner_id', userId)
        .maybeSingle();
    final storeId = row?['id']?.toString();
    if (storeId == null || storeId.isEmpty) {
      throw const AuthException('Store is not configured');
    }
    return storeId;
  }

  Future<RatingsSnapshot> load() async {
    final storeId = await _requireOwnedStoreId();

    final storeRowsFuture = _client
        .from('store_reviews')
        .select('id, store_id, customer_id, customer_name, rating, comment, order_id, created_at')
        .eq('store_id', storeId)
        .order('created_at', ascending: false);

    final productRowsFuture = _client
        .from('product_reviews')
        .select('id, store_id, product_id, customer_id, customer_name, rating, comment, order_id, created_at')
        .eq('store_id', storeId)
        .order('created_at', ascending: false);

    final storeRows = List<Map<String, dynamic>>.from(await storeRowsFuture);
    final productRows = List<Map<String, dynamic>>.from(await productRowsFuture);

    final productIds = productRows
        .map((e) => e['product_id']?.toString())
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final productsById = <String, Map<String, dynamic>>{};
    if (productIds.isNotEmpty) {
      final products = await _client
          .from('products')
          .select('id, name, image_url')
          .eq('store_id', storeId)
          .inFilter('id', productIds);
      for (final product in products) {
        productsById[product['id'].toString()] = Map<String, dynamic>.from(product);
      }
    }

    final enrichedProductRows = productRows.map((review) {
      final productId = review['product_id']?.toString();
      final product = productId == null ? null : productsById[productId];
      return <String, dynamic>{
        ...review,
        'product_name': product?['name'],
        'product_image_url': product?['image_url'],
      };
    }).toList();

    return RatingsSnapshot(
      storeReviews: storeRows,
      productReviews: enrichedProductRows,
    );
  }
}
