part of 'partner_dashboard.dart';

String _p55(BuildContext context, String ar, String ku, String en) {
  final code = AppStrings.of(context).languageCode;
  if (code == 'en') return en;
  if (code == 'ku') return ku;
  return ar;
}


bool _isFoodCatalog(String businessType) => const {'restaurant', 'cafe', 'sweets'}.contains(businessType);
bool _supportsWeightPresets(String businessType) => const {'grocery', 'sweets'}.contains(businessType);
bool _isDrinkCatalog(String businessType) => businessType == 'beverages';
bool _usesInventory(String businessType) => const {'grocery', 'pharmacy', 'beverages', 'flowers', 'hookah'}.contains(businessType);

String _catalogItem(BuildContext context, String businessType, {bool plural = false}) {
  if (businessType == 'restaurant' || businessType == 'sweets' || businessType == 'cafe') {
    return plural ? _p55(context, 'الوجبات', 'خواردنەکان', 'meals') : _p55(context, 'الوجبة', 'خواردن', 'meal');
  }
  if (businessType == 'beverages') {
    return plural ? _p55(context, 'المشروبات', 'خواردنەوەکان', 'drinks') : _p55(context, 'المشروب', 'خواردنەوە', 'drink');
  }
  if (businessType == 'flowers') {
    return plural ? _p55(context, 'المنتجات والباقات', 'بەرهەم و گوڵدەستەکان', 'products & bouquets') : _p55(context, 'المنتج / الباقة', 'بەرهەم / گوڵدەستە', 'product / bouquet');
  }
  return plural ? _p55(context, 'المنتجات', 'بەرهەمەکان', 'products') : _p55(context, 'المنتج', 'بەرهەم', 'product');
}

IconData _catalogIcon(String businessType) {
  switch (businessType) {
    case 'grocery': return Icons.shopping_basket_rounded;
    case 'pharmacy': return Icons.medication_outlined;
    case 'beverages': return Icons.local_drink_rounded;
    case 'flowers': return Icons.local_florist_rounded;
    case 'hookah': return Icons.inventory_2_outlined;
    default: return Icons.restaurant_menu_rounded;
  }
}

class _ProductsManagementPage extends StatefulWidget {
  const _ProductsManagementPage({this.businessType = 'restaurant'});
  final String businessType;
  @override
  State<_ProductsManagementPage> createState() => _ProductsManagementPageState();
}

class _ProductsManagementPageState extends State<_ProductsManagementPage> {
  String get businessType => widget.businessType;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _storeCategories = const [];
  bool _loading = true;
  String? _error;
  String? _selectedCategoryId;
  int _shiftMode = 1;
  List<Map<String, dynamic>> _shifts = const [];
  String? _activeShiftId;
  String _availability = 'all';
  String _sort = 'menuOrder';

