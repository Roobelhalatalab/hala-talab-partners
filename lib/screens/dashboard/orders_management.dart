part of 'partner_dashboard.dart';

class _OrdersManagementPage extends StatefulWidget {
  const _OrdersManagementPage();

  @override
  State<_OrdersManagementPage> createState() => _OrdersManagementPageState();
}

class _OrdersManagementPageState extends State<_OrdersManagementPage> {
  List<Map<String, dynamic>> _orders = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'pending';
  String _dateFilter = 'today';
  Timer? _refreshTimer;
  RealtimeChannel? _ordersChannel;
  final Set<String> _updatingOrderIds = <String>{};
  final Set<String> _printingOrderIds = <String>{};
  final Map<String, Map<String, dynamic>> _printStates = <String, Map<String, dynamic>>{};

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _subscribeToIncomingOrders();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadOrders(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    final channel = _ordersChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  Future<void> _subscribeToIncomingOrders() async {
    try {
      final store = await AuthService.instance.getCurrentStore();
      final storeId = store?['id']?.toString();
      if (storeId == null || !mounted) return;
      _ordersChannel = Supabase.instance.client
          .channel('store-orders-$storeId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'store_id',
              value: storeId,
            ),
            callback: (payload) =>
                _handleRealtimeOrder(payload.newRecord, isNew: true),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'store_id',
              value: storeId,
            ),
            callback: (payload) => _handleRealtimeOrder(payload.newRecord),
          )
          .subscribe();
    } catch (_) {
      // The periodic refresh remains active as a fallback.
    }
  }

  Future<void> _handleRealtimeOrder(
    Map<String, dynamic> record, {
    bool isNew = false,
  }) async {
    final id = record['id']?.toString();
    if (id == null || !mounted) return;
    final fullOrder = await OrdersRepository.instance.getOrderById(id);
    if (fullOrder == null || !mounted) return;
    setState(() {
      final next = List<Map<String, dynamic>>.from(_orders);
      final index = next.indexWhere((item) => item['id']?.toString() == id);
      if (index >= 0) {
        next[index] = fullOrder;
      } else {
        next.insert(0, fullOrder);
      }
      _orders = next;
      _error = null;
      _loading = false;
      if (isNew) _filter = 'pending';
    });
    if (isNew) {
      final s = AppStrings.of(context);
      final number = fullOrder['order_number']?.toString() ?? '';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text('${s.t('newOrderRealtimeBody')} #$number'),
            action: SnackBarAction(
              label: s.t('openOrder'),
              onPressed: () => setState(() => _filter = 'pending'),
            ),
          ),
        );
    }
  }

  Future<void> _loadOrders({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final orders = await OrdersRepository.instance.getOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _error = null;
      });
      unawaited(_loadPrintStates(orders));
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPrintStates(List<Map<String, dynamic>> orders) async {
    final entries = await Future.wait(
      orders.map((order) async {
        final id = order['id']?.toString() ?? '';
        if (id.isEmpty) return null;
        final state = await ReceiptPrinterService.instance.getLastPrintState(id);
        return state == null ? null : MapEntry(id, state);
      }),
    );
    if (!mounted) return;
    setState(() {
      for (final entry in entries.whereType<MapEntry<String, Map<String, dynamic>>>()) {
        _printStates[entry.key] = entry.value;
      }
    });
  }

  Future<void> _printOrder(
    Map<String, dynamic> order, {
    bool automatic = false,
  }) async {
    final id = order['id']?.toString() ?? '';
    if (id.isEmpty || _printingOrderIds.contains(id)) return;
    if (mounted) setState(() => _printingOrderIds.add(id));
    try {
      final store = await AuthService.instance.getCurrentStore();
      if (!mounted) return;
      final result = await ReceiptPrinterService.instance.printOrder(
        order: order,
        store: store,
        appLanguage: Localizations.localeOf(context).languageCode,
        allowPrinterDialog: !automatic,
      );
      final state = await ReceiptPrinterService.instance.getLastPrintState(id);
      if (!mounted) return;
      setState(() {
        if (state != null) _printStates[id] = state;
      });
      final message = automatic && !result.success
          ? 'تم قبول الطلب، لكن تعذرت الطباعة. اضغط زر طباعة لإعادة المحاولة. (${result.message})'
          : result.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _printingOrderIds.remove(id));
    }
  }

  bool _matchesFilter(Map<String, dynamic> order) {
    final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '')?.toLocal();
    if (createdAt != null) {
      final now = DateTime.now();
      final startToday = DateTime(now.year, now.month, now.day);
      if (_dateFilter == 'today' && createdAt.isBefore(startToday)) return false;
      if (_dateFilter == 'week' && createdAt.isBefore(startToday.subtract(const Duration(days: 6)))) return false;
      if (_dateFilter == 'month' && createdAt.isBefore(DateTime(now.year, now.month, 1))) return false;
    }
    final status = order['status']?.toString() ?? 'pending';
    switch (_filter) {
      case 'pending':
        return status == 'pending';
      case 'preparing':
        return const ['accepted', 'preparing'].contains(status);
      case 'ready':
        return const ['ready', 'assigned', 'picked_up'].contains(status);
      case 'delivered':
        return status == 'delivered';
      case 'cancelled':
        return const ['cancelled', 'rejected'].contains(status);
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _filteredOrders =>
      _orders.where(_matchesFilter).toList();

  int _countFor(String filter) {
    final current = _filter;
    _filter = filter;
    final count = _orders.where(_matchesFilter).length;
    _filter = current;
    return count;
  }

  Future<void> _changeStatus(Map<String, dynamic> order, String status) async {
    final s = AppStrings.of(context);
    final orderId = order['id']?.toString();
    if (orderId == null || _updatingOrderIds.contains(orderId)) return;
    if (status == 'rejected') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(s.t('rejectOrder')),
          content: Text(s.t('confirmRejectOrder')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(s.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(s.t('rejectOrder')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (mounted) setState(() => _updatingOrderIds.add(orderId));
    try {
      final updated = await OrdersRepository.instance.updateStatus(
        orderId: orderId,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        final next = List<Map<String, dynamic>>.from(_orders);
        final index = next.indexWhere((item) => item['id']?.toString() == orderId);
        if (index >= 0) {
          next[index] = {...next[index], ...updated};
        }
        _orders = next;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('orderUpdated'))));
      if (status == 'preparing') {
        final printerSettings = await ReceiptPrinterService.instance.loadSettings();
        if (printerSettings.autoPrintAfterAccept) {
          final currentOrder = <String, dynamic>{...order, ...updated, 'status': status};
          // Printing is deliberately detached from accepting the order.
          // A printer/driver failure must never roll back or block the order status.
          unawaited(_printOrder(currentOrder, automatic: true));
        }
      }
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _updatingOrderIds.remove(orderId));
    }
  }

  void _showDetails(Map<String, dynamic> order) {
    showDialog<void>(
      context: context,
      builder: (_) => _OrderDetailsDialog(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final pendingCount = _countFor('pending');
    final preparingCount = _countFor('preparing');
    final readyCount = _countFor('ready');
    final deliveredCount = _countFor('delivered');
    final cancelledCount = _countFor('cancelled');

    return ColoredBox(
      color: const Color(0xFFF8F9FB),
      child: RefreshIndicator(
        onRefresh: () => _loadOrders(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            width >= 900 ? 28 : 14,
            width >= 900 ? 26 : 14,
            width >= 900 ? 28 : 14,
            34,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OrdersHeroHeader(
                      isLoading: _loading,
                      onRefresh: () => _loadOrders(),
                    ),
                    const SizedBox(height: 12),
                    _OrderStageStrip(
                      selected: _filter,
                      pendingCount: pendingCount,
                      preparingCount: preparingCount,
                      readyCount: readyCount,
                      deliveredCount: deliveredCount,
                      onSelected: (value) => setState(() => _filter = value),
                    ),
                    const SizedBox(height: 10),
                    _OrdersToolbar(
                      filter: _filter,
                      dateFilter: _dateFilter,
                      totalCount: _orders.length,
                      cancelledCount: cancelledCount,
                      onAll: () => setState(() => _filter = 'all'),
                      onCancelled: () => setState(() => _filter = 'cancelled'),
                      onDateChanged: (value) => setState(() => _dateFilter = value),
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(60),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      _ProductsErrorState(
                        message: _error!,
                        onRetry: () => _loadOrders(),
                      )
                    else if (_filteredOrders.isEmpty)
                      _EmptyOrdersState(message: s.t('noOrdersForFilter'))
                    else
                      ..._filteredOrders.map(
                        (order) => Padding(
                          padding: const EdgeInsets.only(bottom: 13),
                          child: _OrderCard(
                            order: order,
                            onDetails: () => _showDetails(order),
                            isUpdating: _updatingOrderIds.contains(
                              order['id']?.toString(),
                            ),
                            onStatusChanged: (status) =>
                                _changeStatus(order, status),
                            onPrint: () => _printOrder(order),
                            isPrinting: _printingOrderIds.contains(order['id']?.toString()),
                            printState: _printStates[order['id']?.toString()],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersHeroHeader extends StatelessWidget {
  const _OrdersHeroHeader({required this.isLoading, required this.onRefresh});

  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final compact = MediaQuery.sizeOf(context).width < 700;
    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: compact ? 40 : 50,
          height: compact ? 40 : 50,
          decoration: BoxDecoration(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(compact ? 12 : 15),
          ),
          child: Icon(Icons.receipt_long_rounded, color: Colors.white, size: compact ? 21 : 25),
        ),
        SizedBox(width: compact ? 10 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('ordersManagement'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 19 : 25, fontWeight: FontWeight.w900, height: 1.12)),
              SizedBox(height: compact ? 3 : 5),
              Text(s.t('ordersManagementSubtitle'), maxLines: compact ? 2 : 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, height: 1.3, fontSize: compact ? 10.5 : 13)),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: compact ? 7 : 9),
          decoration: BoxDecoration(color: const Color(0xFFEAF8EF), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFC9EDD5))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_tethering_rounded, size: 16, color: Color(0xFF168243)),
            const SizedBox(width: 6),
            Text('Realtime', style: TextStyle(color: const Color(0xFF168243), fontWeight: FontWeight.w900, fontSize: compact ? 10.5 : 12)),
          ]),
        ),
        IconButton.filledTonal(tooltip: s.t('refreshOrders'), onPressed: isLoading ? null : onRefresh, icon: const Icon(Icons.refresh_rounded, size: 20), style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.orangeDark, side: const BorderSide(color: Color(0xFFFFDCC2)))),
      ],
    );
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 18),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFF7F0), Colors.white], begin: Alignment.topRight, end: Alignment.bottomLeft), borderRadius: BorderRadius.circular(compact ? 18 : 18), border: Border.all(color: const Color(0xFFFFDEC7))),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 10), Align(alignment: AlignmentDirectional.centerStart, child: actions)])
          : Row(children: [Expanded(child: title), const SizedBox(width: 18), actions]),
    );
  }
}

