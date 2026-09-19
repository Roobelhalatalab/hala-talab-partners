part of 'partner_dashboard.dart';

class _DriverAssignedOrderScreen extends StatefulWidget {
  const _DriverAssignedOrderScreen({
    required this.order,
    required this.onRefresh,
    required this.onBackToHome,
  });

  final Map<String, dynamic> order;
  final Future<void> Function() onRefresh;
  final VoidCallback onBackToHome;

  @override
  State<_DriverAssignedOrderScreen> createState() => _DriverAssignedOrderScreenState();
}

class _DriverAssignedOrderScreenState extends State<_DriverAssignedOrderScreen> {
  bool _openingMaps = false;
  bool _calling = false;
  bool _confirmingPickup = false;
  bool _confirmingDelivery = false;
  bool _notifyingArrival = false;
  bool _arrivalNotifiedLocally = false;

  String _text(String key) => widget.order[key]?.toString().trim() ?? '';

  String _money(dynamic value) {
    final n = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (n == null) return '—';
    return '${n.toStringAsFixed(n % 1 == 0 ? 0 : 2)} د.ع';
  }


  double? _coordinate(List<String> keys) {
    for (final key in keys) {
      final raw = widget.order[key];
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  List<Map<String, dynamic>> get _items {
    final raw = widget.order['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _showLocationPreview() async {
    if (_openingMaps) return;
    final pickedUp = _text('status') == 'picked_up';
    final address = pickedUp ? _text('delivery_address') : _text('store_address');
    final lat = _coordinate(
      pickedUp
          ? const ['delivery_latitude', 'customer_latitude']
          : const ['store_latitude', 'restaurant_latitude'],
    );
    final lng = _coordinate(
      pickedUp
          ? const ['delivery_longitude', 'customer_longitude']
          : const ['store_longitude', 'restaurant_longitude'],
    );
    if ((lat == null || lng == null) && address.isEmpty) return;

    final s = AppStrings.of(context);
    setState(() => _openingMaps = true);
    final opened = lat != null && lng != null
        ? await MapsService.instance.openWazeNavigationCoordinates(
            latitude: lat,
            longitude: lng,
          )
        : await MapsService.instance.openWazeNavigationAddress(address);
    if (!mounted) return;
    setState(() => _openingMaps = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.t('driverCouldNotOpenWaze'))),
      );
    }
  }

