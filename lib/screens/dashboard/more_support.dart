part of 'partner_dashboard.dart';

class _StoreMorePage extends StatelessWidget {
  const _StoreMorePage({
    required this.store,
    required this.onNavigate,
    required this.onNotifications,
    required this.unreadNotifications,
    required this.onLogout,
  });

  final Map<String, dynamic>? store;
  final ValueChanged<int> onNavigate;
  final VoidCallback onNotifications;
  final int unreadNotifications;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 700;
    final gridColumns = _adaptiveGridColumns(width, phone: 2, tablet: 3, desktop: 6);
    final veryNarrow = width < 350;
    final storeName = store?['name']?.toString().trim();
    final storeId = store?['id']?.toString();

    void openManager(_StoreManagerMode mode) {
      if (storeId == null || storeId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('storeSetupRequired'))));
        return;
      }
      if (mode == _StoreManagerMode.reviews) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => _RatingsManagementPage(storeId: storeId)));
      } else {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => _StoreSimpleRecordsPage(storeId: storeId, mode: mode)));
      }
    }

    void openOperational(_OperationalToolMode mode) {
      if (storeId == null || storeId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('storeSetupRequired'))));
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _StoreOperationalToolPage(storeId: storeId, mode: mode)));
    }

    void openInfo(String title, String body, IconData icon) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SettingsInfoPage(title: title, body: body, icon: icon)));
    }

    Widget actionTile(IconData icon, String title, Color accent, VoidCallback onTap, {int? badge}) {
      final tilePadding = compact ? 9.0 : 14.0;
      final iconBox = compact ? 40.0 : 48.0;
      final iconSize = compact ? 21.0 : 26.0;
      final titleSize = compact ? 10.5 : 13.0;
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(tilePadding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE8EAF0)),
            boxShadow: const [BoxShadow(color: Color(0x08111827), blurRadius: 16, offset: Offset(0, 7))],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(width: iconBox, height: iconBox, decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(compact ? 13 : 16)), child: Icon(icon, color: accent, size: iconSize)),
              if ((badge ?? 0) > 0) Positioned(top: -5, right: -5, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white, width: 2)), child: Text(badge! > 99 ? '99+' : badge.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)))),
            ]),
            SizedBox(height: compact ? 7 : 10),
            Text(title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: titleSize, height: 1.15)),
          ]),
        ),
      );
    }

    return ColoredBox(
      color: const Color(0xFFF8F9FB),
      child: ListView(
        padding: EdgeInsets.fromLTRB(_adaptivePagePadding(context), compact ? 12 : 28, _adaptivePagePadding(context), compact ? 24 : 28),
        children: [Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1050), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _ModernPageHero(title: s.t('more'), subtitle: storeName == null || storeName.isEmpty ? s.t('businessSubtitle') : storeName, icon: Icons.apps_rounded, accent: AppColors.orange, trailing: _DashboardNotificationBell(count: unreadNotifications, onPressed: onNotifications)),
          SizedBox(height: compact ? 8 : 18),
          _ReportSectionCard(
            title: s.t('manageYourStore'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(s.t('storeManagementSubtitle'), style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: compact ? 11 : 14, height: 1.35)),
              SizedBox(height: compact ? 10 : 14),
              GridView.count(
                crossAxisCount: gridColumns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: veryNarrow ? 1.35 : compact ? 1.05 : .90,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  actionTile(Icons.local_offer_rounded, s.t('offers'), const Color(0xFF16A34A), () => onNavigate(3)),
                  actionTile(Icons.grid_view_rounded, s.t('categories'), const Color(0xFF7C3AED), () => openManager(_StoreManagerMode.categories)),
                  actionTile(Icons.restaurant_menu_rounded, s.t('mealManagement'), AppColors.orange, () => onNavigate(2)),
                  actionTile(Icons.star_outline_rounded, s.t('reviews'), const Color(0xFFF59E0B), () => openManager(_StoreManagerMode.reviews)),
                  actionTile(Icons.receipt_long_rounded, s.t('orders'), const Color(0xFF2563EB), () => onNavigate(1)),
                  actionTile(Icons.add_circle_outline_rounded, s.t('addons'), const Color(0xFF0F766E), () => openManager(_StoreManagerMode.addons)),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _ReportSectionCard(
            title: s.t('toolsReports'),
            child: GridView.count(
              crossAxisCount: gridColumns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: veryNarrow ? 1.35 : compact ? 1.05 : .90,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                actionTile(Icons.groups_2_outlined, s.t('customers'), const Color(0xFF16A34A), () => openOperational(_OperationalToolMode.customers)),
                actionTile(Icons.description_outlined, s.t('reports'), const Color(0xFF2563EB), () => onNavigate(4)),
                actionTile(Icons.bar_chart_rounded, s.t('statistics'), AppColors.orange, () => onNavigate(4)),
                actionTile(Icons.speed_rounded, s.t('performance'), const Color(0xFF7C3AED), () => openOperational(_OperationalToolMode.performance)),
                actionTile(Icons.delivery_dining_rounded, s.t('drivers'), const Color(0xFF0284C7), () => openOperational(_OperationalToolMode.drivers)),
                actionTile(Icons.notifications_active_outlined, s.t('alerts'), const Color(0xFFDC2626), onNotifications, badge: unreadNotifications),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ReportSectionCard(
            title: s.t('moreOptions'),
            child: Column(children: [
              _MoreListTile(icon: Icons.chat_bubble_outline_rounded, title: s.t('messagesSupport'), subtitle: s.t('contactSupportSubtitle'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _StoreSupportInboxPage(storeId: storeId)))),
              _MoreListTile(icon: Icons.help_outline_rounded, title: s.t('faq'), subtitle: s.t('supportHelp'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _StoreFaqPage()))),
              _MoreListTile(icon: Icons.info_outline_rounded, title: s.t('aboutHalaTalab'), subtitle: s.t('appTitle'), onTap: () => openInfo(s.t('aboutHalaTalab'), s.t('aboutHalaTalabBody'), Icons.info_outline_rounded)),
            ]),
          ),
          const SizedBox(height: 16),
          _ReportSectionCard(
            title: s.t('settings'),
            child: Column(children: [
              _MoreListTile(icon: Icons.settings_outlined, title: s.t('storeSettingsTitle'), subtitle: s.t('settingsSubtitle'), onTap: () => onNavigate(5)),
              _MoreListTile(icon: Icons.notifications_none_rounded, title: s.t('storeNotificationsTitle'), subtitle: s.t('orderNotificationsSubtitle'), onTap: onNotifications),
            ]),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: onLogout, style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626), side: const BorderSide(color: Color(0xFFFCA5A5)), padding: const EdgeInsets.symmetric(vertical: 15)), icon: const Icon(Icons.logout_rounded), label: Text(s.t('logout'), style: const TextStyle(fontWeight: FontWeight.w900))),
        ])))],
      ),
    );
  }
}