class _OrderStageStrip extends StatelessWidget {
  const _OrderStageStrip({
    required this.selected,
    required this.pendingCount,
    required this.preparingCount,
    required this.readyCount,
    required this.deliveredCount,
    required this.onSelected,
  });

  final String selected;
  final int pendingCount;
  final int preparingCount;
  final int readyCount;
  final int deliveredCount;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final cards = [
      _StageData(
        value: 'pending',
        label: s.t('newOrders'),
        count: pendingCount,
        icon: Icons.notifications_active_outlined,
        color: AppColors.orange,
      ),
      _StageData(
        value: 'preparing',
        label: s.t('inProgressOrders'),
        count: preparingCount,
        icon: Icons.soup_kitchen_rounded,
        color: const Color(0xFFF59E0B),
      ),
      _StageData(
        value: 'ready',
        label: s.t('readyOrders'),
        count: readyCount,
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF0F9D68),
      ),
      _StageData(
        value: 'delivered',
        label: s.t('completedOrders'),
        count: deliveredCount,
        icon: Icons.task_alt_rounded,
        color: const Color(0xFF2563EB),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final itemWidth = compact
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 30) / 4;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map(
                (data) => SizedBox(
                  width: itemWidth,
                  child: _OrderStageCard(
                    data: data,
                    selected: selected == data.value,
                    onTap: () => onSelected(data.value),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _StageData {
  const _StageData({
    required this.value,
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final int count;
  final IconData icon;
  final Color color;
}

class _OrderStageCard extends StatelessWidget {
  const _OrderStageCard({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _StageData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(compact ? 11 : 13),
          decoration: BoxDecoration(
            color: selected ? data.color.withValues(alpha: .08) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? data.color.withValues(alpha: .45)
                  : const Color(0xFFE8EAEE),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: data.color.withValues(alpha: .12),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 36 : 38,
                height: compact ? 36 : 38,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(data.icon, color: data.color, size: compact ? 19 : 20),
              ),
              SizedBox(width: compact ? 7 : 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 10.5 : 11,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${data.count}',
                      style: TextStyle(
                        color: data.color,
                        fontSize: compact ? 20 : 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: data.color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersToolbar extends StatelessWidget {
  const _OrdersToolbar({
    required this.filter,
    required this.dateFilter,
    required this.totalCount,
    required this.cancelledCount,
    required this.onAll,
    required this.onCancelled,
    required this.onDateChanged,
  });

  final String filter;
  final String dateFilter;
  final int totalCount;
  final int cancelledCount;
  final VoidCallback onAll;
  final VoidCallback onCancelled;
  final ValueChanged<String> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EAEE)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _OrderFilterChip(
              label: s.t('allOrders'), count: totalCount, selected: filter == 'all', onSelected: onAll,
            ),
            _OrderFilterChip(
              label: s.t('cancelledOrders'), count: cancelledCount, selected: filter == 'cancelled', onSelected: onCancelled, danger: true,
            ),
          ]),
          Container(
            padding: const EdgeInsetsDirectional.only(start: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.calendar_month_outlined, size: 18, color: AppColors.muted),
              const SizedBox(width: 6),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: dateFilter,
                  borderRadius: BorderRadius.circular(14),
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('اليوم')),
                    DropdownMenuItem(value: 'week', child: Text('آخر 7 أيام')),
                    DropdownMenuItem(value: 'month', child: Text('هذا الشهر')),
                    DropdownMenuItem(value: 'all', child: Text('كل التواريخ')),
                  ],
                  onChanged: (value) { if (value != null) onDateChanged(value); },
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _OrderFilterChip extends StatelessWidget {
  const _OrderFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.count,
    this.danger = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final int? count;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final activeColor = danger ? const Color(0xFFDC2626) : AppColors.orange;
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? activeColor : const Color(0xFFE4E7EC),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: .20)
                      : const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onDetails,
    required this.onStatusChanged,
    required this.isUpdating,
    required this.onPrint,
    required this.isPrinting,
    required this.printState,
  });

  final Map<String, dynamic> order;
  final VoidCallback onDetails;
  final ValueChanged<String> onStatusChanged;
  final bool isUpdating;
  final VoidCallback onPrint;
  final bool isPrinting;
  final Map<String, dynamic>? printState;

  double? _coordinate(List<String> keys) {
    for (final key in keys) {
      final raw = order[key];
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  Future<void> _openOrderLocation(BuildContext context) async {
    final latitude = _coordinate(const [
      'delivery_latitude',
      'customer_latitude',
      'latitude',
    ]);
    final longitude = _coordinate(const [
      'delivery_longitude',
      'customer_longitude',
      'longitude',
    ]);
    final address = (order['delivery_address'] ?? '').toString().trim();

    bool opened = false;
    if (latitude != null && longitude != null) {
      opened = await MapsService.instance.openDirectionsToCoordinates(
        latitude: latitude,
        longitude: longitude,
      );
    } else if (address.isNotEmpty && address != '-') {
      opened = await MapsService.instance.openDirectionsToAddress(address);
    }

    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('لا يوجد موقع أو عنوان صالح لهذا الطلب.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final compact = MediaQuery.sizeOf(context).width < 700;
    final status = order['status'] as String? ?? 'pending';
    final id = order['id']?.toString() ?? '';
    final number = order['order_number']?.toString() ??
        (id.length >= 6 ? id.substring(0, 6) : id);
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final customer = order['customer_name'] as String? ?? '-';
    final address = order['delivery_address'] as String? ?? '-';
    final items = List<Map<String, dynamic>>.from(
      order['order_items'] as List? ?? const [],
    );
    final quantity = items.fold<int>(
      0,
      (sum, item) => sum + ((item['quantity'] as num?)?.toInt() ?? 0),
    );
    final date = DateTime.tryParse(order['created_at']?.toString() ?? '')
        ?.toLocal();
    final statusColor = _orderStatusColor(status);
    final isPickup = _isPickupOrder(order);

    final infoItems = <Widget>[
      _OrderInfo(icon: Icons.person_outline_rounded, text: customer),
      _OrderInfo(
        icon: isPickup ? Icons.storefront_outlined : Icons.location_on_outlined,
        text: isPickup ? 'استلام من المتجر' : address,
        onTap: isPickup ? null : () => _openOrderLocation(context),
        interactive: !isPickup,
      ),
      _OrderInfo(
        icon: Icons.shopping_bag_outlined,
        text: quantity > 0 ? '$quantity' : '${items.length}',
        onTap: onDetails,
        interactive: true,
      ),
      _OrderInfo(
        icon: Icons.payments_outlined,
        text: '${total.toStringAsFixed(0)} د.ع',
        emphasized: true,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 18 : 18),
        border: Border.all(color: const Color(0xFFE8EAEE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 18 : 18),
        child: Stack(
          children: [
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: statusColor),
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                compact ? 16 : 17,
                compact ? 12 : 13,
                compact ? 12 : 14,
                compact ? 12 : 13,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: compact ? 38 : 38,
                            height: compact ? 38 : 38,
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: .10),
                              borderRadius:
                                  BorderRadius.circular(compact ? 12 : 12),
                            ),
                            child: Icon(
                              _statusIcon(status),
                              color: statusColor,
                              size: compact ? 19 : 19,
                            ),
                          ),
                          SizedBox(width: compact ? 8 : 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${s.t('orderNumber')} #$number',
                                style: TextStyle(
                                  fontSize: compact ? 15 : 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (date != null)
                                Text(
                                  _formatOrderTime(date),
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: compact ? 10.5 : 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _FulfillmentBadge(isPickup: isPickup),
                          _OrderStatusBadge(status: status),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 10 : 10),
                  Container(
                    padding: EdgeInsets.all(compact ? 10 : 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(compact ? 14 : 14),
                    ),
                    child: compact
                        ? Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: infoItems[0]),
                                  const SizedBox(width: 8),
                                  Expanded(child: infoItems[1]),
                                ],
                              ),
                              const SizedBox(height: 9),
                              Row(
                                children: [
                                  Expanded(child: infoItems[2]),
                                  const SizedBox(width: 8),
                                  Expanded(child: infoItems[3]),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              for (var i = 0; i < infoItems.length; i++) ...[
                                Expanded(child: infoItems[i]),
                                if (i != infoItems.length - 1)
                                  const SizedBox(width: 10),
                              ],
                            ],
                          ),
                  ),
                  if (items.isNotEmpty) ...[
                    SizedBox(height: compact ? 9 : 9),
                    _OrderItemsPreview(items: items),
                  ],
                  if (printState != null && const ['accepted', 'preparing'].contains(status)) ...[
                    const SizedBox(height: 8),
                    _OrderPrintStateBadge(state: printState!),
                  ],
                  SizedBox(height: compact ? 10 : 9),
                  if (compact) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onDetails,
                        icon: const Icon(Icons.visibility_outlined, size: 17),
                        label: Text(s.t('viewDetails')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.ink,
                          side: const BorderSide(color: Color(0xFFE4E7EC)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _OrderPrimaryActions(
                      status: status,
                      isUpdating: isUpdating,
                      onStatusChanged: onStatusChanged,
                      onPrint: onPrint,
                      isPrinting: isPrinting,
                      hasPrinted: printState?['success'] == true,
                    ),
                  ] else
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: onDetails,
                          icon: const Icon(Icons.visibility_outlined, size: 17),
                          label: Text(s.t('viewDetails')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.ink,
                            side: const BorderSide(color: Color(0xFFE4E7EC)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                          ),
                        ),
                        const Spacer(),
                        _OrderPrimaryActions(
                          status: status,
                          isUpdating: isUpdating,
                          onStatusChanged: onStatusChanged,
                          onPrint: onPrint,
                          isPrinting: isPrinting,
                          hasPrinted: printState?['success'] == true,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderPrimaryActions extends StatelessWidget {
  const _OrderPrimaryActions({
    required this.status,
    required this.onStatusChanged,
    required this.isUpdating,
    required this.onPrint,
    required this.isPrinting,
    required this.hasPrinted,
  });

  final String status;
  final ValueChanged<String> onStatusChanged;
  final bool isUpdating;
  final VoidCallback onPrint;
  final bool isPrinting;
  final bool hasPrinted;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (isUpdating)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        if (status == 'pending') ...[
          OutlinedButton.icon(
            onPressed: isUpdating ? null : () => onStatusChanged('rejected'),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(s.t('rejectOrder')),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFFFCDD2)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            ),
          ),
          FilledButton.icon(
            onPressed: isUpdating ? null : () => onStatusChanged('preparing'),
            icon: const Icon(Icons.check_rounded),
            label: Text(s.t('acceptOrder')),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
          ),
        ],
        if (const ['accepted', 'preparing'].contains(status))
          OutlinedButton.icon(
            onPressed: isPrinting ? null : onPrint,
            icon: isPrinting
                ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.print_outlined, size: 18),
            label: Text(hasPrinted ? 'إعادة طباعة' : 'طباعة'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F766E),
              side: const BorderSide(color: Color(0xFF99D5CD)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            ),
          ),
        if (status == 'preparing')
          FilledButton.icon(
            onPressed: isUpdating ? null : () => onStatusChanged('ready'),
            icon: const Icon(Icons.inventory_2_outlined),
            label: Text(s.t('markReady')),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F9D68),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
          ),
      ],
    );
  }
}

class _OrderPrintStateBadge extends StatelessWidget {
  const _OrderPrintStateBadge({required this.state});

  final Map<String, dynamic> state;

  @override
  Widget build(BuildContext context) {
    final success = state['success'] == true;
    final printedAt = DateTime.tryParse(state['printedAt']?.toString() ?? '')?.toLocal();
    final time = printedAt == null
        ? ''
        : ' • ${printedAt.hour.toString().padLeft(2, '0')}:${printedAt.minute.toString().padLeft(2, '0')}';
    final color = success ? const Color(0xFF0F766E) : const Color(0xFFDC2626);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(success ? Icons.print_rounded : Icons.error_outline_rounded, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              '${success ? 'تمت الطباعة' : 'فشلت الطباعة'}$time',
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderItemsPreview extends StatelessWidget {
  const _OrderItemsPreview({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final visible = items.take(3).toList();
    final remaining = items.length - visible.length;
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        ...visible.map((item) {
          final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          final name = orderItemDisplayName(item);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7F0),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFFFE1CC)),
            ),
            child: Text(
              '$quantity× $name',
              style: const TextStyle(
                color: AppColors.orangeDark,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          );
        }),
        if (remaining > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              '+$remaining',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

class _FulfillmentBadge extends StatelessWidget {
  const _FulfillmentBadge({required this.isPickup});

  final bool isPickup;

  @override
  Widget build(BuildContext context) {
    final color = isPickup ? const Color(0xFF7C3AED) : const Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPickup ? Icons.storefront_outlined : Icons.delivery_dining_outlined,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            isPickup ? 'استلام' : 'توصيل',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

bool _isPickupOrder(Map<String, dynamic> order) {
  final type = (order['fulfillment_type'] ??
          order['order_type'] ??
          order['delivery_type'] ??
          '')
      .toString()
      .toLowerCase();
  return type.contains('pickup') ||
      type.contains('collection') ||
      type.contains('استلام');
}

String _formatOrderTime(DateTime date) {
  final now = DateTime.now();
  final sameDay = now.year == date.year &&
      now.month == date.month &&
      now.day == date.day;
  final time =
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  if (sameDay) return time;
  return '${date.day}/${date.month} • $time';
}

IconData _statusIcon(String status) => switch (status) {
      'accepted' => Icons.check_circle_outline_rounded,
      'preparing' => Icons.soup_kitchen_rounded,
      'ready' => Icons.inventory_2_outlined,
      'assigned' => Icons.delivery_dining_outlined,
      'picked_up' => Icons.two_wheeler_rounded,
      'delivered' => Icons.task_alt_rounded,
      'cancelled' => Icons.block_outlined,
      'rejected' => Icons.cancel_outlined,
      _ => Icons.notifications_active_outlined,
    };

Color _orderStatusColor(String status) => switch (status) {
      'accepted' => const Color(0xFFF59E0B),
      'preparing' => const Color(0xFFF59E0B),
      'ready' => const Color(0xFF0F9D68),
      'assigned' => const Color(0xFF0F9D68),
      'picked_up' => const Color(0xFF0F9D68),
      'delivered' => const Color(0xFF2563EB),
      'cancelled' => const Color(0xFF667085),
      'rejected' => const Color(0xFFEF4444),
      _ => AppColors.orange,
    };

class _OrderInfo extends StatelessWidget {
  const _OrderInfo({
    required this.icon,
    required this.text,
    this.emphasized = false,
    this.onTap,
    this.interactive = false,
  });

  final IconData icon;
  final String text;
  final bool emphasized;
  final VoidCallback? onTap;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: interactive
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 5)
          : EdgeInsets.zero,
      decoration: interactive
          ? BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: interactive
                  ? const Color(0xFFFFF7F0)
                  : Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 16,
              color: interactive
                  ? AppColors.orange
                  : emphasized
                      ? AppColors.orangeDark
                      : AppColors.muted,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
                color: interactive
                    ? AppColors.ink
                    : emphasized
                        ? AppColors.orangeDark
                        : AppColors.ink,
              ),
            ),
          ),
          if (interactive) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: AppColors.muted,
            ),
          ],
        ],
      ),
    );

    if (!interactive || onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: content,
    );
  }
}

