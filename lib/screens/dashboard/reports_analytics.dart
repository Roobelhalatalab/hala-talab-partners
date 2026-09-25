part of 'partner_dashboard.dart';

class _ReportsAnalyticsPage extends StatefulWidget {
  const _ReportsAnalyticsPage();

  @override
  State<_ReportsAnalyticsPage> createState() => _ReportsAnalyticsPageState();
}

class _ReportsAnalyticsPageState extends State<_ReportsAnalyticsPage> {
  int _days = 30;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _reviews = const [];
  Map<String, dynamic> _salesOverview = const {};

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
      final results = await Future.wait([
        ReportsRepository.instance.loadSnapshot(days: _days),
        ReportsRepository.instance.loadSalesOverview(),
      ]);
      final snapshot = results[0] as ReportsSnapshot;
      final overview = Map<String, dynamic>.from(results[1] as Map);
      final orders = snapshot.orders;
      final reviews = snapshot.reviews;
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _reviews = reviews;
        _salesOverview = overview;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _periodOrders => _orders;

  double _storeRevenue(Map<String, dynamic> order) {
    final subtotal = (order['subtotal'] as num?)?.toDouble() ?? 0;
    final discount = (order['discount_amount'] as num?)?.toDouble() ?? 0;
    return (subtotal - discount).clamp(0, double.infinity).toDouble();
  }

  double _discount(Map<String, dynamic> order) =>
      (order['discount_amount'] as num?)?.toDouble() ?? 0;

