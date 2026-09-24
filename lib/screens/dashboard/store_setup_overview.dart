part of 'partner_dashboard.dart';

class StoreSetupScreen extends StatefulWidget {
  const StoreSetupScreen({
    required this.currentLocale,
    required this.onLocaleChanged,
    required this.profile,
    required this.onSaved,
    required this.onLogout,
    super.key,
  });

  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final Map<String, dynamic>? profile;
  final Future<void> Function() onSaved;
  final Future<void> Function() onLogout;

  @override
  State<StoreSetupScreen> createState() => _StoreSetupScreenState();
}

class _StoreSetupScreenState extends State<StoreSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  bool _deliveryAvailable = true;
  bool _saving = false;
  bool _locating = false;
  PlatformFile? _logoFile;
  PlatformFile? _coverFile;

  @override
  void initState() {
    super.initState();
    _phone.text = (widget.profile?['phone'] as String?) ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _phone.dispose();
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  double? _coordinate(String value) => double.tryParse(value.trim().replaceAll(',', '.'));

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    final s = AppStrings.of(context);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('LOCATION_SERVICE_DISABLED');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError('LOCATION_PERMISSION_DENIED');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _latitude.text = position.latitude.toStringAsFixed(7);
        _longitude.text = position.longitude.toStringAsFixed(7);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.t('storeCurrentLocationFailed'))),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if ((_formKey.currentState?.validate() == false) || _saving) return;
    final latText = _latitude.text.trim();
    final lngText = _longitude.text.trim();
    final lat = latText.isEmpty ? null : _coordinate(latText);
    final lng = lngText.isEmpty ? null : _coordinate(lngText);
    final invalidLocation = (latText.isEmpty != lngText.isEmpty) ||
        (latText.isNotEmpty && (lat == null || lat < -90 || lat > 90)) ||
        (lngText.isNotEmpty && (lng == null || lng < -180 || lng > 180));
    if (invalidLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).t('storeLocationInvalid'))),
      );
      return;
    }
    if (_deliveryAvailable && (lat == null || lng == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).t('storeLocationRequiredForDelivery'))),
      );
      return;
    }
    setState(() => _saving = true);
    final s = AppStrings.of(context);
    try {
      await AuthService.instance.createStore(
        name: _name.text,
        description: _description.text,
        phone: _phone.text,
        address: _address.text,
        businessType: widget.profile?['business_type'] as String?,
        systemCategoryId: widget.profile?['system_category_id']?.toString(),
        deliveryAvailable: _deliveryAvailable,
        latitude: lat,
        longitude: lng,
      );
      String? logoUrl;
      String? coverUrl;
      if (_logoFile?.bytes != null) {
        logoUrl = await AuthService.instance.uploadStoreImage(bytes: _logoFile!.bytes!, extension: _logoFile!.extension ?? 'jpg', kind: 'logo');
      }
      if (_coverFile?.bytes != null) {
        coverUrl = await AuthService.instance.uploadStoreImage(bytes: _coverFile!.bytes!, extension: _coverFile!.extension ?? 'jpg', kind: 'cover');
      }
      if (logoUrl != null || coverUrl != null) {
        await AuthService.instance.updateStoreImages(logoUrl: logoUrl, coverUrl: coverUrl);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.t('storeSaved'))),
      );
      await widget.onSaved();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.t('authFailed'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('appTitle'), style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          LanguageMenu(currentLocale: widget.currentLocale, onChanged: widget.onLocaleChanged),
          const SizedBox(width: 8),
          TextButton.icon(onPressed: widget.onLogout, icon: const Icon(Icons.logout_rounded), label: Text(s.t('logout'))),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final form = _StoreSetupForm(
            formKey: _formKey,
            name: _name,
            description: _description,
            phone: _phone,
            address: _address,
            latitude: _latitude,
            longitude: _longitude,
            deliveryAvailable: _deliveryAvailable,
            saving: _saving,
            logoFile: _logoFile,
            coverFile: _coverFile,
            onLogoChanged: (v) => setState(() => _logoFile = v),
            onCoverChanged: (v) => setState(() => _coverFile = v),
            onLocationChanged: () => setState(() {}),
            onUseCurrentLocation: _useCurrentLocation,
            locating: _locating,
            onDeliveryChanged: (v) => setState(() => _deliveryAvailable = v),
            onSave: _save,
          );
          return SingleChildScrollView(
            padding: EdgeInsets.all(wide ? 36 : 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: form), const SizedBox(width: 24), const Expanded(flex: 4, child: _StoreSetupInfoCard())])
                    : form,
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

class _StoreSetupForm extends StatelessWidget {
  const _StoreSetupForm({
    required this.formKey,
    required this.name,
    required this.description,
    required this.phone,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.deliveryAvailable,
    required this.saving,
    required this.logoFile,
    required this.coverFile,
    required this.onLogoChanged,
    required this.onCoverChanged,
    required this.onLocationChanged,
    required this.onUseCurrentLocation,
    required this.locating,
    required this.onDeliveryChanged,
    required this.onSave,
  });
  final GlobalKey<FormState> formKey;
  final TextEditingController name, description, phone, address, latitude, longitude;
  final bool deliveryAvailable, saving;
  final PlatformFile? logoFile, coverFile;
  final ValueChanged<PlatformFile?> onLogoChanged, onCoverChanged;
  final VoidCallback onLocationChanged;
  final Future<void> Function() onUseCurrentLocation;
  final bool locating;
  final ValueChanged<bool> onDeliveryChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 620;
      final horizontalPadding = compact ? 16.0 : 26.0;
      final fieldGap = compact ? 10.0 : 14.0;
      final lat = double.tryParse(latitude.text.trim().replaceAll(',', '.'));
      final lng = double.tryParse(longitude.text.trim().replaceAll(',', '.'));