class _OrderStatusBadge extends StatelessWidget {
  const _OrderStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final label = switch (status) {
      'accepted' => s.t('orderStatusAccepted'),
      'preparing' => s.t('orderStatusPreparing'),
      'ready' => s.t('orderStatusReady'),
      'assigned' => s.t('orderStatusAssigned'),
      'picked_up' => s.t('orderStatusPickedUp'),
      'delivered' => s.t('orderStatusDelivered'),
      'cancelled' => s.t('orderStatusCancelled'),
      'rejected' => s.t('orderStatusRejected'),
      _ => s.t('orderStatusPending'),
    };
    final color = _orderStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 14, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderDetailsDialog extends StatelessWidget {
  const _OrderDetailsDialog({required this.order});

  final Map<String, dynamic> order;

  double? _coordinate(List<String> keys) {
    for (final key in keys) {
      final raw = order[key];
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  String _mapsText(BuildContext context, String ar, String ku, String en) {
    final code = AppStrings.of(context).languageCode;
    return code == 'ku' ? ku : code == 'en' ? en : ar;
  }

  Future<void> _openCustomerLocation(BuildContext context) async {
    final latitude = _coordinate(const [
      'delivery_latitude',
      'customer_latitude',
      'latitude',
    ]);
    final longitude = _coordinate(const [
      'delivery_longitude',
      'customer_longitude',
      'longitude',
    ]);
    final address = (order['delivery_address'] ?? '').toString().trim();

    bool opened = false;
    if (latitude != null && longitude != null) {
      opened = await MapsService.instance.openDirectionsToCoordinates(
        latitude: latitude,
        longitude: longitude,
      );
    } else if (address.isNotEmpty && address != '-') {
      opened = await MapsService.instance.openDirectionsToAddress(address);
    }

    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _mapsText(
            context,
            'لا يوجد موقع أو عنوان صالح لهذا الطلب.',
            'شوێن یان ناونیشانی دروست بۆ ئەم داواکارییە نییە.',
            'No valid location or address is available for this order.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final items = List<Map<String, dynamic>>.from(
      order['order_items'] as List? ?? const [],
    );
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final isPickup = _isPickupOrder(order);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${s.t('orderNumber')} #${order['order_number'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          _OrderStatusBadge(status: order['status'] as String? ?? 'pending'),
        ],
      ),
      content: SizedBox(
        width: _adaptiveDialogWidth(context, maxWidth: 650),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: s.t('orderCustomer'),
                      value: order['customer_name'] as String? ?? '-',
                    ),
                    _DetailRow(
                      label: s.t('phone'),
                      value: order['customer_phone'] as String? ?? '-',
                    ),
                    _DetailRow(
                      label: s.t('orderAddress'),
                      value: isPickup
                          ? 'استلام من المتجر'
                          : order['delivery_address'] as String? ?? '-',
                    ),
                    if ((order['notes'] as String?)?.isNotEmpty == true)
                      _DetailRow(
                        label: s.t('orderNotes'),
                        value: order['notes'] as String,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                s.t('orderItems'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                Text(
                  s.t('noOrdersYet'),
                  style: const TextStyle(color: AppColors.muted),
                )
              else
                ...items.map((item) {
                  final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
                  final unitPrice =
                      (item['unit_price'] as num?)?.toDouble() ?? 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE8EAEE)),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEEE2),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Text(
                            '$quantity×',
                            style: const TextStyle(
                              color: AppColors.orangeDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                orderItemDisplayName(item),
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${s.t('unitPrice')}: ${unitPrice.toStringAsFixed(0)} د.ع',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              if (orderItemVariantLabel(item).isNotEmpty &&
                                  !(item['product_name']?.toString().toLowerCase() ?? '').contains(orderItemVariantLabel(item).toLowerCase())) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${_mapsText(context, 'الحجم / الخيار', 'قەبارە / هەڵبژاردە', 'Size / option')}: ${orderItemVariantLabel(item)}',
                                  style: const TextStyle(
                                    color: AppColors.orangeDark,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                              if ((item['notes']?.toString() ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF6EE),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    '${_mapsText(context, 'ملاحظة العميل', 'تێبینی کڕیار', 'Customer note')}: ${item['notes'].toString().trim()}',
                                    style: const TextStyle(
                                      color: AppColors.orangeDark,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          '${(quantity * unitPrice).toStringAsFixed(0)} د.ع',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  );
                }),
              const Divider(height: 28),
              _DetailRow(
                label: s.t('orderTotal'),
                value: '${total.toStringAsFixed(0)} د.ع',
                emphasized: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!isPickup)
          OutlinedButton.icon(
            onPressed: () => _openCustomerLocation(context),
            icon: const Icon(Icons.navigation_rounded),
            label: Text(_mapsText(context, 'الملاحة إلى العميل', 'ڕێنیشاندان بۆ کڕیار', 'Navigate to customer')),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.orange),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.t('cancel')),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: emphasized ? FontWeight.w900 : FontWeight.w600,
                  fontSize: emphasized ? 18 : null,
                ),
              ),
            ),
          ],
        ),
      );
}

class _EmptyOrdersState extends StatelessWidget {
  const _EmptyOrdersState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE7E9ED)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(44),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5ED),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  size: 36,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      );
}