  String _money(double value, AppStrings s) {
    final rounded = value.round();
    final raw = rounded.toString();
    final chars = raw.split('').reversed.toList();
    final parts = <String>[];
    for (var i = 0; i < chars.length; i += 3) {
      final end = i + 3 < chars.length ? i + 3 : chars.length;
      parts.add(chars.sublist(i, end).reversed.join());
    }
    return '${parts.reversed.join(',')} ${s.t('currencyIqd')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final orders = _periodOrders;
    final delivered = orders.where((o) => o['status'] == 'delivered').toList();
    final cancelled = orders.where((o) => const ['cancelled', 'rejected'].contains(o['status'])).length;
    final revenue = delivered.fold<double>(0, (sum, order) => sum + _storeRevenue(order));
    final discounts = delivered.fold<double>(0, (sum, order) => sum + _discount(order));
    final activeOrders = orders.where((o) => !const ['delivered', 'cancelled', 'rejected'].contains(o['status'])).length;
    final double average = delivered.isEmpty ? 0.0 : revenue / delivered.length;
    final cancellationRate = orders.isEmpty ? 0.0 : cancelled * 100 / orders.length;
    final rating = _reviews.isEmpty
        ? 0.0
        : _reviews.fold<double>(0, (sum, item) => sum + ((item['rating'] as num?)?.toDouble() ?? 0)) / _reviews.length;
    final daily = _dailyRevenue(delivered);
    final statuses = _statusCounts(orders);
    final products = _topProducts(delivered);
    final paymentMethods = _paymentMethodCounts(orders);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 700;

    return ColoredBox(
      color: const Color(0xFFF8F9FB),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.all(_adaptivePagePadding(context)),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1250),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ModernPageHero(
                      title: s.t('reportsTitle'),
                      subtitle: s.t('reportsSubtitle'),
                      icon: Icons.insights_rounded,
                      accent: const Color(0xFF7C3AED),
                      trailing: compact
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              DropdownButton<int>(
                                value: _days,
                                underline: const SizedBox.shrink(),
                                isDense: true,
                                items: [
                                  DropdownMenuItem(value: 7, child: Text(s.t('last7Days'), style: const TextStyle(fontSize: 11))),
                                  DropdownMenuItem(value: 30, child: Text(s.t('last30Days'), style: const TextStyle(fontSize: 11))),
                                  DropdownMenuItem(value: 90, child: Text(s.t('last90Days'), style: const TextStyle(fontSize: 11))),
                                ],
                                onChanged: (next) async { if (next == null || next == _days) return; setState(() => _days = next); await _load(); },
                              ),
                              const SizedBox(width: 6),
                              IconButton.filledTonal(onPressed: _loading ? null : _load, tooltip: s.t('refreshReports'), icon: const Icon(Icons.refresh_rounded, size: 19)),
                            ])
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                SegmentedButton<int>(
                                  segments: [
                                    ButtonSegment(value: 7, label: Text(s.t('last7Days'))),
                                    ButtonSegment(value: 30, label: Text(s.t('last30Days'))),
                                    ButtonSegment(value: 90, label: Text(s.t('last90Days'))),
                                  ],
                                  selected: {_days},
                                  onSelectionChanged: (value) async { final next = value.first; if (next == _days) return; setState(() => _days = next); await _load(); },
                                ),
                                IconButton.filledTonal(onPressed: _loading ? null : _load, tooltip: s.t('refreshReports'), icon: const Icon(Icons.refresh_rounded)),
                              ],
                            ),
                    ),
                    const SizedBox(height: 20),
                    if (_loading)
                      const Padding(padding: EdgeInsets.all(70), child: Center(child: CircularProgressIndicator()))
                    else if (_error != null)
                      _ProductsErrorState(message: _error!, onRetry: _load)
                    else ...[
                      _ReportSectionCard(
                        title: s.t('salesOrdersSummary'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (compact)
                              Column(
                                children: [
                                  _PeriodSalesCard(label: s.t('todaySummary'), orders: _overviewInt('today_orders'), revenue: _overviewMoney('today_revenue'), money: (v) => _money(v, s), icon: Icons.today_rounded, accent: AppColors.orange),
                                  const SizedBox(height: 10),
                                  _PeriodSalesCard(label: s.t('weekSummary'), orders: _overviewInt('week_orders'), revenue: _overviewMoney('week_revenue'), money: (v) => _money(v, s), icon: Icons.date_range_rounded, accent: const Color(0xFF2563EB)),
                                  const SizedBox(height: 10),
                                  _PeriodSalesCard(label: s.t('monthSummary'), orders: _overviewInt('month_orders'), revenue: _overviewMoney('month_revenue'), money: (v) => _money(v, s), icon: Icons.calendar_month_rounded, accent: AppColors.green),
                                ],
                              )
                            else
                              GridView.count(
                                crossAxisCount: width >= 1180 ? 3 : 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.9,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  _PeriodSalesCard(label: s.t('todaySummary'), orders: _overviewInt('today_orders'), revenue: _overviewMoney('today_revenue'), money: (v) => _money(v, s), icon: Icons.today_rounded, accent: AppColors.orange),
                                  _PeriodSalesCard(label: s.t('weekSummary'), orders: _overviewInt('week_orders'), revenue: _overviewMoney('week_revenue'), money: (v) => _money(v, s), icon: Icons.date_range_rounded, accent: const Color(0xFF2563EB)),
                                  _PeriodSalesCard(label: s.t('monthSummary'), orders: _overviewInt('month_orders'), revenue: _overviewMoney('month_revenue'), money: (v) => _money(v, s), icon: Icons.calendar_month_rounded, accent: AppColors.green),
                                ],
                              ),
                            const SizedBox(height: 12),
                            Text(s.t('completedOnlyHint'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ReportSectionCard(
                        title: s.t('monthlyArchive'),
                        child: _MonthlySalesArchive(
                          rows: _monthlyArchive,
                          money: (value) => _money(value, s),
                          emptyText: s.t('noMonthlyArchive'),
                          ordersLabel: s.t('ordersLabel'),
                          salesLabel: s.t('salesLabel'),
                          onOpenMonth: _openMonthOrders,
                        ),
                      ),
                      const SizedBox(height: 18),
                      GridView.count(
                        crossAxisCount: width < 350 ? 1 : width >= 1180 ? 4 : 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: width < 350 ? 2.15 : width < 650 ? 1.18 : 1.8,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _MetricCard(label: s.t('totalRevenue'), value: _money(revenue, s), icon: Icons.account_balance_wallet_rounded, accent: AppColors.orange),
                          _MetricCard(label: s.t('totalOrdersMetric'), value: orders.length.toString(), icon: Icons.shopping_bag_rounded, accent: AppColors.green),
                          _MetricCard(label: s.t('averageOrderValue'), value: _money(average, s), icon: Icons.pie_chart_rounded, accent: const Color(0xFF2563EB)),
                          _MetricCard(label: s.t('storeRatingMetric'), value: rating <= 0 ? '—' : rating.toStringAsFixed(1), icon: Icons.star_rounded, accent: const Color(0xFF7C3AED)),
                        ],
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(builder: (context, constraints) {
                        final twoColumns = constraints.maxWidth >= 900;
                        final chart = _ReportSectionCard(
                          title: s.t('salesTrend'),
                          child: _SalesBars(data: daily, money: (value) => _money(value, s)),
                        );
                        final status = _ReportSectionCard(
                          title: s.t('orderStatusBreakdown'),
                          child: _StatusBreakdown(counts: statuses),
                        );
                        if (twoColumns) {
                          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: chart), const SizedBox(width: 16), Expanded(flex: 2, child: status)]);
                        }
                        return Column(children: [chart, const SizedBox(height: 16), status]);
                      }),
                      const SizedBox(height: 18),
                      _ReportSectionCard(
                        title: s.t('topSellingProducts'),
                        child: products.isEmpty
                            ? _ReportEmpty(s: s)
                            : Column(children: products.take(8).map((item) => _TopProductRow(item: item, money: (value) => _money(value, s))).toList()),
                      ),
                      const SizedBox(height: 18),
                      _ReportSectionCard(
                        title: s.t('paymentMethodsMetric'),
                        child: _PaymentMethodsBreakdown(counts: paymentMethods),
                      ),
                      const SizedBox(height: 18),
                      _ReportSectionCard(
                        title: s.t('quickNumbers'),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _AnalyticsQuickChip(icon: Icons.task_alt_rounded, label: s.t('completedOrdersMetric'), value: delivered.length.toString()),
                            _AnalyticsQuickChip(icon: Icons.pending_actions_rounded, label: s.t('activeOrdersMetric'), value: activeOrders.toString()),
                            _AnalyticsQuickChip(
                              icon: Icons.rate_review_rounded,
                              label: s.t('reviewsCountMetric'),
                              value: _reviews.length.toString(),
                              onTap: _openRatings,
                            ),
                            _AnalyticsQuickChip(icon: Icons.cancel_outlined, label: s.t('cancellationRate'), value: '${cancellationRate.toStringAsFixed(1)}%'),
                            _AnalyticsQuickChip(icon: Icons.discount_rounded, label: s.t('totalDiscountsMetric'), value: _money(discounts, s)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  int _overviewInt(String key) => int.tryParse((_salesOverview[key] ?? 0).toString()) ?? 0;

  double _overviewMoney(String key) => double.tryParse((_salesOverview[key] ?? 0).toString()) ?? 0;

  List<Map<String, dynamic>> get _monthlyArchive {
    final raw = _salesOverview['monthly_archive'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }


  Future<void> _openMonthOrders(Map<String, dynamic> row) async {
    final raw = (row['month_start'] ?? '').toString();
    final month = DateTime.tryParse(raw)?.toLocal();
    if (month == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MonthlyOrdersPage(
          month: DateTime(month.year, month.month),
          monthLabel: _monthNameForContext(context, month),
          money: (value) => _money(value, AppStrings.of(context)),
        ),
      ),
    );
  }

  String _monthNameForContext(BuildContext context, DateTime date) {
    const ar = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
    const en = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    const ku = ['کانوونی دووەم','شوبات','ئازار','نیسان','ئایار','حوزەیران','تەمموز','ئاب','ئەیلوول','تشرینی یەکەم','تشرینی دووەم','کانوونی یەکەم'];
    final lang = AppStrings.of(context).languageCode;
    final names = lang == 'en' ? en : lang == 'ku' ? ku : ar;
    return '${names[date.month - 1]} ${date.year}';
  }

  Future<void> _openRatings() async {
    final s = AppStrings.of(context);
    final store = await AuthService.instance.getCurrentStore();
    if (!mounted) return;
    final storeId = store?['id']?.toString();
    if (storeId == null || storeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.t('storeSetupRequired'))),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _RatingsManagementPage(storeId: storeId)),
    );
    if (mounted) {
      await _load();
    }
  }

  List<Map<String, dynamic>> _dailyRevenue(List<Map<String, dynamic>> orders) {
    final now = DateTime.now();
    final daysToShow = _days == 7 ? 7 : 10;
    final result = <Map<String, dynamic>>[];
    for (var i = daysToShow - 1; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i * (_days == 7 ? 1 : (_days / daysToShow).ceil())));
      final next = date.add(Duration(days: _days == 7 ? 1 : (_days / daysToShow).ceil()));
      final total = orders.where((order) {
        final created = DateTime.tryParse(order['created_at']?.toString() ?? '')?.toLocal();
        return created != null && !created.isBefore(date) && created.isBefore(next);
      }).fold<double>(0, (sum, order) => sum + _storeRevenue(order));
      result.add({'label': '${date.day}/${date.month}', 'value': total});
    }
    return result;
  }

  Map<String, int> _statusCounts(List<Map<String, dynamic>> orders) {
    final counts = <String, int>{};
    for (final order in orders) {
      final status = order['status']?.toString() ?? 'pending';
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> _paymentMethodCounts(List<Map<String, dynamic>> orders) {
    final counts = <String, int>{};
    for (final order in orders) {
      final raw = (order['payment_method']?.toString() ?? 'cash').trim().toLowerCase();
      final key = raw.isEmpty ? 'cash' : raw;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  List<Map<String, dynamic>> _topProducts(List<Map<String, dynamic>> orders) {
    final aggregate = <String, Map<String, dynamic>>{};
    for (final order in orders) {
      final items = (order['order_items'] as List?) ?? const [];
      for (final raw in items) {
        final item = Map<String, dynamic>.from(raw as Map);
        final name = orderItemDisplayName(item);
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        final revenue = (item['total_price'] as num?)?.toDouble() ??
            quantity * ((item['unit_price'] as num?)?.toDouble() ?? 0);
        final current = aggregate.putIfAbsent(name, () => {'name': name, 'quantity': 0, 'revenue': 0.0});
        current['quantity'] = (current['quantity'] as int) + quantity;
        current['revenue'] = (current['revenue'] as double) + revenue;
      }
    }
    final values = aggregate.values.toList();
    values.sort((a, b) => (b['quantity'] as int).compareTo(a['quantity'] as int));
    return values;
  }
}

class _PeriodSalesCard extends StatelessWidget {
  const _PeriodSalesCard({required this.label, required this.orders, required this.revenue, required this.money, required this.icon, required this.accent});
  final String label;
  final int orders;
  final double revenue;
  final String Function(double) money;
  final IconData icon;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(compact ? 15 : 18), border: Border.all(color: const Color(0xFFE7EAF0))),
      child: Row(children: [
        Container(width: compact ? 42 : 48, height: compact ? 42 : 48, decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(compact ? 12 : 14)), child: Icon(icon, color: accent, size: compact ? 21 : 24)),
        SizedBox(width: compact ? 10 : 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 13 : 15)),
          SizedBox(height: compact ? 5 : 7),
          Text('${s.t('ordersLabel')}: $orders', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 12 : 14)),
          const SizedBox(height: 3),
          Text('${s.t('salesLabel')}: ${money(revenue)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: compact ? 12 : 14)),
        ])),
      ]),
    );
  }
}