      InputDecoration decoration(String label, String hint, IconData icon) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: compact ? 20 : 24),
        filled: true,
        fillColor: Colors.white,
        isDense: compact,
        contentPadding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: compact ? 13 : 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(compact ? 14 : 18), borderSide: const BorderSide(color: Color(0xFFFFD8BE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(compact ? 14 : 18), borderSide: const BorderSide(color: Color(0xFFFFD8BE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(compact ? 14 : 18), borderSide: const BorderSide(color: AppColors.orange, width: 2)),
      );
      String? required(String? v) => v == null || v.trim().isEmpty ? s.t('requiredField') : null;

      Future<void> pickImage(bool logo) async {
        final file = await pickPartnerPhoto();
        if (file == null) return;
        if (file.bytes == null || file.size > 5 * 1024 * 1024) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الصورة يجب أن تكون أقل من 5MB')));
          return;
        }
        if (!context.mounted) return;
        final cropped = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(
          builder: (_) => PartnerImageCropEditor(bytes: file.bytes!, aspectRatio: logo ? 1.0 : 16 / 9, title: logo ? 'ضبط شعار المتجر' : 'ضبط صورة الغلاف', circularFrame: logo),
        ));
        if (!context.mounted || cropped == null) return;
        final adjusted = PlatformFile(name: '${logo ? 'logo' : 'cover'}_cropped.png', size: cropped.length, bytes: cropped);
        if (logo) { onLogoChanged(adjusted); } else { onCoverChanged(adjusted); }
      }

      Widget imagePicker({required bool logo}) {
        final file = logo ? logoFile : coverFile;
        final height = logo ? (compact ? 110.0 : 130.0) : (compact ? 125.0 : 160.0);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(logo ? 'شعار المتجر' : 'صورة غلاف المتجر', style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 13 : 15)),
          const SizedBox(height: 7),
          InkWell(
            onTap: () => pickImage(logo),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: height,
              decoration: BoxDecoration(color: const Color(0xFFFFF7F0), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFFD8BE))),
              clipBehavior: Clip.antiAlias,
              child: file?.bytes != null
                  ? Image.memory(file!.bytes!, fit: BoxFit.cover, width: double.infinity)
                  : const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_photo_alternate_outlined, color: AppColors.orange, size: 34), SizedBox(height: 6), Text('اضغط لإضافة صورة', style: TextStyle(fontWeight: FontWeight.w800))])),
            ),
          ),
          if (file != null) Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(onPressed: () => logo ? onLogoChanged(null) : onCoverChanged(null), icon: const Icon(Icons.delete_outline_rounded), label: const Text('إزالة'))),
        ]);
      }

      Widget coordinateFields() {
        final latField = TextFormField(
          controller: latitude,
          onChanged: (_) => onLocationChanged(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          textDirection: TextDirection.ltr,
          decoration: decoration(s.t('storeLatitude'), '36.27', Icons.my_location_rounded),
        );
        final lngField = TextFormField(
          controller: longitude,
          onChanged: (_) => onLocationChanged(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          textDirection: TextDirection.ltr,
          decoration: decoration(s.t('storeLongitude'), '43.38', Icons.explore_outlined),
        );
        if (compact) {
          return Column(children: [latField, SizedBox(height: fieldGap), lngField]);
        }
        return Row(children: [Expanded(child: latField), const SizedBox(width: 12), Expanded(child: lngField)]);
      }

      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 20 : 28), side: const BorderSide(color: Color(0xFFFFE1CD))),
        child: Padding(
          padding: EdgeInsets.all(horizontalPadding),
          child: Form(
            key: formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CircleAvatar(radius: compact ? 25 : 34, backgroundColor: const Color(0xFFFFEEE2), child: Icon(Icons.storefront_rounded, color: AppColors.orange, size: compact ? 27 : 36)),
              SizedBox(height: compact ? 10 : 16),
              Text(s.t('setupStoreTitle'), textAlign: TextAlign.center, style: TextStyle(fontSize: compact ? 21 : 28, fontWeight: FontWeight.w900)),
              SizedBox(height: compact ? 5 : 8),
              Text(s.t('setupStoreSubtitle'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: compact ? 12.5 : 14)),
              SizedBox(height: compact ? 16 : 24),
              imagePicker(logo: true),
              SizedBox(height: fieldGap),
              imagePicker(logo: false),
              SizedBox(height: compact ? 14 : 18),
              TextFormField(controller: name, validator: required, textInputAction: TextInputAction.next, decoration: decoration(s.t('storeName'), s.t('storeNameHint'), Icons.store_rounded)),
              SizedBox(height: fieldGap),
              TextFormField(controller: description, maxLines: compact ? 2 : 3, textInputAction: TextInputAction.next, decoration: decoration(s.t('storeDescription'), s.t('storeDescriptionHint'), Icons.notes_rounded)),
              SizedBox(height: fieldGap),
              TextFormField(controller: phone, validator: required, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, textInputAction: TextInputAction.next, decoration: decoration(s.t('storePhone'), s.t('phoneHint'), Icons.phone_rounded)),
              SizedBox(height: fieldGap),
              TextFormField(controller: address, validator: required, maxLines: compact ? 1 : 2, textInputAction: TextInputAction.next, decoration: decoration(s.t('storeAddress'), s.t('storeAddressHint'), Icons.location_on_rounded)),
              SizedBox(height: compact ? 14 : 18),
              Text(s.t('storeLocationTitle'), style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 14 : 16)),
              const SizedBox(height: 4),
              Text(s.t('storeLocationHint'), style: TextStyle(color: AppColors.muted, fontSize: compact ? 11.5 : 12.5, height: 1.35)),
              SizedBox(height: fieldGap),
              coordinateFields(),
              SizedBox(height: compact ? 10 : 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: locating ? null : onUseCurrentLocation,
                  icon: locating
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded),
                  label: Text(s.t('storeUseCurrentLocation')),
                ),
              ),
              SizedBox(height: fieldGap),
              MapboxLocationPreview(
                latitude: lat,
                longitude: lng,
                height: compact ? 150 : 200,
                emptyText: s.t('storeLocationHint'),
                unsupportedText: s.t('storeMapDesktopHint'),
                missingTokenText: s.t('storeMapTokenMissing'),
              ),
              SizedBox(height: compact ? 8 : 12),
              SwitchListTile.adaptive(
                value: deliveryAvailable,
                onChanged: onDeliveryChanged,
                title: Text(s.t('deliveryAvailable'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 13 : 14)),
                activeThumbColor: AppColors.orange,
                dense: compact,
                contentPadding: EdgeInsets.zero,
              ),
              SizedBox(height: compact ? 8 : 12),
              SizedBox(
                height: compact ? 48 : 54,
                child: FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: saving ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_rounded),
                  label: Text(s.t('saveStore'), style: TextStyle(fontSize: compact ? 14.5 : 17, fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

}

class _StoreSetupInfoCard extends StatelessWidget {
  const _StoreSetupInfoCard();
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFF7F0), Color(0xFFFFEBDD)]), borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFFFD9BF))),
      child: Column(children: [
        const Icon(Icons.rocket_launch_rounded, size: 58, color: AppColors.orange),
        const SizedBox(height: 18),
        Text(s.t('storeSetupRequired'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Text(s.t('setupStoreSubtitle'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.6)),
      ]),
    );
  }
}