  @override
  void initState() { super.initState(); _loadProducts(); }
  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  void _normalizeProductsInMemory() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final raw in _products) {
      final item = Map<String, dynamic>.from(raw);
      final key = (item['category_id']?.toString().trim().isNotEmpty ?? false)
          ? 'id:${item['category_id']}'
          : 'name:${(item['category_name']?.toString().trim() ?? '').toLowerCase()}';
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(item);
    }
    final normalized = <Map<String, dynamic>>[];
    for (final group in grouped.values) {
      group.sort((a, b) {
        final ao = (a['sort_order'] as num?)?.toInt() ?? 2147483647;
        final bo = (b['sort_order'] as num?)?.toInt() ?? 2147483647;
        final c = ao.compareTo(bo);
        if (c != 0) return c;
        final created = (a['created_at']?.toString() ?? '').compareTo(b['created_at']?.toString() ?? '');
        if (created != 0) return created;
        return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
      });
      for (var i = 0; i < group.length; i++) {
        group[i]['sort_order'] = i + 1;
        group[i]['__display_order'] = i + 1;
        normalized.add(group[i]);
      }
    }
    _products = normalized;
  }

  void _upsertProductLocal(Map<String, dynamic> product) {
    final id = product['id']?.toString();
    if (id == null || id.isEmpty) return;
    final next = _products.map((e) => Map<String, dynamic>.from(e)).toList();
    final index = next.indexWhere((e) => e['id']?.toString() == id);
    if (index >= 0) {
      next[index] = Map<String, dynamic>.from(product);
    } else {
      next.add(Map<String, dynamic>.from(product));
    }
    _products = next;
    _normalizeProductsInMemory();
  }

  Future<void> _loadProducts({bool showLoading = true}) async {
    if (mounted) setState(() { if (showLoading) _loading = true; _error = null; });
    try {
      final fetchedProducts = await ProductsRepository.instance.getStoreProducts();
      final fetchedCategories = await ProductsRepository.instance.getStoreCategories(activeOnly: true);
      final shiftMeta = await ProductsRepository.instance.getShiftModeAndShifts();
      if (!mounted) return;
      setState(() {
        _products = List<Map<String, dynamic>>.from(fetchedProducts);
        _storeCategories = List<Map<String, dynamic>>.from(fetchedCategories);
        _shiftMode = (shiftMeta?['shift_mode'] as num?)?.toInt() ?? 1;
        _shifts = List<Map<String, dynamic>>.from(shiftMeta?['shifts'] as List? ?? const []);
        if (_shiftMode == 2 && _shifts.isNotEmpty) {
          final activeExists = _activeShiftId != null && _shifts.any((e) => e['id']?.toString() == _activeShiftId);
          if (!activeExists) _activeShiftId = _shifts.first['id']?.toString();
        } else {
          _activeShiftId = null;
        }
        _normalizeProductsInMemory();
        final visibleIds = _visibleCategories.map((e) => e['id']?.toString()).whereType<String>().toSet();
        if (_selectedCategoryId == null || !visibleIds.contains(_selectedCategoryId)) {
          _selectedCategoryId = _visibleCategories.isEmpty ? null : _visibleCategories.first['id']?.toString();
        }
      });
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visibleCategories {
    final items = _storeCategories.where((c) {
      if (_shiftMode != 2 || _activeShiftId == null) return true;
      final sid = c['shift_id']?.toString();
      // NULL is a legacy/shared category and remains visible in both shifts.
      return sid == null || sid.isEmpty || sid == _activeShiftId;
    }).map((e) => Map<String, dynamic>.from(e)).toList();
    items.sort((a, b) {
      final ao = (a['sort_order'] as num?)?.toInt() ?? 999999;
      final bo = (b['sort_order'] as num?)?.toInt() ?? 999999;
      final c = ao.compareTo(bo);
      if (c != 0) return c;
      return (a['created_at']?.toString() ?? '').compareTo(b['created_at']?.toString() ?? '');
    });
    return items;
  }

  Map<String, dynamic>? get _selectedCategory {
    if (_selectedCategoryId == null) return null;
    for (final c in _visibleCategories) {
      if (c['id']?.toString() == _selectedCategoryId) return c;
    }
    return null;
  }

  List<Map<String, dynamic>> get _visibleProducts {
    final q = _searchController.text.trim().toLowerCase();
    final selected = _selectedCategory;
    if (selected == null) return const [];
    final selectedId = selected['id']?.toString() ?? '';
    final selectedName = (selected['name']?.toString() ?? '').trim().toLowerCase();
    var list = _products.where((p) {
      final name = (p['name']?.toString() ?? '').toLowerCase();
      final cat = (p['category_name']?.toString() ?? '').toLowerCase();
      final productCategoryId = p['category_id']?.toString() ?? '';
      final sameCategory = productCategoryId.isNotEmpty
          ? productCategoryId == selectedId
          : cat.trim() == selectedName;
      if (!sameCategory) return false;
      if (q.isNotEmpty && !name.contains(q) && !cat.contains(q)) return false;
      final available = p['is_available'] == true;
      if (_availability == 'available' && !available) return false;
      if (_availability == 'unavailable' && available) return false;
      return true;
    }).toList();
    if (_sort == 'menuOrder') {
      list.sort((a, b) {
        final ao = (a['sort_order'] as num?)?.toInt() ?? 2147483647;
        final bo = (b['sort_order'] as num?)?.toInt() ?? 2147483647;
        final orderCompare = ao.compareTo(bo);
        if (orderCompare != 0) return orderCompare;
        return (a['created_at']?.toString() ?? '').compareTo(b['created_at']?.toString() ?? '');
      });
    }
    if (_sort == 'newest') list.sort((a,b) => (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? ''));
    if (_sort == 'priceAsc') list.sort((a,b) => ((a['price'] as num?) ?? 0).compareTo((b['price'] as num?) ?? 0));
    if (_sort == 'priceDesc') list.sort((a,b) => ((b['price'] as num?) ?? 0).compareTo((a['price'] as num?) ?? 0));
    if (_sort == 'name') list.sort((a,b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
    return list;
  }

  List<Map<String, dynamic>> get _categories => _visibleCategories;

  Future<void> _openCategoriesManager() async {
    final store = await AuthService.instance.getCurrentStore();
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_p55(context, 'تعذر تحديد المتجر الحالي', 'نەتوانرا فرۆشگای ئێستا دیاری بکرێت', 'Could not resolve the current store'))),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _StoreSimpleRecordsPage(
          storeId: storeId,
          mode: _StoreManagerMode.categories,
          initialShiftId: _activeShiftId,
        ),
      ),
    );
    if (mounted) await _loadProducts(showLoading: false);
  }

  Future<void> _openEditor([Map<String, dynamic>? product]) async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductWizardDialog(
        product: product,
        businessType: businessType,
        initialCategoryId: product?['category_id']?.toString() ?? _selectedCategoryId,
        initialShiftId: _activeShiftId,
      ),
    );
    if (saved != null) {
      if (!mounted) return;
      setState(() => _upsertProductLocal(saved));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_p55(context, 'تم حفظ المنتج بنجاح', 'بەرهەمەکە بە سەرکەوتوویی پاشەکەوت کرا', 'Product saved successfully'))));
    }
  }

  Future<void> _toggleAvailability(Map<String,dynamic> p, bool value) async {
    final previous = p['is_available'] == true;
    if (mounted) {
      setState(() {
        p['is_available'] = value;
      });
    }
    try {
      await ProductsRepository.instance.updateProductAvailability(productId: p['id'].toString(), isAvailable: value);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => p['is_available'] = previous);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _deleteProduct(Map<String,dynamic> p) async {
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(_p55(context,'حذف ${_catalogItem(context, businessType)}','سڕینەوە','Delete ${_catalogItem(context, businessType)}')),
      content: Text(_p55(context,'هل تريد الحذف نهائيًا؟','دەتەوێت بە یەکجاری بسڕیتەوە؟','Delete this item permanently?')),
      actions: [TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(_p55(context,'إلغاء','هەڵوەشاندنەوە','Cancel'))), FilledButton(style:FilledButton.styleFrom(backgroundColor:Colors.red),onPressed:()=>Navigator.pop(c,true),child:Text(_p55(context,'حذف','سڕینەوە','Delete')))],
    ));
    if (yes != true) return;
    final previous = _products.map((e) => Map<String, dynamic>.from(e)).toList();
    final id = p['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() {
      _products = _products.where((e) => e['id']?.toString() != id).toList();
      _normalizeProductsInMemory();
    });
    try {
      await ProductsRepository.instance.deleteProduct(id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _products = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_p55(context, 'تعذر حذف المنتج: $e', 'سڕینەوەی بەرهەم سەرکەوتوو نەبوو: $e', 'Could not delete product: $e'))),
      );
    }
  }

  Future<void> _duplicateProduct(Map<String, dynamic> p) async {
    try {
      final created = await ProductsRepository.instance.duplicateProduct(p);
      if (!mounted) return;
      final local = Map<String, dynamic>.from(created)..['sort_order'] = 999999;
      setState(() => _upsertProductLocal(local));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_p55(context, 'تم نسخ المنتج وإضافته في نهاية القسم', 'بەرهەمەکە کۆپی کرا و لە کۆتایی بەش زیاد کرا', 'Product duplicated and added to the end of the category')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_p55(context, 'تعذر نسخ المنتج: $e', 'کۆپیکردنی بەرهەم سەرکەوتوو نەبوو: $e', 'Could not duplicate product: $e')),
        ),
      );
    }
  }


  Future<void> _changeProductOrder(Map<String, dynamic> product) async {
    final categoryId = product['category_id']?.toString() ?? '';
    final category = product['category_name']?.toString().trim() ?? '';
    final sameCategory = _products.where((p) {
      final pid = p['category_id']?.toString() ?? '';
      return categoryId.isNotEmpty ? pid == categoryId : (p['category_name']?.toString().trim() ?? '') == category;
    }).toList()
      ..sort((a, b) {
        final ao = (a['sort_order'] as num?)?.toInt() ?? 2147483647;
        final bo = (b['sort_order'] as num?)?.toInt() ?? 2147483647;
        final c = ao.compareTo(bo);
        return c != 0 ? c : (a['created_at']?.toString() ?? '').compareTo(b['created_at']?.toString() ?? '');
      });
    final maxPosition = sameCategory.isEmpty ? 1 : sameCategory.length;
    final current = ((product['__display_order'] as num?)?.toInt() ?? (product['sort_order'] as num?)?.toInt() ?? 1).clamp(1, maxPosition);
    if (!mounted) return;
    final selected = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ProductOrderDialog(
        current: current,
        maxPosition: maxPosition,
      ),
    );
    if (!mounted || selected == null || selected == current) return;

    final productId = product['id']?.toString();
    if (productId == null || productId.isEmpty) return;
    try {
      await ProductsRepository.instance.setProductPosition(
        productId: productId,
        position: selected,
      );
      if (!mounted) return;
      setState(() {
        final categoryId = product['category_id']?.toString() ?? '';
        final categoryName = product['category_name']?.toString().trim() ?? '';
        final same = _products
            .where((e) {
              final eid = e['category_id']?.toString() ?? '';
              return categoryId.isNotEmpty ? eid == categoryId : (e['category_name']?.toString().trim() ?? '').toLowerCase() == categoryName.toLowerCase();
            })
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
          ..sort((a, b) => ((a['__display_order'] as num?)?.toInt() ?? (a['sort_order'] as num?)?.toInt() ?? 999999)
              .compareTo((b['__display_order'] as num?)?.toInt() ?? (b['sort_order'] as num?)?.toInt() ?? 999999));
        final movedIndex = same.indexWhere((e) => e['id']?.toString() == productId);
        if (movedIndex >= 0) {
          final moved = same.removeAt(movedIndex);
          same.insert((selected - 1).clamp(0, same.length).toInt(), moved);
          for (var i = 0; i < same.length; i++) {
            same[i]['sort_order'] = i + 1;
            same[i]['__display_order'] = i + 1;
          }
          final byId = {for (final e in same) e['id']?.toString(): e};
          _products = _products.map((e) => byId[e['id']?.toString()] ?? e).toList();
          _normalizeProductsInMemory();
        }
      });
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.clearSnackBars();
      messenger?.showSnackBar(
        SnackBar(content: Text(_p55(context, 'تم تحديث التسلسل تلقائيًا بدون أرقام مكررة', 'ڕیزبەندی خۆکارانە نوێکرایەوە', 'Order updated automatically with no duplicate positions'))),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e, st) {
      debugPrint('Product order update failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(_p55(context, 'تعذر تغيير الترتيب. حاول مرة أخرى.', 'گۆڕینی ڕیزبەندی سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.', 'Could not change the order. Please try again.'))),
      );
    }
  }



  @override
  Widget build(BuildContext context) {
    final products = _visibleProducts;
    final available = _products.where((e)=>e['is_available']==true).length;
    final cats = _categories;
    final width = MediaQuery.sizeOf(context).width;
    return ColoredBox(
      color: const Color(0xFFFAFAFB),
      child: Stack(children:[
        RefreshIndicator(
          onRefresh: _loadProducts,
          child: ListView(
            padding: EdgeInsets.fromLTRB(_adaptivePagePadding(context), width < 600 ? 14 : 22, _adaptivePagePadding(context), 110),
            children:[Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:1180),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              _MealsHeader(businessType: businessType, onAddCategory:_openCategoriesManager),
              const SizedBox(height:16),
              Wrap(spacing:12,runSpacing:12,children:[
                _MealStat(icon:_catalogIcon(businessType),label:_p55(context,'إجمالي المنتجات','کۆی بەرهەمەکان','Total products'),value:'${_products.length}',tone:AppColors.orange),
                _MealStat(icon:Icons.check_circle_outline_rounded,label:_p55(context,'متاحة','بەردەست','Available'),value:'$available',tone:const Color(0xFF169447)),
                _MealStat(icon:Icons.visibility_off_outlined,label:_p55(context,'غير متاحة','بەردەست نییە','Unavailable'),value:'${_products.length-available}',tone:const Color(0xFF4776D0)),
                _MealStat(icon:Icons.grid_view_rounded,label:_p55(context,'الأقسام','بەشەکان','Categories'),value:'${cats.length}',tone:const Color(0xFF7247C7)),
              ]),
              const SizedBox(height:16),
              _ProductToolbar(
                businessType: businessType,
                controller:_searchController,
                availability:_availability,
                sort:_sort,
                onSearch:(_)=>setState((){}),
                onAvailability:(v)=>setState(()=>_availability=v),
                onSort:(v)=>setState(()=>_sort=v),
              ),
              if (_shiftMode == 2 && _shifts.length >= 2) ...[
                const SizedBox(height:14),
                Wrap(
                  spacing:8,
                  runSpacing:8,
                  children:_shifts.map((shift){
                    final id=shift['id'].toString();
                    final code=shift['shift_code']?.toString();
                    final selected=_activeShiftId==id;
                    final label=code=='morning'?_p55(context,'الشفت الصباحي','شیفتی بەیانی','Morning shift'):_p55(context,'الشفت المسائي','شیفتی ئێوارە','Evening shift');
                    return ChoiceChip(
                      label:Text(label),
                      selected:selected,
                      selectedColor:const Color(0xFFFFE7D3),
                      onSelected:(_)=>setState((){
                        _activeShiftId=id;
                        final next=_visibleCategories;
                        _selectedCategoryId=next.isEmpty?null:next.first['id']?.toString();
                      }),
                    );
                  }).toList(),
                ),
              ],
              if (cats.isNotEmpty) ...[
                const SizedBox(height:14),
                Text(_p55(context,'الأقسام','بەشەکان','Categories'),style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
                const SizedBox(height:8),
                SingleChildScrollView(
                  scrollDirection:Axis.horizontal,
                  child:Row(children:cats.map((c)=>_CategoryImageCard(
                    category:c,
                    selected:_selectedCategoryId==c['id']?.toString(),
                    onTap:()=>setState(()=>_selectedCategoryId=c['id']?.toString()),
                  )).toList()),
                ),
              ],
              const SizedBox(height:16),
              if (_loading) const Padding(padding:EdgeInsets.all(48),child:Center(child:CircularProgressIndicator()))
              else if (_error != null) _ProductsErrorState(message:_error!,onRetry:_loadProducts)
              else if (products.isEmpty) _EmptyProductsState(businessType: businessType, onAdd:()=>_openEditor())
              else ...products.map((p)=>Padding(padding:const EdgeInsets.only(bottom:12),child:_MealRowCard(product:p,showOrderBadge:true,onEdit:()=>_openEditor(p),onChangeOrder:()=>_changeProductOrder(p),onDuplicate:()=>_duplicateProduct(p),onDelete:()=>_deleteProduct(p),onAvailabilityChanged:(v)=>_toggleAvailability(p,v)))),
            ])))],
          ),
        ),
        PositionedDirectional(end:width>=900?42:(width<350?12:20),bottom:24,child:SafeArea(child:width<350
          ? FloatingActionButton(onPressed:()=>_openEditor(), backgroundColor:AppColors.orange, foregroundColor:Colors.white, child:const Icon(Icons.add_rounded))
          : FilledButton.icon(
              onPressed:()=>_openEditor(),
              icon:const Icon(Icons.add_rounded,size:20),
              label:Text(_p55(context,'إضافة منتج','زیادکردنی بەرهەم','Add product'),style:const TextStyle(fontSize:14,fontWeight:FontWeight.w900)),
              style:FilledButton.styleFrom(
                backgroundColor:AppColors.orange,
                foregroundColor:Colors.white,
                padding:const EdgeInsets.symmetric(horizontal:18,vertical:13),
                elevation:2,
                shadowColor:AppColors.orange.withValues(alpha:.18),
                minimumSize:const Size(0,48),
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
              ),
            ))),
      ]),
    );
  }
}