class _MonthlySalesArchive extends StatelessWidget {
  const _MonthlySalesArchive({
    required this.rows,
    required this.money,
    required this.emptyText,
    required this.ordersLabel,
    required this.salesLabel,
    required this.onOpenMonth,
  });

  final List<Map<String, dynamic>> rows;
  final String Function(double) money;
  final String emptyText;
  final String ordersLabel;
  final String salesLabel;
  final Future<void> Function(Map<String, dynamic> row) onOpenMonth;

  String _monthLabel(BuildContext context, String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    const ar = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
    const en = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    const ku = ['کانوونی دووەم','شوبات','ئازار','نیسان','ئایار','حوزەیران','تەمموز','ئاب','ئەیلوول','تشرینی یەکەم','تشرینی دووەم','کانوونی یەکەم'];
    final lang = AppStrings.of(context).languageCode;
    final names = lang == 'en' ? en : lang == 'ku' ? ku : ar;
    return '${names[date.month - 1]} ${date.year}';
  }

  String _openLabel(BuildContext context) {
    final lang = AppStrings.of(context).languageCode;
    return lang == 'en' ? 'Open' : lang == 'ku' ? 'کردنەوە' : 'فتح';
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(emptyText, style: const TextStyle(color: AppColors.muted))),
      );
    }
    return Column(children: rows.map((row) {
      final orders = int.tryParse((row['orders_count'] ?? 0).toString()) ?? 0;
      final revenue = double.tryParse((row['revenue'] ?? 0).toString()) ?? 0;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFE8EAF0)),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final details = Column(
            crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Text('$ordersLabel: $orders', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: compact ? 12 : 14)),
              const SizedBox(height: 4),
              Text('$salesLabel: ${money(revenue)}', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.green, fontSize: compact ? 12 : 14)),
            ],
          );
          final openButton = FilledButton.tonalIcon(
            onPressed: () => onOpenMonth(row),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(_openLabel(context)),
          );
          if (compact) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const CircleAvatar(backgroundColor: Color(0xFFFFEEE2), child: Icon(Icons.calendar_month_rounded, color: AppColors.orange)),
                const SizedBox(width: 10),
                Expanded(child: Text(_monthLabel(context, (row['month_start'] ?? '').toString()), style: const TextStyle(fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 10),
              details,
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: openButton),
            ]);
          }
          return Row(children: [
            const CircleAvatar(backgroundColor: Color(0xFFFFEEE2), child: Icon(Icons.calendar_month_rounded, color: AppColors.orange)),
            const SizedBox(width: 12),
            Expanded(child: Text(_monthLabel(context, (row['month_start'] ?? '').toString()), style: const TextStyle(fontWeight: FontWeight.w900))),
            details,
            const SizedBox(width: 16),
            openButton,
          ]);
        }),
      );
    }).toList());
  }
}

