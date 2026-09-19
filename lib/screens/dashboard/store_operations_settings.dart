part of 'partner_dashboard.dart';

class _StoreOperationsSettingsPage extends StatefulWidget {
  const _StoreOperationsSettingsPage({
    required this.store,
    required this.onSaved,
    this.initialSection = 0,
  });

  final Map<String, dynamic>? store;
  final ValueChanged<Map<String, dynamic>> onSaved;
  final int initialSection;

  @override
  State<_StoreOperationsSettingsPage> createState() => _StoreOperationsSettingsPageState();
}

class _StoreOperationsSettingsPageState extends State<_StoreOperationsSettingsPage> {
  late int _section;
  bool _saving = false;
  bool _loadingLatest = false;
  bool _locating = false;
  bool _isOpen = false;
  bool _deliveryAvailable = true;
  bool _pickupAvailable = true;
  int _shiftMode = 1;
  String _morningStart = '08:00';
  String _morningEnd = '15:00';
  String _eveningStart = '15:00';
  String _eveningEnd = '23:00';

  late final TextEditingController _address;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late final TextEditingController _locationNote;
  late final TextEditingController _deliveryFee;
  late final TextEditingController _minimumOrder;
  late final TextEditingController _preparationMinutes;
  late final TextEditingController _deliveryZones;
  late final FocusNode _deliveryFeeFocus;
  late final FocusNode _minimumOrderFocus;
  late final FocusNode _preparationMinutesFocus;

  final Map<String, _WorkingDayValue> _days = {};
  final Map<String, _WorkingDayValue> _morningDays = {};
  final Map<String, _WorkingDayValue> _eveningDays = {};
  static const _dayKeys = ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday'];

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection < 0 ? 0 : widget.initialSection > 2 ? 2 : widget.initialSection;
    final store = widget.store ?? const <String, dynamic>{};
    String text(String key, [String fallback = '']) => (store[key] ?? fallback).toString();
    _address = TextEditingController(text: text('address_text'));
    _latitude = TextEditingController(text: store['latitude']?.toString() ?? '');
    _longitude = TextEditingController(text: store['longitude']?.toString() ?? '');
    _locationNote = TextEditingController(text: text('location_note'));
    _deliveryFee = TextEditingController(text: text('delivery_fee', '0'));
    _minimumOrder = TextEditingController(text: text('minimum_order', '0'));
    _preparationMinutes = TextEditingController(text: text('preparation_minutes', '30'));
    final zones = store['delivery_zones'];
    _deliveryZones = TextEditingController(text: zones is List ? zones.map((e) => e.toString()).join('\n') : '');
    _deliveryFeeFocus = FocusNode();
    _minimumOrderFocus = FocusNode();
    _preparationMinutesFocus = FocusNode();
    _installSelectAllOnFocus(_deliveryFeeFocus, _deliveryFee);
    _installSelectAllOnFocus(_minimumOrderFocus, _minimumOrder);
    _installSelectAllOnFocus(_preparationMinutesFocus, _preparationMinutes);
    _deliveryAvailable = store['delivery_available'] != false;
    _pickupAvailable = store['pickup_available'] != false;
    _isOpen = store['is_open'] == true;
    _shiftMode = (store['shift_mode'] as num?)?.toInt() == 2 ? 2 : 1;

