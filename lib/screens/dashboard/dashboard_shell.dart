part of 'partner_dashboard.dart';

class _AccountHomeScreen extends StatefulWidget {
  const _AccountHomeScreen({
    required this.currentLocale,
    required this.onLocaleChanged,
    required this.profile,
    required this.store,
    required this.onLogout,
  });

  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final Map<String, dynamic>? profile, store;
  final Future<void> Function() onLogout;

  @override
  State<_AccountHomeScreen> createState() => _AccountHomeScreenState();
}

class _AccountHomeScreenState extends State<_AccountHomeScreen> {
  int _selectedIndex = 0;
  final List<int> _navigationHistory = <int>[];
  late Map<String, dynamic>? _store;
  bool _updatingOpenStatus = false;
  int _unreadNotifications = 0;
  Timer? _notificationsTimer;
  RealtimeChannel? _notificationsChannel;

  @override
  void initState() {
    super.initState();
    _store = widget.store == null ? null : Map<String, dynamic>.from(widget.store!);
    _refreshUnreadNotifications();
    _startRealtimeNotifications();
    _notificationsTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshUnreadNotifications());
  }

  @override
  void dispose() {
    _notificationsTimer?.cancel();
    final channel = _notificationsChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }


  void _selectIndex(int index, {bool remember = true}) {
    if (index == _selectedIndex) return;
    setState(() {
      if (remember) {
        _navigationHistory.remove(index);
        _navigationHistory.add(_selectedIndex);
      }
      _selectedIndex = index;
    });
  }

  Future<void> _startRealtimeNotifications() async {
    try {
      final storeId = _store?['id']?.toString();
      if (storeId == null || storeId.isEmpty) return;

      final previous = _notificationsChannel;
      if (previous != null) {
        await Supabase.instance.client.removeChannel(previous);
      }

      final channel = Supabase.instance.client
          .channel('store-notifications-$storeId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'store_id',
              value: storeId,
            ),
            callback: (payload) {
              if (!mounted) return;
              final record = Map<String, dynamic>.from(payload.newRecord);
              final s = AppStrings.of(context);
              final number = record['order_number']?.toString() ?? '';
              final total = record['total']?.toString() ?? '';
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 8),
                    behavior: SnackBarBehavior.floating,
                    content: Row(
                      children: [
                        const Icon(Icons.notifications_active_rounded, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            number.isEmpty
                                ? s.t('newOrderRealtimeBody')
                                : '${s.t('newOrderNotification')} #$number${total.isEmpty ? '' : ' • $total د.ع'}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    action: SnackBarAction(
                      label: s.t('openOrder'),
                      textColor: Colors.white,
                      onPressed: () => _selectIndex(1),
                    ),
                  ),
                );
              Future<void>.delayed(const Duration(milliseconds: 350), _refreshUnreadNotifications);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'store_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'store_id',
              value: storeId,
            ),
            callback: (_) => _refreshUnreadNotifications(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'store_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'store_id',
              value: storeId,
            ),
            callback: (_) => _refreshUnreadNotifications(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'store_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'store_id',
              value: storeId,
            ),
            callback: (_) => _refreshUnreadNotifications(),
          )
          .subscribe();
      _notificationsChannel = channel;
    } catch (_) {
      // Keep the periodic fallback active if Realtime is not enabled yet.
    }
  }

  Future<void> _refreshUnreadNotifications() async {
    try {
      final count = await AuthService.instance.getUnreadNotificationCount();
      if (mounted) setState(() => _unreadNotifications = count);
    } catch (_) {
      // The notifications table may not exist until the stage SQL is executed.
    }
  }

  Future<void> _openNotifications() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _StoreNotificationsDialog(
        onUnreadCountChanged: (count) {
          if (mounted) setState(() => _unreadNotifications = count);
        },
        onOpenOrder: (_) {
          if (mounted) _selectIndex(1);
        },
        onOpenSupport: (ticketId) {
          if (!mounted) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _StoreSupportInboxPage(
              storeId: _store?['id']?.toString(),
              initialTicketId: ticketId,
            ),
          ));
        },
      ),
    );
    await _refreshUnreadNotifications();
  }

  Future<void> _toggleOpen(bool value) async {
    if (_updatingOpenStatus) return;
    setState(() => _updatingOpenStatus = true);
    try {
      final updated = await AuthService.instance.updateStoreOpenStatus(value);
      if (!mounted) return;
      setState(() => _store = updated);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تغيير حالة المتجر: $error')),
      );
    } finally {
      if (mounted) setState(() => _updatingOpenStatus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.profile?['role'] as String?;
    if (role == 'driver') {
      return _DriverHomeScreen(
        currentLocale: widget.currentLocale,
        onLocaleChanged: widget.onLocaleChanged,
        profile: widget.profile,
        onLogout: widget.onLogout,
      );
    }

    final s = AppStrings.of(context);
    final surface = Theme.of(context).colorScheme.surface;
    final shellBackground = const Color(0xFFF6F7FB);
    final softSurface = const Color(0xFFF6F7F9);
    final shellBorder = const Color(0xFFE9EBF0);
    final items = [
      (s.t('overview'), Icons.grid_view_rounded),
      (s.t('orders'), Icons.receipt_long_rounded),
      (s.t('products'), Icons.inventory_2_rounded),
      (s.t('offers'), Icons.local_offer_rounded),
      (s.t('reports'), Icons.insights_rounded),
      (s.t('settings'), Icons.tune_rounded),
    ];

    Widget currentContent() => _selectedIndex == 0
        ? _StoreOverviewPage(
            store: _store,
            updatingOpenStatus: _updatingOpenStatus,
            onOpenChanged: _toggleOpen,
            onNavigate: _selectIndex,
          )
        : _selectedIndex == 1
            ? const _OrdersManagementPage()
            : _selectedIndex == 2
                ? _ProductsManagementPage(businessType: _store?['business_type']?.toString() ?? 'restaurant')
                : _selectedIndex == 3
                    ? const _OffersManagementPage()
                    : _selectedIndex == 4
                        ? const _ReportsAnalyticsPage()
                        : _selectedIndex == 5
                            ? _StoreSettingsPage(
                                store: _store,
                                onSaved: (updated) => setState(() => _store = updated),
                                currentLocale: widget.currentLocale,
                                onLocaleChanged: widget.onLocaleChanged,
                                onLogout: widget.onLogout,
                              )
                            : _StoreMorePage(
                                store: _store,
                                onNavigate: _selectIndex,
                                onNotifications: _openNotifications,
                                unreadNotifications: _unreadNotifications,
                                onLogout: widget.onLogout,
                              );

    // Stage 147: keep the active dashboard subtree stable. AnimatedSwitcher
    // was deactivating inherited-widget dependents while Android was also
    // updating keyboard/back state, which could surface the red
    // `_dependents.isEmpty` framework assertion in debug builds.
    Widget stableContent() => KeyedSubtree(
          key: ValueKey<int>(_selectedIndex),
          child: currentContent(),
        );

    final canLeaveShell = _navigationHistory.isEmpty && _selectedIndex == 0;
    return PopScope<Object?>(
      canPop: canLeaveShell,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_navigationHistory.isNotEmpty) {
          final previous = _navigationHistory.removeLast();
          _selectIndex(previous, remember: false);
          return;
        }
        if (_selectedIndex != 0) {
          _selectIndex(0, remember: false);
        }
      },
      child: Scaffold(
        backgroundColor: shellBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 1040;
            final veryNarrow = constraints.maxWidth < 350;
            final tablet = constraints.maxWidth >= 600 && constraints.maxWidth < 1040;
            if (!desktop) {
              return Column(
                children: [
                  _DashboardMobileTopBar(
                    title: _selectedIndex == 6 ? s.t('more') : items[_selectedIndex.clamp(0, 5)].$1,
                    currentLocale: widget.currentLocale,
                    onLocaleChanged: widget.onLocaleChanged,
                    unreadNotifications: _unreadNotifications,
                    onNotifications: _openNotifications,
                  ),
                  Expanded(child: stableContent()),
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: surface,
                          border: Border(top: BorderSide(color: shellBorder)),
                        ),
                        child: NavigationBarTheme(
                          data: NavigationBarThemeData(
                            labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                              fontSize: veryNarrow ? 9.0 : tablet ? 11.0 : 10.5,
                              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
                            )),
                            iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                              size: states.contains(WidgetState.selected) ? (veryNarrow ? 21 : 23) : (veryNarrow ? 19 : 21),
                            )),
                          ),
                          child: NavigationBar(
                          height: veryNarrow ? 58 : 62,
                          backgroundColor: surface,
                          indicatorColor: const Color(0xFFFFE9D9),
                          selectedIndex: _selectedIndex == 0 ? 0 : _selectedIndex == 1 ? 1 : _selectedIndex == 4 ? 2 : 3,
                          onDestinationSelected: (index) {
                            final mapped = [0, 1, 4, 6][index];
                            _selectIndex(mapped);
                          },
                          destinations: [
                            NavigationDestination(icon: const Icon(Icons.home_rounded), selectedIcon: const Icon(Icons.home_rounded, color: AppColors.orange), label: s.t('overview')),
                            NavigationDestination(icon: const Icon(Icons.shopping_bag_outlined), selectedIcon: const Icon(Icons.shopping_bag_rounded, color: AppColors.orange), label: s.t('orders')),
                            NavigationDestination(icon: const Icon(Icons.bar_chart_rounded), selectedIcon: const Icon(Icons.bar_chart_rounded, color: AppColors.orange), label: s.t('reports')),
                            NavigationDestination(icon: const Icon(Icons.more_horiz_rounded), selectedIcon: const Icon(Icons.more_horiz_rounded, color: AppColors.orange), label: s.t('more')),
                          ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                Container(
                  width: 276,
                  margin: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: shellBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A172033),
                        blurRadius: 30,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF2E8),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Image.asset('assets/images/hala_partner_logo.png'),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.t('appTitle'),
                                    style: const TextStyle(
                                      color: AppColors.orange,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    s.t('storeDashboard'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: _StoreIdentityCard(store: _store),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final selected = index == _selectedIndex;
                            return Material(
                              color: selected ? const Color(0xFFFFF1E7) : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                onTap: () => _selectIndex(index),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: selected ? surface : softSurface,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          items[index].$2,
                                          size: 20,
                                          color: selected ? AppColors.orange : const Color(0xFF747C8A),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          items[index].$1,
                                          style: TextStyle(
                                            color: selected ? AppColors.ink : const Color(0xFF596273),
                                            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (selected)
                                        Container(
                                          width: 5,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: AppColors.orange,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                        child: OutlinedButton.icon(
                          onPressed: widget.onLogout,
                          icon: const Icon(Icons.logout_rounded),
                          label: Text(s.t('logout')),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            foregroundColor: const Color(0xFF5C6472),
                            side: const BorderSide(color: Color(0xFFE2E5EA)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _DashboardDesktopTopBar(
                        title: items[_selectedIndex].$1,
                        storeName: _store?['name']?.toString() ?? s.t('storeDashboard'),
                        currentLocale: widget.currentLocale,
                        onLocaleChanged: widget.onLocaleChanged,
                        unreadNotifications: _unreadNotifications,
                        onNotifications: _openNotifications,
                      ),
                      Expanded(child: stableContent()),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      ),
    );
  }
}