class _ProductOrderDialog extends StatefulWidget {
  const _ProductOrderDialog({required this.current, required this.maxPosition});
  final int current;
  final int maxPosition;

  @override
  State<_ProductOrderDialog> createState() => _ProductOrderDialogState();
}

class _ProductOrderDialogState extends State<_ProductOrderDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.current.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 1 || value > widget.maxPosition) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_p55(context, 'تغيير ترتيب المنتج', 'گۆڕینی ڕیزبەندی بەرهەم', 'Change product order')),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _adaptiveDialogWidth(context, maxWidth: 460)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _p55(
                context,
                'اختر رقمًا من 1 إلى ${widget.maxPosition}. إذا كان الرقم مستخدمًا، تتحرك المنتجات الأخرى تلقائيًا بدون تكرار.',
                'ژمارەیەک لە 1 بۆ ${widget.maxPosition} هەڵبژێرە. بەرهەمەکانی تر خۆکارانە دەجوڵێن.',
                'Choose a number from 1 to ${widget.maxPosition}. Other products shift automatically with no duplicate positions.',
              ),
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: _p55(context, 'رقم الترتيب', 'ژمارەی ڕیزبەندی', 'Order number'),
                helperText: '1 - ${widget.maxPosition}',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop();
          },
          child: Text(_p55(context, 'إلغاء', 'هەڵوەشاندنەوە', 'Cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_p55(context, 'حفظ الترتيب', 'پاشەکەوتکردنی ڕیزبەندی', 'Save order')),
        ),
      ],
    );
  }
}

class _MealsHeader extends StatelessWidget {
  const _MealsHeader({required this.businessType, required this.onAddCategory});
  final String businessType;
  final VoidCallback onAddCategory;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      onPressed: onAddCategory,
      icon: const Icon(Icons.create_new_folder_outlined),
      label: Text(_p55(context, 'إضافة قسم', 'زیادکردنی بەش', 'Add category')),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.orange,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_p55(context,'إدارة المنتجات','بەڕێوەبردنی بەرهەمەکان','Product management'),style:const TextStyle(fontSize:29,fontWeight:FontWeight.w900,color:Color(0xFF15171C))),
        const SizedBox(height:5),
        Text(_p55(context,'أنشئ الأقسام أولًا ثم أضف المنتجات داخل كل قسم','سەرەتا بەشەکان دروست بکە، پاشان بەرهەم زیاد بکە','Create categories first, then add products inside each category'),style:const TextStyle(color:AppColors.muted,fontSize:14,fontWeight:FontWeight.w600)),
      ],
    );
    if (MediaQuery.sizeOf(context).width >= 700) {
      return Row(children: [Expanded(child: title), const SizedBox(width: 16), button]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 14), Align(alignment: AlignmentDirectional.centerEnd, child: button)]);
  }
}

class _MealStat extends StatelessWidget {
  const _MealStat({required this.icon,required this.label,required this.value,required this.tone});
  final IconData icon; final String label,value; final Color tone;
  @override Widget build(BuildContext context){
    final width=MediaQuery.sizeOf(context).width;
    final veryNarrow=width<350;
    final cardWidth=width>=900?210.0:veryNarrow?((width-30)/2).clamp(135.0,155.0).toDouble():165.0;
    return Container(width:cardWidth,padding:EdgeInsets.all(veryNarrow?12:18),decoration:BoxDecoration(color:tone.withValues(alpha:.055),borderRadius:BorderRadius.circular(22),border:Border.all(color:tone.withValues(alpha:.14))),child:Row(children:[
      Container(width:veryNarrow?36:44,height:veryNarrow?36:44,decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(14)),child:Icon(icon,color:tone,size:veryNarrow?19:24)),SizedBox(width:veryNarrow?8:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:veryNarrow?10.5:12,fontWeight:FontWeight.w700,color:const Color(0xFF4C525E))),Text(value,style:TextStyle(fontSize:veryNarrow?19:23,fontWeight:FontWeight.w900,color:tone))]))
    ]));
  }
}

class _ProductToolbar extends StatelessWidget {
  const _ProductToolbar({required this.businessType,required this.controller,required this.availability,required this.sort,required this.onSearch,required this.onAvailability,required this.onSort});
  final String businessType; final TextEditingController controller; final String availability,sort; final ValueChanged<String> onSearch,onAvailability,onSort;
  @override Widget build(BuildContext context)=>Wrap(spacing:10,runSpacing:10,children:[
    SizedBox(
      width: MediaQuery.sizeOf(context).width >= 850 ? 520 : double.infinity,
      child: TextField(
        controller: controller,
        onChanged: onSearch,
        decoration: InputDecoration(
          hintText: _p55(context, 'ابحث عن ${_catalogItem(context, businessType)}...', 'بگەڕێ بۆ بەرهەم...', 'Search ${_catalogItem(context, businessType)}...'),
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        ),
      ),
    ),
    _ToolbarMenu(icon:Icons.filter_alt_outlined,label:_p55(context,'تصفية','پاڵاوتن','Filter'),items:{'all':_p55(context,'الكل','هەموو','All'),'available':_p55(context,'متاحة','بەردەست','Available'),'unavailable':_p55(context,'غير متاحة','بەردەست نییە','Unavailable')},value:availability,onChanged:onAvailability),
    _ToolbarMenu(icon:Icons.swap_vert_rounded,label:_p55(context,'ترتيب','ڕیزکردن','Sort'),items:{'menuOrder':_p55(context,'ترتيب المنيو','ڕیزبەندی مێنیو','Menu order'),'newest':_p55(context,'الأحدث','نوێترین','Newest'),'name':_p55(context,'الاسم','ناو','Name'),'priceAsc':_p55(context,'السعر تصاعدي','نرخ لە کەمەوە','Price low to high'),'priceDesc':_p55(context,'السعر تنازلي','نرخ لە زۆرەوە','Price high to low')},value:sort,onChanged:onSort),
  ]);
}

class _ToolbarMenu extends StatelessWidget {
  const _ToolbarMenu({required this.icon,required this.label,required this.items,required this.value,required this.onChanged});
  final IconData icon; final String label,value; final Map<String,String> items; final ValueChanged<String> onChanged;
  @override Widget build(BuildContext context)=>PopupMenuButton<String>(initialValue:value,onSelected:onChanged,itemBuilder:(_)=>items.entries.map((e)=>PopupMenuItem(value:e.key,child:Text(e.value))).toList(),child:Container(padding:const EdgeInsets.symmetric(horizontal:16,vertical:14),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(16),border:Border.all(color:const Color(0xFFE5E7EB))),child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:21),const SizedBox(width:8),Text(label,style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(width:5),const Icon(Icons.keyboard_arrow_down_rounded,size:18)])));
}

class _CategoryImageCard extends StatelessWidget {
  const _CategoryImageCard({required this.category, required this.selected, required this.onTap});
  final Map<String, dynamic> category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = category['image_url']?.toString() ?? '';
    final name = category['name']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 118,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF3E8) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.orange : const Color(0xFFE5E7EB), width: selected ? 1.7 : 1),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: image.isNotEmpty
                      ? PersistentNetworkImage(
                          url: image,
                          fit: BoxFit.cover,
                          cacheWidth: 180,
                          placeholder: const _CategorySmallPlaceholder(),
                          errorBuilder: (_, _, _) => const _CategorySmallPlaceholder(),
                        )
                      : const _CategorySmallPlaceholder(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: selected ? AppColors.orangeDark : const Color(0xFF24272D)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategorySmallPlaceholder extends StatelessWidget {
  const _CategorySmallPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFFFF4EA),
        alignment: Alignment.center,
        child: const Icon(Icons.restaurant_menu_rounded, color: AppColors.orange, size: 21),
      );
}