enum _OperationalToolMode { customers, performance, drivers }

class _StoreOperationalToolPage extends StatefulWidget {
  const _StoreOperationalToolPage({required this.storeId, required this.mode});
  final String storeId;
  final _OperationalToolMode mode;
  @override
  State<_StoreOperationalToolPage> createState() => _StoreOperationalToolPageState();
}

class _StoreOperationalToolPageState extends State<_StoreOperationalToolPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, String>> _driverPeople = const [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await Supabase.instance.client.from('orders').select().eq('store_id', widget.storeId).order('created_at', ascending: false).limit(500);
      var driverPeople = const <Map<String, String>>[];
      if (widget.mode == _OperationalToolMode.drivers) {
        try {
          final rows = await Supabase.instance.client.rpc(
            'store_get_order_drivers_v1',
            params: {'p_store_id': widget.storeId},
          );
          driverPeople = List<Map<String, dynamic>>.from(rows as List)
              .map((row) => <String, String>{
                    'id': row['driver_id']?.toString() ?? '',
                    'name': row['full_name']?.toString().trim() ?? '',
                    'phone': row['phone']?.toString().trim() ?? '',
                  })
              .toList();
        } catch (e, st) {
          debugPrint('Could not load store driver names: $e\n$st');
        }
      }
      if (!mounted) return;
      setState(() {
        _orders = List<Map<String, dynamic>>.from(result);
        _driverPeople = driverPeople;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _title(AppStrings s) => widget.mode == _OperationalToolMode.customers ? s.t('customers') : widget.mode == _OperationalToolMode.performance ? s.t('performance') : s.t('drivers');
  String _subtitle(AppStrings s) => widget.mode == _OperationalToolMode.customers ? s.t('customersSubtitle') : widget.mode == _OperationalToolMode.performance ? s.t('performanceSubtitle') : s.t('driversSubtitle');
  IconData get _icon => widget.mode == _OperationalToolMode.customers ? Icons.groups_2_outlined : widget.mode == _OperationalToolMode.performance ? Icons.speed_rounded : Icons.delivery_dining_rounded;

  List<Map<String, String>> _uniquePeople(bool drivers) {
    final seen = <String>{};
    final out = <Map<String, String>>[];
    for (final order in _orders) {
      final id = (drivers ? order['driver_id'] : order['customer_id'])?.toString().trim() ?? '';
      final name = (drivers ? (order['driver_name'] ?? order['driver_full_name']) : (order['customer_name'] ?? order['customer_full_name']))?.toString().trim() ?? '';
      final phone = (drivers ? order['driver_phone'] : order['customer_phone'])?.toString().trim() ?? '';
      final key = id.isNotEmpty ? id : '${name.toLowerCase()}|$phone';
      if (key.replaceAll('|', '').isEmpty || !seen.add(key)) continue;
      out.add({'id': id, 'name': name, 'phone': phone});
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_title(s)), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: ColoredBox(
        color: const Color(0xFFF8F9FB),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 950), child: Padding(
          padding: const EdgeInsets.all(20),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 44), const SizedBox(height: 12), Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry'))]))
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _ModernPageHero(title: _title(s), subtitle: _subtitle(s), icon: _icon, accent: AppColors.orange),
                      const SizedBox(height: 16),
                      Expanded(child: widget.mode == _OperationalToolMode.performance ? _performanceBody(s) : _peopleBody(s, widget.mode == _OperationalToolMode.drivers)),
                    ]),
        ))),
      ),
    );
  }

  Widget _peopleBody(AppStrings s, bool drivers) {
    final people = drivers && _driverPeople.isNotEmpty ? _driverPeople : _uniquePeople(drivers);
    if (people.isEmpty) return Center(child: Text(drivers ? s.t('noDriversYet') : s.t('noCustomersYet'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)));
    return ListView.separated(
      itemCount: people.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final person = people[index];
        final name = person['name']!.isNotEmpty
            ? person['name']!
            : (person['phone']!.isNotEmpty
                ? person['phone']!
                : (drivers
                    ? _p55(context, 'سائق بدون اسم', 'شۆفێر بێ ناو', 'Unnamed driver')
                    : _p55(context, 'عميل بدون اسم', 'کڕیار بێ ناو', 'Unnamed customer')));
        return ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE8EAF0))),
          leading: CircleAvatar(backgroundColor: AppColors.orange.withValues(alpha: .10), child: Icon(drivers ? Icons.delivery_dining_rounded : Icons.person_outline_rounded, color: AppColors.orange)),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: person['phone']!.isNotEmpty && person['phone'] != name ? Text(person['phone']!) : null,
        );
      },
    );
  }

  Widget _performanceBody(AppStrings s) {
    final total = _orders.length;
    final completed = _orders.where((o) => ['completed', 'delivered'].contains((o['status'] ?? '').toString().toLowerCase())).length;
    final cancelled = _orders.where((o) => ['cancelled', 'canceled', 'rejected'].contains((o['status'] ?? '').toString().toLowerCase())).length;
    double revenue = 0;
    for (final o in _orders) {
      final value = o['total_amount'] ?? o['total'] ?? o['grand_total'];
      if (value is num) {
        revenue += value.toDouble();
      } else {
        revenue += double.tryParse(value?.toString() ?? '') ?? 0;
      }
    }
    final avg = total == 0 ? 0 : revenue / total;
    final items = [
      (s.t('ordersCountLabel'), total.toString(), Icons.receipt_long_outlined),
      (s.t('completedOrdersMetric'), completed.toString(), Icons.check_circle_outline_rounded),
      (s.t('cancelledStatus'), cancelled.toString(), Icons.cancel_outlined),
      (s.t('averageOrderValue'), '${avg.toStringAsFixed(0)} ${s.t('currencyIqd')}', Icons.payments_outlined),
    ];
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 330, mainAxisExtent: 180, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8EAF0))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(item.$3, color: AppColors.orange), const Spacer(), Text(item.$2, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text(item.$1, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700))]),
        );
      },
    );
  }
}

