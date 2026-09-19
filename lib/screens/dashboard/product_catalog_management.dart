part of 'partner_dashboard.dart';

enum _StoreManagerMode { categories, addons, reviews }

class _StoreSimpleRecordsPage extends StatefulWidget {
  const _StoreSimpleRecordsPage({required this.storeId, required this.mode, this.initialShiftId});
  final String storeId;
  final _StoreManagerMode mode;
  final String? initialShiftId;
  @override
  State<_StoreSimpleRecordsPage> createState() => _StoreSimpleRecordsPageState();
}

class _StoreSimpleRecordsPageState extends State<_StoreSimpleRecordsPage> {
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  List<Map<String, dynamic>> _items = const [];
  final Set<String> _pendingLocalIds = <String>{};
  final Set<String> _cancelledLocalIds = <String>{};
  int _shiftMode = 1;
  List<Map<String, dynamic>> _shifts = const [];
  String? _activeShiftId;

  bool _isLocalId(String? id) {
    final value = id ?? '';
    return value.startsWith('__local_') || value.startsWith('_local_');
  }

  List<Map<String, dynamic>> _sortedCategoryScope({String? shiftId}) {
    final scoped = _items.where((item) {
      if (widget.mode != _StoreManagerMode.categories) return false;
      if (_shiftMode != 2) return true;
      final sid = item['shift_id']?.toString();
      return sid == null || sid.isEmpty || sid == shiftId;
    }).map((e) => Map<String, dynamic>.from(e)).toList();
    scoped.sort((a, b) {
      final ao = (a['sort_order'] as num?)?.toInt() ?? 999999;
      final bo = (b['sort_order'] as num?)?.toInt() ?? 999999;
      final c = ao.compareTo(bo);
      if (c != 0) return c;
      final created = (a['created_at']?.toString() ?? '').compareTo(b['created_at']?.toString() ?? '');
      if (created != 0) return created;
      return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
    });
    return scoped;
  }

  int _categoryDisplayPosition(Map<String, dynamic>? item, {String? shiftId}) {
    final scope = _sortedCategoryScope(shiftId: shiftId);
    if (item == null) return scope.length + 1;
    final id = item['id']?.toString();
    final index = scope.indexWhere((entry) => entry['id']?.toString() == id);
    return index >= 0 ? index + 1 : scope.length + 1;
  }

