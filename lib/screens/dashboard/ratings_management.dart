part of 'partner_dashboard.dart';

class _RatingsManagementPage extends StatefulWidget {
  const _RatingsManagementPage({required this.storeId});
  final String storeId;

  @override
  State<_RatingsManagementPage> createState() => _RatingsManagementPageState();
}

class _RatingsManagementPageState extends State<_RatingsManagementPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _storeReviews = const [];
  List<Map<String, dynamic>> _productReviews = const [];
  int? _starsFilter;
  int _tab = 0;
  String? _productFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await RatingsRepository.instance.load();
      if (!mounted) return;
      setState(() {
        _storeReviews = snapshot.storeReviews;
        _productReviews = snapshot.productReviews;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _activeReviews =>
      _tab == 0 ? _storeReviews : _productReviews;

  List<Map<String, dynamic>> get _visible {
    var rows = _activeReviews;
    if (_starsFilter != null) {
      rows = rows
          .where((r) => ((r['rating'] as num?)?.round() ?? 0) == _starsFilter)
          .toList();
    }
    if (_tab == 1 && _productFilter != null) {
      rows = rows
          .where((r) => r['product_id']?.toString() == _productFilter)
          .toList();
    }
    return rows;
  }

  double _averageOf(List<Map<String, dynamic>> rows) => rows.isEmpty
      ? 0
      : rows.fold<double>(
              0,
              (sum, r) => sum + ((r['rating'] as num?)?.toDouble() ?? 0),
            ) /
          rows.length;

  int _count(List<Map<String, dynamic>> rows, int stars) => rows
      .where((r) => ((r['rating'] as num?)?.round() ?? 0) == stars)
      .length;

  Map<String, String> get _productChoices {
    final result = <String, String>{};
    for (final row in _productReviews) {
      final id = row['product_id']?.toString();
      if (id == null || id.isEmpty) continue;
      final name = row['product_name']?.toString().trim();
      result[id] = (name == null || name.isEmpty) ? 'منتج' : name;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('reviews')),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ColoredBox(
        color: const Color(0xFFF8F9FB),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 48, color: Color(0xFFDC2626)),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1050),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _ratingsHero(),
                                const SizedBox(height: 14),
                                _tabSelector(),
                                const SizedBox(height: 14),
                                _filters(),
                                const SizedBox(height: 14),
                                if (_visible.isEmpty)
                                  _emptyState(s)
                                else
                                  ..._visible.map(_reviewCard),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _ratingsHero() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final firstPanelWidth = screenWidth < 520
        ? (screenWidth - 72).clamp(240.0, 330.0).toDouble()
        : 330.0;
    final secondPanelWidth = screenWidth < 520
        ? (screenWidth - 72).clamp(240.0, 390.0).toDouble()
        : 390.0;
    final rows = _activeReviews;
    final average = _averageOf(rows);
    final title = _tab == 0 ? 'تقييم المتجر' : 'تقييم المنتجات';
    final subtitle = _tab == 0
        ? 'تابع تجربة العملاء مع متجرك بشكل مباشر.'
        : 'اعرف المنتجات الأعلى والأقل تقييمًا من العملاء.';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF5EB), Colors.white],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFFFD8B8)),
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: firstPanelWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                        height: 1.45)),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Color(0xFFF59E0B), size: 36),
                    const SizedBox(width: 8),
                    Text(average.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 34, fontWeight: FontWeight.w900)),
                  ],
                ),
                Text('${rows.length} تقييم',
                    style: const TextStyle(
                        color: AppColors.muted, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          SizedBox(
            width: secondPanelWidth,
            child: Column(
              children: [
                for (int stars = 5; stars >= 1; stars--)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text('$stars',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        const Icon(Icons.star_rounded,
                            size: 15, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: rows.isEmpty
                                ? 0
                                : _count(rows, stars) / rows.length,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 30,
                          child: Text('${_count(rows, stars)}'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabSelector() {
    Widget tab({required int index, required IconData icon, required String label, required int count}) {
      final selected = _tab == index;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() {
            _tab = index;
            _starsFilter = null;
            _productFilter = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: selected ? AppColors.orange : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected ? AppColors.orange : const Color(0xFFE8EAF0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: selected ? Colors.white : AppColors.orange),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('$label ($count)',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: selected ? Colors.white : const Color(0xFF111827),
                          fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(
            index: 0,
            icon: Icons.storefront_rounded,
            label: 'المتجر',
            count: _storeReviews.length),
        const SizedBox(width: 10),
        tab(
            index: 1,
            icon: Icons.inventory_2_outlined,
            label: 'المنتجات',
            count: _productReviews.length),
      ],
    );
  }

  Widget _filters() {
    final productChoices = _productChoices;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EAF0)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('التصفية:', style: TextStyle(fontWeight: FontWeight.w900)),
          ChoiceChip(
            label: const Text('الكل'),
            selected: _starsFilter == null,
            onSelected: (_) => setState(() => _starsFilter = null),
          ),
          for (int stars = 5; stars >= 1; stars--)
            ChoiceChip(
              label: Text('$stars ★'),
              selected: _starsFilter == stars,
              onSelected: (_) => setState(() => _starsFilter = stars),
            ),
          if (_tab == 1 && productChoices.isNotEmpty) ...[
            const SizedBox(width: 8),
            DropdownButton<String?>(
              value: _productFilter,
              hint: const Text('كل المنتجات'),
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('كل المنتجات')),
                ...productChoices.entries.map(
                  (e) => DropdownMenuItem<String?>(
                    value: e.key,
                    child: SizedBox(
                        width: 180,
                        child: Text(e.value, overflow: TextOverflow.ellipsis)),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _productFilter = value),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState(AppStrings s) => Container(
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE8EAF0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.reviews_outlined,
                size: 52, color: AppColors.orange),
            const SizedBox(height: 12),
            Text(s.t('noReviews'),
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(
              _tab == 0
                  ? 'ستظهر تقييمات العملاء للمتجر هنا عند وصولها.'
                  : 'ستظهر تقييمات المنتجات هنا بعد أن يقيم العملاء مشترياتهم.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );

  Widget _reviewCard(Map<String, dynamic> item) {
    final rating = (item['rating'] as num?)?.toDouble() ?? 0;
    final created =
        DateTime.tryParse(item['created_at']?.toString() ?? '')?.toLocal();
    final comment = (item['comment'] ?? '').toString().trim();
    final productName = (item['product_name'] ?? '').toString().trim();
    final productImage = (item['product_image_url'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFFFF1E6),
                child: const Icon(Icons.person_outline_rounded,
                    color: AppColors.orange),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((item['customer_name'] ?? 'عميل هلا طلب').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    if (created != null)
                      Text('${created.year}/${created.month}/${created.day}',
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E8),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 17, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    Text(rating.toStringAsFixed(1),
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
          if (_tab == 1 && productName.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  if (productImage.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: PersistentNetworkImage(url: productImage,
                          width: 44,
                          height: 44,
                          cacheWidth: 132,
                          fit: BoxFit.cover,
                          placeholder: _productIcon(),
                          errorBuilder: (_, _, _) => _productIcon()),
                    )
                  else
                    _productIcon(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(productName,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ],
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(comment,
                style:
                    const TextStyle(height: 1.55, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  Widget _productIcon() => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.inventory_2_outlined, color: AppColors.orange),
      );
}