class _StoreIdentityCard extends StatelessWidget {
  const _StoreIdentityCard({required this.store});
  final Map<String, dynamic>? store;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final name = store?['name']?.toString().trim();
    final businessType = store?['business_type']?.toString().trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8F2), Color(0xFFFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFDDC5)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE9D9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.storefront_rounded, color: AppColors.orange, size: 27),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name == null || name.isEmpty ? s.t('storeDashboard') : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                ),
                const SizedBox(height: 3),
                Text(
                  businessType == null || businessType.isEmpty ? s.t('storeUnderReview') : businessType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreOverviewPage extends StatefulWidget {
  const _StoreOverviewPage({
    required this.store,
    required this.updatingOpenStatus,
    required this.onOpenChanged,
    required this.onNavigate,
  });

  final Map<String, dynamic>? store;
  final bool updatingOpenStatus;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<int> onNavigate;

  @override
  State<_StoreOverviewPage> createState() => _StoreOverviewPageState();
}

class _StoreOverviewPageState extends State<_StoreOverviewPage> {
  List<Map<String, dynamic>> _orders = const [];
  int _productCount = 0;
  bool _loadingSummary = true;
  String? _summaryError;
  RealtimeChannel? _ordersChannel;

  String? get _storeId => widget.store?['id']?.toString();

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _subscribeOrders();
  }

  @override
  void didUpdateWidget(covariant _StoreOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store?['id']?.toString() != _storeId) {
      _loadSummary();
      _subscribeOrders();
    }
  }

  @override
  void dispose() {
    final channel = _ordersChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  Future<void> _subscribeOrders() async {
    final storeId = _storeId;
    if (storeId == null || storeId.isEmpty) return;
    final previous = _ordersChannel;
    if (previous != null) {
      await Supabase.instance.client.removeChannel(previous);
    }
    _ordersChannel = Supabase.instance.client
        .channel('store-overview-orders-$storeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'store_id',
            value: storeId,
          ),
          callback: (_) => _loadSummary(silent: true),
        )
        .subscribe();
  }

  Future<void> _loadSummary({bool silent = false}) async {
    final storeId = _storeId;
    if (storeId == null || storeId.isEmpty) return;
    if (!silent && mounted) {
      setState(() {
        _loadingSummary = true;
        _summaryError = null;
      });
    }
    try {
      final client = Supabase.instance.client;
      final ordersData = await client
          .from('orders')
          .select('id,order_number,status,total,created_at')
          .eq('store_id', storeId)
          .order('created_at', ascending: false)
          .limit(100);
      final productsData = await client
          .from('products')
          .select('id')
          .eq('store_id', storeId);
      if (!mounted) return;
      setState(() {
        _orders = List<Map<String, dynamic>>.from(ordersData);
        _productCount = (productsData as List).length;
        _summaryError = null;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _summaryError = error.message);
    } finally {
      if (!silent && mounted) setState(() => _loadingSummary = false);
    }
  }

  bool _isToday(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  String _statusLabel(AppStrings s, String status) => switch (status) {
        'pending' => s.t('newOrders'),
        'accepted' => s.t('acceptedStatus'),
        'preparing' => s.t('preparingStatus'),
        'ready' => s.t('orderStatusReady'),
        'assigned' => s.t('orderStatusReady'),
        'picked_up' => s.t('pickedUpStatusMetric'),
        'delivered' => s.t('deliveredStatus'),
        'cancelled' => s.t('cancelledStatus'),
        'rejected' => s.t('rejectOrder'),
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final s = AppStrings.of(context);
    final approvalStatus = (store?['approval_status'] ?? 'pending').toString();
    final isActive = store?['is_active'] == true;
    final isApproved = approvalStatus == 'approved';
    final isRejected = approvalStatus == 'rejected';
    final canOpenStore = isApproved && isActive;
    final isOpen = canOpenStore && store?['is_open'] == true;
    final statusLabel = isRejected
        ? s.t('storeRejected')
        : isApproved && !isActive
            ? s.t('storeApprovedInactive')
            : isApproved
                ? (isOpen ? s.t('storeOpen') : s.t('storeClosed'))
                : s.t('storeUnderReview');
    final reviewNotice = isRejected
        ? s.t('rejectedReviewNotice')
        : isApproved && !isActive
            ? s.t('approvedActivationNotice')
            : s.t('pendingApprovalNotice');
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    final columns = width < 350 ? 1 : width >= 1320 ? 4 : 2;
    final storeName = store?['name']?.toString() ?? s.t('storeDashboard');

    final todayOrders = _orders.where((o) => _isToday(o['created_at'])).toList();
    final activeOrders = _orders.where((o) => const {
          'pending', 'accepted', 'preparing', 'ready', 'assigned', 'picked_up'
        }.contains(o['status']?.toString())).length;
    final todayRevenue = todayOrders
        .where((o) => o['status']?.toString() == 'delivered')
        .fold<double>(0, (sum, o) => sum + ((o['total'] as num?)?.toDouble() ?? 0));
    final recentOrders = _orders.take(4).toList();

    return ColoredBox(
      color: const Color(0xFFF6F7FB),
      child: RefreshIndicator(
        onRefresh: _loadSummary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(_adaptivePagePadding(context), compact ? 12 : 20, _adaptivePagePadding(context), compact ? 20 : 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: EdgeInsets.all(compact ? 15 : 28),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: AlignmentDirectional.topStart,
                        end: AlignmentDirectional.bottomEnd,
                        colors: [Color(0xFFFF6A13), Color(0xFFFF8A3D)],
                      ),
                      borderRadius: BorderRadius.circular(compact ? 20 : 28),
                      boxShadow: const [
                        BoxShadow(color: Color(0x24FF5A00), blurRadius: 30, offset: Offset(0, 14)),
                      ],
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 18,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: compact ? 420 : 680),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 11, vertical: compact ? 4 : 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .16),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Text(s.t('overview'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: compact ? 10.5 : 12)),
                              ),
                              SizedBox(height: compact ? 8 : 13),
                              Text(storeName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: compact ? 21 : 34, height: 1.15, fontWeight: FontWeight.w900)),
                              SizedBox(height: compact ? 5 : 8),
                              Text(s.t('dashboardReady'), style: TextStyle(color: Colors.white.withValues(alpha: .88), fontSize: compact ? 11.5 : 14, height: compact ? 1.35 : 1.5, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 7 : 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.updatingOpenStatus)
                                const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2))
                              else
                                Icon(isOpen ? Icons.check_circle_rounded : Icons.pause_circle_filled_rounded, color: isOpen ? AppColors.green : AppColors.muted),
                              const SizedBox(width: 8),
                              Text(statusLabel, style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 11.5 : 14)),
                              const SizedBox(width: 6),
                              Switch.adaptive(value: isOpen, onChanged: (widget.updatingOpenStatus || !canOpenStore) ? null : widget.onOpenChanged, activeThumbColor: AppColors.green),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: compact ? 10 : 13),
                    decoration: BoxDecoration(color: const Color(0xFFFFF8F0), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFFDFC8))),
                    child: Row(children: [
                      Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFFFEBDD), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.verified_user_outlined, color: AppColors.orange, size: 20)),
                      const SizedBox(width: 11),
                      Expanded(child: Text(reviewNotice, style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 11.5 : 14, color: const Color(0xFF734323)))),
                    ]),
                  ),
                  if (_summaryError != null) ...[
                    const SizedBox(height: 12),
                    Material(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_summaryError!, style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  GridView.count(
                    crossAxisCount: columns,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: width < 350 ? 2.05 : compact ? 1.22 : 1.75,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _MetricCard(label: s.t('todayOrders'), value: _loadingSummary ? '…' : '${todayOrders.length}', icon: Icons.shopping_bag_outlined, accent: AppColors.orange, onTap: () => widget.onNavigate(1)),
                      _MetricCard(label: s.t('activeOrders'), value: _loadingSummary ? '…' : '$activeOrders', icon: Icons.pending_actions_rounded, accent: const Color(0xFF2563EB), onTap: () => widget.onNavigate(1)),
                      _MetricCard(label: s.t('totalProducts'), value: _loadingSummary ? '…' : '$_productCount', icon: Icons.inventory_2_outlined, accent: const Color(0xFF7C3AED), onTap: () => widget.onNavigate(2)),
                      _MetricCard(label: s.t('todayRevenue'), value: _loadingSummary ? '…' : '${todayRevenue.toStringAsFixed(0)} د.ع', icon: Icons.account_balance_wallet_outlined, accent: AppColors.green, onTap: () => widget.onNavigate(4)),
                    ],
                  ),
                  SizedBox(height: compact ? 20 : 26),
                  Row(children: [Text(s.t('quickActions'), style: TextStyle(fontSize: compact ? 16 : 21, fontWeight: FontWeight.w900)), const Spacer(), Container(width: 34, height: 4, decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(20)))]),
                  const SizedBox(height: 13),
                  LayoutBuilder(builder: (context, constraints) {
                    final actionColumns = constraints.maxWidth < 350 ? 1 : constraints.maxWidth >= 900 ? 4 : 2;
                    final actionWidth = (constraints.maxWidth - 12 * (actionColumns - 1)) / actionColumns;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      SizedBox(width: actionWidth, child: _QuickAction(label: s.t('addProduct'), icon: Icons.add_box_outlined, onTap: () => widget.onNavigate(2))),
                      SizedBox(width: actionWidth, child: _QuickAction(label: s.t('manageOrders'), icon: Icons.receipt_long_outlined, onTap: () => widget.onNavigate(1))),
                      SizedBox(width: actionWidth, child: _QuickAction(label: s.t('createOffer'), icon: Icons.local_offer_outlined, onTap: () => widget.onNavigate(3))),
                      SizedBox(width: actionWidth, child: _QuickAction(label: s.t('viewReports'), icon: Icons.insights_outlined, onTap: () => widget.onNavigate(4))),
                    ]);
                  }),
                  SizedBox(height: compact ? 20 : 26),
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE8EAF0))),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 14 : 22),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(child: Text(s.t('recentOrders'), style: TextStyle(fontSize: compact ? 16 : 20, fontWeight: FontWeight.w900))),
                          TextButton.icon(onPressed: () => widget.onNavigate(1), icon: Icon(Icons.arrow_forward_rounded, size: compact ? 16 : 18), label: Text(s.t('orders'), style: TextStyle(fontSize: compact ? 11.5 : 14))),
                        ]),
                        const SizedBox(height: 14),
                        if (_loadingSummary)
                          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                        else if (recentOrders.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                            decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(18)),
                            child: Column(children: [
                              Container(width: 68, height: 68, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)), child: const Icon(Icons.receipt_long_outlined, size: 34, color: Color(0xFFAAB0BB))),
                              const SizedBox(height: 12),
                              Text(s.t('noOrdersYet'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                            ]),
                          )
                        else
                          ...recentOrders.map((order) {
                            final number = order['order_number']?.toString() ?? '';
                            final status = order['status']?.toString() ?? 'pending';
                            final total = (order['total'] as num?)?.toDouble() ?? 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: const Color(0xFFF8F9FB),
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  onTap: () => widget.onNavigate(1),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                    child: Row(children: [
                                      const Icon(Icons.receipt_long_rounded, color: AppColors.orange),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text('#$number • ${_statusLabel(s, status)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 11.5 : 14))),
                                      Text('${total.toStringAsFixed(0)} د.ع', style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 11.5 : 14)),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          }),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.onTap,
  });
  final String label, value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 230;
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 17 : 22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(compact ? 17 : 22),
          child: Container(
            padding: EdgeInsets.all(compact ? 11 : 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 17 : 22),
              border: Border.all(color: const Color(0xFFE8EAF0)),
              boxShadow: const [BoxShadow(color: Color(0x08172033), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)),
                        child: Icon(icon, color: accent, size: 20),
                      ),
                      const Spacer(),
                      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -.3)),
                      const SizedBox(height: 2),
                      Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 10.5, height: 1.2)),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(17)),
                        child: Icon(icon, color: accent, size: 25),
                      ),
                      SizedBox(width: compact ? 10 : 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.4)),
                            const SizedBox(height: 4),
                            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, size: 15, color: accent.withValues(alpha: .75)),
                    ],
                  ),
          ),
        ),
      );
    });
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 250;
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(compact ? 16 : 20),
          child: Container(
            padding: EdgeInsets.all(compact ? 10 : 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 16 : 20),
              border: Border.all(color: const Color(0xFFE8EAF0)),
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 36 : 44,
                  height: compact ? 36 : 44,
                  decoration: BoxDecoration(color: const Color(0xFFFFF0E5), borderRadius: BorderRadius.circular(compact ? 11 : 14)),
                  child: Icon(icon, color: AppColors.orange, size: compact ? 18 : 22),
                ),
                SizedBox(width: compact ? 8 : 12),
                Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 10.5 : 14))),
                if (!compact) const Icon(Icons.chevron_right_rounded, color: Color(0xFFADB3BE)),
              ],
            ),
          ),
        ),
      );
    });
  }
}