class _MealRowCard extends StatelessWidget {
  const _MealRowCard({required this.product,required this.showOrderBadge,required this.onEdit,required this.onChangeOrder,required this.onDuplicate,required this.onDelete,required this.onAvailabilityChanged});
  final Map<String,dynamic> product; final bool showOrderBadge; final VoidCallback onEdit,onChangeOrder,onDuplicate,onDelete; final ValueChanged<bool> onAvailabilityChanged;
  @override Widget build(BuildContext context){
    final image=product['image_url']?.toString()??''; final available=product['is_available']==true; final price=((product['price'] as num?)??0).toDouble(); final desc=product['description']?.toString()??'';
    return Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(22),border:Border.all(color:const Color(0xFFE9EBEF)),boxShadow:const [BoxShadow(color:Color(0x08101828),blurRadius:16,offset:Offset(0,5))]),child:LayoutBuilder(builder:(context,c){
      final compact=c.maxWidth<650;
      final imageWidget=ClipRRect(borderRadius:BorderRadius.circular(16),child:SizedBox(width:compact?100:150,height:compact?100:118,child:image.isNotEmpty?PersistentNetworkImage(url:image,fit:BoxFit.cover,cacheWidth:compact?320:480,placeholder:const _ProductLargeImagePlaceholder(),errorBuilder:(_,_,_)=>const _ProductLargeImagePlaceholder()):const _ProductLargeImagePlaceholder()));
      final info=Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(product['name']?.toString()??'',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
        const SizedBox(height:6),Text(desc.isEmpty?'—':desc,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:AppColors.muted,height:1.35)),
        const SizedBox(height:8),Wrap(spacing:8,runSpacing:6,crossAxisAlignment:WrapCrossAlignment.center,children:[
          Text('${price.toStringAsFixed(0)} د.ع',style:const TextStyle(color:AppColors.orangeDark,fontSize:17,fontWeight:FontWeight.w900)),
          if ((product['category_name']?.toString()??'').isNotEmpty) Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:4),decoration:BoxDecoration(color:const Color(0xFFF6F1FF),borderRadius:BorderRadius.circular(9)),child:Text(product['category_name'].toString(),style:const TextStyle(color:Color(0xFF7247C7),fontSize:11,fontWeight:FontWeight.w800))),
          if (showOrderBadge && ((product['__display_order'] as num?) != null || (product['sort_order'] as num?) != null)) Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:4),decoration:BoxDecoration(color:const Color(0xFFFFF4E8),borderRadius:BorderRadius.circular(9)),child:Text('#${((product['__display_order'] as num?) ?? (product['sort_order'] as num)).toInt()}',style:const TextStyle(color:AppColors.orangeDark,fontSize:11,fontWeight:FontWeight.w900))),
          if ((product['preparation_time_minutes'] as num?) != null) Text('${product['preparation_time_minutes']} ${_p55(context,'دقيقة','خولەک','min')}',style:const TextStyle(color:AppColors.muted,fontSize:12,fontWeight:FontWeight.w700)),
          if ((product['brand']?.toString()??'').isNotEmpty) Text(product['brand'].toString(),style:const TextStyle(color:AppColors.muted,fontSize:12,fontWeight:FontWeight.w700)),
          if ((product['size_label']?.toString()??'').isNotEmpty) Text(product['size_label'].toString(),style:const TextStyle(color:AppColors.muted,fontSize:12,fontWeight:FontWeight.w700)),
          if (product['track_stock']==true) Text('${_p55(context,'المخزون','کۆگا','Stock')}: ${product['stock_quantity'] ?? 0}',style:TextStyle(color:((product['stock_quantity'] as num?)??0)<=0?Colors.red:const Color(0xFF169447),fontSize:12,fontWeight:FontWeight.w800)),
        ])
      ])));
      final actions=Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        Row(mainAxisSize:MainAxisSize.min,children:[Switch.adaptive(value:available,onChanged:onAvailabilityChanged,activeThumbColor:const Color(0xFF169447)),Text(available?_p55(context,'متاحة','بەردەست','Available'):_p55(context,'غير متاحة','بەردەست نییە','Unavailable'),style:TextStyle(fontWeight:FontWeight.w800,color:available?const Color(0xFF169447):Colors.red))]),
        const SizedBox(height:5),Row(mainAxisSize:MainAxisSize.min,children:[OutlinedButton.icon(onPressed:onEdit,icon:const Icon(Icons.edit_outlined,size:18),label:Text(_p55(context,'تعديل','دەستکاری','Edit'))),const SizedBox(width:7),PopupMenuButton<String>(onSelected:(v){if(v=='order'){onChangeOrder();}else if(v=='duplicate'){onDuplicate();}else if(v=='delete'){onDelete();}else{onEdit();}},itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(_p55(context,'تعديل','دەستکاری','Edit'))),PopupMenuItem(value:'order',child:Row(children:[const Icon(Icons.format_list_numbered_rounded,size:19),const SizedBox(width:9),Text(_p55(context,'تغيير الترتيب','گۆڕینی ڕیزبەندی','Change order'))])),PopupMenuItem(value:'duplicate',child:Text(_p55(context,'نسخ المنتج','کۆپیکردنی بەرهەم','Duplicate product'))),PopupMenuItem(value:'delete',child:Text(_p55(context,'حذف','سڕینەوە','Delete'),style:const TextStyle(color:Colors.red)))],child:Container(padding:const EdgeInsets.symmetric(horizontal:13,vertical:11),decoration:BoxDecoration(border:Border.all(color:const Color(0xFFE1E4E9)),borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.more_horiz_rounded)))])
      ]);
      if (compact) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [imageWidget, info]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Switch.adaptive(value: available, onChanged: onAvailabilityChanged, activeThumbColor: const Color(0xFF169447)),
              Flexible(child: Text(available ? _p55(context,'متاحة','بەردەست','Available') : _p55(context,'غير متاحة','بەردەست نییە','Unavailable'), overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: available ? const Color(0xFF169447) : Colors.red))),
            ])),
            FilledButton.tonalIcon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18), label: Text(_p55(context,'تعديل','دەستکاری','Edit'))),
            PopupMenuButton<String>(onSelected:(v){if(v=='order'){onChangeOrder();}else if(v=='duplicate'){onDuplicate();}else if(v=='delete'){onDelete();}else{onEdit();}},itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(_p55(context,'تعديل','دەستکاری','Edit'))),PopupMenuItem(value:'order',child:Row(children:[const Icon(Icons.format_list_numbered_rounded,size:19),const SizedBox(width:9),Text(_p55(context,'تغيير الترتيب','گۆڕینی ڕیزبەندی','Change order'))])),PopupMenuItem(value:'duplicate',child:Text(_p55(context,'نسخ المنتج','کۆپیکردنی بەرهەم','Duplicate product'))),PopupMenuItem(value:'delete',child:Text(_p55(context,'حذف','سڕینەوە','Delete'),style:const TextStyle(color:Colors.red)))])
          ]),
        ]);
      }
      return Row(children:[imageWidget,info,actions]);
    }));
  }
}

class _ProductLargeImagePlaceholder extends StatelessWidget { const _ProductLargeImagePlaceholder(); @override Widget build(BuildContext context)=>Container(decoration:const BoxDecoration(gradient:LinearGradient(colors:[Color(0xFFFFF5ED),Color(0xFFFFE5D2)])),alignment:Alignment.center,child:const Icon(Icons.restaurant_menu_rounded,size:45,color:AppColors.orange)); }

class _ProductWizardDialog extends StatefulWidget {
  const _ProductWizardDialog({this.product, required this.businessType, this.initialCategoryId, this.initialShiftId});
  final Map<String,dynamic>? product;
  final String businessType;
  final String? initialCategoryId;
  final String? initialShiftId;
  @override State<_ProductWizardDialog> createState()=>_ProductWizardDialogState();
}

class _ProductWizardDialogState extends State<_ProductWizardDialog> {
  String get businessType => widget.businessType;

  final _formKey=GlobalKey<FormState>();
  late final TextEditingController _name,_description,_price,_category,_position,_prep,_calories,_notes,_tags,_brand,_barcode,_sku,_stock,_sizeLabel,_weightValue;
  late bool _available; bool _saving=false,_loadingAddons=true; PlatformFile? _selectedImage; String? _imageUrl,_imagePath; bool _removeImage=false; String? _saveError;
  List<Map<String,dynamic>> _addons=const[], _categories=const[]; final Set<String> _selectedAddonIds={}; String _type='single'; String _unit='piece'; String _weightUnit='g'; bool _trackStock=false;
  final List<_ProductVariantDraft> _variants = <_ProductVariantDraft>[];
  bool _useVariants = false;
  int _shiftMode = 1;
  List<Map<String, dynamic>> _shifts = const [];
  final Set<String> _selectedShiftIds = <String>{};
  String? _selectedCategoryId;
  String? _dialogShiftId;

  @override void initState(){
    super.initState();
    final p=widget.product;
    _name=TextEditingController(text:p?['name']?.toString()??'');
    _description=TextEditingController(text:p?['description']?.toString()??'');
    _price=TextEditingController(text:p==null?'':((p['price'] as num?)?.toStringAsFixed(0)??''));
    _category=TextEditingController(text:p?['category_name']?.toString()??'');
    _selectedCategoryId = p?['category_id']?.toString() ?? widget.initialCategoryId;
    _dialogShiftId = widget.initialShiftId;
    _position=TextEditingController(text:p==null?'':((p['sort_order'] as num?)?.toInt().toString()??''));
    _prep=TextEditingController(text:p?['preparation_time_minutes']?.toString()??'');
    _calories=TextEditingController(text:p?['calories']?.toString()??'');
    _notes=TextEditingController(text:p?['notes']?.toString()??'');
    _tags=TextEditingController(text:(p?['tags'] is List)?(p!['tags'] as List).join(', '):'');
    _brand=TextEditingController(text:p?['brand']?.toString()??'');
    _barcode=TextEditingController(text:p?['barcode']?.toString()??'');
    _sku=TextEditingController(text:p?['sku']?.toString()??'');
    _stock=TextEditingController(text:p?['stock_quantity']?.toString()??'');
    _sizeLabel=TextEditingController(text:p?['size_label']?.toString()??'');
    _weightValue=TextEditingController(text:p?['weight_value']?.toString()??'');
    _available=p?['is_available']!=false;
    _type=p?['product_type']?.toString()??(_isDrinkCatalog(businessType)?'drink':(_isFoodCatalog(businessType)?'single':'product'));
    _unit=p?['unit']?.toString()??'piece';
    _weightUnit=p?['weight_unit']?.toString()??'g';
    _trackStock=p?['track_stock']==true;
    _imageUrl=p?['image_url']?.toString(); _imagePath=p?['image_path']?.toString(); _loadCatalogMeta();
  }
  @override void dispose(){for(final c in [_name,_description,_price,_category,_position,_prep,_calories,_notes,_tags,_brand,_barcode,_sku,_stock,_sizeLabel,_weightValue]){c.dispose();}for(final v in _variants){v.dispose();}super.dispose();}

