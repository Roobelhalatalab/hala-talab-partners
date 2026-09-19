part of 'partner_dashboard.dart';

class _StoreSettingsPage extends StatefulWidget {
  const _StoreSettingsPage({
    required this.store,
    required this.onSaved,
    required this.currentLocale,
    required this.onLocaleChanged,
    required this.onLogout,
  });
  final Map<String, dynamic>? store;
  final ValueChanged<Map<String, dynamic>> onSaved;
  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final Future<void> Function() onLogout;

  @override
  State<_StoreSettingsPage> createState() => _StoreSettingsPageState();
}

class _StoreSettingsPageState extends State<_StoreSettingsPage> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _logoUrl;
  late final TextEditingController _coverUrl;
  late final TextEditingController _deliveryFee;
  late final TextEditingController _minimumOrder;
  late final TextEditingController _preparationMinutes;
  late final TextEditingController _openingTime;
  late final TextEditingController _closingTime;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    final store = widget.store ?? const <String, dynamic>{};
    String text(String key, [String fallback = '']) => (store[key] ?? fallback).toString();
    _name = TextEditingController(text: text('name'));
    _description = TextEditingController(text: text('description'));
    _phone = TextEditingController(text: _partnerLocalIraqiPhone(text('phone')));
    _email = TextEditingController(text: text('email'));
    _address = TextEditingController(text: text('address_text'));
    _logoUrl = TextEditingController(text: text('logo_url'));
    _coverUrl = TextEditingController(text: text('cover_url'));
    _deliveryFee = TextEditingController(text: text('delivery_fee', '0'));
    _minimumOrder = TextEditingController(text: text('minimum_order', '0'));
    _preparationMinutes = TextEditingController(text: text('preparation_minutes', '30'));
    _openingTime = TextEditingController(text: text('opening_time', '09:00'));
    _closingTime = TextEditingController(text: text('closing_time', '23:00'));
    _isOpen = store['is_open'] == true;
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _phone, _email, _address, _logoUrl, _coverUrl, _deliveryFee, _minimumOrder, _preparationMinutes, _openingTime, _closingTime]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _sendPasswordReset() async {
    final s = AppStrings.of(context);
    final email = Supabase.instance.client.auth.currentUser?.email ?? _email.text.trim();
    if (email.isEmpty) return;
    try {
      await AuthService.instance.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('passwordResetSent'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _contactSupport() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _PartnerSupportDialog(
        storeId: widget.store?['id']?.toString(),
        isDriver: false,
      ),
    );
    if (!mounted || sent == null) return;
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(sent ? s.t('supportSent') : s.t('supportSendFailed'))),
    );
  }


  Future<void> _deleteStoreAccount() async {
    final language = widget.currentLocale.languageCode;
    try {
      final confirmed = await _confirmPartnerAccountDeletion(
        context: context,
        role: 'business',
        language: language,
      );
      if (!confirmed || !mounted) return;
      await AuthService.instance.deleteCurrentPartnerAccount(expectedRole: 'business');
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

  Future<void> _openInfoPage(String title, String body, IconData icon) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SettingsInfoPage(title: title, body: body, icon: icon)));
  }

  Future<void> _refreshStore() async {
    final updated = await AuthService.instance.getCurrentStore();
    if (!mounted || updated == null) return;
    widget.onSaved(updated);
  }

  Future<void> _updateExtraSettings(Map<String, dynamic> values) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    await Supabase.instance.client
        .from('stores')
        .update({...values, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('owner_id', userId);
    await _refreshStore();
  }

  Future<void> _openProfileEditor() async {
    // Always refresh the store directly from Supabase before opening the
    // editor. The settings widget can stay alive while the parent shell is
    // rebuilt, so controller values alone are not a reliable source of truth
    // for newly-saved logo/cover URLs.
    final freshStore = await AuthService.instance.getCurrentStore();
    if (!mounted) return;
    if (freshStore != null) {
      _name.text = (freshStore['name'] ?? _name.text).toString();
      _description.text = (freshStore['description'] ?? '').toString();
      _phone.text = _partnerLocalIraqiPhone(freshStore['phone']);
      _email.text = (freshStore['email'] ?? '').toString();
      _address.text = (freshStore['address_text'] ?? '').toString();
      _logoUrl.text = (freshStore['logo_url'] ?? '').toString();
      _coverUrl.text = (freshStore['cover_url'] ?? '').toString();
      widget.onSaved(freshStore);
    }

    final result = await Navigator.of(context).push<_StoreProfileEditResult>(
      MaterialPageRoute(
        builder: (_) => _StoreProfileEditorPage(
          currentLocale: widget.currentLocale,
          name: _name.text,
          description: _description.text,
          phone: _phone.text,
          email: _email.text,
          address: _address.text,
          logoUrl: _logoUrl.text,
          coverUrl: _coverUrl.text,
        ),
      ),
    );
    if (result == null || !mounted) return;

    try {
      var logoUrl = result.removeLogo ? '' : result.logoUrl;
      var coverUrl = result.removeCover ? '' : result.coverUrl;

      if (result.logoFile?.bytes != null) {
        logoUrl = await AuthService.instance.uploadStoreImage(
          bytes: result.logoFile!.bytes!,
          extension: result.logoFile!.extension ?? 'jpg',
          kind: 'logo',
        );
      }
      if (result.coverFile?.bytes != null) {
        coverUrl = await AuthService.instance.uploadStoreImage(
          bytes: result.coverFile!.bytes!,
          extension: result.coverFile!.extension ?? 'jpg',
          kind: 'cover',
        );
      }

      // Save only the profile fields edited on this page. Keeping delivery,
      // opening hours and store state out of this request avoids unrelated
      // validation/database failures when the user is only changing images.
      await AuthService.instance.updateStoreProfile(
        name: result.name,
        description: result.description,
        phone: result.phone,
        email: result.email,
        address: result.address,
        logoUrl: logoUrl,
        coverUrl: coverUrl,
      );

      // Re-read the row after UPDATE and use the persisted database values as
      // the only source of truth. This prevents the UI from reporting success
      // while reopening with stale/empty image URLs.
      final persisted = await AuthService.instance.getCurrentStore();
      if (persisted == null) {
        throw StateError('Store could not be reloaded after save');
      }
      final persistedLogo = (persisted['logo_url'] ?? '').toString().trim();
      final persistedCover = (persisted['cover_url'] ?? '').toString().trim();
      if (logoUrl.trim().isNotEmpty && persistedLogo.isEmpty) {
        throw StateError('Logo URL was not persisted');
      }
      if (coverUrl.trim().isNotEmpty && persistedCover.isEmpty) {
        throw StateError('Cover URL was not persisted');
      }

      if (!mounted) return;
      _name.text = (persisted['name'] ?? result.name).toString();
      _description.text = (persisted['description'] ?? '').toString();
      _phone.text = _partnerLocalIraqiPhone(persisted['phone']);
      _email.text = (persisted['email'] ?? '').toString();
      _address.text = (persisted['address_text'] ?? '').toString();
      _logoUrl.text = persistedLogo;
      _coverUrl.text = persistedCover;
      widget.onSaved(persisted);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ معلومات وصور المتجر والتأكد من بقائها')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ معلومات المتجر: $error')),
      );
    } finally {
    }
  }

  Future<void> _openStoredDocument(String path) async {
    if (path.trim().isEmpty || !path.contains('/')) return;
    try {
      final url = await AuthService.instance.createStoreDocumentSignedUrl(path.trim());
      final uri = Uri.tryParse(url);
      if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open document');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح المستند: $error')),
      );
    }
  }

  Future<void> _openDocumentsEditor() async {
    final commercialCurrent = (widget.store?['commercial_registration'] ?? '').toString();
    final identityCurrent = (widget.store?['identity_document'] ?? '').toString();
    final result = await Navigator.of(context).push<_StoreDocumentsEditResult>(
      MaterialPageRoute(
        builder: (_) => _StoreDocumentsEditorPage(
          currentLocale: widget.currentLocale,
          commercialCurrent: commercialCurrent,
          identityCurrent: identityCurrent,
          onOpenCommercial: commercialCurrent.contains('/')
              ? () => _openStoredDocument(commercialCurrent)
              : null,
          onOpenIdentity: identityCurrent.contains('/')
              ? () => _openStoredDocument(identityCurrent)
              : null,
        ),
      ),
    );
    if (result == null || !mounted) return;

    try {
      var commercialPath = result.removeCommercial ? '' : commercialCurrent;
      var identityPath = result.removeIdentity ? '' : identityCurrent;

      if (result.commercialFile?.bytes != null) {
        commercialPath = await AuthService.instance.uploadStoreDocument(
          bytes: result.commercialFile!.bytes!,
          extension: result.commercialFile!.extension ?? 'pdf',
          kind: 'commercial-registration',
        );
      }
      if (result.identityFile?.bytes != null) {
        identityPath = await AuthService.instance.uploadStoreDocument(
          bytes: result.identityFile!.bytes!,
          extension: result.identityFile!.extension ?? 'pdf',
          kind: 'identity-document',
        );
      }

      await _updateExtraSettings({
        'commercial_registration': commercialPath.trim().isEmpty ? null : commercialPath.trim(),
        'identity_document': identityPath.trim().isEmpty ? null : identityPath.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ مستندات المتجر')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ المستندات: $error')),
      );
    } finally {
    }
  }

  Future<void> _openPrinterSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PrinterSettingsPage(
          store: widget.store,
          currentLocale: widget.currentLocale,
        ),
      ),
    );
  }

  Future<void> _openStoreOperations(int section) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _StoreOperationsSettingsPage(
        store: widget.store,
        initialSection: section,
        onSaved: (updated) {
          widget.onSaved(updated);
          if (!mounted) return;
          setState(() {
            _address.text = (updated['address_text'] ?? '').toString();
            _deliveryFee.text = (updated['delivery_fee'] ?? '0').toString();
            _minimumOrder.text = (updated['minimum_order'] ?? '0').toString();
            _preparationMinutes.text = (updated['preparation_minutes'] ?? '30').toString();
            _isOpen = updated['is_open'] == true;
          });
        },
      ),
    ));
  }

  Future<void> _openPaymentMethods() async {
    final s = AppStrings.of(context);
    final raw = widget.store?['payment_methods'];
    final selected = <String>{...((raw is List ? raw : const ['cash']).map((e) => e.toString()))};
    final result = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: Row(children: [const Icon(Icons.payments_outlined, color: AppColors.orange), const SizedBox(width: 10), Expanded(child: Text(s.t('paymentMethods')))]),
      content: SizedBox(width: _adaptiveDialogWidth(context, maxWidth: 500), child: Column(mainAxisSize: MainAxisSize.min, children: [
        CheckboxListTile(value: selected.contains('cash'), onChanged: (v) => setLocal(() => v == true ? selected.add('cash') : selected.remove('cash')), title: Text(s.t('cashPayment')), secondary: const Icon(Icons.payments_rounded)),
        CheckboxListTile(value: selected.contains('card'), onChanged: (v) => setLocal(() => v == true ? selected.add('card') : selected.remove('card')), title: Text(s.t('cardPayment')), secondary: const Icon(Icons.credit_card_rounded)),
        CheckboxListTile(value: selected.contains('wallet'), onChanged: (v) => setLocal(() => v == true ? selected.add('wallet') : selected.remove('wallet')), title: Text(s.t('walletPayment')), secondary: const Icon(Icons.account_balance_wallet_outlined)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)), FilledButton(onPressed: selected.isEmpty ? null : () => Navigator.pop(dialogContext, true), child: Text(s.t('saveChanges')))],
    )));
    if (result == true) await _updateExtraSettings({'payment_methods': selected.toList()});
  }

  Future<void> _openOrderNotifications() async {
    final s = AppStrings.of(context);
    final raw = widget.store?['order_notification_settings'];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    bool newOrders = map['new_orders'] != false;
    bool cancellations = map['cancellations'] != false;
    bool statusChanges = map['status_changes'] != false;
    bool sound = map['sound'] != false;
    final result = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: Row(children: [const Icon(Icons.notifications_active_outlined, color: AppColors.orange), const SizedBox(width: 10), Expanded(child: Text(s.t('orderNotifications')))]),
      content: SizedBox(width: _adaptiveDialogWidth(context, maxWidth: 520), child: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile.adaptive(value: newOrders, onChanged: (v) => setLocal(() => newOrders = v), title: Text(s.t('notifyNewOrders')), secondary: const Icon(Icons.shopping_bag_outlined)),
        SwitchListTile.adaptive(value: cancellations, onChanged: (v) => setLocal(() => cancellations = v), title: Text(s.t('notifyCancellations')), secondary: const Icon(Icons.cancel_outlined)),
        SwitchListTile.adaptive(value: statusChanges, onChanged: (v) => setLocal(() => statusChanges = v), title: Text(s.t('notifyStatusChanges')), secondary: const Icon(Icons.sync_rounded)),
        SwitchListTile.adaptive(value: sound, onChanged: (v) => setLocal(() => sound = v), title: Text(s.t('notificationSound')), secondary: const Icon(Icons.volume_up_outlined)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(s.t('saveChanges')))],
    )));
    if (result == true) await _updateExtraSettings({'order_notification_settings': {'new_orders': newOrders, 'cancellations': cancellations, 'status_changes': statusChanges, 'sound': sound}});
  }

  Widget _settingsNavTile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap, Color accent = AppColors.orange}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: accent.withValues(alpha: .09), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: accent)),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted))])),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 760;
    final storeName = _name.text.trim().isEmpty ? s.t('storeSettingsTitle') : _name.text.trim();
    final approval = (widget.store?['approval_status'] ?? 'pending').toString();
    final isApproved = approval == 'approved';
    final isRejected = approval == 'rejected';
    final isActive = widget.store?['is_active'] == true;
    final canOpenStore = isApproved && isActive;
    final approvalBadgeText = isRejected ? s.t('storeRejected') : isApproved ? s.t('verified') : s.t('underReview');
    final approvalBadgeIcon = isRejected ? Icons.cancel_rounded : isApproved ? Icons.verified_rounded : Icons.schedule_rounded;
    final statusTitle = isRejected
        ? s.t('storeRejected')
        : isApproved && !isActive
            ? s.t('storeApprovedInactive')
            : canOpenStore
                ? (_isOpen ? s.t('storeOpen') : s.t('storeClosed'))
                : s.t('storeUnderReview');
    final statusSubtitle = isRejected
        ? s.t('rejectedReviewNotice')
        : isApproved && !isActive
            ? s.t('approvedActivationNotice')
            : canOpenStore
                ? s.t('storeStatusSubtitle')
                : s.t('pendingApprovalNotice');
    final docsReady = ((widget.store?['commercial_registration'] ?? '').toString().isNotEmpty && (widget.store?['identity_document'] ?? '').toString().isNotEmpty);
    final pageBackground = const Color(0xFFF7F8FA);
    final surface = Theme.of(context).colorScheme.surface;
    final borderColor = const Color(0xFFE8EAF0);

    return ColoredBox(
      color: pageBackground,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(_adaptivePagePadding(context), compact ? 14 : 24, _adaptivePagePadding(context), 34),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.t('settings'), style: TextStyle(fontSize: compact ? 26 : 32, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(s.t('organizedSettingsSubtitle'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ])),
              ]),
              const SizedBox(height: 18),
              InkWell(
                onTap: _openProfileEditor,
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF7A1A), Color(0xFFFF5A00)], begin: Alignment.topRight, end: Alignment.bottomLeft), borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Color(0x22FF6B00), blurRadius: 28, offset: Offset(0, 12))]),
                  padding: EdgeInsets.all(compact ? 18 : 24),
                  child: Row(children: [
                    Container(width: compact ? 72 : 84, height: compact ? 72 : 84, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.storefront_rounded, color: AppColors.orange, size: 42)),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.t('profile'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(storeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: compact ? 20 : 26, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        _ProfileBadge(text: approvalBadgeText, icon: approvalBadgeIcon),
                        _ProfileBadge(text: docsReady ? s.t('documentsComplete') : s.t('documentsIncomplete'), icon: docsReady ? Icons.task_alt_rounded : Icons.description_outlined),
                      ]),
                    ])),
                    const Icon(Icons.edit_rounded, color: Colors.white),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              _SettingsSection(
                title: s.t('profileStoreSettings'),
                icon: Icons.manage_accounts_outlined,
                child: Column(children: [
                  _settingsNavTile(icon: Icons.storefront_outlined, title: s.t('restaurantInformation'), subtitle: s.t('profileStoreSettingsSubtitle'), onTap: _openProfileEditor),
                  _settingsNavTile(icon: Icons.description_outlined, title: s.t('documents'), subtitle: docsReady ? s.t('documentsComplete') : s.t('documentsIncomplete'), onTap: _openDocumentsEditor, accent: const Color(0xFF16A34A)),
                  _settingsNavTile(icon: Icons.location_on_rounded, title: widget.currentLocale.languageCode == 'en' ? 'Store location' : widget.currentLocale.languageCode == 'ku' ? 'شوێنی فرۆشگا' : 'موقع المتجر', subtitle: widget.currentLocale.languageCode == 'en' ? 'Address, coordinates and arrival note' : widget.currentLocale.languageCode == 'ku' ? 'ناونیشان، کۆئۆردینات و تێبینی گەیشتن' : 'العنوان، الإحداثيات وملاحظة الوصول', onTap: () => _openStoreOperations(0), accent: const Color(0xFF2563EB)),
                  _settingsNavTile(icon: Icons.delivery_dining_rounded, title: widget.currentLocale.languageCode == 'en' ? 'Delivery & pickup' : widget.currentLocale.languageCode == 'ku' ? 'گەیاندن و وەرگرتن' : 'التوصيل والاستلام', subtitle: widget.currentLocale.languageCode == 'en' ? 'Delivery, pickup, fees and zones' : widget.currentLocale.languageCode == 'ku' ? 'گەیاندن، وەرگرتن، کرێ و ناوچەکان' : 'التوصيل، الاستلام، الرسوم والمناطق', onTap: () => _openStoreOperations(1), accent: const Color(0xFF16A34A)),
                  _settingsNavTile(icon: Icons.schedule_rounded, title: s.t('workingHours'), subtitle: widget.currentLocale.languageCode == 'en' ? 'Weekly schedule and days off' : widget.currentLocale.languageCode == 'ku' ? 'خشتەی هەفتانە و ڕۆژانی پشوو' : 'جدول أسبوعي مع تحديد أيام العطلة', onTap: () => _openStoreOperations(2), accent: const Color(0xFF7C3AED)),
                  _settingsNavTile(icon: Icons.payments_outlined, title: s.t('paymentMethods'), subtitle: s.t('paymentMethodsSubtitle'), onTap: _openPaymentMethods, accent: const Color(0xFF7C3AED)),
                  _settingsNavTile(icon: Icons.notifications_active_outlined, title: s.t('orderNotifications'), subtitle: s.t('orderNotificationsSubtitle'), onTap: _openOrderNotifications, accent: const Color(0xFFF59E0B)),
                  _settingsNavTile(icon: Icons.print_outlined, title: 'الطابعة', subtitle: 'طباعة الطلبات، نسخة المطبخ والكاشير وإعدادات الورق', onTap: _openPrinterSettings, accent: const Color(0xFF0F766E)),
                ]),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: borderColor)),
                child: SwitchListTile.adaptive(
                  value: _isOpen,
                  onChanged: canOpenStore ? (v) async {
                    final previous = _isOpen;
                    setState(() => _isOpen = v);
                    try {
                      final updated = await AuthService.instance.updateStoreOpenStatus(v);
                      if (mounted) widget.onSaved(updated);
                    } on PostgrestException catch (error) {
                      if (!context.mounted) return;
                      setState(() => _isOpen = previous);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.message)),
                      );
                    } on AuthException catch (error) {
                      if (!context.mounted) return;
                      setState(() => _isOpen = previous);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.message)),
                      );
                    } catch (error) {
                      if (!context.mounted) return;
                      setState(() => _isOpen = previous);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تعذر تحديث حالة المتجر: $error')),
                      );
                    }
                  } : null,
                  activeThumbColor: AppColors.green,
                  secondary: Container(width: 44, height: 44, decoration: BoxDecoration(color: (_isOpen ? AppColors.green : const Color(0xFF64748B)).withValues(alpha: .1), borderRadius: BorderRadius.circular(14)), child: Icon(_isOpen ? Icons.store_rounded : Icons.store_mall_directory_outlined, color: _isOpen ? AppColors.green : const Color(0xFF64748B))),
                  title: Text(statusTitle, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(statusSubtitle),
                ),
              ),
              const SizedBox(height: 18),
              _SettingsSection(
                title: s.t('appAccountSettings'),
                icon: Icons.manage_accounts_outlined,
                child: Column(children: [
                  _settingsNavTile(icon: Icons.language_rounded, title: s.t('currentLanguage'), subtitle: widget.currentLocale.languageCode == 'ar' ? s.t('arabic') : widget.currentLocale.languageCode == 'ku' ? s.t('kurdish') : s.t('english'), onTap: () async {
                    final code = await showDialog<String>(context: context, builder: (c) => SimpleDialog(title: Text(s.t('currentLanguage')), children: [SimpleDialogOption(onPressed: () => Navigator.pop(c, 'ar'), child: Text(s.t('arabic'))), SimpleDialogOption(onPressed: () => Navigator.pop(c, 'ku'), child: Text(s.t('kurdish'))), SimpleDialogOption(onPressed: () => Navigator.pop(c, 'en'), child: Text(s.t('english')))]));
                    if (code != null) {
                      await WidgetsBinding.instance.endOfFrame;
                      if (!context.mounted) return;
                      widget.onLocaleChanged(Locale(code));
                    }
                  }, accent: const Color(0xFF2563EB)),
                  _settingsNavTile(icon: Icons.lock_reset_rounded, title: s.t('changePassword'), subtitle: Supabase.instance.client.auth.currentUser?.email ?? _email.text, onTap: _sendPasswordReset, accent: const Color(0xFF7C3AED)),
                  _settingsNavTile(icon: Icons.shield_outlined, title: s.t('securityPrivacy'), subtitle: s.t('securityPrivacy'), onTap: () => _openInfoPage(s.t('securityPrivacy'), s.t('securityBody'), Icons.shield_outlined), accent: const Color(0xFF16A34A)),
                  _settingsNavTile(
                    icon: Icons.delete_forever_outlined,
                    title: widget.currentLocale.languageCode == 'en' ? 'Delete account' : widget.currentLocale.languageCode == 'ku' ? 'سڕینەوەی هەژمار' : 'حذف الحساب',
                    subtitle: widget.currentLocale.languageCode == 'en' ? 'Permanently delete this store owner account' : widget.currentLocale.languageCode == 'ku' ? 'هەژماری خاوەنی فرۆشگا بە هەمیشەیی بسڕەوە' : 'حذف حساب مالك المتجر نهائيًا',
                    onTap: _deleteStoreAccount,
                    accent: const Color(0xFFDC2626),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: s.t('supportHelp'),
                icon: Icons.support_agent_rounded,
                child: Column(children: [
                  _settingsNavTile(icon: Icons.headset_mic_outlined, title: s.t('contactSupport'), subtitle: s.t('contactSupportSubtitle'), onTap: _contactSupport),
                  _settingsNavTile(icon: Icons.description_outlined, title: s.t('termsConditions'), subtitle: s.t('appTitle'), onTap: () => _openInfoPage(s.t('termsConditions'), s.t('termsBody'), Icons.description_outlined), accent: const Color(0xFF64748B)),
                  _settingsNavTile(icon: Icons.privacy_tip_outlined, title: s.t('privacyPolicy'), subtitle: s.t('securityPrivacy'), onTap: () => _openInfoPage(s.t('privacyPolicy'), s.t('privacyBody'), Icons.privacy_tip_outlined), accent: const Color(0xFF16A34A)),
                  _settingsNavTile(icon: Icons.help_outline_rounded, title: s.t('faq'), subtitle: s.t('supportHelp'), onTap: () => _openInfoPage(s.t('faq'), s.t('faqBody'), Icons.help_outline_rounded), accent: const Color(0xFFF59E0B)),
                  _settingsNavTile(icon: Icons.info_outline_rounded, title: s.t('aboutHalaTalab'), subtitle: s.t('appTitle'), onTap: () => _openInfoPage(s.t('aboutHalaTalab'), s.t('aboutHalaTalabBody'), Icons.info_outline_rounded), accent: const Color(0xFF7C3AED)),
                  _settingsNavTile(icon: Icons.apps_rounded, title: s.t('appInformation'), subtitle: '${s.t('appVersion')} 1.0.0', onTap: () => _openInfoPage(s.t('appInformation'), '${s.t('appInfoBody')}\n\n${s.t('appVersion')}: 1.0.0', Icons.apps_rounded), accent: const Color(0xFF2563EB)),
                ]),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: widget.onLogout, style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626), side: const BorderSide(color: Color(0xFFFCA5A5)), padding: const EdgeInsets.symmetric(vertical: 16)), icon: const Icon(Icons.logout_rounded), label: Text(s.t('signOut'), style: const TextStyle(fontWeight: FontWeight.w900))),
            ]),
          ),
        ),
      ),
    );
  }
}


