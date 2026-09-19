part of 'partner_dashboard.dart';

class _DriverDeliveryHistoryScreen extends StatefulWidget {
  const _DriverDeliveryHistoryScreen({required this.onBack});
  final VoidCallback onBack;

  @override
  State<_DriverDeliveryHistoryScreen> createState() => _DriverDeliveryHistoryScreenState();
}

class _DriverDeliveryHistoryScreenState extends State<_DriverDeliveryHistoryScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};
  String _statusFilter = 'all';
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = _data.isEmpty; _error = null; });
    try {
      final data = await DriverDeliveryRepository.instance.getDeliveryHistory();
      if (!mounted) return;
      setState(() => _data = data);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code == 'PGRST202'
          ? AppStrings.of(context).t('driverStage13SqlRequired')
          : e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _int(String key) => int.tryParse((_data[key] ?? 0).toString()) ?? 0;
  double _num(String key) => double.tryParse((_data[key] ?? 0).toString()) ?? 0;
  String _money(num value) => '${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)} د.ع';

  List<Map<String, dynamic>> get _filteredOrders {
    final raw = (_data['orders'] as List?) ?? const [];
    final rows = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final now = DateTime.now();
    return rows.where((row) {
      final status = row['status']?.toString() ?? '';
      final statusOk = switch (_statusFilter) {
        'completed' => status == 'delivered',
        'cancelled' => status == 'cancelled' || status == 'canceled',
        'incomplete' => status != 'delivered' && status != 'cancelled' && status != 'canceled',
        _ => true,
      };
      if (!statusOk) return false;
      if (_days <= 0) return true;
      final rawDate = row['happened_at']?.toString();
      final date = rawDate == null ? null : DateTime.tryParse(rawDate)?.toLocal();
      if (date == null) return true;
      return date.isAfter(now.subtract(Duration(days: _days)));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1180 : 720),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(children: [
                    IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back_rounded)),
                    Expanded(child: Text(s.t('driverDeliveryHistoryTitle'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
                    IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
                  ]),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _errorView(s)
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                padding: EdgeInsets.fromLTRB(wide ? 22 : 14, 8, wide ? 22 : 14, 30),
                                children: [
                                  _filters(s),
                                  const SizedBox(height: 12),
                                  _summary(s, wide),
                                  const SizedBox(height: 14),
                                  _dateFilter(s),
                                  const SizedBox(height: 12),
                                  if (_filteredOrders.isEmpty)
                                    _emptyState(s)
                                  else
                                    ..._filteredOrders.map((row) => Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: InkWell(borderRadius: BorderRadius.circular(20), onTap: () => _showOrderDetails(s, row), child: _orderCard(s, row)),
                                    )),
                                ],
                              ),
                            ),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }

  Widget _errorView(AppStrings s) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 42, color: AppColors.orange),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: _load, child: Text(s.t('retry'))),
          ]),
        ),
      );

  Widget _filters(AppStrings s) {
    final items = <(String, String)>[
      ('all', s.t('driverHistoryAll')),
      ('completed', s.t('driverHistoryCompleted')),
      ('cancelled', s.t('driverHistoryCancelled')),
      ('incomplete', s.t('driverHistoryIncomplete')),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items.map((item) {
        final selected = _statusFilter == item.$1;
        return Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: ChoiceChip(
            selected: selected,
            onSelected: (_) => setState(() => _statusFilter = item.$1),
            label: Text(item.$2),
            selectedColor: const Color(0xFFFFEBDD),
            side: BorderSide(color: selected ? AppColors.orange : const Color(0xFFE0E3E8)),
            labelStyle: TextStyle(color: selected ? AppColors.orange : const Color(0xFF373A40), fontWeight: FontWeight.w800),
          ),
        );
      }).toList()),
    );
  }

  Widget _summary(AppStrings s, bool wide) {
    final cards = [
      (Icons.task_alt_rounded, s.t('driverHistoryCompletedOrders'), _int('completed_orders').toString(), const Color(0xFF20A747)),
      (Icons.shopping_bag_outlined, s.t('driverHistoryTotalOrders'), _int('total_orders').toString(), AppColors.orange),
      (Icons.account_balance_wallet_outlined, s.t('driverHistoryTotalEarnings'), _money(_num('total_earnings')), const Color(0xFF7E57C2)),
      (Icons.trending_up_rounded, s.t('driverHistoryAcceptanceRate'), '${_num('acceptance_rate').toStringAsFixed(_num('acceptance_rate') % 1 == 0 ? 0 : 1)}%', const Color(0xFF2878E8)),
    ];
    if (wide) {
      return Row(children: List.generate(cards.length, (i) => Expanded(child: Padding(
        padding: EdgeInsetsDirectional.only(end: i == cards.length - 1 ? 0 : 10),
        child: _summaryCard(cards[i].$1, cards[i].$2, cards[i].$3, cards[i].$4),
      ))));
    }
    return Column(children: [
      Row(children: [Expanded(child: _summaryCard(cards[0].$1, cards[0].$2, cards[0].$3, cards[0].$4)), const SizedBox(width: 10), Expanded(child: _summaryCard(cards[1].$1, cards[1].$2, cards[1].$3, cards[1].$4))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: _summaryCard(cards[2].$1, cards[2].$2, cards[2].$3, cards[2].$4)), const SizedBox(width: 10), Expanded(child: _summaryCard(cards[3].$1, cards[3].$2, cards[3].$3, cards[3].$4))]),
    ]);
  }

  Widget _summaryCard(IconData icon, String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8EAF0))),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w700)),
          ])),
        ]),
      );

  Widget _dateFilter(AppStrings s) => Row(children: [
        Text(s.t('driverHistoryPeriod'), style: const TextStyle(fontWeight: FontWeight.w900)),
        const Spacer(),
        DropdownButton<int>(
          value: _days,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(14),
          items: [
            DropdownMenuItem(value: 7, child: Text(s.t('driverHistoryLast7Days'))),
            DropdownMenuItem(value: 30, child: Text(s.t('driverHistoryLast30Days'))),
            DropdownMenuItem(value: 90, child: Text(s.t('driverHistoryLast90Days'))),
            DropdownMenuItem(value: 0, child: Text(s.t('driverHistoryAllTime'))),
          ],
          onChanged: (value) { if (value != null) setState(() => _days = value); },
        ),
      ]);

  Widget _emptyState(AppStrings s) => Container(
        padding: const EdgeInsets.symmetric(vertical: 54, horizontal: 20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8EAF0))),
        child: Column(children: [
          const Icon(Icons.receipt_long_outlined, size: 54, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(s.t('driverHistoryEmpty'), style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(s.t('driverHistoryEmptySubtitle'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        ]),
      );

  Widget _orderCard(AppStrings s, Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';
    final delivered = status == 'delivered';
    final cancelled = status == 'cancelled' || status == 'canceled';
    final statusColor = delivered ? const Color(0xFF20A747) : cancelled ? const Color(0xFFE94B4B) : AppColors.orange;
    final statusLabel = delivered
        ? s.t('driverHistoryCompleted')
        : cancelled
            ? s.t('driverHistoryCancelled')
            : s.t('driverHistoryIncomplete');
    final number = row['order_number']?.toString() ?? '—';
    final storeName = row['store_name']?.toString() ?? '—';
    final storeAddress = row['store_address']?.toString() ?? '—';
    final customerName = row['customer_name']?.toString() ?? '—';
    final customerAddress = row['delivery_address']?.toString() ?? '—';
    final payment = row['payment_method']?.toString() ?? '—';
    final earning = double.tryParse((row['earning'] ?? 0).toString()) ?? 0;
    final date = _formatDate(row['happened_at']?.toString());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8EAF0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('#$number', style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(width: 10),
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: statusColor.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)), child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 11))),
          const Spacer(),
          Text(date, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
        ]),
        const Divider(height: 24),
        _placeRow(Icons.storefront_rounded, AppColors.orange, storeName, storeAddress),
        const SizedBox(height: 12),
        _placeRow(Icons.person_outline_rounded, const Color(0xFF20A747), customerName, customerAddress),
        const Divider(height: 24),
        Row(children: [
          Expanded(child: _miniInfo(Icons.payments_outlined, s.t('driverHistoryPayment'), _paymentLabel(s, payment))),
          const SizedBox(width: 10),
          Expanded(child: _miniInfo(Icons.account_balance_wallet_outlined, s.t('driverHistoryEarning'), _money(earning), valueColor: delivered ? const Color(0xFF20A747) : AppColors.muted)),
        ]),
      ]),
    );
  }

  Widget _placeRow(IconData icon, Color color, String title, String subtitle) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 21)),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ])),
      ]);

  Widget _miniInfo(IconData icon, String label, String value, {Color? valueColor}) => Row(children: [
        Icon(icon, size: 19, color: AppColors.muted),
        const SizedBox(width: 7),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: valueColor)),
        ])),
      ]);


  Future<void> _showOrderDetails(AppStrings s, Map<String, dynamic> row) async {
    final status = row['status']?.toString() ?? '';
    final cancelled = status == 'cancelled' || status == 'canceled' || status == 'rejected';
    final number = row['order_number']?.toString() ?? '—';
    String val(dynamic x) => (x?.toString().trim().isNotEmpty ?? false) ? x.toString() : '—';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${s.t('driverDeliveryHistoryTitle')} #$number', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            _detailLine(Icons.storefront_rounded, val(row['store_name']), val(row['store_address'])),
            const SizedBox(height: 10),
            _detailLine(Icons.person_outline_rounded, val(row['customer_name']), val(row['delivery_address'])),
            const Divider(height: 28),
            _detailPair('طريقة الدفع', _paymentLabel(s, val(row['payment_method']))),
            _detailPair('أجرة التوصيل', _money(double.tryParse((row['earning'] ?? 0).toString()) ?? 0)),
            _detailPair('إنشاء الطلب', _formatDate(row['created_at']?.toString())),
            _detailPair('وقت الاستلام', _formatDate(row['picked_up_at']?.toString())),
            _detailPair('وقت التسليم', _formatDate(row['delivered_at']?.toString())),
            if (cancelled) _detailPair('سبب الإلغاء', val(row['cancellation_reason']) == '—' ? 'لم يتم تسجيل سبب للإلغاء' : val(row['cancellation_reason'])),
            if (val(row['notes']) != '—') _detailPair('ملاحظة الطلب', val(row['notes'])),
          ]),
        ),
      ),
    );
  }

  Widget _detailLine(IconData icon, String title, String subtitle) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFFFEEE2), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppColors.orange)),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: AppColors.muted, height: 1.35))])),
  ]);

  Widget _detailPair(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700))), const SizedBox(width: 12), Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900)))]),
  );

  String _paymentLabel(AppStrings s, String value) {
    final v = value.toLowerCase();
    if (v.contains('cash') || v.contains('نقد')) return s.t('driverHistoryCash');
    if (v.contains('card') || v.contains('online') || v.contains('electronic')) return s.t('driverHistoryElectronic');
    return value.isEmpty ? '—' : value;
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '—';
    final dt = DateTime.tryParse(value)?.toLocal();
    if (dt == null) return value;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
  }
}