class _ModernPageHero extends StatelessWidget {
  const _ModernPageHero({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
    this.accent = AppColors.orange,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: compact ? 38 : 52,
          height: compact ? 38 : 52,
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(compact ? 12 : 16)),
          child: Icon(icon, color: Colors.white, size: compact ? 20 : 27),
        ),
        SizedBox(width: compact ? 10 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 18 : 27, fontWeight: FontWeight.w900, height: 1.15)),
              SizedBox(height: compact ? 2 : 6),
              Text(subtitle, maxLines: compact ? 2 : 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, height: 1.3, fontSize: compact ? 10.5 : 14)),
            ],
          ),
        ),
      ],
    );
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [accent.withValues(alpha: .12), Colors.white],
        ),
        borderRadius: BorderRadius.circular(compact ? 17 : 24),
        border: Border.all(color: accent.withValues(alpha: .16)),
        boxShadow: const [BoxShadow(color: Color(0x0D111827), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                if (trailing != null) ...[const SizedBox(height: 10), Align(alignment: AlignmentDirectional.centerStart, child: trailing!)],
              ],
            )
          : Row(
              children: [
                Expanded(child: heading),
                if (trailing != null) ...[const SizedBox(width: 18), Flexible(child: Align(alignment: AlignmentDirectional.centerEnd, child: trailing!))],
              ],
            ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.icon, required this.label, required this.value, required this.accent});
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8EAF0)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 19, color: accent),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
          Text(value, style: TextStyle(color: accent, fontWeight: FontWeight.w900)),
        ]),
      );
}


class _DriverHomeScreen extends StatefulWidget {
  const _DriverHomeScreen({required this.currentLocale, required this.onLocaleChanged, required this.profile, required this.onLogout});
  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final Map<String, dynamic>? profile;
  final Future<void> Function() onLogout;