    final rawHours = store['working_hours'];
    final hours = rawHours is Map ? Map<String, dynamic>.from(rawHours) : const <String, dynamic>{};
    for (final key in _dayKeys) {
      final raw = hours[key];
      final data = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
      _days[key] = _WorkingDayValue(
        enabled: data['enabled'] != false,
        open: (data['open'] ?? store['opening_time'] ?? '09:00').toString(),
        close: (data['close'] ?? store['closing_time'] ?? '23:00').toString(),
      );
    }
    for (final key in _dayKeys) {
      final enabled = _days[key]!.enabled;
      _morningDays[key] = _WorkingDayValue(enabled: enabled, open: _morningStart, close: _morningEnd);
      _eveningDays[key] = _WorkingDayValue(enabled: enabled, open: _eveningStart, close: _eveningEnd);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadLatest());
  }

  Future<void> _reloadLatest() async {
    if (_loadingLatest) return;
    setState(() => _loadingLatest = true);
    try {
      final latest = await StoreOperationsRepository.instance.getCurrentStore();
      if (!mounted || latest == null) return;
      _applyStore(latest);
      final shifts = await StoreOperationsRepository.instance.getStoreShifts();
      if (!mounted) return;
      _applyShifts(shifts);
      widget.onSaved(latest);
    } catch (_) {
      // Keep the already supplied store snapshot when the refresh is unavailable.
    } finally {
      if (mounted) setState(() => _loadingLatest = false);
    }
  }

  void _applyStore(Map<String, dynamic> store) {
    String text(String key, [String fallback = '']) => (store[key] ?? fallback).toString();
    _address.text = text('address_text');
    _latitude.text = store['latitude']?.toString() ?? '';
    _longitude.text = store['longitude']?.toString() ?? '';
    _locationNote.text = text('location_note');
    _deliveryFee.text = text('delivery_fee', '0');
    _minimumOrder.text = text('minimum_order', '0');
    _preparationMinutes.text = text('preparation_minutes', '30');
    final zones = store['delivery_zones'];
    _deliveryZones.text = zones is List ? zones.map((e) => e.toString()).join('\n') : '';
    _deliveryAvailable = store['delivery_available'] != false;
    _pickupAvailable = store['pickup_available'] != false;
    _isOpen = store['is_open'] == true;
    _shiftMode = (store['shift_mode'] as num?)?.toInt() == 2 ? 2 : 1;
    final rawHours = store['working_hours'];
    final hours = rawHours is Map ? Map<String, dynamic>.from(rawHours) : const <String, dynamic>{};
    for (final key in _dayKeys) {
      final raw = hours[key];
      final data = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
      final day = _days[key]!;
      day.enabled = data['enabled'] != false;
      day.open = (data['open'] ?? store['opening_time'] ?? '09:00').toString();
      day.close = (data['close'] ?? store['closing_time'] ?? '23:00').toString();
    }
    setState(() {});
  }

  void _applyShifts(List<Map<String, dynamic>> shifts) {
    for (final shift in shifts) {
      final code = shift['shift_code']?.toString();
      final start = _normalizeDbTime(shift['start_time']?.toString(), code == 'morning' ? '08:00' : '15:00');
      final end = _normalizeDbTime(shift['end_time']?.toString(), code == 'morning' ? '15:00' : '23:00');
      final rawWeekly = shift['weekly_hours'];
      final weekly = rawWeekly is Map ? Map<String, dynamic>.from(rawWeekly) : const <String, dynamic>{};
      if (code == 'morning') {
        _morningStart = start;
        _morningEnd = end;
        _applyShiftWeeklyHours(_morningDays, weekly, start, end);
      } else if (code == 'evening') {
        _eveningStart = start;
        _eveningEnd = end;
        _applyShiftWeeklyHours(_eveningDays, weekly, start, end);
      }
    }
    setState(() {});
  }

  void _applyShiftWeeklyHours(
    Map<String, _WorkingDayValue> target,
    Map<String, dynamic> weekly,
    String fallbackOpen,
    String fallbackClose,
  ) {
    for (final key in _dayKeys) {
      final raw = weekly[key];
      final data = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
      final fallbackEnabled = _days[key]?.enabled ?? true;
      final day = target[key] ?? _WorkingDayValue(enabled: fallbackEnabled, open: fallbackOpen, close: fallbackClose);
      day.enabled = data.isEmpty ? fallbackEnabled : data['enabled'] != false;
      day.open = _normalizeDbTime(data['open']?.toString(), fallbackOpen);
      day.close = _normalizeDbTime(data['close']?.toString(), fallbackClose);
      target[key] = day;
    }
  }

  Map<String, dynamic> _weeklyJson(Map<String, _WorkingDayValue> source) => <String, dynamic>{
        for (final key in _dayKeys)
          key: {
            'enabled': source[key]!.enabled,
            'open': source[key]!.open,
            'close': source[key]!.close,
          },
      };

  List<int> _minutesSegments(String open, String close) {
    int minute(String value) {
      final p = value.split(':');
      return (int.parse(p[0]) * 60) + int.parse(p[1]);
    }
    final a = minute(open);
    final b = minute(close);
    if (a < b) return [a, b];
    return [a, 1440, 0, b];
  }

  bool _intervalsOverlap(_WorkingDayValue a, _WorkingDayValue b) {
    if (!a.enabled || !b.enabled) return false;
    final sa = _minutesSegments(a.open, a.close);
    final sb = _minutesSegments(b.open, b.close);
    final ar = <List<int>>[];
    final br = <List<int>>[];
    for (var i = 0; i < sa.length; i += 2) {
      ar.add([sa[i], sa[i + 1]]);
    }
    for (var i = 0; i < sb.length; i += 2) {
      br.add([sb[i], sb[i + 1]]);
    }
    for (final x in ar) {
      for (final y in br) {
        if (x[0] < y[1] && y[0] < x[1]) return true;
      }
    }
    return false;
  }

  _WorkingDayValue? _firstEnabled(Map<String, _WorkingDayValue> source) {
    for (final key in _dayKeys) {
      final day = source[key];
      if (day != null && day.enabled) return day;
    }
    return null;
  }

  String _normalizeDbTime(String? value, String fallback) {
    final v = (value ?? '').trim();
    if (v.length >= 5 && _validTime(v.substring(0, 5))) return v.substring(0, 5);
    return fallback;
  }

  String _display12h(String value) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final pm = hour >= 12;
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = _tx(pm ? 'مساءً' : 'صباحًا', pm ? 'PM' : 'AM', pm ? 'PM' : 'AM');
    return '${h.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $suffix';
  }

  bool _validTime(String value) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

  void _installSelectAllOnFocus(FocusNode node, TextEditingController controller) {
    node.addListener(() {
      if (!node.hasFocus || controller.text.isEmpty) return;
      controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    });
  }

  @override
  void dispose() {
    for (final controller in [_address, _latitude, _longitude, _locationNote, _deliveryFee, _minimumOrder, _preparationMinutes, _deliveryZones]) {
      controller.dispose();
    }
    _deliveryFeeFocus.dispose();
    _minimumOrderFocus.dispose();
    _preparationMinutesFocus.dispose();
    super.dispose();
  }

  String _tx(String ar, String ku, String en) {
    final code = AppStrings.of(context).languageCode;
    if (code == 'ku') return ku;
    if (code == 'en') return en;
    return ar;
  }

  String _dayName(String key) {
    const ar = {
      'saturday': 'السبت', 'sunday': 'الأحد', 'monday': 'الاثنين', 'tuesday': 'الثلاثاء',
      'wednesday': 'الأربعاء', 'thursday': 'الخميس', 'friday': 'الجمعة',
    };
    const ku = {
      'saturday': 'شەممە', 'sunday': 'یەکشەممە', 'monday': 'دووشەممە', 'tuesday': 'سێشەممە',
      'wednesday': 'چوارشەممە', 'thursday': 'پێنجشەممە', 'friday': 'هەینی',
    };
    const en = {
      'saturday': 'Saturday', 'sunday': 'Sunday', 'monday': 'Monday', 'tuesday': 'Tuesday',
      'wednesday': 'Wednesday', 'thursday': 'Thursday', 'friday': 'Friday',
    };
    final code = AppStrings.of(context).languageCode;
    return code == 'ku' ? ku[key]! : code == 'en' ? en[key]! : ar[key]!;
  }

  double? _number(String value) => double.tryParse(value.trim().replaceAll(',', '.'));

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
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
        SnackBar(
          content: Text(_tx(
            'تعذر تحديد موقع المتجر. تأكد من تشغيل الموقع ومنح الإذن للتطبيق.',
            'نەتوانرا شوێنی فرۆشگا دیاری بکرێت. شوێن و مۆڵەتەکان بپشکنە.',
            'Could not detect the store location. Enable location services and grant permission.',
          )),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _openRestaurantInMaps() async {
    final lat = _number(_latitude.text);
    final lng = _number(_longitude.text);
    final address = _address.text.trim();
    bool opened = false;
    if (lat != null && lng != null) {
      opened = await MapsService.instance.openCoordinates(
        latitude: lat,
        longitude: lng,
        label: address.isEmpty ? _tx('المتجر', 'فرۆشگا', 'Store') : address,
      );
    } else if (address.isNotEmpty) {
      opened = await MapsService.instance.openAddress(address);
    }
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tx(
              'أدخل العنوان أو الإحداثيات أولًا، أو تأكد من وجود تطبيق خرائط.',
              'سەرەتا ناونیشان یان کۆئۆردینات بنووسە، یان دڵنیابە لە بوونی نەخشە.',
              'Enter an address or coordinates first, or make sure a maps app is available.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_deliveryAvailable && !_pickupAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tx('فعّل التوصيل أو الاستلام على الأقل.', 'لانیکەم گەیاندن یان وەرگرتن چالاک بکە.', 'Enable delivery or pickup at minimum.'))));
      return;
    }
    if (_address.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tx('أدخل عنوان المتجر.', 'ناونیشانی فرۆشگا بنووسە.', 'Enter the store address.'))));
      return;
    }
    final lat = _latitude.text.trim().isEmpty ? null : _number(_latitude.text);
    final lng = _longitude.text.trim().isEmpty ? null : _number(_longitude.text);
    if ((_latitude.text.trim().isNotEmpty && lat == null) || (_longitude.text.trim().isNotEmpty && lng == null) || (lat != null && (lat < -90 || lat > 90)) || (lng != null && (lng < -180 || lng > 180))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tx('تأكد من إحداثيات الموقع.', 'دڵنیابە لە کۆئۆردیناتی شوێن.', 'Check the location coordinates.'))));
      return;
    }
    if (_deliveryAvailable && (lat == null || lng == null)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tx(
        'حدد موقع المتجر قبل حفظ التوصيل حتى يتمكن السائق من الوصول إليه.',
        'پێش پاشەکەوتکردنی گەیاندن شوێنی فرۆشگا دیاری بکە.',
        'Set the store location before enabling delivery so drivers can navigate to it.',
      ))));
      return;
    }
    final deliveryFee = _number(_deliveryFee.text) ?? -1;
    final minimumOrder = _number(_minimumOrder.text) ?? -1;
    final preparationMinutes = int.tryParse(_preparationMinutes.text.trim()) ?? -1;
    if (deliveryFee < 0 || minimumOrder < 0 || preparationMinutes < 1 || preparationMinutes > 240) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tx('تحقق من الرسوم والحد الأدنى ومدة التجهيز (1–240 دقيقة).', 'کرێ و کەمترین داواکاری و کاتی ئامادەکردن بپشکنە.', 'Check fees, minimum order and preparation time (1–240 min).'))));
      return;
    }
    final schedulesToValidate = _shiftMode == 2 ? <Map<String, _WorkingDayValue>>[_morningDays, _eveningDays] : <Map<String, _WorkingDayValue>>[_days];
    for (final schedule in schedulesToValidate) {
      for (final day in schedule.values) {
        if (day.enabled && (!_validTime(day.open) || !_validTime(day.close) || day.open == day.close)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tx('تحقق من أوقات الدوام؛ وقت الفتح والإغلاق يجب أن يكونا صالحين ومختلفين.', 'کاتەکانی کار بپشکنە.', 'Check working hours; open and close times must be valid and different.'))));
          return;
        }
      }
    }
    if (_shiftMode == 2) {
      for (final key in _dayKeys) {
        if (_intervalsOverlap(_morningDays[key]!, _eveningDays[key]!)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tx('يوجد تداخل بين الشفت الصباحي والمسائي في ${_dayName(key)}. عدّل الأوقات قبل الحفظ.', 'کاتەکانی دوو شیفتەکە یەکتریان دەگرن.', 'Morning and evening shifts overlap on ${_dayName(key)}. Adjust the times before saving.'))));
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      final workingHours = _shiftMode == 1
          ? _weeklyJson(_days)
          : <String, dynamic>{
              for (final key in _dayKeys)
                key: {
                  'enabled': _morningDays[key]!.enabled || _eveningDays[key]!.enabled,
                  'open': _morningDays[key]!.enabled ? _morningDays[key]!.open : _eveningDays[key]!.open,
                  'close': _eveningDays[key]!.enabled ? _eveningDays[key]!.close : _morningDays[key]!.close,
                },
            };
      final zones = _deliveryZones.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      final updated = await StoreOperationsRepository.instance.saveOperations(
        address: _address.text,
        latitude: lat,
        longitude: lng,
        locationNote: _locationNote.text,
        deliveryAvailable: _deliveryAvailable,
        pickupAvailable: _pickupAvailable,
        deliveryFee: deliveryFee,
        minimumOrder: minimumOrder,
        preparationMinutes: preparationMinutes,
        deliveryZones: zones,
        workingHours: workingHours,
        isOpen: _isOpen,
      );
      final morningDefault = _firstEnabled(_morningDays);
      final eveningDefault = _firstEnabled(_eveningDays);
      await StoreOperationsRepository.instance.saveShiftConfiguration(
        shiftMode: _shiftMode,
        morningStart: morningDefault?.open ?? _morningStart,
        morningEnd: morningDefault?.close ?? _morningEnd,
        eveningStart: eveningDefault?.open ?? _eveningStart,
        eveningEnd: eveningDefault?.close ?? _eveningEnd,
        morningWeeklyHours: _weeklyJson(_morningDays),
        eveningWeeklyHours: _weeklyJson(_eveningDays),
      );
      updated['shift_mode'] = _shiftMode;
      if (!mounted) return;
      widget.onSaved(updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tx('تم حفظ إعدادات تشغيل المتجر.', 'ڕێکخستنەکانی کارکردنی فرۆشگا پاشەکەوت کرا.', 'Store operation settings saved.'))));
    } on PostgrestException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text(
          _tx('إعدادات المتجر', 'ڕێکخستنەکانی فرۆشگا', 'Store settings'),
          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF172033)),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF172033),
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          IconButton(
            tooltip: _tx('تحديث', 'نوێکردنەوە', 'Refresh'),
            onPressed: _loadingLatest ? null : _reloadLatest,
            icon: _loadingLatest
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                primary: true,
                padding: EdgeInsets.fromLTRB(compact ? 14 : 28, 18, compact ? 14 : 28, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHero(compact),
                        const SizedBox(height: 18),
                        _buildSectionTabs(compact),
                        const SizedBox(height: 18),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: KeyedSubtree(
                            key: ValueKey(_section),
                            child: _section == 0
                                ? _locationSection()
                                : _section == 1
                                    ? _deliverySection(compact)
                                    : _hoursSection(compact),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(compact ? 14 : 28, 10, compact ? 14 : 28, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE8EAF0))),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _tx('حفظ الإعدادات', 'پاشەکەوتکردنی ڕێکخستنەکان', 'Save settings'),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(bool compact) {
    final closedDays = _days.values.where((d) => !d.enabled).length;
    return Container(
      padding: EdgeInsets.all(compact ? 18 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFF7A18), Color(0xFFFF9A3D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x28FF7A18), blurRadius: 30, offset: Offset(0, 14))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 54, height: 54, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 30)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_tx('تشغيل المتجر', 'بەڕێوەبردنی فرۆشگا', 'Store operations'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(_tx('الموقع، التوصيل والاستلام، وأوقات الدوام من مكان واحد.', 'شوێن، گەیاندن و وەرگرتن، و کاتەکانی کار لە یەک شوێن.', 'Location, delivery, pickup and hours in one place.'), style: const TextStyle(color: Colors.white, height: 1.35)),
          ])),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _heroPill(_isOpen ? _tx('يستقبل الطلبات', 'داواکاری وەردەگرێت', 'Accepting orders') : _tx('مغلق مؤقتًا', 'کاتی داخراوە', 'Temporarily closed'), _isOpen ? Icons.check_circle_rounded : Icons.pause_circle_rounded),
          _heroPill(_deliveryAvailable ? _tx('توصيل مفعّل', 'گەیاندن چالاکە', 'Delivery on') : _tx('التوصيل متوقف', 'گەیاندن وەستاوە', 'Delivery off'), Icons.delivery_dining_rounded),
          _heroPill('$closedDays ${_tx('أيام عطلة', 'ڕۆژی پشوو', 'days off')}', Icons.event_busy_rounded),
        ]),
      ]),
    );
  }

  Widget _heroPill(String text, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white.withValues(alpha: .18))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 17, color: Colors.white), const SizedBox(width: 7), Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12))]),
  );

  Widget _buildSectionTabs(bool compact) {
    final items = [
      (Icons.location_on_rounded, _tx('موقع المتجر', 'شوێنی فرۆشگا', 'Location')),
      (Icons.delivery_dining_rounded, _tx('التوصيل والاستلام', 'گەیاندن و وەرگرتن', 'Delivery & pickup')),
      (Icons.schedule_rounded, _tx('أوقات الدوام', 'کاتەکانی کار', 'Working hours')),
    ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8EAF0))),
      child: Row(children: List.generate(items.length, (index) {
        final selected = _section == index;
        return Expanded(child: InkWell(
          onTap: () => setState(() => _section = index),
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 12 : 14),
            decoration: BoxDecoration(color: selected ? AppColors.orange : Colors.transparent, borderRadius: BorderRadius.circular(15)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(items[index].$1, size: 20, color: selected ? Colors.white : AppColors.muted),
              if (!compact) ...[const SizedBox(width: 7), Flexible(child: Text(items[index].$2, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? Colors.white : const Color(0xFF172033), fontWeight: FontWeight.w900)))],
            ]),
          ),
        ));
      })),
    );
  }

  Widget _card({required String title, required String subtitle, required IconData icon, required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE8EAF0))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: .09), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: AppColors.orange)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF172033))), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35))])),
      ]),
      const SizedBox(height: 20),
      child,
    ]),
  );

  Widget _locationSection() => _card(
    title: _tx('موقع المتجر', 'شوێنی فرۆشگا', 'Store location'),
    subtitle: _tx('هذه البيانات ستُستخدم لاحقًا لحساب المسافة والتوصيل بدقة.', 'ئەم زانیاریانە بۆ دووری و گەیاندن بەکاردێن.', 'These details will be used for distance and delivery calculations.'),
    icon: Icons.location_on_rounded,
    child: Column(children: [
      TextField(controller: _address, decoration: InputDecoration(labelText: _tx('العنوان الكامل', 'ناونیشانی تەواو', 'Full address'), hintText: _tx('المنطقة، الشارع، أقرب نقطة دالة', 'ناوچە، شەقام، نزیکترین نیشانە', 'Area, street, nearest landmark'), prefixIcon: const Icon(Icons.home_work_outlined))),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, constraints) {
        final vertical = constraints.maxWidth < 560;
        final fields = [
          Expanded(child: TextField(controller: _latitude, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: _tx('خط العرض', 'پانی', 'Latitude'), hintText: '36.27', prefixIcon: const Icon(Icons.my_location_rounded)))),
          Expanded(child: TextField(controller: _longitude, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: _tx('خط الطول', 'درێژی', 'Longitude'), hintText: '43.38', prefixIcon: const Icon(Icons.explore_outlined)))),
        ];
        return vertical ? Column(children: [SizedBox(width: double.infinity, child: fields[0].child), const SizedBox(height: 12), SizedBox(width: double.infinity, child: fields[1].child)]) : Row(children: [fields[0], const SizedBox(width: 12), fields[1]]);
      }),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _locating ? null : _useCurrentLocation,
          icon: _locating
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location_rounded),
          label: Text(_tx('استخدام موقعي الحالي', 'بەکارهێنانی شوێنی ئێستام', 'Use my current location')),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.orange,
            side: const BorderSide(color: Color(0xFFFFC58F)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      const SizedBox(height: 14),
      TextField(controller: _locationNote, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: _tx('ملاحظة للوصول', 'تێبینی بۆ گەیشتن', 'Location note'), hintText: _tx('مثال: مقابل الكنيسة، مدخل جانبي...', 'نموونە: بەرامبەر کڵێسا...', 'Example: opposite the church, side entrance...'), prefixIcon: const Icon(Icons.notes_rounded), alignLabelWithHint: true)),
      const SizedBox(height: 12),
      MapboxLocationPreview(
        latitude: _number(_latitude.text),
        longitude: _number(_longitude.text),
        emptyText: _tx(
          'أدخل إحداثيات صحيحة ليظهر موقع المتجر على Mapbox في Android وiOS. على Windows يبقى زر فتح الخرائط الخارجية متاحًا.',
          'کۆئۆردیناتی دروست بنووسە بۆ ئەوەی شوێنی فرۆشگا لە Mapbox لە Android وiOS پیشان بدرێت. لە Windows کردنەوەی نەخشەی دەرەکی بەردەستە.',
          'Enter valid coordinates to preview the store on Mapbox on Android/iOS. Windows keeps the external maps button.',
        ),
        unsupportedText: _tx(
          'خريطة Mapbox المدمجة تعمل على Android وiOS. على Windows يبقى زر فتح الخرائط الخارجية متاحًا.',
          'نەخشەی ناوخۆی Mapbox لە Android و iOS کاردەکات. لە Windows دوگمەی نەخشەی دەرەکی بەردەستە.',
          'Embedded Mapbox works on Android and iOS. Windows keeps the external maps button.',
        ),
        missingTokenText: _tx(
          'الخريطة داخل التطبيق غير متاحة حاليًا. يبقى زر فتح الخرائط متاحًا.',
          'نەخشەی ناوخۆی ئەپ ئێستا بەردەست نییە. دوگمەی کردنەوەی نەخشە بەردەستە.',
          'The in-app map is not available right now. The Open Maps button remains available.',
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(
          onPressed: _openRestaurantInMaps,
          icon: const Icon(Icons.map_rounded),
          label: Text(_tx('فتح موقع المتجر في الخرائط', 'شوێنی فرۆشگا لە نەخشە بکەرەوە', 'Open store in maps')),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.orange,
            side: const BorderSide(color: Color(0xFFFFC58F)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.navigation_rounded, color: AppColors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _tx(
                'إذا أدخلت الإحداثيات سيفتح الموقع بدقة. وإذا لم تدخلها فسيتم البحث عن العنوان في الخرائط.',
                'ئەگەر کۆئۆردینات بنووسیت شوێنەکە بە وردی دەکرێتەوە، ئەگەر نا بە ناونیشان دەگەڕێت.',
                'Coordinates open the exact location; otherwise Maps searches using the address.',
              ),
              style: const TextStyle(fontSize: 12, color: Color(0xFF7C4A12), height: 1.4),
            ),
          ),
        ]),
      ),
    ]),
  );

  Widget _deliverySection(bool compact) {
    Widget numericField({
      required TextEditingController controller,
      required FocusNode focusNode,
      required String label,
      required String suffix,
      required IconData icon,
      required bool enabled,
      required bool integerOnly,
    }) => TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: integerOnly
          ? TextInputType.number
          : const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: integerOnly
          ? [FilteringTextInputFormatter.digitsOnly]
          : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        prefixIcon: Icon(icon),
        helperText: _tx(
          'عند الضغط يتم تحديد القيمة كاملة لتكتب الرقم مباشرة.',
          'کاتێک دەیکەیتەوە هەموو ژمارەکە هەڵدەبژێردرێت.',
          'Tap once to select the whole value and type a replacement.',
        ),
        helperMaxLines: 2,
      ),
    );

    final feeField = numericField(
      controller: _deliveryFee,
      focusNode: _deliveryFeeFocus,
      label: _tx('رسوم التوصيل', 'کرێی گەیاندن', 'Delivery fee'),
      suffix: _tx('د.ع', 'د.ع', 'IQD'),
      icon: Icons.payments_outlined,
      enabled: _deliveryAvailable,
      integerOnly: false,
    );
    final minimumField = numericField(
      controller: _minimumOrder,
      focusNode: _minimumOrderFocus,
      label: _tx('الحد الأدنى للطلب', 'کەمترین داواکاری', 'Minimum order'),
      suffix: _tx('د.ع', 'د.ع', 'IQD'),
      icon: Icons.shopping_cart_outlined,
      enabled: true,
      integerOnly: false,
    );

    return Column(children: [
      _card(
        title: _tx('طرق استلام الطلب', 'شێوازی وەرگرتنی داواکاری', 'Order fulfilment'),
        subtitle: _tx('حدد كيف يستطيع العميل استلام طلبه.', 'دیاری بکە کڕیار چۆن داواکاری وەردەگرێت.', 'Choose how customers can receive their orders.'),
        icon: Icons.local_shipping_outlined,
        child: Column(children: [
          _toggleTile(icon: Icons.delivery_dining_rounded, title: _tx('توصيل للعميل', 'گەیاندن بۆ کڕیار', 'Delivery'), subtitle: _tx('إرسال الطلب إلى عنوان العميل', 'ناردنی داواکاری بۆ ناونیشانی کڕیار', 'Send orders to the customer address'), value: _deliveryAvailable, onChanged: (v) => setState(() => _deliveryAvailable = v)),
          const SizedBox(height: 10),
          _toggleTile(icon: Icons.shopping_bag_outlined, title: _tx('استلام من المتجر', 'وەرگرتن لە فرۆشگا', 'Pickup'), subtitle: _tx('العميل يأتي ويستلم الطلب بنفسه', 'کڕیار خۆی دێت داواکاری وەردەگرێت', 'Customer collects the order at the store'), value: _pickupAvailable, onChanged: (v) => setState(() => _pickupAvailable = v)),
        ]),
      ),
      const SizedBox(height: 16),
      _card(
        title: _tx('إعدادات التوصيل', 'ڕێکخستنەکانی گەیاندن', 'Delivery settings'),
        subtitle: _tx('الرسوم، الحد الأدنى، ووقت تجهيز الطلب.', 'کرێ، کەمترین داواکاری و کاتی ئامادەکردن.', 'Fees, minimum order and preparation time.'),
        icon: Icons.tune_rounded,
        child: Column(children: [
          if (compact) ...[
            feeField,
            const SizedBox(height: 14),
            minimumField,
          ] else
            Row(children: [
              Expanded(child: feeField),
              const SizedBox(width: 12),
              Expanded(child: minimumField),
            ]),
          const SizedBox(height: 14),
          numericField(
            controller: _preparationMinutes,
            focusNode: _preparationMinutesFocus,
            label: _tx('مدة التجهيز المتوقعة', 'کاتی ئامادەکردنی چاوەڕوانکراو', 'Estimated preparation time'),
            suffix: _tx('دقيقة', 'خولەک', 'min'),
            icon: Icons.timer_outlined,
            enabled: true,
            integerOnly: true,
          ),
          const SizedBox(height: 14),
          TextField(controller: _deliveryZones, enabled: _deliveryAvailable, minLines: 4, maxLines: 7, decoration: InputDecoration(labelText: _tx('مناطق التوصيل', 'ناوچەکانی گەیاندن', 'Delivery zones'), hintText: _tx('اكتب كل منطقة في سطر مستقل', 'هەر ناوچەیەک لە هێڵێکی جیا', 'Enter one area per line'), prefixIcon: const Icon(Icons.map_outlined), alignLabelWithHint: true)),
        ]),
      ),
    ]);
  }

  Widget _toggleTile({required IconData icon, required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) => Container(
    decoration: BoxDecoration(color: value ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(18), border: Border.all(color: value ? const Color(0xFFFFD6AD) : const Color(0xFFE8EAF0))),
    child: SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.orange,
      secondary: Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: value ? AppColors.orange : AppColors.muted)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
    ),
  );

  Widget _hoursSection(bool compact) => Column(children: [
    _card(
      title: _tx('حالة المتجر الآن', 'دۆخی ئێستای فرۆشگا', 'Store status now'),
      subtitle: _tx('يمكنك إيقاف استقبال الطلبات مؤقتًا بدون تغيير جدول الدوام.', 'دەتوانیت کاتی وەرگرتنی داواکاری بوەستێنیت بەبێ گۆڕینی خشتە.', 'Pause orders temporarily without changing the weekly schedule.'),
      icon: Icons.store_mall_directory_outlined,
      child: _toggleTile(icon: _isOpen ? Icons.storefront_rounded : Icons.store_mall_directory_outlined, title: _isOpen ? _tx('المتجر مفتوح ويستقبل الطلبات', 'فرۆشگا کراوەیە', 'Store is accepting orders') : _tx('المتجر مغلق مؤقتًا', 'فرۆشگا کاتی داخراوە', 'Store temporarily closed'), subtitle: _tx('هذا المفتاح لا يغيّر أيام العطلة الأسبوعية.', 'ئەم دوگمەیە ڕۆژانی پشوو ناگۆڕێت.', 'This does not change weekly days off.'), value: _isOpen, onChanged: (v) => setState(() => _isOpen = v)),
    ),
    const SizedBox(height: 16),
    _shiftSettingsCard(compact),
    const SizedBox(height: 16),
    if (_shiftMode == 1)
      _card(
        title: _tx('جدول الدوام الأسبوعي', 'خشتەی هەفتانەی کار', 'Weekly working hours'),
        subtitle: _tx('فعّل أيام العمل وحدد وقت الفتح والإغلاق. عطّل اليوم إذا كان عطلة.', 'ڕۆژانی کار چالاک بکە و کاتی کردنەوە/داخستن دیاری بکە.', 'Enable working days and set open/close times. Disable a day to mark it off.'),
        icon: Icons.calendar_month_outlined,
        child: Column(children: _dayKeys.map((key) => _dayRowFor(_days, key, compact)).toList()),
      )
    else ...[
      _shiftWeeklyCard('morning', compact),
      const SizedBox(height: 16),
      _shiftWeeklyCard('evening', compact),
    ],
  ]);

  Widget _shiftSettingsCard(bool compact) => _card(
    title: _tx('نظام الشفتات', 'سیستەمی شیفت', 'Shift system'),
    subtitle: _tx('إذا عندك منيو صباحي ومسائي فعّل شفتين. إذا عندك منيو واحد اترك شفت واحد.', 'ئەگەر دوو منیو هەیە دوو شیفت هەڵبژێرە.', 'Choose two shifts only when the store has separate morning and evening menus.'),
    icon: Icons.schedule_rounded,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<int>(
        segments: [
          ButtonSegment(value: 1, label: Text(_tx('شفت واحد', 'یەک شیفت', 'One shift')), icon: const Icon(Icons.looks_one_rounded)),
          ButtonSegment(value: 2, label: Text(_tx('شفتين', 'دوو شیفت', 'Two shifts')), icon: const Icon(Icons.looks_two_rounded)),
        ],
        selected: {_shiftMode},
        onSelectionChanged: (value) => setState(() => _shiftMode = value.first),
      ),
      if (_shiftMode == 2) ...[
        const SizedBox(height: 12),
        Text(_tx('لكل شفت جدول أسبوعي مستقل بالأسفل. يمكن تشغيل شفت واحد فقط في يوم معيّن، أو تشغيل الاثنين بأوقات غير متداخلة.', 'هەر شیفتێک خشتەی هەفتانەی جیاواز هەیە.', 'Each shift has its own weekly schedule below. You can run one or both shifts on a day as long as their times do not overlap.'), style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
      ],
    ]),
  );

  Widget _shiftWeeklyCard(String code, bool compact) {
    final morning = code == 'morning';
    final source = morning ? _morningDays : _eveningDays;
    return _card(
      title: morning ? _tx('جدول الشفت الصباحي', 'خشتەی شیفتی بەیانی', 'Morning shift schedule') : _tx('جدول الشفت المسائي', 'خشتەی شیفتی ئێوارە', 'Evening shift schedule'),
      subtitle: _tx('فعّل أيام هذا الشفت وحدد بدايته ونهايته لكل يوم بشكل مستقل.', 'ڕۆژ و کاتەکانی ئەم شیفتە دیاری بکە.', 'Enable this shift by day and set its start/end times independently.'),
      icon: morning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
      child: Column(children: _dayKeys.map((key) => _dayRowFor(source, key, compact)).toList()),
    );
  }

  Widget _dayRowFor(Map<String, _WorkingDayValue> source, String key, bool compact) {
    final day = source[key]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: day.enabled ? Colors.white : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(18), border: Border.all(color: day.enabled ? const Color(0xFFE8EAF0) : const Color(0xFFF0F1F4))),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [Expanded(child: Text(_dayName(key), style: const TextStyle(fontWeight: FontWeight.w900))), _daySwitchFor(source, key)]),
              const SizedBox(height: 10),
              if (day.enabled) Row(children: [Expanded(child: _timeButtonFor(source, key, true)), const SizedBox(width: 8), Expanded(child: _timeButtonFor(source, key, false))]) else Text(_tx('عطلة لهذا الشفت', 'پشوو بۆ ئەم شیفتە', 'Shift off'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800)),
            ])
          : Row(children: [
              SizedBox(width: 125, child: Text(_dayName(key), style: const TextStyle(fontWeight: FontWeight.w900))),
              _daySwitchFor(source, key),
              const SizedBox(width: 12),
              Expanded(child: day.enabled ? Row(children: [Expanded(child: _timeButtonFor(source, key, true)), const SizedBox(width: 10), Expanded(child: _timeButtonFor(source, key, false))]) : Text(_tx('عطلة لهذا الشفت', 'پشوو بۆ ئەم شیفتە', 'Shift off'), style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700))),
            ]),
    );
  }

  Widget _daySwitchFor(Map<String, _WorkingDayValue> source, String key) {
    final day = source[key]!;
    return Switch.adaptive(value: day.enabled, onChanged: (v) => setState(() => day.enabled = v), activeThumbColor: AppColors.orange);
  }

  Widget _timeButtonFor(Map<String, _WorkingDayValue> source, String key, bool opening) {
    final day = source[key]!;
    final value = opening ? day.open : day.close;
    return OutlinedButton.icon(
      onPressed: () => _pickTimeFor(source, key, opening),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14), side: const BorderSide(color: Color(0xFFE4E7EC)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      icon: Icon(opening ? Icons.login_rounded : Icons.logout_rounded, size: 18, color: opening ? AppColors.orange : const Color(0xFF475569)),
      label: Text('${opening ? _tx('من', 'لە', 'From') : _tx('إلى', 'بۆ', 'To')}  ${_display12h(value)}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF172033))),
    );
  }

  Future<void> _pickTimeFor(Map<String, _WorkingDayValue> source, String key, bool opening) async {
    final day = source[key]!;
    final value = opening ? day.open : day.close;
    final pieces = value.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(pieces.first) ?? (opening ? 9 : 23), minute: pieces.length > 1 ? int.tryParse(pieces[1]) ?? 0 : 0),
    );
    if (!mounted || picked == null) return;
    final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (opening) {
        day.open = formatted;
      } else {
        day.close = formatted;
      }
    });
  }

}

class _WorkingDayValue {
  _WorkingDayValue({required this.enabled, required this.open, required this.close});
  bool enabled;
  String open;
  String close;
}