  Future<void> _loadCatalogMeta() async {
    try {
      final addons = await ProductsRepository.instance.getStoreAddons();
      final categories = await ProductsRepository.instance.getStoreCategories(activeOnly:true);
      final shiftMeta = await ProductsRepository.instance.getShiftModeAndShifts();
      final links=widget.product==null?<String>{}:await ProductsRepository.instance.getProductAddonIds(widget.product!['id'].toString());
      final shiftMode = (shiftMeta?['shift_mode'] as num?)?.toInt() ?? 1;
      final shifts = List<Map<String, dynamic>>.from(shiftMeta?['shifts'] as List? ?? const []);
      final assignedShiftIds = widget.product==null || shifts.isEmpty ? <String>{} : await ProductsRepository.instance.getProductShiftIds(widget.product!['id'].toString());
      var variants=const <Map<String,dynamic>>[];
      if(widget.product!=null){
        try{variants=await ProductsRepository.instance.getProductVariants(widget.product!['id'].toString());}
        catch(e,st){debugPrint('Stage 156 variants are not available yet: $e\n$st');}
      }
      if (mounted) {
        setState(() {
        _addons=List<Map<String,dynamic>>.from(addons);
        _categories=List<Map<String,dynamic>>.from(categories);
        _selectedAddonIds.addAll(links);
        _shiftMode = shiftMode;
        _shifts = shifts;
        Map<String, dynamic>? selectedCategory;
        for (final c in _categories) {
          if (c['id']?.toString() == _selectedCategoryId) {
            selectedCategory = c;
            break;
          }
        }
        final categoryShiftId = selectedCategory?['shift_id']?.toString();
        if ((categoryShiftId ?? '').isNotEmpty) _dialogShiftId = categoryShiftId;
        if (_shiftMode == 2 && (_dialogShiftId ?? '').isEmpty && shifts.isNotEmpty) {
          _dialogShiftId = shifts.first['id']?.toString();
        }
        final scoped = _categories.where((c) {
          if (_shiftMode != 2 || _dialogShiftId == null) return true;
          final sid = c['shift_id']?.toString();
          return sid == null || sid.isEmpty || sid == _dialogShiftId;
        }).toList();
        if (_selectedCategoryId == null || !scoped.any((c) => c['id']?.toString() == _selectedCategoryId)) {
          _selectedCategoryId = scoped.isEmpty ? null : scoped.first['id']?.toString();
          if (scoped.isNotEmpty) _category.text = scoped.first['name']?.toString() ?? '';
        }
        _selectedShiftIds
          ..clear()
          ..addAll(assignedShiftIds.isEmpty
              ? ((_dialogShiftId ?? '').isNotEmpty ? {_dialogShiftId!} : shifts.map((e) => e['id'].toString()))
              : assignedShiftIds);
        for(final old in _variants){old.dispose();}
        _variants
          ..clear()
          ..addAll(variants.map((v)=>_ProductVariantDraft(
            name:v['name']?.toString()??'',
            price:((v['price'] as num?)??0).toDouble(),
            available:v['is_available']!=false,
          )));
        _useVariants=_variants.isNotEmpty;
        _loadingAddons=false;
      });
      }
    } catch(e,st){debugPrint('Product catalog metadata load failed: $e\n$st');if(mounted)setState(()=>_loadingAddons=false);}
  }

  void _addVariant(){setState(()=>_variants.add(_ProductVariantDraft()));}
  void _removeVariant(int index){if(index<0||index>=_variants.length)return;final item=_variants.removeAt(index);item.dispose();setState((){});}
  void _moveVariant(int from,int to){if(from<0||from>=_variants.length||to<0||to>=_variants.length)return;setState((){final item=_variants.removeAt(from);_variants.insert(to,item);});}