  Future<void> _callPhone(String phone, String failureKey) async {
    if (_calling || phone.isEmpty) return;
    setState(() => _calling = true);
    try {
      final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).t(failureKey))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).t(failureKey))),
        );
      }
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  Future<void> _callStore() => _callPhone(_text('store_phone'), 'driverCouldNotCallStore');
  Future<void> _callCustomer() => _callPhone(_text('customer_phone'), 'driverCouldNotCallCustomer');

  Future<void> _notifyCustomerArrival() async {
    if (_notifyingArrival || _arrivalNotifiedLocally) return;
    final orderId = _text('order_id');
    if (orderId.isEmpty) return;
    final s = AppStrings.of(context);

    setState(() => _notifyingArrival = true);
    try {
      final result = await DriverDeliveryRepository.instance.notifyCustomerArrival(orderId);
      if (!mounted) return;
      setState(() => _arrivalNotifiedLocally = true);
      await widget.onRefresh();
      if (!mounted) return;
      final alreadyNotified = result['already_notified'] == true;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              alreadyNotified
                  ? s.t('driverCustomerAlreadyNotifiedArrival')
                  : s.t('driverCustomerNotifiedArrival'),
            ),
          ),
        );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.code == 'PGRST202'
          ? s.t('driverArrivalSqlRequired')
          : error.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _notifyingArrival = false);
    }
  }

  Future<void> _confirmDelivery() async {
    if (_confirmingDelivery) return;
    final orderId = _text('order_id');
    if (orderId.isEmpty) return;
    final s = AppStrings.of(context);

    setState(() => _confirmingDelivery = true);
    try {
      await DriverDeliveryRepository.instance.confirmDelivery(orderId: orderId);
      if (!mounted) return;
      await widget.onRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.t('driverDeliveryCompletedSuccessfully'))));
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = error.code == 'PGRST202'
          ? s.t('driverStage17SqlRequired')
          : error.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _confirmingDelivery = false);
    }
  }

  Future<void> _confirmPickup() async {
    if (_confirmingPickup) return;
    final orderId = _text('order_id');
    if (orderId.isEmpty) return;
    setState(() => _confirmingPickup = true);
    try {
      await DriverDeliveryRepository.instance.confirmPickup(orderId);
      if (!mounted) return;
      await widget.onRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(AppStrings.of(context).t('driverPickupConfirmed'))));
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final strings = AppStrings.of(context);
      final message = error.code == 'PGRST202'
          ? strings.t('driverStage9SqlRequired')
          : error.message.toLowerCase().contains('not available for pickup')
              ? strings.t('driverPickupNotReady')
              : strings.t('driverOfferActionFailed');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _confirmingPickup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final orderNumber = _text('order_number');
    final storeName = _text('store_name');
    final storeAddress = _text('store_address');
    final storePhone = _text('store_phone');
    final customerName = _text('customer_name');
    final deliveryAddress = _text('delivery_address');
    final paymentMethod = _text('payment_method');
    final notes = _text('notes');
    final customerPhone = _text('customer_phone');
    final status = _text('status');
    final pickedUp = status == 'picked_up';
    final arrivalNotified = _arrivalNotifiedLocally || _text('driver_arrived_at').isNotEmpty;
    final canConfirmPickup = status == 'assigned' || status == 'ready';
    final navigationLat = _coordinate(
      pickedUp
          ? const ['delivery_latitude', 'customer_latitude']
          : const ['store_latitude', 'restaurant_latitude'],
    );
    final navigationLng = _coordinate(
      pickedUp
          ? const ['delivery_longitude', 'customer_longitude']
          : const ['store_longitude', 'restaurant_longitude'],
    );
    final navigationAddress = pickedUp ? deliveryAddress : storeAddress;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 14, vertical: wide ? 22 : 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 900 : 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(onPressed: widget.onBackToHome, icon: const Icon(Icons.arrow_back_rounded)),
                          Expanded(
                            child: Text(
                              s.t('driverOrderDetailsTitle'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                            ),
                          ),
                          if (orderNumber.isNotEmpty)
                            Text('#$orderNumber', style: const TextStyle(color: AppColors.orange, fontSize: 18, fontWeight: FontWeight.w900))
                          else
                            const SizedBox(width: 48),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1E7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFFD5B8)),
                        ),
                        child: Row(children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(color: pickedUp ? const Color(0xFF20A747) : AppColors.orange, shape: BoxShape.circle),
                            child: Icon(pickedUp ? Icons.home_rounded : Icons.storefront_rounded, color: Colors.white, size: 29),
                          ),
                          const SizedBox(width: 13),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(pickedUp ? s.t('driverHeadingToCustomer') : s.t('driverHeadingToStore'), style: TextStyle(color: pickedUp ? const Color(0xFF20A747) : AppColors.orange, fontSize: 18, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 3),
                            Text(pickedUp ? s.t('driverHeadingToCustomerSubtitle') : s.t('driverHeadingToStoreSubtitle'), style: const TextStyle(color: AppColors.muted, height: 1.35)),
                          ])),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      MapboxLocationPreview(
                        latitude: _coordinate(
                          pickedUp
                              ? const ['delivery_latitude', 'customer_latitude']
                              : const ['store_latitude', 'restaurant_latitude'],
                        ),
                        longitude: _coordinate(
                          pickedUp
                              ? const ['delivery_longitude', 'customer_longitude']
                              : const ['store_longitude', 'restaurant_longitude'],
                        ),
                        height: wide ? 260 : 220,
                        zoom: 14.5,
                        emptyText: s.t('driverMapWaitingCoordinates'),
                        missingTokenText: s.t('driverMapboxMissingToken'),
                        unsupportedText: s.t('driverMapboxMobileOnly'),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: ((navigationLat == null || navigationLng == null) && navigationAddress.isEmpty) ? null : _showLocationPreview,
                        icon: const Icon(Icons.map_outlined),
                        label: Text(pickedUp ? s.t('driverPreviewCustomerLocation') : s.t('driverPreviewStoreLocation')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _DriverOrderSection(
                        title: s.t('driverPickupStore'),
                        icon: Icons.storefront_rounded,
                        accent: AppColors.orange,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(storeName.isEmpty ? s.t('driverUnknownStore') : storeName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                          if (storeAddress.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(storeAddress, style: const TextStyle(color: AppColors.muted, height: 1.35)),
                          ],
                          if (storePhone.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _calling ? null : _callStore,
                              icon: const Icon(Icons.phone_outlined),
                              label: Text('${s.t('driverCallStore')}  $storePhone'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.orange,
                                side: const BorderSide(color: AppColors.orange),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 12),
                      _DriverOrderSection(
                        title: s.t('driverDeliveryCustomer'),
                        icon: Icons.home_rounded,
                        accent: const Color(0xFF20A747),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(customerName.isEmpty ? s.t('driverCustomer') : customerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                          if (deliveryAddress.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(deliveryAddress, style: const TextStyle(color: AppColors.muted, height: 1.35)),
                          ],
                          if (pickedUp && customerPhone.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _calling ? null : _callCustomer,
                              icon: const Icon(Icons.phone_outlined),
                              label: Text('${s.t('driverCallCustomer')}  $customerPhone'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF20A747),
                                side: const BorderSide(color: Color(0xFF20A747)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 12),
                      _DriverOrderSection(
                        title: s.t('driverOrderContents'),
                        icon: Icons.shopping_bag_outlined,
                        accent: AppColors.orange,
                        child: _items.isEmpty
                            ? Text(s.t('driverNoOrderItems'), style: const TextStyle(color: AppColors.muted))
                            : Column(
                                children: _items.map((item) {
                                  final qty = item['quantity']?.toString() ?? '1';
                                  final name = item['product_name']?.toString() ?? '—';
                                  final itemNotes = item['notes']?.toString().trim() ?? '';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 7),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                        decoration: BoxDecoration(color: const Color(0xFFFFF0E5), borderRadius: BorderRadius.circular(9)),
                                        child: Text('${qty}x', style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900)),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                        if (itemNotes.isNotEmpty) Text(itemNotes, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                      ])),
                                    ]),
                                  );
                                }).toList(),
                              ),
                      ),
                      if (notes.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _DriverOrderSection(
                          title: s.t('driverOrderNotes'),
                          icon: Icons.notes_rounded,
                          accent: AppColors.orange,
                          child: Text(notes, style: const TextStyle(color: AppColors.muted, height: 1.4)),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE7E9ED))),
                        child: Row(children: [
                          Expanded(child: _OfferStat(icon: Icons.credit_card_rounded, label: s.t('driverPaymentMethod'), value: _paymentLabel(s, paymentMethod))),
                          Container(width: 1, height: 48, color: const Color(0xFFE7E9ED)),
                          Expanded(child: _OfferStat(icon: Icons.payments_outlined, label: s.t('driverExpectedEarning'), value: AppStrings.of(context).t('free'), valueColor: const Color(0xFF20A747))),
                          Container(width: 1, height: 48, color: const Color(0xFFE7E9ED)),
                          Expanded(child: _OfferStat(icon: Icons.receipt_long_outlined, label: s.t('driverOrderTotal'), value: _money(widget.order['total']))),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      if (!pickedUp) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: const Color(0xFFFFF7E8), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFFE3AF))),
                          child: Row(children: [
                            const Icon(Icons.info_outline_rounded, color: AppColors.orange),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                canConfirmPickup ? s.t('driverVerifyPickupBeforeConfirm') : s.t('driverPickupWaitingStoreReady'),
                                style: const TextStyle(color: AppColors.muted, height: 1.35),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: !canConfirmPickup || _confirmingPickup ? null : _confirmPickup,
                          icon: _confirmingPickup
                              ? const SizedBox.square(dimension: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.inventory_2_outlined),
                          label: Text(s.t('driverConfirmPickup')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.orange,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(58),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: const Color(0xFFEAF8EE), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFBFE8C8))),
                          child: Row(children: [
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF20A747)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(s.t('driverPickupCompleteHeadingToCustomer'), style: const TextStyle(color: AppColors.muted, height: 1.35))),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: deliveryAddress.isEmpty ? null : _showLocationPreview,
                          icon: const Icon(Icons.map_outlined),
                          label: Text(s.t('driverPreviewCustomerLocation')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF20A747),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(58),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: arrivalNotified || _notifyingArrival ? null : _notifyCustomerArrival,
                          icon: _notifyingArrival
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  arrivalNotified
                                      ? Icons.notifications_active_rounded
                                      : Icons.notifications_outlined,
                                ),
                          label: Text(
                            arrivalNotified
                                ? s.t('driverCustomerArrivalNotified')
                                : s.t('driverNotifyCustomerArrival'),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: arrivalNotified
                                ? const Color(0xFF20A747)
                                : AppColors.orange,
                            side: BorderSide(
                              color: arrivalNotified
                                  ? const Color(0xFFBFE8C8)
                                  : AppColors.orange,
                            ),
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: _confirmingDelivery ? null : _confirmDelivery,
                          icon: _confirmingDelivery
                              ? const SizedBox.square(dimension: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_circle_rounded),
                          label: Text(s.t('driverDeliveredOneTap')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF20A747),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(62),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _paymentLabel(AppStrings s, String raw) {
    switch (raw.toLowerCase()) {
      case 'cash':
        return s.t('driverPaymentCash');
      case 'card':
      case 'online':
      case 'electronic':
        return s.t('driverPaymentElectronic');
      default:
        return raw.isEmpty ? '—' : raw;
    }
  }
}

class _DriverOrderSection extends StatelessWidget {
  const _DriverOrderSection({required this.title, required this.icon, required this.accent, required this.child});

  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE7E9ED))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: accent),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: accent, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 11),
        child,
      ]),
    );
  }
}


class _OfferStat extends StatelessWidget {
  const _OfferStat({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: AppColors.orange),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? const Color(0xFF292D35),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
