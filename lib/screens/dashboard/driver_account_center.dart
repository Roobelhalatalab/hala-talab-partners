part of 'partner_dashboard.dart';

class _DriverNotificationsScreen extends StatefulWidget {
  const _DriverNotificationsScreen({required this.onBack, required this.onChanged, required this.onOpenOrder});
  final VoidCallback onBack;
  final VoidCallback onChanged;
  final Future<void> Function(String orderId) onOpenOrder;

  @override
  State<_DriverNotificationsScreen> createState() => _DriverNotificationsScreenState();
}

class _DriverNotificationsScreenState extends State<_DriverNotificationsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  RealtimeChannel? _notificationsChannel;

  String get _language => AppStrings.of(context).languageCode;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _notificationsChannel = Supabase.instance.client
        .channel('driver-notifications-screen-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: userId,
          ),
          callback: (_) {
            if (mounted) _load();
            widget.onChanged();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _notificationsChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await DriverDeliveryRepository.instance.getDriverNotifications();
      if (!mounted) return;
      setState(() => _rows = rows);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code == '42P01' || e.code == 'PGRST205' ? 'SQL_REQUIRED' : e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _titleFor(AppStrings s, String type) => switch (type) {
        'available' => _language == 'en' ? 'New delivery request' : _language == 'ku' ? 'داواکاری گەیاندنی نوێ' : 'طلب توصيل جديد',
        'assigned' => s.t('driverNotificationAssignedTitle'),
        'picked_up' => s.t('driverNotificationPickedUpTitle'),
        'delivered' => s.t('driverNotificationDeliveredTitle'),
        'support_reply' => _language == 'en' ? 'New support reply' : _language == 'ku' ? 'وەڵامی نوێی پشتیوانی' : 'رد جديد من دعم هلا طلب',
        'cancelled' || 'canceled' => s.t('driverNotificationCancelledTitle'),
        _ => s.t('driverNotificationsTitle'),
      };

  String _bodyFor(AppStrings s, Map<String, dynamic> row) {
    final number = row['order_number']?.toString().trim();
    final shown = number == null || number.isEmpty ? '—' : '#$number';
    final type = row['event_type']?.toString() ?? '';
    return switch (type) {
      'available' => _language == 'en' ? 'A delivery order from your store is ready $shown' : _language == 'ku' ? 'داواکارییەکی گەیاندن لە فرۆشگاکەت ئامادەیە $shown' : 'يوجد طلب جاهز للتوصيل من متجرك $shown',
      'assigned' => '${s.t('driverNotificationAssignedBody')} $shown',
      'picked_up' => '${s.t('driverNotificationPickedUpBody')} $shown',
      'delivered' => '${s.t('driverNotificationDeliveredBody')} $shown',
      'support_reply' => _language == 'en' ? 'A new reply arrived from Hala Talab support.' : _language == 'ku' ? 'وەڵامێکی نوێ لە پشتیوانی هەلا طلب گەیشت.' : 'وصل رد جديد على رسالة الدعم.',
      'cancelled' || 'canceled' => '${s.t('driverNotificationCancelledBody')} $shown',
      _ => shown,
    };
  }

  IconData _iconFor(String type) => switch (type) {
        'available' => Icons.notifications_active_rounded,
        'assigned' => Icons.delivery_dining_rounded,
        'picked_up' => Icons.shopping_bag_rounded,
        'delivered' => Icons.check_circle_rounded,
        'support_reply' => Icons.support_agent_rounded,
        'cancelled' || 'canceled' => Icons.cancel_rounded,
        _ => Icons.notifications_rounded,
      };


  Future<void> _openNotification(Map<String, dynamic> row) async {
    if (row['is_read'] != true) {
      await DriverDeliveryRepository.instance.setDriverNotificationRead(row['id'].toString(), true);
      widget.onChanged();
    }
    final orderId = row['order_id']?.toString().trim() ?? '';
    final type = row['event_type']?.toString() ?? '';
    if (orderId.isNotEmpty && (type == 'available' || type == 'assigned' || type == 'picked_up')) {
      await widget.onOpenOrder(orderId);
      return;
    }
    await _load();
  }

  Future<void> _markAll() async {
    await DriverDeliveryRepository.instance.markAllDriverNotificationsRead();
    widget.onChanged();
    await _load();
  }

  Future<void> _toggleRead(Map<String, dynamic> row) async {
    await DriverDeliveryRepository.instance.setDriverNotificationRead(
      row['id'].toString(),
      !(row['is_read'] == true),
    );
    widget.onChanged();
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    await DriverDeliveryRepository.instance.deleteDriverNotification(row['id'].toString());
    widget.onChanged();
    await _load();
  }

  Future<void> _deleteAll() async {
    final language = AppStrings.of(context).languageCode;
    final title = language == 'ku' ? 'سڕینەوەی هەموو ئاگادارکردنەوەکان' : language == 'en' ? 'Delete all notifications' : 'حذف جميع الإشعارات';
    final body = language == 'ku' ? 'دڵنیایت دەتەوێت هەموو ئاگادارکردنەوەکان بسڕیتەوە؟' : language == 'en' ? 'Are you sure you want to delete all notifications?' : 'هل أنت متأكد من حذف جميع الإشعارات؟';
    final cancel = language == 'ku' ? 'پاشگەزبوونەوە' : language == 'en' ? 'Cancel' : 'إلغاء';
    final remove = language == 'ku' ? 'سڕینەوەی هەموو' : language == 'en' ? 'Delete all' : 'حذف الكل';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(cancel)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(remove)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DriverDeliveryRepository.instance.deleteAllDriverNotifications();
      if (!mounted) return;
      setState(() => _rows = const []);
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(language == 'en' ? 'All notifications deleted' : language == 'ku' ? 'هەموو ئاگادارکردنەوەکان سڕانەوە' : 'تم حذف جميع الإشعارات')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(language == 'en' ? 'Could not delete notifications' : language == 'ku' ? 'سڕینەوەی ئاگادارکردنەوەکان سەرکەوتوو نەبوو' : 'تعذر حذف الإشعارات')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: AppBar(
        title: Text(s.t('driverNotificationsTitle')),
        leading: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back_rounded)),
        actions: [
          if (_rows.isNotEmpty)
            TextButton.icon(
              onPressed: _deleteAll,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(AppStrings.of(context).languageCode == 'en' ? 'Delete all' : AppStrings.of(context).languageCode == 'ku' ? 'سڕینەوەی هەموو' : 'حذف الكل'),
            ),
          if (_rows.any((e) => e['is_read'] != true))
            TextButton(onPressed: _markAll, child: Text(s.t('driverMarkAllRead'))),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error == 'SQL_REQUIRED'
                  ? _DriverEmptyState(icon: Icons.storage_rounded, title: s.t('driverStage14SqlRequired'), subtitle: s.t('driverStage14SqlHint'))
                  : _error != null
                      ? _DriverEmptyState(icon: Icons.error_outline_rounded, title: s.t('driverLoadFailed'), subtitle: _error!)
                      : _rows.isEmpty
                          ? _DriverEmptyState(icon: Icons.notifications_none_rounded, title: s.t('driverNoNotifications'), subtitle: s.t('driverNoNotificationsSubtitle'))
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _rows.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final row = _rows[index];
                                final type = row['event_type']?.toString() ?? '';
                                final unread = row['is_read'] != true;
                                return Material(
                                  color: unread ? const Color(0xFFFFF5EE) : Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => _openNotification(row),
                                    child: Container(
                                      padding: const EdgeInsets.all(15),
                                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: unread ? const Color(0xFFFFD7BA) : const Color(0xFFE8EAF0))),
                                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        CircleAvatar(backgroundColor: AppColors.orange.withValues(alpha: .12), child: Icon(_iconFor(type), color: AppColors.orange)),
                                        const SizedBox(width: 12),
                                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(_titleFor(s, type), style: TextStyle(fontWeight: unread ? FontWeight.w900 : FontWeight.w700)),
                                          const SizedBox(height: 4),
                                          Text(_bodyFor(s, row), style: const TextStyle(color: AppColors.muted, height: 1.35)),
                                          const SizedBox(height: 6),
                                          Text(_formatDriverDate(row['created_at']), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                        ])),
                                        PopupMenuButton<String>(
                                          onSelected: (value) => value == 'delete' ? _delete(row) : _toggleRead(row),
                                          itemBuilder: (_) => [
                                            PopupMenuItem(value: 'read', child: Text(unread ? s.t('driverMarkRead') : s.t('driverMarkUnread'))),
                                            PopupMenuItem(value: 'delete', child: Text(s.t('driverDeleteNotification'))),
                                          ],
                                        ),
                                      ]),
                                    ),
                                  ),
                                );
                              },
                            ),
        ),
      ),
    );
  }
}