  String? _validateVariants(){
    if(!_useVariants)return null;
    if(_variants.isEmpty)return _p55(context,'أضف حجمًا أو خيارًا واحدًا على الأقل','لانیکەم قەبارەیەک زیاد بکە','Add at least one size or option');
    final names=<String>{};
    for(final v in _variants){
      final name=v.name.text.trim();
      final price=double.tryParse(v.price.text.trim());
      if(name.isEmpty||price==null||price<0)return _p55(context,'أكمل اسم وسعر كل حجم أو خيار','ناو و نرخی هەموو قەبارەکان تەواو بکە','Complete the name and price for every size or option');
      if(!names.add(name.toLowerCase()))return _p55(context,'لا تكرر اسم الحجم أو الخيار نفسه','ناوی هەمان قەبارە دووبارە مەکە','Do not repeat the same size or option name');
    }
    return null;
  }
  Future<void> _pickImage() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.single;
    if (f.size > 5 * 1024 * 1024 || f.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_p55(context, 'الصورة يجب أن تكون أقل من 5MB', 'وێنەکە دەبێت کەمتر لە 5MB بێت', 'Image must be under 5MB'))),
        );
      }
      return;
    }
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => PartnerImageCropEditor(
          bytes: f.bytes!,
          aspectRatio: 4 / 3,
          preserveWholeImage: true,
          title: _p55(context, 'ضبط صورة المنتج', 'ڕێکخستنی وێنەی بەرهەم', 'Adjust product image'),
        ),
      ),
    );
    if (!mounted || cropped == null) return;
    setState(() {
      _selectedImage = PlatformFile(
        name: 'product_${DateTime.now().millisecondsSinceEpoch}.png',
        size: cropped.length,
        bytes: cropped,
      );
      _removeImage = false;
    });
  }
  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final category = _category.text.trim();
    final categoryId = _selectedCategoryId;
    final parsedBasePrice = double.tryParse(_price.text.trim());
    final variantError = _validateVariants();
    final variantPrices = _variants.map((v)=>double.tryParse(v.price.text.trim())).whereType<double>().toList();
    final effectivePrice = _useVariants && variantPrices.isNotEmpty
        ? (parsedBasePrice != null && parsedBasePrice >= 0 ? parsedBasePrice : variantPrices.reduce((a,b)=>a<b?a:b))
        : parsedBasePrice;
    final rawPosition = _position.text.trim();
    final desiredPosition = rawPosition.isEmpty ? null : int.tryParse(rawPosition);
    if (name.isEmpty || category.isEmpty || categoryId == null || categoryId.isEmpty || effectivePrice == null || effectivePrice < 0 || variantError != null || (rawPosition.isNotEmpty && (desiredPosition == null || desiredPosition < 1))) {
      setState(() {
        _saveError = variantError ?? _p55(
          context,
          'تأكد من اسم المنتج والقسم والسعر قبل الحفظ.',
          'پێش پاشەکەوتکردن ناوی بەرهەم و بەش و نرخ بپشکنە.',
          'Check the product name, category and price before saving.',
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      var url = _removeImage ? null : _imageUrl;
      var path = _removeImage ? null : _imagePath;

      String? imageWarning;
      if (_selectedImage?.bytes != null) {
        try {
          final up = await ProductsRepository.instance.uploadProductImage(
            bytes: _selectedImage!.bytes!,
            extension: 'png',
            oldPath: _imagePath,
          );
          url = up['url'];
          path = up['path'];
        } on StorageException catch (e) {
          // Stage 123: never block the core product record because Storage
          // rejected an optional image. Save the product first, then surface
          // the image warning to the merchant.
          imageWarning = e.message;
          debugPrint('Product image upload warning: ${e.message}');
          url = _imageUrl;
          path = _imagePath;
        }
      } else if (_removeImage && (_imagePath ?? '').isNotEmpty) {
        await ProductsRepository.instance.removeProductImage(_imagePath);
      }

      final saved = await ProductsRepository.instance.saveProduct(
        productId: widget.product?['id']?.toString(),
        name: name,
        description: _description.text,
        price: effectivePrice,
        categoryId: categoryId,
        categoryName: category,
        isAvailable: _available,
        imageUrl: url,
        imagePath: path,
        preparationTimeMinutes: int.tryParse(_prep.text.trim()),
        calories: int.tryParse(_calories.text.trim()),
        notes: _notes.text,
        tags: _tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        productType: _type,
        brand: _brand.text,
        barcode: _barcode.text,
        sku: _sku.text,
        unit: _unit,
        trackStock: _trackStock,
        stockQuantity: double.tryParse(_stock.text.trim()),
        sizeLabel: _sizeLabel.text,
        weightValue: double.tryParse(_weightValue.text.trim()),
        weightUnit: _weightUnit,
        catalogKind: businessType,
      );

      await ProductsRepository.instance.setProductPosition(
        productId: saved['id'].toString(),
        position: desiredPosition ?? 999999,
      );

      if (_shiftMode == 2 && _shifts.isNotEmpty) {
        Map<String, dynamic>? selectedCategory;
        for (final c in _categories) {
          if (c['id']?.toString() == categoryId) {
            selectedCategory = c;
            break;
          }
        }
        final categoryShiftId = selectedCategory?['shift_id']?.toString();
        final productShiftIds = (categoryShiftId ?? '').isNotEmpty ? <String>{categoryShiftId!} : _selectedShiftIds;
        await ProductsRepository.instance.setProductShifts(
          productId: saved['id'].toString(),
          selectedShiftIds: productShiftIds,
          allShiftIds: _shifts.map((e) => e['id'].toString()).toSet(),
        );
      }

      await ProductsRepository.instance.replaceProductVariants(
        productId: saved['id'].toString(),
        variants: _useVariants
            ? _variants.asMap().entries.map((entry)=>{
                'name': entry.value.name.text.trim(),
                'price': double.parse(entry.value.price.text.trim()),
                'sort_order': entry.key + 1,
                'is_available': entry.value.available,
              }).toList()
            : const <Map<String,dynamic>>[],
      );

      // A new product with no selected add-ons should not perform an unnecessary
      // link-table write. This keeps the core product save independent.
      if (widget.product != null || _selectedAddonIds.isNotEmpty) {
        try {
          await ProductsRepository.instance.setProductAddons(
            saved['id'].toString(),
            _selectedAddonIds.toList(),
          );
        } catch (e) {
          // The product itself is already saved. Do not keep the dialog stuck
          // because an optional add-on sync failed.
          debugPrint('Product add-on sync warning: $e');
        }
      }

      if (mounted) {
        if (imageWarning != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_p55(
                context,
                'تم حفظ المنتج، لكن تعذر رفع الصورة. شغّل Stage 123 في Supabase ثم أعد إضافة الصورة.',
                'بەرهەم پاشەکەوت کرا، بەڵام وێنە بارنەکرا. Stage 123 لە Supabase جێبەجێ بکە.',
                'Product saved, but the image upload failed. Run Stage 123 in Supabase, then add the image again.',
              )),
            ),
          );
        }
        final savedForUi = Map<String, dynamic>.from(saved)
          ..['image_url'] = url
          ..['image_path'] = path
          ..['category_id'] = categoryId
          ..['category_name'] = category
          ..['is_available'] = _available
          ..['sort_order'] = desiredPosition ?? 999999;
        Navigator.pop(context, savedForUi);
      }
    } on StorageException catch (e) {
      if (mounted) {
        setState(() {
          _saveError = _p55(
            context,
            'تعذر تنفيذ عملية التخزين: ${e.message}. شغّل ملف Stage 123 في Supabase ثم حاول مجددًا.',
            'هەڵەی Storage: ${e.message}',
            'Storage operation failed: ${e.message}. Run the Stage 123 SQL in Supabase and try again.',
          );
        });
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        final lower='${e.code ?? ''} ${e.message} ${e.details ?? ''}'.toLowerCase();
        final stage155Missing=lower.contains('store_set_product_position_v6')||lower.contains('store_replace_product_variants_v2')||lower.contains('product_variants')||lower.contains('schema cache');
        setState(() => _saveError = stage155Missing
            ? _p55(context,'يلزم تشغيل Stage 200 في Supabase مرة واحدة لتفعيل فصل أقسام الشفتات والترتيب الجديد.','پێویستە Stage 200 لە Supabase جێبەجێ بکرێت.','Run the Stage 200 SQL in Supabase once to enable shift-scoped categories and the new ordering system.')
            : e.message);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _saveError = e.message);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saveError = _p55(
            context,
            'تعذر حفظ المنتج. التفاصيل: $e',
            'پاشەکەوتکردنی بەرهەم سەرکەوتوو نەبوو: $e',
            'Could not save the product. Details: $e',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width < 700 ? 8 : 30,
        vertical: size.height < 700 ? 8 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 860),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(size.width < 600 ? 10 : 22, 14, size.width < 600 ? 10 : 22, 8),
              child: Row(
                children: [
                  IconButton(onPressed: _saving ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          widget.product == null
                              ? _p55(context, 'إضافة منتج', 'زیادکردنی بەرهەم', 'Add product')
                              : _p55(context, 'تعديل المنتج', 'دەستکاری بەرهەم', 'Edit product'),
                          style: TextStyle(fontSize: size.width < 600 ? 18 : 22, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _p55(context, 'كل المعلومات في صفحة واحدة — الحقول تتكيف مع نوع متجرك', 'هەموو زانیارییەکان لە یەک پەڕەدا', 'Everything on one page — fields adapt to your store'),
                          style: TextStyle(color: AppColors.muted, fontSize: size.width < 600 ? 10 : 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(size.width < 600 ? 14 : 24),
                  child: _singlePageForm(),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.all(size.width < 600 ? 10 : 18),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE9EAED)))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_saveError != null) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFFF2F0), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFFC9C2))),
                      child: Text(_saveError!, style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w700)),
                    ),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_rounded),
                      label: Text(_p55(context, 'حفظ المنتج', 'پاشەکەوتکردنی بەرهەم', 'Save product')),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.orange, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _singlePageForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _basicStep(),
          const SizedBox(height: 24),
          _detailsStep(),
          const SizedBox(height: 12),
          _variantsSection(),
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 8),
            title: Text(_p55(context, 'الإضافات والخيارات (اختياري)', 'زیادکراوە و هەڵبژاردەکان', 'Add-ons & options (optional)'), style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(_p55(context, 'افتحها فقط إذا يحتاج المنتج إضافات', 'تەنها ئەگەر پێویستە بیکەرەوە', 'Open only when this product needs add-ons')),
            children: [_addonsStep()],
          ),
          const SizedBox(height: 18),
        ],
      );

  Widget _field(TextEditingController c,String label,{String? hint,int maxLines=1,TextInputType? keyboard,bool readOnly=false})=>Padding(padding:const EdgeInsets.only(bottom:16),child:TextFormField(controller:c,maxLines:maxLines,keyboardType:keyboard,readOnly:readOnly,decoration:InputDecoration(labelText:label,hintText:hint,filled:true,fillColor:const Color(0xFFFBFBFC),border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:const BorderSide(color:Color(0xFFE2E4E8))))));

  Widget _basicStep()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    _SectionTitle(title:_p55(context,'معلومات أساسية','زانیاری سەرەتایی','Basic information')),
    _field(_name,_p55(context,'اسم المنتج *','ناوی بەرهەم *','Product name *'),hint:_p55(context,'اكتب الاسم كما سيظهر للعميل','ناوەکە بنووسە','Enter the customer-facing name')),
    _field(_description,_p55(context,'الوصف','وەسف','Description'),hint:_p55(context,'وصف مختصر وواضح...','وەسفێکی کورت بنووسە...','Write a short clear description...'),maxLines:4),
    _field(_category,_p55(context,'القسم *','بەش *','Category *'),hint:_p55(context,'اختر من الأقسام المسجلة أدناه','لە بەشە تۆمارکراوەکان هەڵبژێرە','Choose from the registered categories below'),readOnly:true),
    Builder(builder:(context){
      final scoped=_categories.where((c){
        if(_shiftMode!=2||_dialogShiftId==null)return true;
        final sid=c['shift_id']?.toString();
        return sid==null||sid.isEmpty||sid==_dialogShiftId;
      }).toList();
      if(scoped.isEmpty){
        return Container(margin:const EdgeInsets.only(bottom:14),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFFFFF4E8),borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0xFFFFC99F))),child:Text(_p55(context,'لا توجد أقسام لهذا الشفت. أضف قسمًا أولًا من إدارة الأقسام.','هیچ بەشێک بۆ ئەم شیفتە نییە.','No categories exist for this shift. Add a category first.'),style:const TextStyle(fontWeight:FontWeight.w800,color:AppColors.orangeDark)));
      }
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(_p55(context,'اختر من أقسام هذا الشفت','لە بەشەکانی ئەم شیفتە هەڵبژێرە','Choose from this shift categories'),style:const TextStyle(fontWeight:FontWeight.w800,color:AppColors.muted)),
        const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:8,children:scoped.map((c){
          final id=c['id']?.toString()??'';
          final n=(c['name']??'').toString();
          final selected=_selectedCategoryId==id;
          return ChoiceChip(label:Text(n),selected:selected,onSelected:(_)=>setState((){_selectedCategoryId=id;_category.text=n;}),selectedColor:const Color(0xFFFFE7D3),side:BorderSide(color:selected?AppColors.orange:const Color(0xFFE1E4E9)));
        }).toList()),
        const SizedBox(height:14),
      ]);
    }),
    _field(_position,_p55(context,'ترتيب المنتج داخل القسم','ڕیزبەندی بەرهەم لە ناو بەش','Product order inside category'),hint:_p55(context,'مثال: 1 — اتركه فارغًا ليضاف في نهاية القسم','نموونە: 1 — بەتاڵی بهێڵە بۆ کۆتایی بەش','Example: 1 — leave blank to place it at the end'),keyboard:TextInputType.number),
    if(_shiftMode==2 && _shifts.length>=2 && _dialogShiftId!=null)...[
      Container(
        margin:const EdgeInsets.only(bottom:14),
        padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
        decoration:BoxDecoration(color:const Color(0xFFF8FAFC),borderRadius:BorderRadius.circular(12),border:Border.all(color:const Color(0xFFE3E7ED))),
        child:Row(children:[
          const Icon(Icons.schedule_rounded,size:19,color:AppColors.orange),
          const SizedBox(width:8),
          Expanded(child:Text(_p55(context,'هذا المنتج يتبع شفت القسم المحدد','ئەم بەرهەمە شیفتی بەشەکەی خۆی هەیە','This product follows the selected category shift'),style:const TextStyle(fontWeight:FontWeight.w800))),
        ]),
      ),
    ],
    Text(_p55(context,'الصورة','وێنە','Image'),style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:8),
    InkWell(onTap:_saving?null:_pickImage,borderRadius:BorderRadius.circular(18),child:Container(height:190,decoration:BoxDecoration(color:const Color(0xFFFFFAF6),borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xFFFFC99F))),clipBehavior:Clip.antiAlias,child:_selectedImage?.bytes!=null?Image.memory(_selectedImage!.bytes!,fit:BoxFit.cover):(_imageUrl??'').isNotEmpty?PersistentNetworkImage(url:_imageUrl!,fit:BoxFit.cover,cacheWidth:900,placeholder:_uploadPlaceholder(),errorBuilder:(_,_,_)=>_uploadPlaceholder()):_uploadPlaceholder())),
    if(_selectedImage!=null||(_imageUrl??'').isNotEmpty)Align(alignment:AlignmentDirectional.centerStart,child:TextButton.icon(onPressed:()=>setState((){_selectedImage=null;_imageUrl=null;_removeImage=true;}),icon:const Icon(Icons.delete_outline,color:Colors.red),label:Text(_p55(context,'إزالة الصورة','سڕینەوەی وێنە','Remove image'),style:const TextStyle(color:Colors.red)))),const SizedBox(height:10),
    Text(_p55(context,'الحالة','دۆخ','Status'),style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:8),Row(children:[Expanded(child:_StatusChoice(title:_p55(context,'متاح','بەردەست','Available'),subtitle:_p55(context,'سيظهر للعملاء','بۆ کڕیاران دەردەکەوێت','Visible to customers'),selected:_available,positive:true,onTap:()=>setState(()=>_available=true))),const SizedBox(width:10),Expanded(child:_StatusChoice(title:_p55(context,'غير متاح','بەردەست نییە','Unavailable'),subtitle:_p55(context,'لن يظهر حاليًا','ئێستا پیشان نادرێت','Hidden for now'),selected:!_available,positive:false,onTap:()=>setState(()=>_available=false)))])
  ]);

  Widget _uploadPlaceholder()=>Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.add_photo_alternate_outlined,size:48,color:AppColors.orange),const SizedBox(height:8),Text(_p55(context,'إضافة صورة المنتج','زیادکردنی وێنەی بەرهەم','Add product image'),style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:4),Text(_p55(context,'يفضل صورة واضحة وجذابة • حتى 5MB','وێنەیەکی ڕوون و جوان • تا 5MB','Prefer a clear attractive image • up to 5MB'),style:const TextStyle(color:AppColors.muted,fontSize:12))]);

  Widget _detailsStep(){
    final inventory=_usesInventory(businessType);
    final food=_isFoodCatalog(businessType);
    final drink=_isDrinkCatalog(businessType);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      _SectionTitle(title:_p55(context,'التفاصيل والسعر','وردەکاری و نرخ','Details & price')),
      _field(_price,_p55(context,_useVariants?'السعر الأساسي (اختياري مع الأحجام)':'السعر *',_useVariants?'نرخی سەرەکی (ئارەزوومەندانە)':'نرخ *',_useVariants?'Base price (optional with sizes)':'Price *'),hint:'0',keyboard:const TextInputType.numberWithOptions(decimal:true)),
      if (_supportsWeightPresets(businessType)) ...[
        Text(_p55(context,'بيع بالوزن','فرۆشتن بە کێش','Sell by weight'), style:const TextStyle(fontWeight:FontWeight.w900)),
        const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:8,children:[
          ActionChip(label:Text(_p55(context,'نصف كيلو','نیو کیلۆ','0.5 kg')),onPressed:()=>setState((){_unit='kg';_weightUnit='kg';_weightValue.text='0.5';_sizeLabel.text=_p55(context,'نصف كيلو','نیو کیلۆ','0.5 kg');})),
          ActionChip(label:Text(_p55(context,'1 كيلو','1 کیلۆ','1 kg')),onPressed:()=>setState((){_unit='kg';_weightUnit='kg';_weightValue.text='1';_sizeLabel.text=_p55(context,'1 كيلو','1 کیلۆ','1 kg');})),
          ActionChip(label:Text(_p55(context,'2 كيلو','2 کیلۆ','2 kg')),onPressed:()=>setState((){_unit='kg';_weightUnit='kg';_weightValue.text='2';_sizeLabel.text=_p55(context,'2 كيلو','2 کیلۆ','2 kg');})),
        ]),
        const SizedBox(height:14),
      ] else ...[
        Text(_p55(context,'كمية / عبوة جاهزة','بڕ / پاکەت','Pack / quantity'), style:const TextStyle(fontWeight:FontWeight.w900)),
        const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:8,children:[
          ActionChip(label:Text(_p55(context,'قطعة واحدة','1 دانە','1 piece')),onPressed:()=>setState((){_unit='piece';_sizeLabel.text=_p55(context,'قطعة واحدة','1 دانە','1 piece');})),
          ActionChip(label:Text(_p55(context,'5 قطع','5 دانە','5 pieces')),onPressed:()=>setState((){_unit='pack';_sizeLabel.text=_p55(context,'5 قطع','5 دانە','5 pieces');})),
          ActionChip(label:Text(_p55(context,'10 قطع','10 دانە','10 pieces')),onPressed:()=>setState((){_unit='pack';_sizeLabel.text=_p55(context,'10 قطع','10 دانە','10 pieces');})),
          ActionChip(label:Text(_p55(context,'12 قطعة','12 دانە','12 pieces')),onPressed:()=>setState((){_unit='pack';_sizeLabel.text=_p55(context,'12 قطعة','12 دانە','12 pieces');})),
        ]),
        const SizedBox(height:14),
      ],
      if(food)...[
        _field(_prep,_p55(context,'وقت التحضير بالدقائق','کاتی ئامادەکردن بە خولەک','Preparation time (minutes)'),hint:'30',keyboard:TextInputType.number),
        _field(_calories,_p55(context,'السعرات الحرارية (اختياري)','کالۆری (ئارەزوومەندانە)','Calories (optional)'),hint:'450',keyboard:TextInputType.number),
        Text(_p55(context,'نوع المنتج الغذائي','جۆری بەرهەمی خواردن','Food product type'),style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:10),
        Wrap(spacing:10,runSpacing:10,children:[_TypeChoice(icon:Icons.ramen_dining_rounded,label:_p55(context,'فردي','تاک','Single'),selected:_type=='single',onTap:()=>setState(()=>_type='single')),_TypeChoice(icon:Icons.groups_2_outlined,label:_p55(context,'عائلي','خێزانی','Family'),selected:_type=='family',onTap:()=>setState(()=>_type='family')),_TypeChoice(icon:Icons.local_drink_outlined,label:_p55(context,'مشروب','خواردنەوە','Drink'),selected:_type=='drink',onTap:()=>setState(()=>_type='drink'))]),const SizedBox(height:18),
      ],
      if(drink)...[
        Container(padding:const EdgeInsets.all(14),margin:const EdgeInsets.only(bottom:14),decoration:BoxDecoration(color:const Color(0xFFF6F9FF),borderRadius:BorderRadius.circular(16)),child:Row(children:[const Icon(Icons.local_drink_rounded,color:Color(0xFF4776D0)),const SizedBox(width:10),Expanded(child:Text(_p55(context,'يمكنك تسجيل الحجم والعبوة والمخزون والباركود للمشروب أدناه.','دەتوانیت قەبارە و کۆگا تۆمار بکەیت.','You can record size, package, stock and barcode below.'),style:const TextStyle(fontWeight:FontWeight.w700,color:Color(0xFF3C4657))))])),
      ],
      if(inventory)...[
        Wrap(spacing:12,runSpacing:4,children:[SizedBox(width:260,child:_field(_brand,_p55(context,'العلامة التجارية (اختياري)','براند','Brand (optional)'))),SizedBox(width:260,child:_field(_barcode,_p55(context,'الباركود (اختياري)','بارکۆد','Barcode (optional)'),keyboard:TextInputType.number)),SizedBox(width:260,child:_field(_sku,_p55(context,'رمز المنتج SKU (اختياري)','کۆدی بەرهەم','SKU (optional)')))]),
        _field(_sizeLabel,_p55(context,'الحجم / العبوة (اختياري)','قەبارە / پاکەت','Size / package (optional)'),hint:_p55(context,'مثال: 1 لتر، علبة 12 حبة','نموونە: 1 لیتر','Example: 1 L, pack of 12')),
        Row(children:[Expanded(child:DropdownButtonFormField<String>(initialValue:_unit,decoration:InputDecoration(labelText:_p55(context,'وحدة البيع','یەکە','Selling unit'),border:OutlineInputBorder(borderRadius:BorderRadius.circular(14))),items:{'piece':_p55(context,'قطعة','دانە','Piece'),'pack':_p55(context,'عبوة','پاکەت','Pack'),'box':_p55(context,'صندوق','سندوق','Box'),'bottle':_p55(context,'قنينة','بوتڵ','Bottle'),'kg':_p55(context,'كيلوغرام','کیلۆگرام','Kilogram'),'g':_p55(context,'غرام','گرام','Gram'),'l':_p55(context,'لتر','لیتر','Liter'),'ml':_p55(context,'مل','مل','ml')}.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),onChanged:(v)=>setState((){_unit=v??'piece';if(_unit=='kg'||_unit=='g')_weightUnit=_unit;}))),const SizedBox(width:12),Expanded(child:_field(_weightValue,_p55(context,'الوزن / السعة الرقمية','کێش / قەبارە','Weight / volume'),keyboard:const TextInputType.numberWithOptions(decimal:true)))]),
        SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,value:_trackStock,onChanged:(v)=>setState(()=>_trackStock=v),activeThumbColor:AppColors.orange,title:Text(_p55(context,'تتبع المخزون','شوێنکەوتنی کۆگا','Track stock'),style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text(_p55(context,'فعّله للمنتجات التي لها كمية محددة','بۆ بەرهەمە سنووردارەکان','Enable for items with limited quantity'))),
        if(_trackStock)_field(_stock,_p55(context,'الكمية المتوفرة','بڕی بەردەست','Stock quantity'),hint:'0',keyboard:const TextInputType.numberWithOptions(decimal:true)),
      ],
      if(!food && !inventory)...[_field(_brand,_p55(context,'العلامة / النوع (اختياري)','جۆر / براند','Brand / type (optional)'))],
      if(!inventory)...[
        _field(_sizeLabel,_p55(context,'الكمية / الحجم (اختياري)','بڕ / قەبارە','Quantity / size (optional)'),hint:_p55(context,'مثال: 10 قطع، 1 كيلو','نموونە: 10 دانە','Example: 10 pieces, 1 kg')),
        DropdownButtonFormField<String>(
          initialValue:_unit,
          decoration:InputDecoration(labelText:_p55(context,'وحدة البيع','یەکە','Selling unit'),border:OutlineInputBorder(borderRadius:BorderRadius.circular(14))),
          items:{'piece':_p55(context,'قطعة','دانە','Piece'),'pack':_p55(context,'عبوة / مجموعة','پاکەت','Pack'),'box':_p55(context,'صندوق','سندوق','Box'),'kg':_p55(context,'كيلوغرام','کیلۆگرام','Kilogram'),'g':_p55(context,'غرام','گرام','Gram')}.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),
          onChanged:(v)=>setState((){_unit=v??'piece';if(_unit=='kg'||_unit=='g')_weightUnit=_unit;}),
        ),
        const SizedBox(height:16),
        if(_supportsWeightPresets(businessType)) _field(_weightValue,_p55(context,'الوزن','کێش','Weight'),keyboard:const TextInputType.numberWithOptions(decimal:true)),
      ],
      _field(_tags,_p55(context,'وسوم المنتج (افصل بفاصلة)','تاگەکان','Product tags (comma separated)'),hint:_p55(context,'الأكثر طلبًا، جديد، عرض','زۆر داواکراو، نوێ','Popular, New, Offer')),
      _field(_notes,_p55(context,'ملاحظة تظهر للعميل (اختياري)','تێبینی بۆ کڕیار','Note shown to customer (optional)'),hint:_p55(context,'مثال: السعر للعبوة، المنتج طازج يوميًا، يحفظ مبردًا...','نموونە: تێبینی بۆ کڕیار','Example: pack price, baked fresh daily, keep refrigerated...'),maxLines:4)
    ]);
  }

  Widget _variantsSection()=>Container(
    padding:const EdgeInsets.all(16),
    decoration:BoxDecoration(color:const Color(0xFFF8FAFC),borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xFFE3E7ED))),
    child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      SwitchListTile.adaptive(
        contentPadding:EdgeInsets.zero,
        value:_useVariants,
        onChanged:(v)=>setState((){_useVariants=v;if(v&&_variants.isEmpty)_variants.add(_ProductVariantDraft());}),
        activeThumbColor:AppColors.orange,
        title:Text(_p55(context,'للمنتج أحجام أو خيارات بأسعار مختلفة','بەرهەمەکە قەبارە یان هەڵبژاردەی جیاواز هەیە','Product has sizes/options with different prices'),style:const TextStyle(fontWeight:FontWeight.w900)),
        subtitle:Text(_p55(context,'مثال: صغير، وسط، كبير — ولكل واحد سعره','نموونە: بچووک، ناوەند، گەورە','Example: Small, Medium, Large — each with its own price')),
      ),
      if(_useVariants)...[
        const Divider(height:20),
        ..._variants.asMap().entries.map((entry){
          final i=entry.key;final v=entry.value;
          return Container(
            key:ValueKey(v),
            margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(12),
            decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0xFFE4E7EC))),
            child:Column(children:[
              LayoutBuilder(builder:(context,c){
                final nameField=TextField(controller:v.name,decoration:InputDecoration(labelText:_p55(context,'اسم الحجم / الخيار','ناوی قەبارە','Size / option name'),hintText:_p55(context,'مثال: وسط','نموونە: ناوەند','Example: Medium'),border:OutlineInputBorder(borderRadius:BorderRadius.circular(12))));
                final priceField=TextField(controller:v.price,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:_p55(context,'السعر','نرخ','Price'),suffixText:'د.ع',border:OutlineInputBorder(borderRadius:BorderRadius.circular(12))));
                if(c.maxWidth<520)return Column(children:[nameField,const SizedBox(height:10),priceField]);
                return Row(children:[Expanded(child:nameField),const SizedBox(width:10),Expanded(child:priceField)]);
              }),
              const SizedBox(height:8),
              Row(children:[
                Expanded(child:SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,dense:true,value:v.available,onChanged:(x)=>setState(()=>v.available=x),activeThumbColor:AppColors.orange,title:Text(_p55(context,'متاح','بەردەست','Available'),style:const TextStyle(fontWeight:FontWeight.w800)))),
                IconButton(tooltip:_p55(context,'للأعلى','بۆ سەرەوە','Move up'),onPressed:i>0?()=>_moveVariant(i,i-1):null,icon:const Icon(Icons.arrow_upward_rounded)),
                IconButton(tooltip:_p55(context,'للأسفل','بۆ خوارەوە','Move down'),onPressed:i<_variants.length-1?()=>_moveVariant(i,i+1):null,icon:const Icon(Icons.arrow_downward_rounded)),
                IconButton(tooltip:_p55(context,'حذف','سڕینەوە','Delete'),onPressed:()=>_removeVariant(i),icon:const Icon(Icons.delete_outline_rounded,color:Colors.red)),
              ]),
            ]),
          );
        }),
        Align(alignment:AlignmentDirectional.centerStart,child:OutlinedButton.icon(onPressed:_addVariant,icon:const Icon(Icons.add_rounded),label:Text(_p55(context,'إضافة حجم / خيار','زیادکردنی قەبارە','Add size / option')))),
      ],
    ]),
  );

  Widget _addonsStep()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[_SectionTitle(title:_p55(context,'الإضافات والخيارات','زیادکراوە و هەڵبژاردەکان','Add-ons & options')),Text(_p55(context,'اختر الإضافات أو الخيارات المتاحة مع هذا المنتج. يمكنك إدارتها من قسم إدارة المتجر.','زیادکراوە بەردەستەکان بۆ ئەم خواردنە هەڵبژێرە.','Choose add-ons or options available with this item. Manage them from Store Management.'),style:const TextStyle(color:AppColors.muted,height:1.5)),const SizedBox(height:16),if(_loadingAddons)const Center(child:CircularProgressIndicator())else if(_addons.isEmpty)Container(padding:const EdgeInsets.all(24),decoration:BoxDecoration(color:const Color(0xFFF8F9FB),borderRadius:BorderRadius.circular(18)),child:Column(children:[const Icon(Icons.tune_rounded,size:42,color:AppColors.muted),const SizedBox(height:8),Text(_p55(context,'لا توجد إضافات مسجلة بعد','هێشتا زیادکراوە نییە','No add-ons yet'),style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:4),Text(_p55(context,'يمكنك إكمال المنتج الآن وإضافة الخيارات لاحقًا','دەتوانیت ئێستا بەردەوام بیت','You can finish now and add options later'),style:const TextStyle(color:AppColors.muted))]))else ..._addons.map((a){final id=a['id'].toString();final selected=_selectedAddonIds.contains(id);return CheckboxListTile(value:selected,onChanged:(v)=>setState(()=>v==true?_selectedAddonIds.add(id):_selectedAddonIds.remove(id)),title:Text(a['name']?.toString()??'',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${((a['price'] as num?)??0).toString()} د.ع'),activeColor:AppColors.orange,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),tileColor:selected?const Color(0xFFFFF7F0):const Color(0xFFF9FAFB));})]);

}

class _ProductVariantDraft {
  _ProductVariantDraft({String name='', double? price, this.available=true})
      : name=TextEditingController(text:name),
        price=TextEditingController(text:price==null?'':price.toStringAsFixed(price.truncateToDouble()==price?0:2));
  final TextEditingController name;
  final TextEditingController price;
  bool available;
  void dispose(){name.dispose();price.dispose();}
}

class _SectionTitle extends StatelessWidget { const _SectionTitle({required this.title});final String title;@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:18),child:Text(title,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900)));}
class _StatusChoice extends StatelessWidget { const _StatusChoice({required this.title,required this.subtitle,required this.selected,required this.positive,required this.onTap});final String title,subtitle;final bool selected,positive;final VoidCallback onTap;@override Widget build(BuildContext context)=>InkWell(onTap:onTap,borderRadius:BorderRadius.circular(16),child:Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:selected?(positive?const Color(0xFFF0FBF4):const Color(0xFFFFF5F4)):Colors.white,borderRadius:BorderRadius.circular(16),border:Border.all(color:selected?(positive?const Color(0xFF7BCB95):const Color(0xFFFFA69E)):const Color(0xFFE1E4E9))),child:Row(children:[Icon(selected?(positive?Icons.check_circle:Icons.cancel):Icons.circle_outlined,color:positive?const Color(0xFF169447):Colors.red),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w900)),Text(subtitle,style:const TextStyle(color:AppColors.muted,fontSize:11))]))])));}
class _TypeChoice extends StatelessWidget { const _TypeChoice({required this.icon,required this.label,required this.selected,required this.onTap});final IconData icon;final String label;final bool selected;final VoidCallback onTap;@override Widget build(BuildContext context)=>InkWell(onTap:onTap,borderRadius:BorderRadius.circular(16),child:Container(width:175,padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:selected?const Color(0xFFFFF5EC):Colors.white,borderRadius:BorderRadius.circular(16),border:Border.all(color:selected?AppColors.orange:const Color(0xFFE1E4E9))),child:Column(children:[Icon(icon,color:selected?AppColors.orangeDark:const Color(0xFF5A606C),size:30),const SizedBox(height:7),Text(label,style:TextStyle(fontWeight:FontWeight.w900,color:selected?AppColors.orangeDark:const Color(0xFF292D35)))])));}

