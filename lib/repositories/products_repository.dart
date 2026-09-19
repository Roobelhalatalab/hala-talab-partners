import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class ProductsRepository {
  ProductsRepository._();
  static final ProductsRepository instance = ProductsRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  // Stage 196: resolving the current store used to hit the `stores` table on
  // every product/category action. Keep the resolved id in memory for the
  // active auth user so save/delete/toggle operations start immediately.
  String? _cachedStoreOwnerId;
  String? _cachedStoreId;
  Future<String?>? _storeIdLookup;

  static const _allowedRecordTables = <String>{
    'product_categories',
    'product_addons',
    'store_reviews',
  };
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  Future<String?> _currentStoreId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      _cachedStoreOwnerId = null;
      _cachedStoreId = null;
      _storeIdLookup = null;
      return null;
    }
    if (_cachedStoreOwnerId == userId && (_cachedStoreId ?? '').isNotEmpty) {
      return _cachedStoreId;
    }
    if (_cachedStoreOwnerId != userId) {
      _cachedStoreOwnerId = userId;
      _cachedStoreId = null;
      _storeIdLookup = null;
    }
    final pending = _storeIdLookup;
    if (pending != null) return pending;

    final lookup = () async {
      final store = await _client
          .from('stores')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();
      final resolved = store?['id']?.toString();
      if (_client.auth.currentUser?.id == userId) {
        _cachedStoreOwnerId = userId;
        _cachedStoreId = resolved;
      }
      return resolved;
    }();
    _storeIdLookup = lookup;
    try {
      return await lookup;
    } finally {
      if (identical(_storeIdLookup, lookup)) _storeIdLookup = null;
    }
  }

  Future<String> _requireStoreId() async {
    final storeId = await _currentStoreId();
    if (storeId == null) {
      throw const AuthException('Store is not configured');
    }
    return storeId;
  }

  Future<List<Map<String, dynamic>>> getStoreProducts() async {
    final storeId = await _requireStoreId();
    final data = await _client
        .from('products')
        .select()
        .eq('store_id', storeId)
        .order('sort_order')
        .order('created_at');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>?> getShiftModeAndShifts() async {
    final storeId = await _requireStoreId();
    final store = await _client.from('stores').select('shift_mode').eq('id', storeId).maybeSingle();
    final shifts = await _client.from('store_shifts').select().eq('store_id', storeId).eq('is_active', true).order('sort_order');
    return {
      'shift_mode': (store?['shift_mode'] as num?)?.toInt() ?? 1,
      'shifts': List<Map<String, dynamic>>.from(shifts),
    };
  }

  Future<Set<String>> getCategoryShiftIds(String categoryId) async {
    final rows = await _client.from('store_category_shifts').select('shift_id').eq('category_id', categoryId);
    return rows.map<String>((e) => e['shift_id'].toString()).toSet();
  }

  Future<Set<String>> getProductShiftIds(String productId) async {
    final rows = await _client.from('store_product_shifts').select('shift_id').eq('product_id', productId);
    return rows.map<String>((e) => e['shift_id'].toString()).toSet();
  }

  Future<void> setCategoryShifts({required String categoryId, required Set<String> selectedShiftIds, required Set<String> allShiftIds}) async {
    await _client.from('store_category_shifts').delete().eq('category_id', categoryId);
    if (allShiftIds.isEmpty || selectedShiftIds.length == allShiftIds.length) return;
    if (selectedShiftIds.isEmpty) return;
    await _client.from('store_category_shifts').insert(selectedShiftIds.map((id) => {'category_id': categoryId, 'shift_id': id}).toList());
  }

  Future<void> setProductShifts({required String productId, required Set<String> selectedShiftIds, required Set<String> allShiftIds}) async {
    await _client.from('store_product_shifts').delete().eq('product_id', productId);
    if (allShiftIds.isEmpty || selectedShiftIds.length == allShiftIds.length) return;
    if (selectedShiftIds.isEmpty) return;
    await _client.from('store_product_shifts').insert(selectedShiftIds.map((id) => {'product_id': productId, 'shift_id': id}).toList());
  }

  Future<List<Map<String, dynamic>>> getStoreCategories({bool activeOnly = false}) async {
    final storeId = await _requireStoreId();
    var query = _client.from('product_categories').select().eq('store_id', storeId);
    if (activeOnly) query = query.eq('is_active', true);
    final data = await query.order('sort_order', ascending: true).order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getStoreAddons({bool activeOnly = true}) async {
    final storeId = await _requireStoreId();
    var query = _client.from('product_addons').select().eq('store_id', storeId);
    if (activeOnly) query = query.eq('is_active', true);
    final data = await query.order('created_at');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> saveProduct({
    String? productId,
    required String name,
    required String description,
    required double price,
    String? categoryId,
    required String categoryName,
    required bool isAvailable,
    String? imageUrl,
    String? imagePath,
    int? preparationTimeMinutes,
    int? calories,
    String? notes,
    List<String> tags = const [],
    String productType = 'single',
    String? brand,
    String? barcode,
    String? sku,
    String unit = 'piece',
    bool trackStock = false,
    double? stockQuantity,
    String? sizeLabel,
    double? weightValue,
    String weightUnit = 'g',
    String catalogKind = 'restaurant',
  }) async {
    final storeId = await _requireStoreId();
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Product name is required');
    if (price < 0) throw ArgumentError('Price cannot be negative');
    if (preparationTimeMinutes != null && preparationTimeMinutes < 0) {
      throw ArgumentError('Preparation time cannot be negative');
    }
    if (calories != null && calories < 0) {
      throw ArgumentError('Calories cannot be negative');
    }
    if (weightValue != null && weightValue < 0) {
      throw ArgumentError('Weight cannot be negative');
    }
    if (trackStock && (stockQuantity ?? 0) < 0) {
      throw ArgumentError('Stock cannot be negative');
    }

    final cleanBarcode = (barcode ?? '').trim();
    final cleanSku = (sku ?? '').trim();
    final values = <String, dynamic>{
      'store_id': storeId,
      'name': cleanName,
      'description': description.trim().isEmpty ? null : description.trim(),
      'price': price,
      'category_id': (categoryId ?? '').trim().isEmpty ? null : categoryId!.trim(),
      'category_name': categoryName.trim().isEmpty ? null : categoryName.trim(),
      'is_available': isAvailable,
      'image_url': imageUrl,
      'image_path': imagePath,
      'preparation_time_minutes': preparationTimeMinutes,
      'calories': calories,
      'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      'tags': tags.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList(),
      'product_type': productType,
      'brand': (brand ?? '').trim().isEmpty ? null : brand!.trim(),
      'barcode': cleanBarcode.isEmpty ? null : cleanBarcode,
      'sku': cleanSku.isEmpty ? null : cleanSku,
      'unit': unit,
      'track_stock': trackStock,
      'stock_quantity': trackStock ? (stockQuantity ?? 0) : null,
      'size_label': (sizeLabel ?? '').trim().isEmpty ? null : sizeLabel!.trim(),
      'weight_value': weightValue,
      'weight_unit': weightUnit,
      'catalog_kind': catalogKind,
      // Stage 155: ordering is applied atomically by the reorder RPC after the
      // product record is saved. Keeping this null during create/edit also
      // prevents a category change from colliding with an occupied position.
      'sort_order': null,
    };

    if (productId == null || productId.isEmpty) {
      return _client.from('products').insert(values).select().single();
    }
    return _client
        .from('products')
        .update(values)
        .eq('id', productId)
        .eq('store_id', storeId)
        .select()
        .single();
  }

  Future<Set<String>> getProductAddonIds(String productId) async {
    final storeId = await _requireStoreId();
    final product = await _client
        .from('products')
        .select('id')
        .eq('id', productId)
        .eq('store_id', storeId)
        .maybeSingle();
    if (product == null) return <String>{};
    final data = await _client
        .from('product_addon_links')
        .select('addon_id')
        .eq('product_id', productId);
    return data.map<String>((row) => row['addon_id'].toString()).toSet();
  }

  Future<void> setProductAddons(String productId, List<String> addonIds) async {
    final storeId = await _requireStoreId();
    final product = await _client
        .from('products')
        .select('id')
        .eq('id', productId)
        .eq('store_id', storeId)
        .maybeSingle();
    if (product == null) throw StateError('Product does not belong to the current store');

    final validAddonIds = <String>[];
    if (addonIds.isNotEmpty) {
      final rows = await _client
          .from('product_addons')
          .select('id')
          .eq('store_id', storeId)
          .inFilter('id', addonIds.toSet().toList());
      validAddonIds.addAll(rows.map((e) => e['id'].toString()));
    }

    await _client.from('product_addon_links').delete().eq('product_id', productId);
    if (validAddonIds.isEmpty) return;
    await _client.from('product_addon_links').insert(
      validAddonIds
          .map((addonId) => {'product_id': productId, 'addon_id': addonId})
          .toList(),
    );
  }

  Future<List<Map<String, dynamic>>> getProductVariants(String productId) async {
    final storeId = await _requireStoreId();
    final product = await _client
        .from('products')
        .select('id')
        .eq('id', productId)
        .eq('store_id', storeId)
        .maybeSingle();
    if (product == null) return const <Map<String, dynamic>>[];
    final data = await _client
        .from('product_variants')
        .select()
        .eq('product_id', productId)
        .order('sort_order')
        .order('created_at');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> replaceProductVariants({
    required String productId,
    required List<Map<String, dynamic>> variants,
  }) async {
    final storeId = await _requireStoreId();
    await _client.rpc(
      'store_replace_product_variants_v2',
      params: {
        'p_store_id': storeId,
        'p_product_id': productId,
        'p_variants': variants,
      },
    );
  }

  Future<Map<String, dynamic>> duplicateProduct(Map<String, dynamic> source) async {
    final sourceId = source['id']?.toString();
    if (sourceId == null || sourceId.isEmpty) {
      throw ArgumentError('Source product id is required');
    }
    final originalName = source['name']?.toString().trim() ?? '';
    final duplicateName = originalName.isEmpty ? 'نسخة منتج' : '$originalName - نسخة';
    final created = await saveProduct(
      name: duplicateName,
      description: source['description']?.toString() ?? '',
      price: ((source['price'] as num?) ?? 0).toDouble(),
      categoryId: source['category_id']?.toString(),
      categoryName: source['category_name']?.toString() ?? '',
      isAvailable: source['is_available'] == true,
      imageUrl: source['image_url']?.toString(),
      imagePath: source['image_path']?.toString(),
      preparationTimeMinutes: (source['preparation_time_minutes'] as num?)?.toInt(),
      calories: (source['calories'] as num?)?.toInt(),
      notes: source['notes']?.toString(),
      tags: source['tags'] is List ? (source['tags'] as List).map((e) => e.toString()).toList() : const [],
      productType: source['product_type']?.toString() ?? 'single',
      brand: source['brand']?.toString(),
      // Barcode/SKU are intentionally cleared so a duplicated product never
      // collides with unique inventory identifiers.
      barcode: null,
      sku: null,
      unit: source['unit']?.toString() ?? 'piece',
      trackStock: source['track_stock'] == true,
      stockQuantity: (source['stock_quantity'] as num?)?.toDouble(),
      sizeLabel: source['size_label']?.toString(),
      weightValue: (source['weight_value'] as num?)?.toDouble(),
      weightUnit: source['weight_unit']?.toString() ?? 'g',
      catalogKind: source['catalog_kind']?.toString() ?? 'restaurant',
    );
    final newId = created['id'].toString();
    final addonIds = await getProductAddonIds(sourceId);
    if (addonIds.isNotEmpty) {
      await setProductAddons(newId, addonIds.toList());
    }
    final variants = await getProductVariants(sourceId);
    if (variants.isNotEmpty) {
      await replaceProductVariants(
        productId: newId,
        variants: variants.asMap().entries.map((entry) => {
          'name': entry.value['name']?.toString() ?? '',
          'price': ((entry.value['price'] as num?) ?? 0).toDouble(),
          'sort_order': entry.key + 1,
          'is_available': entry.value['is_available'] != false,
        }).toList(),
      );
    }
    final shiftIds = await getProductShiftIds(sourceId);
    if (shiftIds.isNotEmpty) {
      final meta = await getShiftModeAndShifts();
      final allShiftIds = List<Map<String, dynamic>>.from(meta?['shifts'] as List? ?? const [])
          .map((e) => e['id'].toString()).toSet();
      await setProductShifts(productId: newId, selectedShiftIds: shiftIds, allShiftIds: allShiftIds);
    }
    await setProductPosition(productId: newId, position: 999999);
    return created;
  }

  Future<Map<String, dynamic>> updateProductAvailability({
    required String productId,
    required bool isAvailable,
  }) async {
    final storeId = await _requireStoreId();
    return _client
        .from('products')
        .update({'is_available': isAvailable})
        .eq('id', productId)
        .eq('store_id', storeId)
        .select()
        .single();
  }

  Future<void> setProductPosition({
    required String productId,
    required int position,
  }) async {
    final storeId = await _requireStoreId();
    final params = <String, dynamic>{
      'p_store_id': storeId,
      'p_product_id': productId,
      'p_position': position,
    };

    // Stage 200: v6 is the authoritative category-id-aware ordering RPC. It handles existing
    // NULL/duplicate historical positions without colliding with the unique index.
    // Do not fall back to older RPCs. Retry once only for PostgREST schema reload.
    try {
      await _client.rpc('store_set_product_position_v6', params: params);
      return;
    } on PostgrestException catch (e) {
      if (!_isMissingRpc(e)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await _client.rpc('store_set_product_position_v6', params: params);
    }
  }

  bool _isMissingRpc(PostgrestException e) {
    final text = '${e.code ?? ''} ${e.message} ${e.details ?? ''}'.toLowerCase();
    return text.contains('pgrst202') ||
        text.contains('could not find the function') ||
        text.contains('schema cache');
  }

  Future<Map<String, String>> uploadProductImage({
    required Uint8List bytes,
    required String extension,
    String? oldPath,
  }) async {
    final storeId = await _requireStoreId();
    if (bytes.isEmpty) throw ArgumentError('Image is empty');
    if (bytes.length > 5 * 1024 * 1024) throw ArgumentError('Image must be under 5MB');
    final safeExtension = extension.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(safeExtension)) {
      throw ArgumentError('Unsupported image type');
    }
    final path = '$storeId/${DateTime.now().microsecondsSinceEpoch}.$safeExtension';
    await _client.storage.from('product-images').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(cacheControl: '31536000', upsert: false),
    );
    if (oldPath != null && oldPath.isNotEmpty && oldPath != path && oldPath.startsWith('$storeId/')) {
      try {
        await _client.storage.from('product-images').remove([oldPath]);
      } catch (_) {}
    }
    return {
      'path': path,
      'url': _client.storage.from('product-images').getPublicUrl(path),
    };
  }

  Future<void> removeProductImage(String? path) async {
    if (path == null || path.isEmpty) return;
    final storeId = await _requireStoreId();
    if (!path.startsWith('$storeId/')) return;
    try {
      await _client.storage.from('product-images').remove([path]);
    } catch (_) {}
  }

  Future<void> deleteProduct(String productId) async {
    final storeId = await _requireStoreId();
    final product = await _client
        .from('products')
        .select('id,image_path,category_id,category_name')
        .eq('id', productId)
        .eq('store_id', storeId)
        .maybeSingle();
    if (product == null) return;
    final imagePath = product['image_path']?.toString();
    final categoryId = product['category_id']?.toString();
    final categoryName = product['category_name']?.toString();
    await _client
        .from('products')
        .delete()
        .eq('id', productId)
        .eq('store_id', storeId);
    if (categoryName != null && categoryName.trim().isNotEmpty) {
      await _client.rpc(
        'store_normalize_product_positions_v2',
        params: {
          'p_store_id': storeId,
          'p_category_id': (categoryId ?? '').isEmpty ? null : categoryId,
          'p_category_name': categoryName.trim(),
        },
      );
    }
    await removeProductImage(imagePath);
  }

  Future<Map<String, dynamic>> saveCategory({
    String? id,
    required String name,
    bool isActive = true,
    String? imageUrl,
    String? imagePath,
    String? shiftId,
  }) async {
    final storeId = await _requireStoreId();
    final payload = <String, dynamic>{
      'store_id': storeId,
      'name': name.trim(),
      'is_active': isActive,
      'image_url': imageUrl,
      'image_path': imagePath,
      'shift_id': (shiftId ?? '').isEmpty ? null : shiftId,
    };
    if (id == null || id.isEmpty) {
      final rows = await _client
          .from('product_categories')
          .select('sort_order,shift_id')
          .eq('store_id', storeId);
      final sameScope = rows.where((row) => (row['shift_id']?.toString() ?? '') == (shiftId ?? '')).toList();
      final maxOrder = sameScope.fold<int>(0, (maxValue, row) {
        final value = (row['sort_order'] as num?)?.toInt() ?? 0;
        return value > maxValue ? value : maxValue;
      });
      payload['sort_order'] = maxOrder + 1;
    }
    if (payload['name'] == '') throw ArgumentError('Category name is required');
    if (id == null || id.isEmpty) {
      return _client.from('product_categories').insert(payload).select().single();
    }
    return _client
        .from('product_categories')
        .update(payload)
        .eq('id', id)
        .eq('store_id', storeId)
        .select()
        .single();
  }


  Future<Map<String, String>> uploadCategoryImage({
    required Uint8List bytes,
    String? oldPath,
  }) async {
    final storeId = await _requireStoreId();
    if (bytes.isEmpty) throw ArgumentError('Image is empty');
    if (bytes.length > 5 * 1024 * 1024) throw ArgumentError('Image must be under 5MB');
    final path = '$storeId/categories/${DateTime.now().microsecondsSinceEpoch}.png';
    await _client.storage.from('product-images').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(cacheControl: '31536000', upsert: false, contentType: 'image/png'),
    );
    if (oldPath != null && oldPath.isNotEmpty && oldPath != path && oldPath.startsWith('$storeId/')) {
      try { await _client.storage.from('product-images').remove([oldPath]); } catch (_) {}
    }
    return {
      'path': path,
      'url': _client.storage.from('product-images').getPublicUrl(path),
    };
  }

  Future<void> moveCategory({required String categoryId, required int direction}) async {
    if (direction != -1 && direction != 1) return;
    final storeId = await _requireStoreId();
    final rows = await _client
        .from('product_categories')
        .select('id,sort_order,created_at')
        .eq('store_id', storeId)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);
    final items = List<Map<String, dynamic>>.from(rows);
    final index = items.indexWhere((e) => e['id']?.toString() == categoryId);
    if (index < 0) return;
    final target = index + direction;
    if (target < 0 || target >= items.length) return;

    final currentId = items[index]['id'].toString();
    final targetId = items[target]['id'].toString();
    final currentOrder = (items[index]['sort_order'] as num?)?.toInt() ?? (index + 1);
    final targetOrder = (items[target]['sort_order'] as num?)?.toInt() ?? (target + 1);

    // Use a temporary order to avoid unique-order collisions if a constraint exists.
    await _client.from('product_categories').update({'sort_order': -1000000}).eq('id', currentId).eq('store_id', storeId);
    await _client.from('product_categories').update({'sort_order': currentOrder}).eq('id', targetId).eq('store_id', storeId);
    await _client.from('product_categories').update({'sort_order': targetOrder}).eq('id', currentId).eq('store_id', storeId);
  }

  Future<void> setCategoryPosition({required String categoryId, required int position}) async {
    final storeId = await _requireStoreId();
    await _client.rpc('store_set_menu_category_position_v2', params: {
      'p_store_id': storeId,
      'p_category_id': categoryId,
      'p_position': position,
    });
  }

  Future<void> deleteCategory(String id) async {
    // Never send an optimistic/local UI id to a UUID database column.
    // The screen normally resolves it first, and this guard is the final safety net.
    final cleanId = id.trim();
    if (cleanId.isEmpty || !_uuidPattern.hasMatch(cleanId)) return;
    final storeId = await _requireStoreId();
    await _client.from('product_categories').delete().eq('id', cleanId).eq('store_id', storeId);
  }

  Future<Map<String, dynamic>> saveAddon({
    String? id,
    required String name,
    required double price,
    bool isActive = true,
  }) async {
    final storeId = await _requireStoreId();
    if (name.trim().isEmpty) throw ArgumentError('Add-on name is required');
    if (price < 0) throw ArgumentError('Add-on price cannot be negative');
    final payload = <String, dynamic>{
      'store_id': storeId,
      'name': name.trim(),
      'price': price,
      'is_active': isActive,
    };
    if (id == null || id.isEmpty) {
      return _client.from('product_addons').insert(payload).select().single();
    }
    return _client
        .from('product_addons')
        .update(payload)
        .eq('id', id)
        .eq('store_id', storeId)
        .select()
        .single();
  }

  Future<void> deleteAddon(String id) async {
    final storeId = await _requireStoreId();
    await _client.from('product_addons').delete().eq('id', id).eq('store_id', storeId);
  }

  Future<List<Map<String, dynamic>>> getStoreRecords({
    required String table,
    required String storeId,
  }) async {
    if (!_allowedRecordTables.contains(table)) throw ArgumentError('Unsupported table');
    final ownStoreId = await _requireStoreId();
    if (storeId != ownStoreId) return const [];
    var query = _client.from(table).select().eq('store_id', ownStoreId);
    final data = table == 'product_categories'
        ? await query.order('sort_order', ascending: true).order('created_at', ascending: true)
        : await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>?> saveStoreRecord({
    required String table,
    required Map<String, dynamic> payload,
    String? id,
  }) async {
    if (table == 'product_categories') {
      return saveCategory(
        id: id,
        name: payload['name']?.toString() ?? '',
        isActive: payload['is_active'] != false,
        imageUrl: payload['image_url']?.toString(),
        imagePath: payload['image_path']?.toString(),
        shiftId: payload['shift_id']?.toString(),
      );
    }
    if (table == 'product_addons') {
      return saveAddon(
        id: id,
        name: payload['name']?.toString() ?? '',
        price: (payload['price'] as num?)?.toDouble() ?? 0,
        isActive: payload['is_active'] != false,
      );
    }
    throw ArgumentError('This record type is read-only or unsupported');
  }

  Future<void> deleteStoreRecord({required String table, required String id}) async {
    if (table == 'product_categories') {
      await deleteCategory(id);
      return;
    }
    if (table == 'product_addons') {
      await deleteAddon(id);
      return;
    }
    throw ArgumentError('This record type is read-only or unsupported');
  }
}