class _MonthlyOrdersPage extends StatefulWidget {
  const _MonthlyOrdersPage({
    required this.month,
    required this.monthLabel,
    required this.money,
  });

  final DateTime month;
  final String monthLabel;
  final String Function(double) money;

  @override
  State<_MonthlyOrdersPage> createState() => _MonthlyOrdersPageState();
}

class _MonthlyOrdersPageState extends State<_MonthlyOrdersPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = const [];

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
      final orders = await ReportsRepository.instance.loadMonthOrders(widget.month);
      if (!mounted) return;
      setState(() => _orders = orders);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _localized(BuildContext context, String ar, String ku, String en) {
    final lang = AppStrings.of(context).languageCode;
    return lang == 'en' ? en : lang == 'ku' ? ku : ar;
  }

  String _date(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return '—';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}  ${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _openDetails(Map<String, dynamic> order) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _OrderDetailsDialog(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Text('${_localized(context, 'طلبات', 'داواکارییەکانی', 'Orders for')} ${widget.monthLabel}'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: s.t('refreshReports'),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [SizedBox(height: 180), Center(child: CircularProgressIndicator())])
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: [_ProductsErrorState(message: _error!, onRetry: _load)],
                  )
                : _orders.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          const SizedBox(height: 100),
                          const Icon(Icons.receipt_long_outlined, size: 58, color: Color(0xFFB6BBC5)),
                          const SizedBox(height: 12),
                          Text(
                            _localized(context, 'لا توجد طلبات في هذا الشهر', 'لەو مانگەدا هیچ داواکارییەک نییە', 'No orders in this month'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _orders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final order = _orders[index];
                          final number = (order['order_number'] ?? '').toString();
                          final total = (order['total'] as num?)?.toDouble() ?? 0;
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              onTap: () => _openDetails(order),
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: const Color(0xFFE7E9ED)),
                                ),
                                child: Row(children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: AppColors.orange.withValues(alpha: .10),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(Icons.receipt_long_rounded, color: AppColors.orange),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Expanded(
                                            child: Text(
                                              '${s.t('orderNumber')} #$number',
                                              style: const TextStyle(fontWeight: FontWeight.w900),
                                            ),
                                          ),
                                          _OrderStatusBadge(status: order['status']?.toString() ?? 'pending'),
                                        ]),
                                        const SizedBox(height: 6),
                                        Text(_date(order['created_at']), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 5),
                                        Text(widget.money(total), style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w900)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class _AnalyticsQuickChip extends StatelessWidget {
  const _AnalyticsQuickChip({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minWidth: 210),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFE4D1)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AppColors.orange, size: 20),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ]),
              if (onTap != null) ...[
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.muted),
              ],
            ]),
          ),
        ),
      );
}