class _EmptyProductsState extends StatelessWidget { const _EmptyProductsState({required this.businessType,required this.onAdd});final String businessType;final VoidCallback onAdd;@override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.all(42),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(24),border:Border.all(color:const Color(0xFFE7E9ED))),child:Column(children:[const Icon(Icons.restaurant_menu_rounded,size:60,color:Color(0xFFB6BBC5)),const SizedBox(height:12),Text(_p55(context,'لا توجد منتجات','هیچ بەرهەمێک نییە','No products yet'),style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900)),const SizedBox(height:6),Text(_p55(context,'أضف أول منتج إلى متجرك','یەکەم بەرهەم زیاد بکە','Add your first product'),style:const TextStyle(color:AppColors.muted)),const SizedBox(height:16),FilledButton.icon(onPressed:onAdd,icon:const Icon(Icons.add_rounded),label:Text(_p55(context,'إضافة منتج','زیادکردنی بەرهەم','Add product')))]));}
class _ProductsErrorState extends StatelessWidget { const _ProductsErrorState({required this.message,required this.onRetry});final String message;final VoidCallback onRetry;@override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.all(32),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20)),child:Column(children:[const Icon(Icons.error_outline_rounded,size:48,color:Colors.redAccent),const SizedBox(height:10),Text(message,textAlign:TextAlign.center),const SizedBox(height:14),OutlinedButton.icon(onPressed:onRetry,icon:const Icon(Icons.refresh_rounded),label:Text(_p55(context,'إعادة المحاولة','دووبارە هەوڵبدەوە','Retry')))]));}