class _DriverAccountCenterScreen extends StatefulWidget {
  const _DriverAccountCenterScreen({
    required this.currentLocale,
    required this.onLocaleChanged,
    required this.profile,
    required this.onBack,
    required this.onLogout,
  });
  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final Map<String, dynamic>? profile;
  final VoidCallback onBack;
  final Future<void> Function() onLogout;

  @override
  State<_DriverAccountCenterScreen> createState() => _DriverAccountCenterScreenState();
}

class _DriverAccountCenterScreenState extends State<_DriverAccountCenterScreen> {
  Map<String, dynamic>? _personal;
  Map<String, String>? _vehicle;
  bool _notificationsEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final personal = await AuthService.instance.getDriverPersonalInfo();
    final vehicle = await AuthService.instance.getDriverVehicleInfo();
    final notifications = await AuthService.instance.areDriverNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _personal = personal;
      _vehicle = vehicle;
      _notificationsEnabled = notifications;
      _loading = false;
    });
  }

  Future<void> _editProfile() async {
    final p = _personal ?? const <String, dynamic>{};
    final name = TextEditingController(text: p['full_name']?.toString() ?? widget.profile?['full_name']?.toString() ?? Supabase.instance.client.auth.currentUser?.userMetadata?['full_name']?.toString() ?? '');
    final phone = TextEditingController(text: _partnerLocalIraqiPhone(p['phone'] ?? widget.profile?['phone'] ?? ''));
    final birth = TextEditingController(text: p['birth_date']?.toString() ?? '');
    final address = TextEditingController(text: p['address']?.toString() ?? '');
    var gender = p['gender']?.toString() == 'female' ? 'female' : 'male';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        final s = AppStrings.of(context);
        return StatefulBuilder(builder: (context, setLocal) => AlertDialog(
          title: Text(s.t('driverEditProfile')),
          content: SizedBox(width: _adaptiveDialogWidth(context, maxWidth: 520), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: s.t('fullName'))),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)], decoration: InputDecoration(labelText: s.t('phone'))),
            const SizedBox(height: 10),
            TextField(controller: birth, decoration: InputDecoration(labelText: s.t('driverBirthDate'))),
            const SizedBox(height: 10),
            TextField(controller: address, decoration: InputDecoration(labelText: s.t('driverAddress'))),
            const SizedBox(height: 12),
            SegmentedButton<String>(segments: [ButtonSegment(value: 'male', label: Text(s.t('driverMale'))), ButtonSegment(value: 'female', label: Text(s.t('driverFemale')))], selected: {gender}, onSelectionChanged: (v) => setLocal(() => gender = v.first)),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
            FilledButton(onPressed: () async {
              if (name.text.trim().isEmpty || !_isValidPartnerLocalPhone(phone.text) || birth.text.trim().isEmpty || address.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رقم الهاتف يجب أن يبدأ بـ 07 ويتكون من 11 رقمًا'))); return; }
              await AuthService.instance.saveDriverPersonalInfo(fullName: name.text, phone: phone.text, birthDate: birth.text, address: address.text, gender: gender);
              if (context.mounted) Navigator.pop(context, true);
            }, child: Text(s.t('save'))),
          ],
        ));
      },
    );
    // showDialog completes when pop is requested, while the route can still be
    // animating out. Do not dispose controllers until that transition is over.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose(); phone.dispose(); birth.dispose(); address.dispose();
    if (!mounted) return;
    if (saved == true) await _load();
  }

  Future<void> _toggleNotifications(bool value) async {
    await AuthService.instance.setDriverNotificationsEnabled(value);
    if (mounted) setState(() => _notificationsEnabled = value);
  }

  void _openInfo(String title, String body, IconData icon) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _DriverStructuredInfoPage(title: title, body: body, icon: icon)));
  }

  void _openFaq(String title, String body) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _DriverFaqPage(title: title, body: body)));
  }


  Future<void> _deleteDriverAccount() async {
    final language = widget.currentLocale.languageCode;
    try {
      final confirmed = await _confirmPartnerAccountDeletion(
        context: context,
        role: 'driver',
        language: language,
      );
      if (!confirmed || !mounted) return;
      await AuthService.instance.deleteCurrentPartnerAccount(expectedRole: 'driver');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(language == 'en' ? 'Account deleted' : language == 'ku' ? 'هەژمار سڕایەوە' : 'تم حذف الحساب')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(language == 'en' ? 'Could not delete account: $error' : language == 'ku' ? 'سڕینەوەی هەژمار سەرکەوتوو نەبوو: $error' : 'تعذر حذف الحساب: $error')),
      );
    }
  }

  String _vehicleTypeLabel(AppStrings s, String? type) => switch (type) {
        'motorcycle' => s.t('driverMotorcycle'),
        'car' => s.t('driverCar'),
        'bicycle' => s.t('driverBicycle'),
        _ => type == null || type.trim().isEmpty ? '—' : type,
      };

  Future<void> _editVehicle() async {
    final s = AppStrings.of(context);
    final vehicle = Map<String, String>.from(_vehicle ?? const <String, String>{});
    var type = vehicle['type']?.trim().isNotEmpty == true ? vehicle['type']! : 'motorcycle';
    final plateNumber = TextEditingController(text: vehicle['plate_number'] ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.two_wheeler_rounded, color: AppColors.orange),
            const SizedBox(width: 10),
            Expanded(child: Text(s.t('driverVehicleInfo'))),
          ]),
          content: SizedBox(
            width: _adaptiveDialogWidth(context, maxWidth: 520),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(labelText: s.t('driverVehicleType')),
                items: [
                  DropdownMenuItem(value: 'motorcycle', child: Text(s.t('driverMotorcycle'))),
                  DropdownMenuItem(value: 'car', child: Text(s.t('driverCar'))),
                  DropdownMenuItem(value: 'bicycle', child: Text(s.t('driverBicycle'))),
                ],
                onChanged: (value) => setLocal(() => type = value ?? 'motorcycle'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: plateNumber,
                decoration: InputDecoration(
                  labelText: '${s.t('driverPlateNumber')} (اختياري)',
                  helperText: 'لا نطلب صور المركبة أو رقم الشاصي في النسخة الحالية.',
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(s.t('cancel'))),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await AuthService.instance.saveDriverBasicProfile(
                    vehicleType: type,
                    plateNumber: plateNumber.text,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (_) {
                  if (dialogContext.mounted) Navigator.pop(dialogContext, false);
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: Text(s.t('save')),
            ),
          ],
        ),
      ),
    );

    // Keep the controller alive through the dialog reverse transition.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    plateNumber.dispose();
    if (!mounted || saved == null) return;
    if (saved) {
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('driverVehicleSaved'))));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('driverVehicleSaveFailed'))));
    }
  }

  Future<void> _contactSupport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _StoreSupportInboxPage(storeId: null, isDriver: true),
      ),
    );
  }

  Widget _tile({required IconData icon, required String title, String? subtitle, VoidCallback? onTap, Widget? trailing}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8EAF0))),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(backgroundColor: AppColors.orange.withValues(alpha: .10), child: Icon(icon, color: AppColors.orange)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: AppColors.muted)),
          trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final p = _personal ?? const <String, dynamic>{};
    final vehicle = _vehicle ?? const <String, String>{};
    final personalName = p['full_name']?.toString().trim() ?? '';
    final profileName = widget.profile?['full_name']?.toString().trim() ?? '';
    final metadataName = Supabase.instance.client.auth.currentUser?.userMetadata?['full_name']?.toString().trim() ?? '';
    final name = personalName.isNotEmpty ? personalName : profileName.isNotEmpty ? profileName : metadataName;
    final rawEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final email = rawEmail.toLowerCase().endsWith('@phone.halatalab.invalid') ? '' : rawEmail;
    final shownPhone = _partnerLocalIraqiPhone(p['phone'] ?? widget.profile?['phone'] ?? '');
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: AppBar(title: Text(s.t('driverAccountCenter')), leading: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back_rounded))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE8EAF0))),
          child: LayoutBuilder(builder: (context, c) {
            final compact = c.maxWidth < 560;
            final identity = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(radius: 32, backgroundColor: Color(0xFFFFEEE2), child: Icon(Icons.delivery_dining_rounded, color: AppColors.orange, size: 34)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.isEmpty ? s.t('driver') : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  if (email.isNotEmpty) Directionality(textDirection: TextDirection.ltr, child: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted))),
                  if (shownPhone.isNotEmpty) Directionality(textDirection: TextDirection.ltr, child: Text(shownPhone, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted))),
                ])),
              ],
            );
            if (compact) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                identity,
                const SizedBox(height: 14),
                OutlinedButton.icon(onPressed: _editProfile, icon: const Icon(Icons.edit_outlined), label: Text(s.t('driverEditProfile'))),
              ]);
            }
            return Row(children: [Expanded(child: identity), const SizedBox(width: 14), OutlinedButton.icon(onPressed: _editProfile, icon: const Icon(Icons.edit_outlined), label: Text(s.t('driverEditProfile')))]);
          }),
        ),
        const SizedBox(height: 18),
        Text(s.t('driverProfileSection'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        _tile(icon: Icons.person_outline_rounded, title: s.t('driverPersonalInfo'), subtitle: p['address']?.toString(), onTap: _editProfile),
        _tile(
          icon: Icons.two_wheeler_rounded,
          title: s.t('driverVehicleInfo'),
          subtitle: [_vehicleTypeLabel(s, vehicle['type']), vehicle['plate_number']].where((e) => e != null && e.trim().isNotEmpty).join(' • '),
          onTap: _editVehicle,
        ),
        const SizedBox(height: 8),
        Text(s.t('settings'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        _tile(icon: Icons.language_rounded, title: s.t('language'), subtitle: widget.currentLocale.languageCode == 'ar' ? s.t('arabic') : widget.currentLocale.languageCode == 'ku' ? s.t('kurdish') : s.t('english'), trailing: LanguageMenu(currentLocale: widget.currentLocale, onChanged: widget.onLocaleChanged)),
        _tile(icon: Icons.notifications_active_outlined, title: s.t('driverOrderNotifications'), subtitle: s.t('driverOrderNotificationsSubtitle'), trailing: Switch(value: _notificationsEnabled, onChanged: _toggleNotifications)),
        _tile(
          icon: Icons.delete_forever_outlined,
          title: widget.currentLocale.languageCode == 'en' ? 'Delete account' : widget.currentLocale.languageCode == 'ku' ? 'سڕینەوەی هەژمار' : 'حذف الحساب',
          subtitle: widget.currentLocale.languageCode == 'en' ? 'Permanently delete this driver account' : widget.currentLocale.languageCode == 'ku' ? 'هەژماری شۆفێر بە هەمیشەیی بسڕەوە' : 'حذف حساب السائق نهائيًا',
          onTap: _deleteDriverAccount,
        ),
        const SizedBox(height: 8),
        Text(s.t('driverSupportSection'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        _tile(icon: Icons.headset_mic_outlined, title: s.t('driverContactSupport'), subtitle: s.t('driverSupportAlways'), onTap: _contactSupport),
        _tile(icon: Icons.help_outline_rounded, title: s.t('faq'), onTap: () => _openFaq(s.t('faq'), s.t('driverFaqBody'))),
        _tile(icon: Icons.privacy_tip_outlined, title: s.t('privacyPolicy'), onTap: () => _openInfo(s.t('privacyPolicy'), s.t('driverPrivacyBody'), Icons.privacy_tip_outlined)),
        _tile(icon: Icons.description_outlined, title: s.t('termsConditions'), onTap: () => _openInfo(s.t('termsConditions'), s.t('driverTermsBody'), Icons.description_outlined)),
        _tile(icon: Icons.info_outline_rounded, title: s.t('aboutHalaTalab'), onTap: () => _openInfo(s.t('aboutHalaTalab'), s.t('driverAboutHalaTalabBody'), Icons.info_outline_rounded)),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: widget.onLogout, icon: const Icon(Icons.logout_rounded), label: Text(s.t('logout')), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626), side: const BorderSide(color: Color(0xFFFCA5A5)), padding: const EdgeInsets.symmetric(vertical: 15))),
      ]))),
    );
  }
}