class _ReportSectionCard extends StatelessWidget {
  const _ReportSectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
        side: const BorderSide(color: Color(0xFFE7E9ED)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TextStyle(fontSize: compact ? 16 : 20, fontWeight: FontWeight.w900)),
            SizedBox(height: compact ? 12 : 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _SalesBars extends StatelessWidget {
  const _SalesBars({required this.data, required this.money});
  final List<Map<String, dynamic>> data;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final maxValue = data.fold<double>(0, (max, item) {
      final value = (item['value'] as num).toDouble();
      return value > max ? value : max;
    });
    return SizedBox(
      height: 245,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((item) {
          final value = (item['value'] as num).toDouble();
          final height = maxValue <= 0 ? 8.0 : 170 * value / maxValue + 8;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(message: money(value), child: AnimatedContainer(duration: const Duration(milliseconds: 250), height: height, decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: .82), borderRadius: const BorderRadius.vertical(top: Radius.circular(8))))),
                  const SizedBox(height: 8),
                  FittedBox(child: Text(item['label'].toString(), style: const TextStyle(fontSize: 11, color: AppColors.muted))),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.counts});
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final rows = <(String, String, Color)>[
      ('pending', s.t('pendingStatus'), AppColors.orange),
      ('accepted', s.t('acceptedStatus'), const Color(0xFF2563EB)),
      ('preparing', s.t('preparingStatus'), const Color(0xFF7C3AED)),
      ('ready', s.t('readyStatus'), const Color(0xFF0891B2)),
      ('assigned', s.t('assignedStatusMetric'), const Color(0xFF0F766E)),
      ('picked_up', s.t('pickedUpStatusMetric'), const Color(0xFF0369A1)),
      ('delivered', s.t('deliveredStatus'), AppColors.green),
      ('cancelled', s.t('cancelledStatus'), const Color(0xFFDC2626)),
    ];
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return Column(
      children: rows.map((row) {
        final count = row.$1 == 'cancelled' ? (counts['cancelled'] ?? 0) + (counts['rejected'] ?? 0) : counts[row.$1] ?? 0;
        final ratio = total == 0 ? 0.0 : count / total;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(children: [Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: row.$3, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text(row.$2, style: const TextStyle(fontWeight: FontWeight.w700))), Text('$count', style: const TextStyle(fontWeight: FontWeight.w900))]), const SizedBox(height: 7), LinearProgressIndicator(value: ratio, minHeight: 7, borderRadius: BorderRadius.circular(10), color: row.$3, backgroundColor: row.$3.withValues(alpha: .10))]),
        );
      }).toList(),
    );
  }
}