class _StoreProfileEditResult {
  const _StoreProfileEditResult({
    required this.name,
    required this.description,
    required this.phone,
    required this.email,
    required this.address,
    required this.logoUrl,
    required this.coverUrl,
    required this.logoFile,
    required this.coverFile,
    required this.removeLogo,
    required this.removeCover,
  });

  final String name;
  final String description;
  final String phone;
  final String email;
  final String address;
  final String logoUrl;
  final String coverUrl;
  final PlatformFile? logoFile;
  final PlatformFile? coverFile;
  final bool removeLogo;
  final bool removeCover;
}

class _StoreProfileEditorPage extends StatefulWidget {
  const _StoreProfileEditorPage({
    required this.currentLocale,
    required this.name,
    required this.description,
    required this.phone,
    required this.email,
    required this.address,
    required this.logoUrl,
    required this.coverUrl,
  });

  final Locale currentLocale;
  final String name;
  final String description;
  final String phone;
  final String email;
  final String address;
  final String logoUrl;
  final String coverUrl;

  @override
  State<_StoreProfileEditorPage> createState() => _StoreProfileEditorPageState();
}

class _StoreProfileEditorPageState extends State<_StoreProfileEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  PlatformFile? _logoFile;
  PlatformFile? _coverFile;
  late String _savedLogoUrl;
  late String _savedCoverUrl;
  bool _removeLogo = false;
  bool _removeCover = false;
  bool _picking = false;
  bool _uploadingLogo = false;
  bool _uploadingCover = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name);
    _description = TextEditingController(text: widget.description);
    _phone = TextEditingController(text: _partnerLocalIraqiPhone(widget.phone));
    _email = TextEditingController(text: widget.email);
    _address = TextEditingController(text: widget.address);
    _savedLogoUrl = widget.logoUrl;
    _savedCoverUrl = widget.coverUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  String _label(String ar, String ku, String en) {
    final code = widget.currentLocale.languageCode;
    if (code == 'en') return en;
    if (code == 'ku') return ku;
    return ar;
  }

  Future<PlatformFile?> _pickImage() async {
    if (_picking) return null;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
        allowMultiple: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return null;
      final file = result.files.single;
      if (file.bytes == null || file.size > 10 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_label(
              'الصورة يجب أن تكون JPG/PNG/WebP وأقل من 10MB',
              'وێنەکە دەبێت JPG/PNG/WebP و کەمتر لە 10MB بێت',
              'Image must be JPG/PNG/WebP and under 10MB',
            ))),
          );
        }
        return null;
      }
      return file;
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _chooseImage({required bool logo}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final file = await _pickImage();
    if (!mounted || file == null || file.bytes == null) return;
    final cropped = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(
      builder: (_) => PartnerImageCropEditor(
        bytes: file.bytes!,
        aspectRatio: logo ? 1.0 : 16 / 9,
        title: logo ? 'ضبط شعار المتجر' : 'ضبط صورة الغلاف',
        circularFrame: logo,
      ),
    ));
    if (!mounted || cropped == null) return;
    final adjusted = PlatformFile(name: '${logo ? 'logo' : 'cover'}_cropped.png', size: cropped.length, bytes: cropped);

    // Show the local preview immediately, then persist the image in the
    // background. A successful upload is written to the store row before the
    // user leaves this page, so reopening the screen cannot lose the image.
    setState(() {
      if (logo) {
        _logoFile = adjusted;
        _removeLogo = false;
        _uploadingLogo = true;
      } else {
        _coverFile = adjusted;
        _removeCover = false;
        _uploadingCover = true;
      }
    });

    try {
      final uploadedUrl = await AuthService.instance.uploadStoreImage(
        bytes: adjusted.bytes!,
        extension: 'png',
        kind: logo ? 'logo' : 'cover',
      );
      await AuthService.instance.updateStoreImages(
        logoUrl: logo ? uploadedUrl : null,
        coverUrl: logo ? null : uploadedUrl,
      );
      if (!mounted) return;
      setState(() {
        if (logo) {
          _savedLogoUrl = uploadedUrl;
          _logoFile = null;
          _uploadingLogo = false;
        } else {
          _savedCoverUrl = uploadedUrl;
          _coverFile = null;
          _uploadingCover = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_label(
          logo ? 'تم حفظ شعار المتجر' : 'تم حفظ صورة الغلاف',
          logo ? 'لۆگۆی فرۆشگا پاشەکەوت کرا' : 'وێنەی پۆششی فرۆشگا پاشەکەوت کرا',
          logo ? 'Store logo saved' : 'Store cover image saved',
        ))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (logo) {
          _uploadingLogo = false;
        } else {
          _uploadingCover = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_label(
          'تعذر رفع الصورة. تأكد من إعداد مخزن store-images ثم حاول مرة أخرى.\n$error',
          'بارکردنی وێنە سەرکەوتوو نەبوو. دڵنیابە لە ڕێکخستنی store-images و دووبارە هەوڵبدە.\n$error',
          'Image upload failed. Verify the store-images storage setup and try again.\n$error',
        ))),
      );
    }
  }

  Widget _previewImage({
    required String title,
    required String currentUrl,
    required PlatformFile? selected,
    required bool removed,
    required bool logo,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final previewHeight = logo ? (compact ? 150.0 : 170.0) : (compact ? 170.0 : 170.0);
    final hasExisting = !removed && currentUrl.trim().isNotEmpty;
    final hasSelected = selected?.bytes != null;

    Widget preview;
    if (hasSelected) {
      preview = Image.memory(
        selected!.bytes!,
        key: ValueKey('${logo ? 'logo' : 'cover'}-${selected.name}-${selected.size}'),
        fit: BoxFit.cover,
        width: double.infinity,
        height: previewHeight,
        gaplessPlayback: true,
      );
    } else if (hasExisting) {
      preview = PersistentNetworkImage(
        key: ValueKey(currentUrl),
        url: currentUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: previewHeight,
        cacheWidth: compact ? 900 : 1400,
        placeholder: const Center(child: Icon(Icons.image_outlined, color: AppColors.muted, size: 32)),
        errorBuilder: (_, _, _) => const Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.muted, size: 36),
        ),
      );
    } else {
      preview = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add_photo_alternate_outlined, color: AppColors.orange, size: 40),
          const SizedBox(height: 7),
          Text(_label('لا توجد صورة', 'وێنە نییە', 'No image'), style: const TextStyle(color: AppColors.muted)),
        ]),
      );
    }

    final hasImage = hasSelected || hasExisting;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: previewHeight,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7F0),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFD8BE)),
          ),
          child: preview,
        ),
      ),
      const SizedBox(height: 9),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: (_picking || (logo ? _uploadingLogo : _uploadingCover)) ? null : () => _chooseImage(logo: logo),
          icon: (_picking || (logo ? _uploadingLogo : _uploadingCover))
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_rounded),
          label: Text(hasImage ? _label('تغيير الصورة', 'گۆڕینی وێنە', 'Change image') : _label('اختيار صورة', 'وێنە هەڵبژێرە', 'Choose image')),
        ),
        if (hasImage)
          TextButton.icon(
            onPressed: (_picking || (logo ? _uploadingLogo : _uploadingCover))
                ? null
                : () => setState(() {
                    if (logo) {
                      _logoFile = null;
                      _removeLogo = true;
                    } else {
                      _coverFile = null;
                      _removeCover = true;
                    }
                  }),
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(_label('إزالة', 'سڕینەوە', 'Remove')),
          ),
      ]),
    ]);
  }

  void _submit() {
    if (!_isValidPartnerLocalPhone(_phone.text)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_label('رقم الهاتف يجب أن يبدأ بـ 07 ويتكون من 11 رقمًا', 'ژمارەی مۆبایل دەبێت 11 ژمارە بێت', 'Phone number must contain exactly 11 digits'))));
      return;
    }
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_label('اسم المتجر مطلوب', 'ناوی فرۆشگا پێویستە', 'Store name is required'))),
      );
      return;
    }
    Navigator.of(context).pop(_StoreProfileEditResult(
      name: _name.text.trim(),
      description: _description.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      address: _address.text.trim(),
      logoUrl: _savedLogoUrl,
      coverUrl: _savedCoverUrl,
      logoFile: null,
      coverFile: null,
      removeLogo: _removeLogo,
      removeCover: _removeCover,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final images = compact
        ? Column(children: [
            _previewImage(
              title: _label('شعار المتجر', 'لۆگۆی فرۆشگا', 'Store logo'),
              currentUrl: _savedLogoUrl,
              selected: _logoFile,
              removed: _removeLogo,
              logo: true,
            ),
            const SizedBox(height: 16),
            _previewImage(
              title: _label('صورة غلاف المتجر', 'وێنەی پۆششی فرۆشگا', 'Store cover image'),
              currentUrl: _savedCoverUrl,
              selected: _coverFile,
              removed: _removeCover,
              logo: false,
            ),
          ])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 250,
              child: _previewImage(
                title: _label('شعار المتجر', 'لۆگۆی فرۆشگا', 'Store logo'),
                currentUrl: _savedLogoUrl,
                selected: _logoFile,
                removed: _removeLogo,
                logo: true,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _previewImage(
                title: _label('صورة غلاف المتجر', 'وێنەی پۆششی فرۆشگا', 'Store cover image'),
                currentUrl: _savedCoverUrl,
                selected: _coverFile,
                removed: _removeCover,
                logo: false,
              ),
            ),
          ]);

    return Scaffold(
      appBar: AppBar(title: Text(_label('معلومات المتجر', 'زانیارییەکانی فرۆشگا', 'Store information'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              padding: EdgeInsets.fromLTRB(_adaptivePagePadding(context), 18, _adaptivePagePadding(context), 32),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 16 : 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: const Color(0xFFFFF1E6), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.storefront_outlined, color: AppColors.orange),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_label('هوية ومعلومات المتجر', 'ناسنامە و زانیارییەکانی فرۆشگا', 'Store identity & information'), style: TextStyle(fontSize: compact ? 18 : 21, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(_label('هذه البيانات والصور تظهر للعميل.', 'ئەم زانیاری و وێنانە بۆ کڕیار دەردەکەون.', 'These details and images are shown to customers.'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ])),
                    ]),
                    const SizedBox(height: 20),
                    images,
                    const SizedBox(height: 22),
                    TextField(controller: _name, decoration: InputDecoration(labelText: _label('اسم المتجر', 'ناوی فرۆشگا', 'Store name'), prefixIcon: const Icon(Icons.storefront_rounded))),
                    const SizedBox(height: 12),
                    TextField(controller: _description, minLines: 2, maxLines: compact ? 4 : 3, decoration: InputDecoration(labelText: _label('وصف مختصر', 'وەسفی کورت', 'Short description'), prefixIcon: const Icon(Icons.notes_rounded), alignLabelWithHint: true)),
                    const SizedBox(height: 12),
                    TextField(controller: _phone, keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)], decoration: InputDecoration(labelText: _label('رقم تواصل المتجر', 'ژمارەی پەیوەندی', 'Store phone'), prefixIcon: const Icon(Icons.phone_rounded))),
                    const SizedBox(height: 12),
                    TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: _label('البريد الإلكتروني للمتجر', 'ئیمەیڵی فرۆشگا', 'Store email'), prefixIcon: const Icon(Icons.email_outlined))),
                    const SizedBox(height: 12),
                    TextField(controller: _address, minLines: 1, maxLines: 2, decoration: InputDecoration(labelText: _label('عنوان المتجر', 'ناونیشانی فرۆشگا', 'Store address'), prefixIcon: const Icon(Icons.location_on_outlined))),
                    const SizedBox(height: 22),
                    if (compact) ...[
                      FilledButton.icon(onPressed: (_picking || _uploadingLogo || _uploadingCover) ? null : _submit, icon: const Icon(Icons.save_rounded), label: Text(_label('حفظ التغييرات', 'پاشەکەوتکردن', 'Save changes'))),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: (_picking || _uploadingLogo || _uploadingCover) ? null : () => Navigator.of(context).pop(), child: Text(_label('إلغاء', 'هەڵوەشاندنەوە', 'Cancel'))),
                    ] else
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(onPressed: (_picking || _uploadingLogo || _uploadingCover) ? null : () => Navigator.of(context).pop(), child: Text(_label('إلغاء', 'هەڵوەشاندنەوە', 'Cancel'))),
                        const SizedBox(width: 10),
                        FilledButton.icon(onPressed: (_picking || _uploadingLogo || _uploadingCover) ? null : _submit, icon: const Icon(Icons.save_rounded), label: Text(_label('حفظ التغييرات', 'پاشەکەوتکردن', 'Save changes'))),
                      ]),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreDocumentsEditResult {
  const _StoreDocumentsEditResult({
    required this.commercialFile,
    required this.identityFile,
    required this.removeCommercial,
    required this.removeIdentity,
  });

  final PlatformFile? commercialFile;
  final PlatformFile? identityFile;
  final bool removeCommercial;
  final bool removeIdentity;
}

