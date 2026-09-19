part of 'partner_dashboard.dart';

class _StoreNotificationsDialog extends StatefulWidget {
  const _StoreNotificationsDialog({this.onUnreadCountChanged, this.onOpenOrder, this.onOpenSupport});

  final ValueChanged<int>? onUnreadCountChanged;
  final ValueChanged<String>? onOpenOrder;
  final ValueChanged<String>? onOpenSupport;

  @override
  State<_StoreNotificationsDialog> createState() => _StoreNotificationsDialogState();
}

class _StoreNotificationsDialogState extends State<_StoreNotificationsDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  RealtimeChannel? _channel;
  String _filter = 'all';

  int get _unreadCount => _items.where((item) => item['is_read'] != true).length;

  List<Map<String, dynamic>> get _visibleItems => switch (_filter) {
    'unread' => _items.where((item) => item['is_read'] != true).toList(),
    'read' => _items.where((item) => item['is_read'] == true).toList(),
    _ => _items,
  };

  void _notifyUnreadCount() => widget.onUnreadCountChanged?.call(_unreadCount);

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  Future<void> _subscribeRealtime() async {
    try {
      final store = await AuthService.instance.getCurrentStore();
      final storeId = store?['id']?.toString();
      if (storeId == null || !mounted) return;
      _channel = Supabase.instance.client
          .channel('notifications-dialog-$storeId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'store_notifications',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'store_id', value: storeId),
            callback: (payload) {
              if (!mounted) return;
              final item = Map<String, dynamic>.from(payload.newRecord);
              setState(() => _items = [item, ..._items.where((x) => x['id'] != item['id'])]);
              _notifyUnreadCount();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'store_notifications',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'store_id', value: storeId),
            callback: (payload) {
              if (!mounted) return;
              final item = Map<String, dynamic>.from(payload.newRecord);
              setState(() {
                final index = _items.indexWhere((x) => x['id'] == item['id']);
                if (index >= 0) _items[index] = item;
              });
              _notifyUnreadCount();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'store_notifications',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'store_id', value: storeId),
            callback: (payload) {
              if (!mounted) return;
              final deletedId = payload.oldRecord['id']?.toString();
              if (deletedId == null) return;
              setState(() => _items = _items.where((x) => x['id']?.toString() != deletedId).toList());
              _notifyUnreadCount();
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await AuthService.instance.getStoreNotifications();
      if (mounted) {
        setState(() => _items = items);
        _notifyUnreadCount();
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(Map<String, dynamic> item) async {
    if (item['is_read'] == true) return;
    await AuthService.instance.markNotificationRead(item['id'].toString());
    if (!mounted) return;
    setState(() {
      final index = _items.indexWhere((x) => x['id'] == item['id']);
      if (index >= 0) _items[index] = {..._items[index], 'is_read': true};
    });
    _notifyUnreadCount();
  }

  Future<void> _markUnread(Map<String, dynamic> item) async {
    if (item['is_read'] != true) return;
    await AuthService.instance.markNotificationUnread(item['id'].toString());
    if (!mounted) return;
    setState(() {
      final index = _items.indexWhere((x) => x['id'] == item['id']);
      if (index >= 0) _items[index] = {..._items[index], 'is_read': false, 'read_at': null};
    });
    _notifyUnreadCount();
  }

  Future<void> _markAllRead() async {
    await AuthService.instance.markAllNotificationsRead();
    if (!mounted) return;
    setState(() => _items = _items.map((x) => {...x, 'is_read': true}).toList());
    _notifyUnreadCount();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    await AuthService.instance.deleteStoreNotification(item['id'].toString());
    if (!mounted) return;
    setState(() => _items = _items.where((x) => x['id'] != item['id']).toList());
    _notifyUnreadCount();
  }

  Future<void> _deleteAll() async {
    if (_items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف جميع الإشعارات'),
        content: const Text('هل تريد حذف جميع إشعارات المتجر؟ لا يمكن التراجع عن هذه العملية.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('حذف الكل'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AuthService.instance.deleteAllStoreNotifications();
      if (!mounted) return;
      setState(() {
        _items = const [];
        _filter = 'all';
      });
      _notifyUnreadCount();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف جميع الإشعارات')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف الإشعارات: $error')));
    }
  }

  String _timeLabel(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inMinutes < 1) return 'الآن';
    if (difference.inHours < 1) return 'منذ ${difference.inMinutes} د';
    if (difference.inDays < 1) return 'منذ ${difference.inHours} س';
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  IconData _iconFor(String type) => switch (type) {
    'new_order' => Icons.receipt_long_rounded,
    'order_status' => Icons.delivery_dining_rounded,
    'promotion' => Icons.local_offer_rounded,
    'system' => Icons.campaign_rounded,
    'support_reply' => Icons.support_agent_rounded,
    _ => Icons.notifications_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: size.height * .82),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 14, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFFFF1E7), Colors.white]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Row(children: [
              Container(width: 46, height: 46, decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.notifications_active_rounded, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('storeNotificationsTitle'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                Text(s.t('notificationsSubtitle'), style: const TextStyle(color: AppColors.muted)),
              ])),
              if (_unreadCount > 0)
                Container(
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEEE2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${s.t('unreadNotificationsCount')}: ${_unreadCount > 99 ? '99+' : _unreadCount}',
                    style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              IconButton(onPressed: _load, tooltip: s.t('refreshNotifications'), icon: const Icon(Icons.refresh_rounded)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(s.t('allNotifications')),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.mark_email_unread_rounded, size: 18),
                  label: Text('${s.t('unreadOnly')} ($_unreadCount)'),
                  selected: _filter == 'unread',
                  onSelected: (_) => setState(() => _filter = 'unread'),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.drafts_rounded, size: 18),
                  label: Text(s.t('readOnly')),
                  selected: _filter == 'read',
                  onSelected: (_) => setState(() => _filter = 'read'),
                ),
              ],
            ),
          ),
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 2, 14, 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_items.any((x) => x['is_read'] != true))
                    TextButton.icon(
                      onPressed: _markAllRead,
                      icon: const Icon(Icons.done_all_rounded),
                      label: Text(s.t('markAllRead')),
                    ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _deleteAll,
                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
                    label: const Text('حذف الكل', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.muted),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(s.t('retry'))),
                      ])))
                    : _visibleItems.isEmpty
                        ? Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.notifications_off_outlined, size: 62, color: Color(0xFFB6BBC5)),
                            const SizedBox(height: 14),
                            Text(s.t('noNotifications'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text(s.t('noNotificationsSubtitle'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                          ])))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                            itemCount: _visibleItems.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = _visibleItems[index];
                              final read = item['is_read'] == true;
                              final type = item['type']?.toString() ?? 'system';
                              return Material(
                                color: read ? Colors.white : const Color(0xFFFFF3EA),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  side: BorderSide(
                                    color: read ? const Color(0xFFE7E9EE) : const Color(0xFFFFC79F),
                                    width: read ? 1 : 1.5,
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () async {
                                    await _markRead(item);
                                    final data = item['data'];
                                    final orderId = data is Map ? data['order_id']?.toString() : null;
                                    final supportTicketId = data is Map ? data['support_ticket_id']?.toString() : null;
                                    if (type == 'support_reply' && supportTicketId != null && supportTicketId.isNotEmpty && widget.onOpenSupport != null && context.mounted) {
                                      Navigator.pop(context);
                                      widget.onOpenSupport!(supportTicketId);
                                      return;
                                    }
                                    if (orderId != null && orderId.isNotEmpty && widget.onOpenOrder != null && context.mounted) {
                                      Navigator.pop(context);
                                      widget.onOpenOrder!(orderId);
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(15),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      CircleAvatar(backgroundColor: read ? const Color(0xFFF1F3F6) : const Color(0xFFFFE1CC), child: Icon(_iconFor(type), color: read ? AppColors.muted : AppColors.orange)),
                                      const SizedBox(width: 12),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Row(children: [
                                          Expanded(child: Text(item['title']?.toString() ?? s.t('storeNotificationsTitle'), style: TextStyle(fontWeight: read ? FontWeight.w700 : FontWeight.w900))),
                                          Text(_timeLabel(item['created_at']), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                        ]),
                                        const SizedBox(height: 5),
                                        Text(item['body']?.toString() ?? '', style: const TextStyle(color: AppColors.muted, height: 1.45)),
                                        const SizedBox(height: 9),
                                        Row(children: [
                                          Icon(
                                            read ? Icons.done_all_rounded : Icons.circle,
                                            size: read ? 17 : 10,
                                            color: read ? const Color(0xFF6F7785) : AppColors.orange,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            read ? s.t('notificationRead') : s.t('notificationUnread'),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: read ? FontWeight.w700 : FontWeight.w900,
                                              color: read ? const Color(0xFF6F7785) : AppColors.orange,
                                            ),
                                          ),
                                        ]),
                                      ])),
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'delete') _delete(item);
                                          if (value == 'unread') _markUnread(item);
                                        },
                                        itemBuilder: (_) => [
                                          if (read)
                                            PopupMenuItem(
                                              value: 'unread',
                                              child: Row(children: [
                                                const Icon(Icons.mark_email_unread_outlined),
                                                const SizedBox(width: 8),
                                                Text(s.t('markUnread')),
                                              ]),
                                            ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Row(children: [
                                              const Icon(Icons.delete_outline_rounded),
                                              const SizedBox(width: 8),
                                              Text(s.t('deleteNotification')),
                                            ]),
                                          ),
                                        ],
                                      ),
                                    ]),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}