  @override
  State<_DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<_DriverHomeScreen> {
  bool _online = false;
  bool _loading = true;
  bool _savingOnline = false;
  bool _checkingOffer = false;
  List<Map<String, dynamic>> _activeOrders = const [];
  Map<String, dynamic>? _selectedActiveOrder;
  bool _showAllActiveOrders = false;
  Map<String, dynamic>? _earningsSummary;
  bool _showEarnings = false;
  _DriverFinanceView _driverFinanceView = _DriverFinanceView.dues;
  bool _showHistory = false;
  bool _showNotifications = false;
  bool _showRatings = false;
  bool _showAccountCenter = false;
  int _driverUnreadNotifications = 0;
  int _driverUnreadSupport = 0;
  double? _driverLatitude;
  double? _driverLongitude;
  bool _openingHomeMaps = false;
  Timer? _offerTimer;
  Timer? _driverNotificationsTimer;
  Timer? _driverActiveOrdersTimer;
  StreamSubscription<PartnerPushEvent>? _pushEventsSub;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshDriverNotifications();
    _refreshDriverLocation();
    _driverNotificationsTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshDriverNotifications());
    _driverActiveOrdersTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshActiveOrders();
      if (_activeOrders.isNotEmpty) _refreshDriverLocation();
    });
    _pushEventsSub = PushNotificationService.instance.events.listen(_handlePushEvent);
    final pendingPush = PushNotificationService.instance.takePendingOpenedEvent();
    if (pendingPush != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handlePushEvent(pendingPush));
    }
  }

  @override
  void dispose() {
    _offerTimer?.cancel();
    _driverNotificationsTimer?.cancel();
    _driverActiveOrdersTimer?.cancel();
    _pushEventsSub?.cancel();
    super.dispose();
  }

  Future<void> _handlePushEvent(PartnerPushEvent event) async {
    if (!mounted) return;
    await _refreshDriverNotifications();
    if (!mounted || event.orderId.isEmpty) return;
    if (event.openedByUser) {
      await _openOrClaimOrder(event.orderId);
      return;
    }

    // Android/iOS do not show a normal system banner while FCM arrives in the
    // foreground. Surface the same event inside Hala Talab so a driver testing
    // on an open phone never appears to have "missed" the notification.
    final language = widget.currentLocale.languageCode;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            language == 'en'
                ? 'New delivery request received.'
                : language == 'ku'
                    ? 'داواکاری گەیاندنی نوێ گەیشت.'
                    : 'وصل طلب توصيل جديد.',
          ),
          action: SnackBarAction(
            label: language == 'en' ? 'Open' : language == 'ku' ? 'کردنەوە' : 'فتح',
            onPressed: () => _openOrClaimOrder(event.orderId),
          ),
        ),
      );
  }

  Future<void> _openOrClaimOrder(String orderId) async {
    if (!mounted || orderId.trim().isEmpty) return;
    final s = AppStrings.of(context);
    try {
      await _refreshActiveOrders();
      if (!mounted) return;
      var matches = _activeOrders.where(
        (item) => item['order_id']?.toString() == orderId,
      );
      if (matches.isEmpty) {
        // A ready notification is an offer, not yet an assigned trip. Claim it
        // through the same atomic RPC used by polling. Store-scoped and Hala
        // drivers share this path; Supabase decides eligibility.
        await DriverDeliveryRepository.instance.claimOffer(orderId);
        await _refreshActiveOrders();
        if (!mounted) return;
        matches = _activeOrders.where(
          (item) => item['order_id']?.toString() == orderId,
        );
      }
      if (matches.isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(
            widget.currentLocale.languageCode == 'en'
                ? 'This delivery is no longer available.'
                : widget.currentLocale.languageCode == 'ku'
                    ? 'ئەم گەیاندنە چیتر بەردەست نییە.'
                    : 'طلب التوصيل لم يعد متاحًا للاستلام.',
          )));
        return;
      }
      setState(() {
        _showNotifications = false;
        _showAllActiveOrders = false;
        _selectedActiveOrder = matches.first;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = (error.message).toLowerCase();
      final unavailable = message.contains('no longer available') ||
          message.contains('not available') ||
          message.contains('assigned store');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(
          unavailable
              ? (widget.currentLocale.languageCode == 'en'
                  ? 'This delivery is no longer available.'
                  : widget.currentLocale.languageCode == 'ku'
                      ? 'ئەم گەیاندنە چیتر بەردەست نییە.'
                      : 'طلب التوصيل لم يعد متاحًا للاستلام.')
              : '${s.t('driverLoadFailed')}: ${error.message}',
        )));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${s.t('driverLoadFailed')}: $error')));
    }
  }

  Future<void> _load() async {
    bool online = false;
    try {
      online = await AuthService.instance.isDriverOnline().timeout(const Duration(seconds: 6));
    } catch (_) {}
    List<Map<String, dynamic>> activeOrders = const [];
    Map<String, dynamic>? earningsSummary;
    try {
      activeOrders = await DriverDeliveryRepository.instance.getActiveAssignedOrders().timeout(const Duration(seconds: 12));
    } on PostgrestException catch (error) {
      if (mounted && error.code == 'PGRST202') {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(AppStrings.of(context).t('driverStage8SqlRequired'))));
      }
    } catch (_) {
      // Network/timeouts must never leave the driver home stuck on the loader.
      activeOrders = const [];
    }
    try {
      earningsSummary = await DriverDeliveryRepository.instance.getEarningsWallet().timeout(const Duration(seconds: 10));
    } catch (_) {
      // Stage 12 SQL may not be installed yet; keep home usable with zero values.
    }
    if (!mounted) return;
    setState(() {
      _online = online;
      _activeOrders = activeOrders;
      _earningsSummary = earningsSummary;
      _loading = false;
    });
    if (online && activeOrders.length < 10) _startOfferPolling();
  }

  Future<void> _setOnline(bool value) async {
    if (_savingOnline) return;
    final s = AppStrings.of(context);
    setState(() => _savingOnline = true);
    try {
      await AuthService.instance.setDriverOnline(value);
      if (!mounted) return;
      setState(() => _online = value);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(value ? s.t('driverOnlineSubtitle') : s.t('driverOfflineSubtitle'))));
      if (value) {
        if (_activeOrders.length < 10) {
          _startOfferPolling();
        }
      } else {
        _offerTimer?.cancel();
      }
    } finally {
      if (mounted) setState(() => _savingOnline = false);
    }
  }

  void _startOfferPolling() {
    _offerTimer?.cancel();
    _checkForDeliveryOffer();
    _offerTimer = Timer.periodic(const Duration(seconds: 8), (_) => _checkForDeliveryOffer());
  }

  Future<void> _refreshActiveOrders() async {
    try {
      final activeOrders = await DriverDeliveryRepository.instance.getActiveAssignedOrders();
      if (!mounted) return;
      setState(() {
        _activeOrders = activeOrders;
        final selectedId = _selectedActiveOrder?['order_id']?.toString();
        if (selectedId != null) {
          final matches = activeOrders.where((item) => item['order_id']?.toString() == selectedId);
          _selectedActiveOrder = matches.isEmpty ? null : matches.first;
        }
      });
    } catch (_) {
      // Keep the driver home usable if the RPC is temporarily unavailable.
    }
  }

  Future<void> _checkForDeliveryOffer() async {
    if (!_online || _checkingOffer || !mounted || _activeOrders.length >= 10) return;
    setState(() => _checkingOffer = true);
    try {
      final offer = await DriverDeliveryRepository.instance.getNextAvailableOffer();
      if (!mounted || offer == null || !_online) return;

      // Stage 113: no driver accept/reject step. While the driver is online,
      // claim the next ready order atomically and surface it as an active trip.
      await DriverDeliveryRepository.instance.claimOffer(offer['order_id'].toString());
      await _refreshActiveOrders();
      await _refreshDriverNotifications();

      if (_activeOrders.length >= 10) {
        _offerTimer?.cancel();
      }
    } on PostgrestException catch (error) {
      if (mounted && error.code == 'PGRST202') {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(AppStrings.of(context).t('driverStage7SqlRequired'))));
      }
      // A competing online driver may claim the same ready order first.
      // The next polling tick will simply try the next available order.
    } finally {
      if (mounted) setState(() => _checkingOffer = false);
    }
  }

  Future<void> _refreshDriverNotifications() async {
    try {
      final enabled = await AuthService.instance.areDriverNotificationsEnabled();
      final count = enabled ? await DriverDeliveryRepository.instance.getUnreadDriverNotificationCount() : 0;
      final supportCount = await _loadUnreadSupportCount();
      if (mounted) {
        setState(() {
          _driverUnreadNotifications = count;
          _driverUnreadSupport = supportCount;
        });
      }
    } catch (_) {
      // Keep the home usable if notifications/support are temporarily unavailable.
    }
  }

  Future<int> _loadUnreadSupportCount() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return 0;
    final ticketsRaw = await Supabase.instance.client
        .from('partner_support_tickets')
        .select('id')
        .eq('user_id', user.id);
    final ids = List<Map<String, dynamic>>.from(ticketsRaw)
        .map((e) => e['id']?.toString())
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isEmpty) return 0;
    final rows = await Supabase.instance.client
        .from('partner_support_messages')
        .select('sender_role,is_read')
        .inFilter('ticket_id', ids);
    var count = 0;
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final role = (row['sender_role'] ?? '').toString().toLowerCase();
      final fromSupport = role == 'admin' || role == 'support' || role == 'management';
      if (fromSupport && row['is_read'] != true) count++;
    }
    return count;
  }

  Future<void> _refreshDriverLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _driverLatitude = position.latitude;
        _driverLongitude = position.longitude;
      });
    } catch (_) {}
  }

  Future<void> _openSupportInbox() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _StoreSupportInboxPage(storeId: null, isDriver: true)));
    await _refreshDriverNotifications();
  }

  void _stageNotice() {
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.t('driverHomeNextStages'))));
  }


  Widget _tool(BuildContext context, IconData icon, String label, {VoidCallback? onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap ?? _stageNotice,
      child: Container(
        constraints: const BoxConstraints(minHeight: 102),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8EAF0)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: AppColors.orange),
          const SizedBox(height: 8),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _driverLanguageButton() {
    final code = widget.currentLocale.languageCode;
    return PopupMenuButton<String>(
      tooltip: AppStrings.of(context).t('language'),
      icon: const Icon(Icons.language_rounded),
      onSelected: (value) async {
        // Let PopupMenuRoute finish dismissing before switching RTL/LTR.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        widget.onLocaleChanged(Locale(value));
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: 'ar', checked: code == 'ar', child: const Text('العربية')),
        CheckedPopupMenuItem(value: 'ku', checked: code == 'ku', child: const Text('کوردی')),
        CheckedPopupMenuItem(value: 'en', checked: code == 'en', child: const Text('English')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final selectedActiveOrder = _selectedActiveOrder;
    if (selectedActiveOrder != null) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && mounted) setState(() => _selectedActiveOrder = null);
        },
        child: _DriverAssignedOrderScreen(
        order: selectedActiveOrder,
        onRefresh: () async {
          await _load();
          if (!mounted) return;
          final orderId = selectedActiveOrder['order_id']?.toString();
          final refreshed = _activeOrders.where(
            (item) => item['order_id']?.toString() == orderId,
          );
          setState(() {
            _selectedActiveOrder = refreshed.isEmpty ? null : refreshed.first;
          });
        },
        onBackToHome: () => setState(() => _selectedActiveOrder = null),
        ),
      );
    }
    if (_showAllActiveOrders) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && mounted) setState(() => _showAllActiveOrders = false);
        },
        child: _DriverActiveOrdersScreen(
          orders: _activeOrders,
          onBack: () => setState(() => _showAllActiveOrders = false),
          onOpenOrder: (order) => setState(() {
            _showAllActiveOrders = false;
            _selectedActiveOrder = order;
          }),
        ),
      );
    }
    if (_showEarnings) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && mounted) setState(() => _showEarnings = false);
        },
        child: _DriverEarningsWalletScreen(
          view: _driverFinanceView,
          onBack: () => setState(() => _showEarnings = false),
        ),
      );
    }
    if (_showHistory) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && mounted) setState(() => _showHistory = false);
        },
        child: _DriverDeliveryHistoryScreen(
          onBack: () => setState(() => _showHistory = false),
        ),
      );
    }
    if (_showNotifications) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && mounted) setState(() => _showNotifications = false);
        },
        child: _DriverNotificationsScreen(
        onBack: () => setState(() => _showNotifications = false),
        onChanged: _refreshDriverNotifications,
        onOpenOrder: _openOrClaimOrder,
        ),
      );
    }
    if (_showRatings) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && mounted) setState(() => _showRatings = false);
        },
        child: _DriverRatingsScreen(
          onBack: () => setState(() => _showRatings = false),
        ),
      );
    }
    if (_showAccountCenter) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && mounted) setState(() => _showAccountCenter = false);
        },
        child: _DriverAccountCenterScreen(
        currentLocale: widget.currentLocale,
        onLocaleChanged: widget.onLocaleChanged,
        profile: widget.profile,
        onBack: () => setState(() => _showAccountCenter = false),
        onLogout: widget.onLogout,
        ),
      );
    }
    final name = widget.profile?['full_name']?.toString().trim();
    final displayName = (name == null || name.isEmpty) ? s.t('driver') : name;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final tablet = constraints.maxWidth >= 600 && constraints.maxWidth < 900;
          final veryNarrow = constraints.maxWidth < 350;
          final maxWidth = wide ? 1180.0 : tablet ? 860.0 : 680.0;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: wide ? 28 : veryNarrow ? 10 : tablet ? 20 : 14, vertical: wide ? 22 : 12),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (veryNarrow)
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        IconButton(onPressed: () => setState(() => _showAccountCenter = true), icon: const Icon(Icons.menu_rounded), tooltip: s.t('more')),
                        Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(s.t('appTitle'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.orange)),
                          Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                        ])),
                        Stack(clipBehavior: Clip.none, children: [
                          IconButton(onPressed: () => setState(() => _showNotifications = true), icon: const Icon(Icons.notifications_none_rounded, size: 24)),
                          if (_driverUnreadNotifications > 0) Positioned(top: 3, right: 3, child: Container(constraints: const BoxConstraints(minWidth: 17, minHeight: 17), padding: const EdgeInsets.symmetric(horizontal: 3), alignment: Alignment.center, decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle), child: Text(_driverUnreadNotifications > 9 ? '9+' : '$_driverUnreadNotifications', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)))),
                        ]),
                      ]),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Flexible(child: _driverLanguageButton()),
                        IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout_rounded), tooltip: s.t('logout')),
                      ]),
                    ])
                  else
                    Row(children: [
                      IconButton(onPressed: () => setState(() => _showAccountCenter = true), icon: const Icon(Icons.menu_rounded), tooltip: s.t('more')),
                      const SizedBox(width: 4),
                      Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(s.t('appTitle'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.orange)),
                        Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                      ])),
                      const SizedBox(width: 4),
                      Stack(clipBehavior: Clip.none, children: [
                        IconButton(onPressed: () => setState(() => _showNotifications = true), icon: const Icon(Icons.notifications_none_rounded, size: 26)),
                        if (_driverUnreadNotifications > 0) Positioned(top: 3, right: 3, child: Container(constraints: const BoxConstraints(minWidth: 17, minHeight: 17), padding: const EdgeInsets.symmetric(horizontal: 3), alignment: Alignment.center, decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle), child: Text(_driverUnreadNotifications > 9 ? '9+' : '$_driverUnreadNotifications', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)))),
                      ]),
                      _driverLanguageButton(),
                      IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout_rounded), tooltip: s.t('logout')),
                    ]),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE3E5E9))),
                    child: Row(children: [
                      Container(width: 13, height: 13, decoration: BoxDecoration(shape: BoxShape.circle, color: _online ? const Color(0xFF20B44B) : const Color(0xFF8F949B))),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_online ? s.t('driverOnline') : s.t('driverOffline'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _online ? const Color(0xFF20A747) : const Color(0xFF555A62))),
                        const SizedBox(height: 2),
                        Text(_online ? s.t('driverOnlineSubtitle') : s.t('driverOfflineSubtitle'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ])),
                      Switch(value: _online, onChanged: _savingOnline ? null : _setOnline, activeTrackColor: const Color(0xFF20B44B), activeThumbColor: Colors.white),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  if (_activeOrders.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE3E5E9)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF0E6),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(Icons.delivery_dining_rounded, color: AppColors.orange),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${s.t('driverActiveOrders')} (${_activeOrders.length}/10)',
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      s.t('driverActiveOrdersSubtitle'),
                                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.25),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () => setState(() => _showAllActiveOrders = true),
                                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                                label: Text(s.t('driverViewAll')),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.orangeDark,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FB),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, size: 17, color: AppColors.muted),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    s.t('driverActiveOrdersHint'),
                                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._activeOrders.take(2).toList().asMap().entries.map((entry) {
                            final index = entry.key;
                            final order = entry.value;
                            final number = order['order_number']?.toString() ?? '—';
                            final store = order['store_name']?.toString().trim() ?? '';
                            final status = order['status']?.toString() ?? 'assigned';
                            final distance = order['distance_km'] ?? order['distance'];
                            final eta = order['eta_minutes'] ?? order['estimated_minutes'];
                            final statusLabel = switch (status) {
                              'assigned' => s.t('orderStatusAssigned'),
                              'picked_up' => s.t('orderStatusPickedUp'),
                              'ready' => s.t('orderStatusReady'),
                              _ => status,
                            };
                            final isCurrent = index == 0;
                            return Padding(
                              padding: const EdgeInsets.only(top: 9),
                              child: Material(
                                color: isCurrent ? const Color(0xFFFFF5EE) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => setState(() => _selectedActiveOrder = order),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: isCurrent ? const Color(0xFFFFCDA9) : const Color(0xFFE5E7EB)),
                                    ),
                                    child: Row(children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(color: isCurrent ? AppColors.orange : const Color(0xFFF3F4F6), shape: BoxShape.circle),
                                        child: Icon(Icons.delivery_dining_rounded, color: isCurrent ? Colors.white : AppColors.orange),
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Row(children: [
                                          Expanded(child: Text('#$number${store.isEmpty ? '' : ' • $store'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
                                          if (isCurrent) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFFFE3D0), borderRadius: BorderRadius.circular(20)), child: Text(s.t('driverCurrentOrder'), style: const TextStyle(color: AppColors.orangeDark, fontSize: 10, fontWeight: FontWeight.w900))),
                                        ]),
                                        const SizedBox(height: 5),
                                        Wrap(spacing: 10, runSpacing: 4, children: [
                                          _DriverOrderMeta(icon: Icons.flag_outlined, text: statusLabel),
                                          if (distance != null) _DriverOrderMeta(icon: Icons.route_outlined, text: '${distance.toString()} كم'),
                                          if (eta != null) _DriverOrderMeta(icon: Icons.schedule_outlined, text: '${eta.toString()} د'),
                                        ]),
                                      ])),
                                      const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (wide)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 6, child: _driverMapCard(s)),
                      const SizedBox(width: 16),
                      Expanded(flex: 5, child: Column(children: [_todayCard(s), const SizedBox(height: 16), _earnMoreCard(s)])),
                    ])
                  else ...[
                    _driverMapCard(s),
                    const SizedBox(height: 16),
                    _todayCard(s),
                    const SizedBox(height: 16),
                    _earnMoreCard(s),
                  ],
                  const SizedBox(height: 18),
                  Text(s.t('driverTools'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  LayoutBuilder(builder: (context, toolConstraints) {
                    final columns = toolConstraints.maxWidth < 380 ? 2 : 4;
                    final spacing = 10.0;
                    final width = (toolConstraints.maxWidth - spacing * (columns - 1)) / columns;
                    final tools = [
                      _tool(context, Icons.star_outline_rounded, s.t('driverRatingsTool'), onTap: () => setState(() => _showRatings = true)),
                      _tool(context, Icons.account_balance_wallet_outlined, s.t('driverWalletTool'), onTap: () => setState(() { _driverFinanceView = _DriverFinanceView.dues; _showEarnings = true; })),
                      _tool(context, Icons.receipt_long_outlined, s.t('driverHistoryTool'), onTap: () => setState(() => _showHistory = true)),
                      _tool(context, Icons.payments_outlined, s.t('driverEarningsTool'), onTap: () => setState(() { _driverFinanceView = _DriverFinanceView.payments; _showEarnings = true; })),
                    ];
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [for (final tool in tools) SizedBox(width: width, child: tool)],
                    );
                  }),
                  const SizedBox(height: 16),
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _openSupportInbox,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFFFFF5EE), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFFFE0C9))),
                      child: Row(children: [
                        const Icon(Icons.headset_mic_outlined, color: AppColors.orange, size: 30),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.t('driverNeedHelp'), style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(s.t('driverSupportAlways'), style: const TextStyle(color: AppColors.muted))])),
                        if (_driverUnreadSupport > 0)
                          Container(
                            margin: const EdgeInsetsDirectional.only(end: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(20)),
                            child: Text(_driverUnreadSupport > 99 ? '99+' : '$_driverUnreadSupport', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                          ),
                        const Icon(Icons.chevron_right_rounded),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  double? _driverCoordinate(Map<String, dynamic>? order, List<String> keys) {
    if (order == null) return null;
    for (final key in keys) {
      final raw = order[key];
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }


  Future<void> _showHomeActiveOrderPreview() async {
    if (_openingHomeMaps || _activeOrders.isEmpty) return;
    final order = _activeOrders.first;
    final pickedUp = order['status']?.toString() == 'picked_up';
    final lat = _driverCoordinate(
      order,
      pickedUp
          ? const ['delivery_latitude', 'customer_latitude', 'latitude']
          : const ['store_latitude', 'restaurant_latitude', 'latitude'],
    );
    final lng = _driverCoordinate(
      order,
      pickedUp
          ? const ['delivery_longitude', 'customer_longitude', 'longitude']
          : const ['store_longitude', 'restaurant_longitude', 'longitude'],
    );
    final address = (order[pickedUp ? 'delivery_address' : 'store_address']?.toString() ?? '').trim();
    if ((lat == null || lng == null) && address.isEmpty) return;

    final s = AppStrings.of(context);
    setState(() => _openingHomeMaps = true);
    final opened = lat != null && lng != null
        ? await MapsService.instance.openWazeNavigationCoordinates(
            latitude: lat,
            longitude: lng,
          )
        : await MapsService.instance.openWazeNavigationAddress(address);
    if (!mounted) return;
    setState(() => _openingHomeMaps = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.t('driverCouldNotOpenWaze'))),
      );
    }
  }

  Widget _driverMapCard(AppStrings s) {
    final veryNarrow = MediaQuery.sizeOf(context).width < 350;
    final order = _activeOrders.isEmpty ? null : _activeOrders.first;
    final pickedUp = order?['status']?.toString() == 'picked_up';
    final lat = _driverCoordinate(
      order,
      pickedUp
          ? const ['delivery_latitude', 'customer_latitude', 'latitude']
          : const ['store_latitude', 'restaurant_latitude', 'latitude'],
    );
    final lng = _driverCoordinate(
      order,
      pickedUp
          ? const ['delivery_longitude', 'customer_longitude', 'longitude']
          : const ['store_longitude', 'restaurant_longitude', 'longitude'],
    );

    final address = order == null
        ? ''
        : (order[pickedUp ? 'delivery_address' : 'store_address']?.toString() ?? '').trim();
    final canNavigate = order != null && ((lat != null && lng != null) || address.isNotEmpty);

    return Container(
      height: 300,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFECEFF1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0E2E5)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MapboxDriverTripPreview(
            driverLatitude: order == null ? null : _driverLatitude,
            driverLongitude: order == null ? null : _driverLongitude,
            storeLatitude: pickedUp ? null : _driverCoordinate(order, const ['store_latitude', 'restaurant_latitude']),
            storeLongitude: pickedUp ? null : _driverCoordinate(order, const ['store_longitude', 'restaurant_longitude']),
            customerLatitude: pickedUp ? _driverCoordinate(order, const ['delivery_latitude', 'customer_latitude']) : null,
            customerLongitude: pickedUp ? _driverCoordinate(order, const ['delivery_longitude', 'customer_longitude']) : null,
            height: 300,
            emptyText: _activeOrders.isEmpty ? s.t('driverNoActiveMapOrder') : s.t('driverMapWaitingCoordinates'),
            missingTokenText: s.t('driverMapboxMissingToken'),
          ),
          if (canNavigate)
            Positioned(
              right: 14,
              bottom: 14,
              child: veryNarrow
                  ? ElevatedButton(
                      onPressed: _showHomeActiveOrderPreview,
                      style: ElevatedButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(14), backgroundColor: AppColors.orange, foregroundColor: Colors.white),
                      child: const Icon(Icons.map_outlined),
                    )
                  : ElevatedButton.icon(
                onPressed: _showHomeActiveOrderPreview,
                icon: const Icon(Icons.map_outlined),
                label: Text(pickedUp ? s.t('driverPreviewCustomerLocation') : s.t('driverPreviewStoreLocation')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _todayCard(AppStrings s) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8EAF0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Text(s.t('driverTodayStats'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const Spacer(), Text(s.t('driverViewDetails'), style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w800))]),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth < 420 ? 2 : 4;
            final gap = 8.0;
            final itemWidth = (c.maxWidth - gap * (cols - 1)) / cols;
            final cards = [
              _metricBox(Icons.shopping_bag_outlined, (_earningsSummary?['today_orders'] ?? 0).toString(), s.t('driverOrdersToday'), AppColors.orange),
              _metricBox(Icons.payments_outlined, (_earningsSummary?['today_earnings'] ?? 0).toString(), s.t('driverTodayEarnings'), const Color(0xFF22A447)),
              _metricBox(Icons.star_rounded, (_earningsSummary?['rating'] ?? '—').toString(), s.t('driverRating'), const Color(0xFFF6B318)),
              _metricBox(Icons.schedule_rounded, (_earningsSummary?['today_work_minutes'] ?? 0).toString(), s.t('driverWorkTime'), const Color(0xFF2878E8)),
            ];
            return Wrap(spacing: gap, runSpacing: gap, children: [for (final card in cards) SizedBox(width: itemWidth, child: card)]);
          }),
        ]),
      );

  Widget _metricBox(IconData icon, String value, String label, Color color) {
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFFCFCFD), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE8EAF0))),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 7),
        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
        const SizedBox(height: 4),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w700)),
      ]),
    );
  }


  Widget _earnMoreCard(AppStrings s) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: const Color(0xFFFFF4EC), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFFFDFC8))),
        child: Row(children: [
          const Icon(Icons.trending_up_rounded, color: AppColors.orange, size: 42),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.t('driverEarnMore'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text(s.t('driverEarnMoreSubtitle'), style: const TextStyle(color: AppColors.muted, height: 1.35))])),
        ]),
      );
}