class _StoreDocumentsEditorPage extends StatefulWidget {
  const _StoreDocumentsEditorPage({
    required this.currentLocale,
    required this.commercialCurrent,
    required this.identityCurrent,
    this.onOpenCommercial,
    this.onOpenIdentity,
  });

  final Locale currentLocale;
  final String commercialCurrent;
  final String identityCurrent;
  final VoidCallback? onOpenCommercial;
  final VoidCallback? onOpenIdentity;

  @override
  State<_StoreDocumentsEditorPage> createState() => _StoreDocumentsEditorPageState();
}

class _StoreDocumentsEditorPageState extends State<_StoreDocumentsEditorPage> {
  PlatformFile? _commercialFile;
  PlatformFile? _identityFile;
  bool _removeCommercial = false;
  bool _removeIdentity = false;
  bool _picking = false;

  String _label(String ar, String ku, String en) {
    final code = widget.currentLocale.languageCode;
    if (code == 'en') return en;
    if (code == 'ku') return ku;
    return ar;
  }

  Future<void> _chooseDocument({required bool commercial}) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        withData: true,
        allowMultiple: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.bytes == null || file.size > 8 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_label(
            'المستند يجب أن يكون PDF أو صورة وأقل من 8MB',
            'بەڵگەنامەکە دەبێت PDF یان وێنە و کەمتر لە 8MB بێت',
            'Document must be PDF or image and under 8MB',
          ))),
        );
        return;
      }
      setState(() {
        if (commercial) {
          _commercialFile = file;
          _removeCommercial = false;
        } else {
          _identityFile = file;
          _removeIdentity = false;
        }
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _documentCard({
    required String title,
    required String current,
    required PlatformFile? selected,
    required bool removed,
    required bool commercial,
    required VoidCallback? onOpen,
  }) {
    final existing = !removed && current.trim().isNotEmpty;
    final hasDocument = selected != null || existing;
    final fileName = selected?.name ??
        (existing
            ? _label('مستند محفوظ', 'بەڵگەنامە پاشەکەوتکراوە', 'Saved document')
            : _label('لم يتم رفع مستند', 'بەڵگەنامە بارنەکراوە', 'No document uploaded'));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: const Color(0xFFFFF1E6), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.description_outlined, color: AppColors.orange),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ])),
          if (hasDocument) const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _picking ? null : () => _chooseDocument(commercial: commercial),
            icon: _picking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file_rounded),
            label: Text(hasDocument ? _label('تغيير الملف', 'گۆڕینی فایل', 'Change file') : _label('اختيار ملف', 'فایل هەڵبژێرە', 'Choose file')),
          ),
          if (selected == null && existing && onOpen != null)
            TextButton.icon(onPressed: _picking ? null : onOpen, icon: const Icon(Icons.open_in_new_rounded), label: Text(_label('فتح', 'کردنەوە', 'Open'))),
          if (hasDocument)
            TextButton.icon(
              onPressed: _picking
                  ? null
                  : () => setState(() {
                      if (commercial) {
                        _commercialFile = null;
                        _removeCommercial = true;
                      } else {
                        _identityFile = null;
                        _removeIdentity = true;
                      }
                    }),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(_label('إزالة', 'سڕینەوە', 'Remove')),
            ),
        ]),
      ]),
    );
  }

  void _submit() {
    Navigator.of(context).pop(_StoreDocumentsEditResult(
      commercialFile: _commercialFile,
      identityFile: _identityFile,
      removeCommercial: _removeCommercial,
      removeIdentity: _removeIdentity,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 650;
    return Scaffold(
      appBar: AppBar(title: Text(_label('المستندات', 'بەڵگەنامەکان', 'Documents'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: EdgeInsets.fromLTRB(compact ? 14 : 28, 18, compact ? 14 : 28, 32),
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 16 : 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: const Color(0xFFFFF1E6), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.folder_copy_outlined, color: AppColors.orange),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_label('مستندات المتجر', 'بەڵگەنامەکانی فرۆشگا', 'Store documents'), style: TextStyle(fontSize: compact ? 18 : 21, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(_label('المستندات اختيارية حاليًا. يمكنك رفع نسخة واضحة عند الحاجة للمراجعة أو التحقق. PDF أو صورة، حتى 8MB.', 'بەڵگەنامەکان ئێستا ئارەزوومەندانەن. دەتوانیت کۆپییەکی ڕوون باربکەیت کاتێک پێویست بێت. PDF یان وێنە، تا 8MB.', 'Documents are optional for now. Upload clear copies when verification is needed. PDF or image, up to 8MB.'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ])),
                    ]),
                    const SizedBox(height: 18),
                    _documentCard(
                      title: _label('السجل التجاري', 'تۆماری بازرگانی', 'Commercial registration'),
                      current: widget.commercialCurrent,
                      selected: _commercialFile,
                      removed: _removeCommercial,
                      commercial: true,
                      onOpen: widget.onOpenCommercial,
                    ),
                    const SizedBox(height: 12),
                    _documentCard(
                      title: _label('الهوية الشخصية', 'ناسنامەی کەسی', 'Personal identity'),
                      current: widget.identityCurrent,
                      selected: _identityFile,
                      removed: _removeIdentity,
                      commercial: false,
                      onOpen: widget.onOpenIdentity,
                    ),
                    const SizedBox(height: 22),
                    if (compact) ...[
                      FilledButton.icon(onPressed: _picking ? null : _submit, icon: const Icon(Icons.save_rounded), label: Text(_label('حفظ المستندات', 'پاشەکەوتکردنی بەڵگەنامەکان', 'Save documents'))),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: _picking ? null : () => Navigator.of(context).pop(), child: Text(_label('إلغاء', 'هەڵوەشاندنەوە', 'Cancel'))),
                    ] else
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(onPressed: _picking ? null : () => Navigator.of(context).pop(), child: Text(_label('إلغاء', 'هەڵوەشاندنەوە', 'Cancel'))),
                        const SizedBox(width: 10),
                        FilledButton.icon(onPressed: _picking ? null : _submit, icon: const Icon(Icons.save_rounded), label: Text(_label('حفظ المستندات', 'پاشەکەوتکردنی بەڵگەنامەکان', 'Save documents'))),
                      ]),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsInfoPage extends StatelessWidget {
  const _SettingsInfoPage({required this.title, required this.body, required this.icon});
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFF7A1A), Color(0xFFFF5A00)]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Icon(icon, color: AppColors.orange, size: 30)),
                    const SizedBox(width: 16),
                    Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))),
                  ]),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: Theme.of(context).dividerColor)),
                  child: SelectableText(body, style: TextStyle(fontSize: 15, height: 1.9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({required this.text, required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 15), const SizedBox(width: 5), Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))]),
  );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Theme.of(context).dividerColor),
      boxShadow: const [BoxShadow(color: Color(0x09111827), blurRadius: 18, offset: Offset(0, 8))],
    ),
    child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFFFF1E7), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: AppColors.orange)),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
      ]),
      const SizedBox(height: 20), child,
    ])),
  );
}