class _MoreListTile extends StatelessWidget {
  const _MoreListTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return ListTile(
      onTap: onTap,
      dense: compact,
      minVerticalPadding: compact ? 4 : 8,
      contentPadding: EdgeInsets.symmetric(horizontal: compact ? 2 : 4, vertical: compact ? 1 : 4),
      leading: Container(
        width: compact ? 38 : 44,
        height: compact ? 38 : 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(compact ? 12 : 14),
          border: Border.all(color: const Color(0xFFE8EAF0)),
        ),
        child: Icon(icon, color: const Color(0xFF475569), size: compact ? 19 : 24),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 12 : 14)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontSize: compact ? 10.5 : 12)),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: compact ? 18 : 24),
    );
  }
}


class _StoreFaqPage extends StatelessWidget {
  const _StoreFaqPage();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final blocks = s.t('faqBody').split(RegExp(r'\n\s*\n')).where((e) => e.trim().isNotEmpty).toList();
    final items = <({String q, String a})>[];
    for (final block in blocks) {
      final lines = block.split('\n').where((e) => e.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;
      items.add((q: lines.first.trim(), a: lines.skip(1).join('\n').trim()));
    }
    return Scaffold(
      appBar: AppBar(title: Text(s.t('faq'))),
      body: ListView(
        padding: EdgeInsets.all(_adaptivePagePadding(context)),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF6A1A), Color(0xFFFF8A3D)]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(children: [
              Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.help_outline_rounded, color: AppColors.orange)),
              const SizedBox(width: 14),
              Expanded(child: Text(s.t('faq'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900))),
            ]),
          ),
          const SizedBox(height: 14),
          ...items.map((item) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE8EAF0))),
            elevation: 0,
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Text(item.q, style: const TextStyle(fontWeight: FontWeight.w900)),
              children: [Align(alignment: AlignmentDirectional.centerStart, child: Text(item.a, style: const TextStyle(color: AppColors.muted, height: 1.6)))],
            ),
          )),
        ],
      ),
    );
  }
}

