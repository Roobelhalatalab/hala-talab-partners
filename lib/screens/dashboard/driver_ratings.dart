part of 'partner_dashboard.dart';

class _DriverRatingsScreen extends StatefulWidget {
  const _DriverRatingsScreen({required this.onBack});
  final VoidCallback onBack;

  @override
  State<_DriverRatingsScreen> createState() => _DriverRatingsScreenState();
}

class _DriverRatingsScreenState extends State<_DriverRatingsScreen> {
  bool _loading = true;
  String? _error;
  int? _starsFilter;
  List<Map<String, dynamic>> _reviews = const [];

  String _txt(BuildContext context, String ar, String ku, String en) {
    final code = AppStrings.of(context).languageCode;
    if (code == 'ku') return ku;
    if (code == 'en') return en;
    return ar;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = _reviews.isEmpty; _error = null; });
    try {
      final rows = await DriverDeliveryRepository.instance.getDriverRatings();
      if (!mounted) return;
      setState(() => _reviews = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visible => _starsFilter == null
      ? _reviews
      : _reviews.where((r) => ((r['rating'] as num?)?.round() ?? 0) == _starsFilter).toList();

  double get _average => _reviews.isEmpty
      ? 0
      : _reviews.fold<double>(0, (sum, r) => sum + ((r['rating'] as num?)?.toDouble() ?? 0)) / _reviews.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back_rounded)),
        title: Text(_txt(context, 'تقييمات السائق', 'هەڵسەنگاندنەکانی شۆفێر', 'Driver ratings')),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline_rounded, size: 50, color: Color(0xFFDC2626)),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: Text(_txt(context, 'إعادة المحاولة', 'دووبارە هەوڵبدەرەوە', 'Retry'))),
                ])))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _hero(),
                      const SizedBox(height: 14),
                      _filters(),
                      const SizedBox(height: 14),
                      if (_visible.isEmpty) _empty() else ..._visible.map(_card),
                    ])))],
                  ),
                ),
    );
  }

  Widget _hero() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFFFFF3E8), Colors.white]),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFFFD7B6)),
    ),
    child: Wrap(spacing: 24, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Container(width: 86, height: 86, decoration: const BoxDecoration(color: Color(0xFFFFE8D7), shape: BoxShape.circle), child: const Icon(Icons.star_rounded, color: Color(0xFFFFA000), size: 48)),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_average <= 0 ? '—' : _average.toStringAsFixed(1), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(_txt(context, 'متوسط تقييمك', 'تێکڕای هەڵسەنگاندنت', 'Your average rating'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
      ]),
      Container(width: 1, height: 54, color: const Color(0xFFE5E7EB)),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_reviews.length}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        Text(_txt(context, 'إجمالي التقييمات', 'کۆی هەڵسەنگاندنەکان', 'Total ratings'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
      ]),
    ]),
  );

  Widget _filters() => Wrap(spacing: 8, runSpacing: 8, children: [
    FilterChip(label: Text(_txt(context, 'الكل', 'هەموو', 'All')), selected: _starsFilter == null, onSelected: (_) => setState(() => _starsFilter = null)),
    for (var stars = 5; stars >= 1; stars--)
      FilterChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Text('$stars'), const SizedBox(width: 3), const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFA000))]), selected: _starsFilter == stars, onSelected: (_) => setState(() => _starsFilter = stars)),
  ]);

  Widget _empty() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 46),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE5E7EB))),
    child: Column(children: [
      const Icon(Icons.reviews_outlined, size: 54, color: Color(0xFF9CA3AF)),
      const SizedBox(height: 12),
      Text(_txt(context, 'لا توجد تقييمات للسائق بعد', 'هێشتا هەڵسەنگاندنی شۆفێر نییە', 'No driver ratings yet'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text(_txt(context, 'ستظهر تقييمات العملاء هنا بعد إكمال التوصيلات.', 'هەڵسەنگاندنی کڕیار لێرە دەردەکەوێت دوای تەواوکردنی گەیاندن.', 'Customer ratings will appear here after completed deliveries.'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
    ]),
  );

  Widget _card(Map<String, dynamic> row) {
    final rating = ((row['rating'] as num?)?.toDouble() ?? 0).clamp(0, 5);
    final customer = _txt(context, 'عميل هلا طلب', 'کڕیاری هەلا تەلەب', 'Hala Talab customer');
    final orderId = row['order_id']?.toString() ?? '';
    final orderLabel = orderId.isEmpty ? '' : '#${orderId.length > 8 ? orderId.substring(0, 8) : orderId}';
    final comment = row['comment']?.toString().trim() ?? '';
    final date = DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(backgroundColor: Color(0xFFFFEEE2), child: Icon(Icons.person_outline_rounded, color: AppColors.orange)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(customer, style: const TextStyle(fontWeight: FontWeight.w900)), if (date != null) Text('${date.year}/${date.month.toString().padLeft(2,'0')}/${date.day.toString().padLeft(2,'0')}', style: const TextStyle(fontSize: 12, color: AppColors.muted))])),
          Row(mainAxisSize: MainAxisSize.min, children: [Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(width: 3), const Icon(Icons.star_rounded, color: Color(0xFFFFA000), size: 20)]),
        ]),
        if (comment.isNotEmpty) ...[const SizedBox(height: 12), Text(comment, style: const TextStyle(height: 1.5))],
        if (orderLabel.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [const Icon(Icons.receipt_long_outlined, size: 15, color: AppColors.muted), Text('${_txt(context, 'رقم الطلب', 'ژمارەی داواکاری', 'Order')}: $orderLabel', style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w700))])],
      ]),
    );
  }
}
