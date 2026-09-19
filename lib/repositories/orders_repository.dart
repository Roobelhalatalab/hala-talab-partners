import '../services/auth_service.dart';

/// Data access boundary for store orders.
///
/// Stage 49 keeps the existing Supabase behavior intact while moving order
/// queries away from dashboard widgets so the feature can evolve independently.
class OrdersRepository {
  OrdersRepository._();

  static final OrdersRepository instance = OrdersRepository._();

  Future<List<Map<String, dynamic>>> getOrders() {
    return AuthService.instance.getStoreOrders();
  }

  Future<Map<String, dynamic>?> getOrderById(String orderId) {
    return AuthService.instance.getStoreOrderById(orderId);
  }

  Future<Map<String, dynamic>> updateStatus({
    required String orderId,
    required String status,
  }) {
    return AuthService.instance.updateOrderStatus(
      orderId: orderId,
      status: status,
    );
  }
}