class _DriverFaqPage extends StatelessWidget {
  const _DriverFaqPage({required this.title, required this.body});
  final String title;
  final String body;

  List<(String, String)> _items() {
    final blocks = body.split(RegExp(r'\n\s*\n')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    return blocks.map((block) {
      final lines = block.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (lines.isEmpty) return ('', '');
      return (lines.first, lines.skip(1).join('\n'));
    }).where((e) => e.$1.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.help_outline_rounded, color: AppColors.orange, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900))),
                ]),
              ),
              const SizedBox(height: 14),
              ...items.map((item) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE8EAF0)),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFFFEEE2),
                          child: Icon(Icons.question_mark_rounded, color: AppColors.orange, size: 20),
                        ),
                        title: Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w900, height: 1.35)),
                        children: [Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(item.$2, style: const TextStyle(color: Color(0xFF667085), height: 1.65, fontSize: 14.5)),
                        )],
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverStructuredInfoPage extends StatelessWidget {
  const _DriverStructuredInfoPage({required this.title, required this.body, required this.icon});
  final String title;
  final String body;
  final IconData icon;

  List<String> _sections() => body
      .split(RegExp(r'\n\s*\n'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(22)),
                child: Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(16)),
                    child: Icon(icon, color: AppColors.orange, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900))),
                ]),
              ),
              const SizedBox(height: 14),
              ...sections.asMap().entries.map((entry) {
                final text = entry.value;
                final first = entry.key == 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE8EAF0)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!first) ...[
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: const Color(0xFFFFEEE2), borderRadius: BorderRadius.circular(10)),
                        child: Text('${entry.key}', style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: Text(text, style: TextStyle(fontSize: first ? 15.5 : 14.5, height: 1.7, fontWeight: first ? FontWeight.w700 : FontWeight.w500, color: first ? const Color(0xFF344054) : const Color(0xFF475467)))),
                  ]),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverEmptyState extends StatelessWidget {
  const _DriverEmptyState({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 48, color: AppColors.orange), const SizedBox(height: 12), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.4)),
  ])));
}

String _formatDriverDate(dynamic value) {
  final dt = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (dt == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
}