class _DriverActiveOrdersScreen extends StatelessWidget {
  const _DriverActiveOrdersScreen({
    required this.orders,
    required this.onBack,
    required this.onOpenOrder,
  });

  final List<Map<String, dynamic>> orders;
  final VoidCallback onBack;
  final ValueChanged<Map<String, dynamic>> onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
        title: Text(s.t('driverActiveOrdersPageTitle'), style: const TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, c) {
            final horizontal = c.maxWidth < 380 ? 12.0 : 18.0;
            return RefreshIndicator(
              onRefresh: () async {},
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE3E5E9)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0E6),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(Icons.delivery_dining_rounded, color: AppColors.orange, size: 27),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${orders.length}/10', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 2),
                              Text(s.t('driverActiveOrders'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFFEAF8EF), borderRadius: BorderRadius.circular(999)),
                          child: Text(s.t('driverOnline'), style: const TextStyle(color: Color(0xFF1D8F45), fontWeight: FontWeight.w900, fontSize: 11.5)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (orders.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 44),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE3E5E9))),
                      child: Column(
                        children: [
                          const Icon(Icons.inbox_outlined, size: 42, color: AppColors.muted),
                          const SizedBox(height: 10),
                          Text(s.t('driverNoActiveMapOrder'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    )
                  else
                    ...orders.asMap().entries.map((entry) {
                      final index = entry.key;
                      final order = entry.value;
                      final number = order['order_number']?.toString() ?? '—';
                      final store = order['store_name']?.toString().trim() ?? '';
                      final status = order['status']?.toString() ?? 'assigned';
                      final distance = order['distance_km'] ?? order['distance'];
                      final eta = order['eta_minutes'] ?? order['estimated_minutes'];
                      final statusLabel = switch (status) {
                        'assigned' => s.t('orderStatusAssigned'),
                        'picked_up' => s.t('orderStatusPickedUp'),
                        'ready' => s.t('orderStatusReady'),
                        _ => status,
                      };
                      final isCurrent = index == 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: isCurrent ? const Color(0xFFFFF5EE) : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            onTap: () => onOpenOrder(order),
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: isCurrent ? const Color(0xFFFFCDA9) : const Color(0xFFE3E5E9)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(color: isCurrent ? AppColors.orange : const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(14)),
                                    child: Icon(Icons.delivery_dining_rounded, color: isCurrent ? Colors.white : AppColors.orange),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(child: Text('#$number${store.isEmpty ? '' : ' • $store'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900))),
                                            if (isCurrent)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(color: const Color(0xFFFFE3D0), borderRadius: BorderRadius.circular(999)),
                                                child: Text(s.t('driverCurrentOrder'), style: const TextStyle(color: AppColors.orangeDark, fontSize: 10.5, fontWeight: FontWeight.w900)),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 7),
                                        Wrap(
                                          spacing: 11,
                                          runSpacing: 6,
                                          children: [
                                            _DriverOrderMeta(icon: Icons.flag_outlined, text: statusLabel),
                                            if (distance != null) _DriverOrderMeta(icon: Icons.route_outlined, text: '${distance.toString()} كم'),
                                            if (eta != null) _DriverOrderMeta(icon: Icons.schedule_outlined, text: '${eta.toString()} د'),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Padding(padding: EdgeInsets.only(top: 11), child: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}


class _DriverOrderMeta extends StatelessWidget {
  const _DriverOrderMeta({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: AppColors.muted), const SizedBox(width: 4), Text(text, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w700))]);
}