  String get _table => widget.mode == _StoreManagerMode.categories ? 'product_categories' : widget.mode == _StoreManagerMode.addons ? 'product_addons' : 'store_reviews';

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  Future<void> _load({bool showLoading = true}) async {
    if (mounted) setState(() { if (showLoading) _loading = true; _error = null; });
    try {
      final result = await ProductsRepository.instance.getStoreRecords(table: _table, storeId: widget.storeId);
      Map<String, dynamic>? shiftMeta;
      if (widget.mode == _StoreManagerMode.categories) {
        shiftMeta = await ProductsRepository.instance.getShiftModeAndShifts();
      }
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(result);
        if (shiftMeta != null) {
          _shiftMode = (shiftMeta['shift_mode'] as num?)?.toInt() ?? 1;
          _shifts = List<Map<String, dynamic>>.from(shiftMeta['shifts'] as List? ?? const []);
          if (_shiftMode == 2 && _shifts.isNotEmpty) {
            final preferred = widget.initialShiftId;
            final preferredExists = preferred != null && _shifts.any((e) => e['id']?.toString() == preferred);
            _activeShiftId ??= preferredExists ? preferred : _shifts.first['id']?.toString();
          } else {
            _activeShiftId = null;
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final s = AppStrings.of(context);
    if (widget.mode == _StoreManagerMode.reviews) return;
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final price = TextEditingController(text: item?['price']?.toString() ?? '0');
    final order = TextEditingController();
    bool active = item?['is_active'] != false;
    PlatformFile? categoryImage;
    String? categoryImageUrl = item?['image_url']?.toString();
    String? categoryImagePath = item?['image_path']?.toString();
    bool removeCategoryImage = false;
    int shiftMode = _shiftMode;
    List<Map<String, dynamic>> shifts = List<Map<String, dynamic>>.from(_shifts);
    String? categoryShiftId = item?['shift_id']?.toString();
    if (widget.mode == _StoreManagerMode.categories && shiftMode == 2 && shifts.isNotEmpty) {
      categoryShiftId ??= _activeShiftId ?? shifts.first['id']?.toString();
      // Legacy Stage 199 rows may only have the link table populated. Promote
      // a single old assignment in the dialog until Stage 200 migration is run.
      if (item != null && (categoryShiftId ?? '').isEmpty) {
        try {
          final assigned = await ProductsRepository.instance.getCategoryShiftIds(item['id'].toString());
          if (assigned.length == 1) categoryShiftId = assigned.first;
        } catch (e, st) {
          debugPrint('Category shift fallback unavailable: $e\n$st');
        }
      }
    }

    if (widget.mode == _StoreManagerMode.categories) {
      order.text = _categoryDisplayPosition(
        item,
        shiftId: shiftMode == 2 ? categoryShiftId : null,
      ).toString();
    }

    Future<void> pickCategoryImage(StateSetter setLocal) async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
        allowMultiple: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.bytes == null || file.size > 5 * 1024 * 1024) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_p55(context, 'الصورة يجب أن تكون أقل من 5MB', 'وێنەکە دەبێت کەمتر لە 5MB بێت', 'Image must be under 5MB'))));
        return;
      }
      final cropped = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(
        builder: (_) => PartnerImageCropEditor(
          bytes: file.bytes!,
          aspectRatio: 1,
          preserveWholeImage: true,
          title: _p55(context, 'ضبط صورة القسم', 'ڕێکخستنی وێنەی بەش', 'Adjust category image'),
        ),
      ));
      if (!mounted || cropped == null) return;
      setLocal(() {
        categoryImage = PlatformFile(name: 'category_${DateTime.now().millisecondsSinceEpoch}.png', size: cropped.length, bytes: cropped);
        removeCategoryImage = false;
      });
    }

    if (!mounted) {
      name.dispose();
      price.dispose();
      order.dispose();
      return;
    }

    final saved = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: Text(widget.mode == _StoreManagerMode.categories ? s.t('addCategory') : s.t('addAddon')),
      content: SizedBox(width: MediaQuery.sizeOf(context).width < 600 ? (MediaQuery.sizeOf(context).width - 56).clamp(240.0, 480.0).toDouble() : 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: InputDecoration(labelText: widget.mode == _StoreManagerMode.categories ? s.t('categoryName') : s.t('addonName'))),
        if (widget.mode == _StoreManagerMode.categories) ...[
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(_p55(context, 'صورة القسم', 'وێنەی بەش', 'Category image'), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => pickCategoryImage(setLocal),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFAF6),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.orange, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: categoryImage?.bytes != null
                  ? Image.memory(categoryImage!.bytes!, fit: BoxFit.cover)
                  : (!removeCategoryImage && (categoryImageUrl ?? '').isNotEmpty)
                      ? PersistentNetworkImage(url: categoryImageUrl!, fit: BoxFit.cover, cacheWidth: 720, placeholder: const Center(child: Icon(Icons.image_outlined, color: AppColors.muted, size: 32)), errorBuilder: (_, _, _) => const Center(child: Icon(Icons.add_photo_alternate_outlined, color: AppColors.orange, size: 42)))
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.add_photo_alternate_outlined, color: AppColors.orange, size: 42),
                          const SizedBox(height: 8),
                          Text(_p55(context, 'اضغط لإضافة صورة مربعة للقسم', 'بۆ زیادکردنی وێنەی چوارگۆشە کرتە بکە', 'Tap to add a square category image'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
                        ]),
            ),
          ),
          if (categoryImage?.bytes != null || (!removeCategoryImage && (categoryImageUrl ?? '').isNotEmpty))
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setLocal(() { categoryImage = null; removeCategoryImage = true; }),
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(_p55(context, 'إزالة الصورة', 'سڕینەوەی وێنە', 'Remove image')),
              ),
            ),
          Text(_p55(context, 'يمكنك تحريك الصورة وتكبيرها وتصغيرها قبل الحفظ. ستظهر للعميل داخل إطار برتقالي.', 'پێش پاشەکەوتکردن دەتوانیت وێنەکە بجوڵێنیت و گەورە/بچووک بکەیت.', 'You can move and zoom the image before saving. It will appear to customers inside an orange frame.'), style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35)),
          const SizedBox(height: 12),
          TextField(
            controller: order,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _p55(context, 'ترتيب القسم', 'ڕیزبەندی بەش', 'Category order'),
              helperText: _p55(context, '1 = أول قسم، 2 = ثاني قسم…', '1 = یەکەم بەش، 2 = دووەم بەش…', '1 = first category, 2 = second category…'),
              prefixIcon: const Icon(Icons.format_list_numbered_rounded),
            ),
          ),
        ],
        if (widget.mode == _StoreManagerMode.categories && shiftMode == 2 && shifts.length >= 2) ...[
          const SizedBox(height: 12),
          Align(alignment: AlignmentDirectional.centerStart, child: Text(_p55(context, 'شفت هذا القسم', 'شیفتی ئەم بەشە', 'Category shift'), style: const TextStyle(fontWeight: FontWeight.w900))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: shifts.map((shift) {
              final id = shift['id'].toString();
              final code = shift['shift_code']?.toString();
              final label = code == 'morning' ? _p55(context, 'الصباحي', 'بەیانی', 'Morning') : _p55(context, 'المسائي', 'ئێوارە', 'Evening');
              return ChoiceChip(
                label: Text(label),
                selected: categoryShiftId == id,
                onSelected: (_) => setLocal(() => categoryShiftId = id),
                selectedColor: const Color(0xFFFFE7D3),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(_p55(context, 'كل شفت يملك أقسامه المستقلة، ويمكن تكرار اسم القسم في شفت آخر.', 'هەر شیفتێک بەشە تایبەتەکانی خۆی هەیە.', 'Each shift has independent categories; the same name may be reused in another shift.'), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
        if (widget.mode == _StoreManagerMode.addons) ...[const SizedBox(height: 12), TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.t('addonPrice')))],
        const SizedBox(height: 8), SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setLocal(() => active = v), title: Text(s.t('activeItem'))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('save')))],
    )));
    // Capture values before disposing the transient dialog controllers. The
    // dialog Future may complete before its reverse transition has finished.
    final nameValue = name.text.trim();
    final priceValue = price.text;
    final orderValue = order.text.trim();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    name.dispose(); price.dispose(); order.dispose();
    if (!mounted || saved != true || nameValue.isEmpty) return;

    // Optimistic UI: keep the manager visible and show the saved text
    // immediately while Storage/Supabase finish in the background. If the
    // request fails we restore the exact previous list.
    final previousItems = _items.map((e) => Map<String, dynamic>.from(e)).toList();
    final optimisticId = item?['id']?.toString() ?? '__local_${DateTime.now().microsecondsSinceEpoch}';
    if (item == null) _pendingLocalIds.add(optimisticId);
    final optimistic = Map<String, dynamic>.from(item ?? const <String, dynamic>{})
      ..addAll(<String, dynamic>{
        'id': optimisticId,
        'store_id': widget.storeId,
        'name': nameValue,
        'is_active': active,
        if (widget.mode == _StoreManagerMode.categories) 'shift_id': shiftMode == 2 ? categoryShiftId : null,
        if (widget.mode == _StoreManagerMode.categories)
          'sort_order': int.tryParse(orderValue) ?? _categoryDisplayPosition(null, shiftId: shiftMode == 2 ? categoryShiftId : null),
        if (widget.mode == _StoreManagerMode.addons)
          'price': double.tryParse(priceValue.replaceAll(',', '.')) ?? 0,
      });
    setState(() {
      final existingIndex = _items.indexWhere((e) => e['id']?.toString() == optimisticId);
      final next = List<Map<String, dynamic>>.from(_items);
      if (existingIndex >= 0) {
        next[existingIndex] = optimistic;
      } else {
        next.add(optimistic);
      }
      if (widget.mode == _StoreManagerMode.categories) {
        next.sort((a, b) => ((a['sort_order'] as num?)?.toInt() ?? 999999)
            .compareTo((b['sort_order'] as num?)?.toInt() ?? 999999));
      }
      _items = next;
    });

    try {
      final payload = <String, dynamic>{'store_id': widget.storeId, 'name': nameValue, 'is_active': active};
      if (widget.mode == _StoreManagerMode.categories) {
        var imageUrl = removeCategoryImage ? null : categoryImageUrl;
        var imagePath = removeCategoryImage ? null : categoryImagePath;
        if (categoryImage?.bytes != null) {
          final uploaded = await ProductsRepository.instance.uploadCategoryImage(bytes: categoryImage!.bytes!, oldPath: categoryImagePath);
          imageUrl = uploaded['url'];
          imagePath = uploaded['path'];
        }
        payload['image_url'] = imageUrl;
        payload['image_path'] = imagePath;
        payload['shift_id'] = shiftMode == 2 ? categoryShiftId : null;
      }
      if (widget.mode == _StoreManagerMode.addons) payload['price'] = double.tryParse(priceValue.replaceAll(',', '.')) ?? 0;
      final savedRecord = await ProductsRepository.instance.saveStoreRecord(
        table: _table,
        payload: payload,
        id: item?['id']?.toString(),
      );
      if (widget.mode == _StoreManagerMode.categories) {
        final requested = int.tryParse(orderValue);
        final categoryId = savedRecord?['id']?.toString() ?? item?['id']?.toString();
        if (requested != null && requested > 0 && categoryId != null && categoryId.isNotEmpty) {
          await ProductsRepository.instance.setCategoryPosition(categoryId: categoryId, position: requested);
        }
        if (shiftMode == 2 && categoryId != null && categoryId.isNotEmpty && shifts.isNotEmpty && categoryShiftId != null) {
          await ProductsRepository.instance.setCategoryShifts(
            categoryId: categoryId,
            selectedShiftIds: {categoryShiftId!},
            allShiftIds: shifts.map((e) => e['id'].toString()).toSet(),
          );
        }
      }

      final realId = savedRecord?['id']?.toString();
      if (_cancelledLocalIds.remove(optimisticId)) {
        _pendingLocalIds.remove(optimisticId);
        // The user deleted the optimistic row before Supabase finished saving.
        // Clean up the just-created server record by its real UUID, never by
        // the temporary __local_ id.
        if (realId != null && realId.isNotEmpty) {
          await ProductsRepository.instance.deleteStoreRecord(table: _table, id: realId);
        }
        return;
      }

      if (mounted && savedRecord != null) {
        final resolved = Map<String, dynamic>.from(savedRecord);
        if (widget.mode == _StoreManagerMode.categories) {
          resolved['sort_order'] = int.tryParse(orderValue) ?? optimistic['sort_order'];
          resolved['image_url'] = payload['image_url'];
          resolved['image_path'] = payload['image_path'];
          resolved['shift_id'] = payload['shift_id'];
        }
        setState(() {
          final next = List<Map<String, dynamic>>.from(_items);
          final index = next.indexWhere((e) => e['id']?.toString() == optimisticId);
          if (index >= 0) {
            next[index] = resolved;
          } else {
            final realIndex = next.indexWhere((e) => e['id']?.toString() == realId);
            if (realIndex >= 0) next[realIndex] = resolved;
          }
          if (widget.mode == _StoreManagerMode.categories) {
            next.sort((a, b) => ((a['sort_order'] as num?)?.toInt() ?? 999999)
                .compareTo((b['sort_order'] as num?)?.toInt() ?? 999999));
          }
          _items = next;
        });
      }
      _pendingLocalIds.remove(optimisticId);
      if (widget.mode == _StoreManagerMode.categories && mounted) {
        // Re-read the server order after the shift-scoped reorder RPC. This keeps
        // the merchant's chosen order exact while the visible numbering remains
        // contiguous (1..N) inside each shift.
        await _load(showLoading: false);
      }
    } catch (e, st) {
      _pendingLocalIds.remove(optimisticId);
      final wasCancelled = _cancelledLocalIds.remove(optimisticId);
      debugPrint('Store record save failed: $e\n$st');
      if (mounted) {
        // If the user intentionally deleted the optimistic row while saving,
        // do not resurrect it on an unrelated upload/save failure.
        if (!wasCancelled) {
          setState(() => _items = previousItems);
        }
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final previousItems = _items.map((e) => Map<String, dynamic>.from(e)).toList();
    if (mounted) {
      setState(() {
        _items = _items.where((e) => e['id']?.toString() != id).toList();
      });
    }

    if (_isLocalId(id)) {
      _cancelledLocalIds.add(id);
      return;
    }

    try {
      await ProductsRepository.instance.deleteStoreRecord(table: _table, id: id);
    } catch (e) {
      if (mounted) {
        setState(() => _items = previousItems);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isCategories = widget.mode == _StoreManagerMode.categories;
    final isAddons = widget.mode == _StoreManagerMode.addons;
    final title = isCategories ? strings.t('categories') : isAddons ? strings.t('addons') : strings.t('reviews');
    final icon = isCategories ? Icons.grid_view_rounded : isAddons ? Icons.add_circle_outline_rounded : Icons.star_outline_rounded;
    final empty = isCategories ? strings.t('noCategories') : isAddons ? strings.t('noAddons') : strings.t('noReviews');
    final query = _search.trim().toLowerCase();
    final scopedItems = isCategories
        ? _sortedCategoryScope(shiftId: _activeShiftId)
        : List<Map<String, dynamic>>.from(_items);
    final categoryDisplayPositions = <String, int>{};
    if (isCategories) {
      for (var i = 0; i < scopedItems.length; i++) {
        final id = scopedItems[i]['id']?.toString();
        if (id != null && id.isNotEmpty) categoryDisplayPositions[id] = i + 1;
      }
    }
    final visibleItems = query.isEmpty
        ? scopedItems
        : scopedItems.where((item) => (item['name']?.toString() ?? '').toLowerCase().contains(query)).toList();
    final compact = MediaQuery.sizeOf(context).width < 600;

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 44),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: Text(_p55(context, 'إعادة المحاولة', 'دووبارە هەوڵبدە', 'Retry'))),
          ]),
        ),
      );
    } else if (_items.isEmpty) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: AppColors.orange, size: 54),
            const SizedBox(height: 14),
            Text(empty, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ]),
        ),
      );
    } else {
      content = Column(children: [
        if (isAddons)
          Container(
            margin: EdgeInsets.fromLTRB(compact ? 12 : 20, 14, compact ? 12 : 20, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFD9BF)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _p55(
                      context,
                      'أنشئ الإضافات العامة هنا (مثل جبن إضافي أو صوص)، ثم اربط كل إضافة بالمنتجات المناسبة فقط من شاشة إضافة/تعديل المنتج.',
                      'زیادکراوە گشتییەکان لێرە دروست بکە، پاشان لە شاشەی زیادکردن/دەستکاریکردنی بەرهەم تەنها بە بەرهەمە گونجاوەکانەوە پەیوەستیان بکە.',
                      'Create reusable add-ons here, then link each add-on only to the relevant products from the Add/Edit Product screen.',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        if (isCategories && _shiftMode == 2 && _shifts.length >= 2)
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 14, compact ? 12 : 20, 0),
            child: Row(
              children: _shifts.map((shift) {
                final id = shift['id'].toString();
                final code = shift['shift_code']?.toString();
                final label = code == 'morning' ? _p55(context, 'الشفت الصباحي', 'شیفتی بەیانی', 'Morning shift') : _p55(context, 'الشفت المسائي', 'شیفتی ئێوارە', 'Evening shift');
                final selected = _activeShiftId == id;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: SizedBox(width: double.infinity, child: Text(label, textAlign: TextAlign.center)),
                      selected: selected,
                      onSelected: (_) => setState(() => _activeShiftId = id),
                      selectedColor: const Color(0xFFFFE7D3),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 14, compact ? 12 : 20, 6),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _search = value),
            decoration: InputDecoration(
              hintText: isCategories
                  ? _p55(context, 'ابحث عن قسم...', 'بگەڕێ بۆ بەش...', 'Search categories...')
                  : _p55(context, 'ابحث...', 'بگەڕێ...', 'Search...'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: visibleItems.isEmpty
              ? Center(child: Text(_p55(context, 'لا توجد نتائج مطابقة', 'هیچ ئەنجامێکی گونجاو نییە', 'No matching results')))
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 10, compact ? 12 : 20, 96),
                  itemCount: visibleItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = visibleItems[index];
                    if (widget.mode == _StoreManagerMode.reviews) {
                      final rating = (item['rating'] as num?)?.toDouble() ?? 0;
                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8EAF0))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 6),
                            Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w900)),
                            const Spacer(),
                            Text((item['customer_name'] ?? '').toString(), style: const TextStyle(color: AppColors.muted)),
                          ]),
                          if ((item['comment'] ?? '').toString().trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(item['comment'].toString(), style: const TextStyle(height: 1.5)),
                          ],
                        ]),
                      );
                    }
                    final orderLabel = isCategories ? '#${categoryDisplayPositions[item['id']?.toString()] ?? (index + 1)}' : null;
                    final menu = PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _edit(item);
                        if (value == 'delete') _delete(item);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(_p55(context, 'تعديل', 'دەستکاری', 'Edit'))),
                        PopupMenuItem(value: 'delete', child: Text(strings.t('delete'))),
                      ],
                    );
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 6 : 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8EAF0))),
                      child: Row(children: [
                        Container(
                          width: compact ? 48 : 54,
                          height: compact ? 48 : 54,
                          decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: .08), borderRadius: BorderRadius.circular(14), border: isCategories ? Border.all(color: AppColors.orange, width: 1.2) : null),
                          clipBehavior: Clip.antiAlias,
                          child: isCategories && (item['image_url']?.toString() ?? '').isNotEmpty
                              ? PersistentNetworkImage(url: item['image_url'].toString(), fit: BoxFit.cover, cacheWidth: compact ? 280 : 420, placeholder: Icon(icon, color: AppColors.muted), errorBuilder: (_, _, _) => Icon(icon, color: AppColors.orange))
                              : Icon(icon, color: AppColors.orange),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text((item['name'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
                              if (orderLabel != null) ...[
                                const SizedBox(width: 8),
                                Text(orderLabel, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800)),
                              ],
                            ]),
                            const SizedBox(height: 3),
                            Text(isAddons ? '${item['price'] ?? 0} د.ع' : (item['is_active'] == false ? strings.t('inactive') : strings.t('active')), style: const TextStyle(color: AppColors.muted)),
                          ]),
                        ),
                        menu,
                      ]),
                    );
                  },
                ),
        ),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: widget.mode == _StoreManagerMode.reviews
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded),
              label: Text(isCategories ? strings.t('addCategory') : strings.t('addAddon')),
            ),
      body: ColoredBox(
        color: const Color(0xFFF8F9FB),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: content)),
      ),
    );
  }
}