class _TopProductRow extends StatelessWidget {
  const _TopProductRow({required this.item, required this.money});
  final Map<String, dynamic> item;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final meta = compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${s.t('soldQuantity')}: ${item['quantity']}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(money((item['revenue'] as num).toDouble()), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.green)),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${s.t('soldQuantity')}: ${item['quantity']}', style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(width: 18),
                    Text(money((item['revenue'] as num).toDouble()), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.green)),
                  ],
                );
          return Row(
            children: [
              const CircleAvatar(backgroundColor: Color(0xFFFFEEE2), child: Icon(Icons.restaurant_menu_rounded, color: AppColors.orange)),
              const SizedBox(width: 12),
              Expanded(child: Text(item['name'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
              const SizedBox(width: 8),
              meta,
            ],
          );
        },
      ),
    );
  }
}

class _PaymentMethodsBreakdown extends StatelessWidget {
  const _PaymentMethodsBreakdown({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final cash = counts.entries
        .where((entry) => entry.key == 'cash' || entry.key == 'cod')
        .fold<int>(0, (sum, entry) => sum + entry.value);
    final electronic = counts.entries
        .where((entry) => entry.key != 'cash' && entry.key != 'cod')
        .fold<int>(0, (sum, entry) => sum + entry.value);
    final total = cash + electronic;

    if (total == 0) {
      return Text(
        s.t('noPaymentDataMetric'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
      );
    }

    Widget row(IconData icon, String label, int value, Color color) {
      final ratio = total == 0 ? 0.0 : value / total;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
                Text('$value', style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              borderRadius: BorderRadius.circular(12),
              color: color,
              backgroundColor: color.withValues(alpha: .10),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        row(Icons.payments_outlined, s.t('cashPaymentMetric'), cash, AppColors.green),
        row(Icons.credit_card_rounded, s.t('electronicPaymentMetric'), electronic, const Color(0xFF2563EB)),
      ],
    );
  }
}

class _ReportEmpty extends StatelessWidget {
  const _ReportEmpty({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Column(children: [const Icon(Icons.query_stats_rounded, size: 56, color: Color(0xFFB6BBC5)), const SizedBox(height: 12), Text(s.t('noReportData'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text(s.t('reportDataHint'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted))]),
      );
}