class _StoreSupportInboxPage extends StatefulWidget {
  const _StoreSupportInboxPage({required this.storeId, this.initialTicketId, this.isDriver = false});
  final String? storeId;
  final String? initialTicketId;
  final bool isDriver;
  @override
  State<_StoreSupportInboxPage> createState() => _StoreSupportInboxPageState();
}

class _StoreSupportInboxPageState extends State<_StoreSupportInboxPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = const [];
  Map<String, int> _unreadByTicket = const {};
  RealtimeChannel? _ticketsChannel;
  bool _openedInitial = false;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    if (_ticketsChannel != null) Supabase.instance.client.removeChannel(_ticketsChannel!);
    super.dispose();
  }

  Future<void> _subscribe() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final storeId = widget.storeId?.trim();
    final ticketFilter = widget.isDriver || storeId == null || storeId.isEmpty
        ? PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          )
        : PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'store_id',
            value: storeId,
          );
    _ticketsChannel = Supabase.instance.client
        .channel('store-support-inbox-${storeId ?? user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'partner_support_tickets',
          filter: ticketFilter,
          callback: (_) => _load(silent: true),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'partner_support_messages',
          callback: (_) => _load(silent: true),
        )
        .subscribe();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw const AuthException('No signed-in user');
      var ticketQuery = Supabase.instance.client
          .from('partner_support_tickets')
          .select()
          .eq('user_id', user.id);
      final storeId = widget.storeId?.trim();
      if (!widget.isDriver && storeId != null && storeId.isNotEmpty) {
        ticketQuery = ticketQuery.eq('store_id', storeId);
      }
      final rows = await ticketQuery.order('updated_at', ascending: false);
      final tickets = List<Map<String, dynamic>>.from(rows);
      final ids = tickets.map((e) => e['id']?.toString()).whereType<String>().where((e) => e.isNotEmpty).toList();
      final unread = <String, int>{};
      if (ids.isNotEmpty) {
        final messageRows = await Supabase.instance.client
            .from('partner_support_messages')
            .select('ticket_id,sender_role,is_read')
            .inFilter('ticket_id', ids);
        for (final raw in messageRows) {
          final m = Map<String, dynamic>.from(raw);
          final role = (m['sender_role'] ?? '').toString().toLowerCase();
          final isAdmin = role == 'admin' || role == 'support' || role == 'management';
          if (isAdmin && m['is_read'] != true) {
            final id = m['ticket_id']?.toString();
            if (id != null && id.isNotEmpty) unread[id] = (unread[id] ?? 0) + 1;
          }
        }
      }
      if (!mounted) return;
      setState(() { _tickets = tickets; _unreadByTicket = unread; _loading = false; });
      final target = widget.initialTicketId;
      if (!_openedInitial && target != null && target.isNotEmpty) {
        final match = _tickets.where((t) => t['id']?.toString() == target).toList();
        if (match.isNotEmpty) {
          _openedInitial = true;
          WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _openTicket(match.first); });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _newTicket() async {
    final created = await showDialog<bool>(context: context, builder: (_) => _PartnerSupportDialog(storeId: widget.storeId, isDriver: widget.isDriver));
    if (created == true) await _load();
  }

  Future<void> _deleteTicket(Map<String, dynamic> ticket) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف المحادثة'),
      content: const Text('هل تريد حذف محادثة الدعم هذه؟'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.delete_outline), label: const Text('حذف'))],
    ));
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc('partner_delete_support_ticket_v1', params: {'p_ticket_id': ticket['id']});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف المحادثة: $e')));
    }
  }

  Future<void> _openTicket(Map<String, dynamic> ticket) async {
    final id = ticket['id']?.toString();
    if (id != null && id.isNotEmpty) {
      try {
        await Supabase.instance.client.rpc('partner_mark_support_ticket_read_v1', params: {'p_ticket_id': id});
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _StoreSupportConversationPage(ticket: ticket, isDriver: widget.isDriver)));
    await _load(silent: true);
  }

  String _categoryLabel(String category) => switch (category.toLowerCase()) {
    'general' => 'عام',
    'orders' || 'order' => 'الطلبات',
    'payments' || 'payment' => 'الدفع',
    'products' || 'product' => 'المنتجات',
    'account' => 'الحساب',
    'technical' => 'مشكلة تقنية',
    _ => category,
  };

  String _statusLabel(String status) => switch (status) { 'resolved' => 'تم الحل', 'closed' => 'مغلقة', 'in_progress' => 'قيد المتابعة', _ => 'مفتوحة' };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('messagesSupport')), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _newTicket, icon: const Icon(Icons.add_comment_outlined), label: Text(s.t('contactSupport'))),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center))) : _tickets.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.forum_outlined, size: 64, color: AppColors.muted), const SizedBox(height: 12), Text(s.t('messagesSupport'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text(s.t('contactSupportSubtitle'), style: const TextStyle(color: AppColors.muted))]))
        : ListView.separated(
            padding: EdgeInsets.fromLTRB(_adaptivePagePadding(context), 14, _adaptivePagePadding(context), 96),
            itemCount: _tickets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final ticket = _tickets[index];
              final message = ticket['message']?.toString() ?? '';
              final category = ticket['category']?.toString() ?? 'general';
              final status = ticket['status']?.toString() ?? 'open';
              final ticketId = ticket['id']?.toString() ?? '';
              final unread = _unreadByTicket[ticketId] ?? 0;
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE5E7EB))),
                child: ListTile(
                  onTap: () => _openTicket(ticket),
                  contentPadding: const EdgeInsetsDirectional.fromSTEB(15, 10, 6, 10),
                  leading: Stack(clipBehavior: Clip.none, children: [
                    const CircleAvatar(backgroundColor: Color(0xFFFFEEE2), child: Icon(Icons.support_agent_rounded, color: AppColors.orange)),
                    if (unread > 0) PositionedDirectional(top: -4, end: -5, child: Container(
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white, width: 2)),
                      child: Text(unread > 99 ? '99+' : unread.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                    )),
                  ]),
                  title: Row(children: [
                    Expanded(child: Text(_categoryLabel(category), style: TextStyle(fontWeight: FontWeight.w900, color: unread > 0 ? const Color(0xFF111827) : null))),
                    if (unread > 0) Container(margin: const EdgeInsetsDirectional.only(start: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFFFE8E8), borderRadius: BorderRadius.circular(20)), child: Text('جديد $unread', style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 10, fontWeight: FontWeight.w900))),
                  ]),
                  subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(message, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(_statusLabel(status), style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w700)),
                  ])),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) { if (v == 'delete') _deleteTicket(ticket); },
                    itemBuilder: (_) => [const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded), SizedBox(width: 8), Text('حذف')]))],
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ),
              );
            },
          ),
    );
  }
}

class _StoreSupportConversationPage extends StatefulWidget {
  const _StoreSupportConversationPage({required this.ticket, this.isDriver = false});
  final Map<String, dynamic> ticket;
  final bool isDriver;
  @override
  State<_StoreSupportConversationPage> createState() => _StoreSupportConversationPageState();
}

class _StoreSupportConversationPageState extends State<_StoreSupportConversationPage> {
  bool _loading = true;
  bool _sending = false;
  List<Map<String, dynamic>> _messages = const [];
  RealtimeChannel? _channel;
  final TextEditingController _reply = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() { super.initState(); _load(); _subscribe(); }
  @override
  void dispose() {
    _reply.dispose();
    _scrollController.dispose();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _subscribe() async {
    final id = widget.ticket['id']?.toString();
    if (id == null) return;
    _channel = Supabase.instance.client.channel('store-support-chat-$id')
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'partner_support_messages', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'ticket_id', value: id), callback: (_) => _load(silent: true))
      .subscribe();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final id = widget.ticket['id']?.toString();
      if (id == null) return;
      final rows = await Supabase.instance.client
          .from('partner_support_messages')
          .select()
          .eq('ticket_id', id)
          .order('created_at', ascending: true)
          .order('id', ascending: true);
      try {
        await Supabase.instance.client.rpc('partner_mark_support_ticket_read_v1', params: {'p_ticket_id': id});
      } catch (_) {}
      if (mounted) {
        final ordered = List<Map<String, dynamic>>.from(rows)..sort(_compareMessages);
        setState(() { _messages = ordered; _loading = false; });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime _messageTime(Map<String, dynamic> row) {
    return DateTime.tryParse(row['created_at']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  int _compareMessages(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byTime = _messageTime(a).compareTo(_messageTime(b));
    if (byTime != 0) return byTime;
    return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    final id = widget.ticket['id']?.toString();
    if (text.isEmpty || id == null || id.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await Supabase.instance.client.rpc(
        'partner_send_support_reply_v1',
        params: {'p_ticket_id': id, 'p_message': text},
      );
      if (!mounted) return;
      _reply.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال الرد: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.ticket['message']?.toString() ?? '';
    final all = <Map<String, dynamic>>[
      {
        'id': 'ticket:${widget.ticket['id'] ?? ''}',
        'sender_role': 'partner',
        'message': initial,
        'created_at': widget.ticket['created_at'],
      },
      ..._messages,
    ]..sort(_compareMessages);
    _scrollToBottom();
    return Scaffold(
      appBar: AppBar(title: const Text('محادثة الدعم'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: Column(
        children: [
          Expanded(
            child: _loading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
              controller: _scrollController,
              reverse: false,
              padding: const EdgeInsets.all(16),
              itemCount: all.length,
              itemBuilder: (context, index) {
                final m = all[index];
                final role = m['sender_role']?.toString() ?? '';
                final mine = role != 'admin' && role != 'support';
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(color: mine ? const Color(0xFFFFEEE2) : const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(mine ? (widget.isDriver ? 'السائق' : 'المتجر') : 'دعم هلا طلب', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: mine ? AppColors.orangeDark : AppColors.muted)),
                      const SizedBox(height: 4),
                      Text(m['message']?.toString() ?? '', style: const TextStyle(height: 1.5)),
                    ]),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'اكتب ردك إلى دعم هلا طلب...',
                        filled: true,
                        fillColor: const Color(0xFFF7F8FA),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendReply,
                    style: IconButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white),
                    icon: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
