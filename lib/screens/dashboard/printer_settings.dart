part of 'partner_dashboard.dart';

class _PrinterSettingsPage extends StatefulWidget {
  const _PrinterSettingsPage({required this.store, required this.currentLocale});

  final Map<String, dynamic>? store;
  final Locale currentLocale;

  @override
  State<_PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<_PrinterSettingsPage> {
  ReceiptPrinterSettings _settings = const ReceiptPrinterSettings();
  List<Printer> _printers = const [];
  List<DirectPrinterDevice> _directDevices = const [];
  bool _loading = true;
  bool _directLoading = false;
  bool _saving = false;
  bool _testing = false;
  bool _checkingConnection = false;
  bool? _connectionOk;
  String _connectionMessage = 'لم يتم اختبار الاتصال بعد';
  late final TextEditingController _customWidth;
  late final TextEditingController _networkHost;
  late final TextEditingController _networkPort;

  @override
  void initState() {
    super.initState();
    _customWidth = TextEditingController(text: '80');
    _networkHost = TextEditingController();
    _networkPort = TextEditingController(text: '9100');
    _load();
  }

  @override
  void dispose() {
    _customWidth.dispose();
    _networkHost.dispose();
    _networkPort.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      ReceiptPrinterService.instance.loadSettings(),
      ReceiptPrinterService.instance.listPrinters(),
    ]);
    if (!mounted) return;
    final settings = results[0] as ReceiptPrinterSettings;
    setState(() {
      _settings = settings;
      _customWidth.text = settings.customPaperWidthMm.toStringAsFixed(0);
      _networkHost.text = settings.networkHost ?? '';
      _networkPort.text = settings.networkPort.toString();
      _printers = List<Printer>.from(results[1] as List);
      _loading = false;
    });
    if (settings.usesDirectPrinter && settings.directTransport != 'network') {
      await _refreshDirectDevices(requestPermission: false);
    }
  }

  ReceiptPrinterSettings _normalizedSettings([ReceiptPrinterSettings? source]) {
    final base = source ?? _settings;
    final custom = double.tryParse(_customWidth.text.trim()) ?? base.customPaperWidthMm;
    final port = int.tryParse(_networkPort.text.trim()) ?? base.networkPort;
    return base.copyWith(
      customPaperWidthMm: custom.clamp(40, 150).toDouble(),
      networkHost: _networkHost.text.trim(),
      networkPort: port.clamp(1, 65535).toInt(),
    );
  }

  Future<void> _save({bool popAfter = false, bool showMessage = true}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final normalized = _normalizedSettings();
      await ReceiptPrinterService.instance.saveSettings(normalized);
      if (!mounted) return;
      setState(() => _settings = normalized);
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ إعدادات الطابعة')),
        );
      }
      if (popAfter) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _persistSettingsSilently(ReceiptPrinterSettings settings) async {
    final normalized = _normalizedSettings(settings);
    await ReceiptPrinterService.instance.saveSettings(normalized);
    if (!mounted) return;
    setState(() => _settings = normalized);
  }

  Future<void> _setPrintingEnabled(bool value) async {
    final next = _settings.copyWith(enabled: value);
    setState(() => _settings = next);
    await _persistSettingsSilently(next);
  }

  Future<void> _selectPrinter(String? value) async {
    ReceiptPrinterSettings next;
    if (value == null) {
      next = _settings.copyWith(clearPrinter: true);
    } else {
      final printer = _printers.firstWhere((p) => p.url == value);
      next = _settings.copyWith(printerUrl: printer.url, printerName: printer.name);
    }
    await _persistSettingsSilently(next);
    if (!mounted) return;
    setState(() { _connectionOk = null; _connectionMessage = 'لم يتم اختبار الاتصال بعد'; });
    final label = next.printerName?.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          label == null || label.isEmpty
              ? 'لم يتم اختيار طابعة افتراضية'
              : 'تم حفظ الطابعة الافتراضية: $label',
        ),
      ),
    );
  }

  Future<void> _refreshPrinters() async {
    setState(() => _loading = true);
    final printers = await ReceiptPrinterService.instance.listPrinters();
    if (!mounted) return;
    setState(() {
      _printers = printers;
      _loading = false;
    });
  }

  Future<void> _setConnectionMode(String value) async {
    final next = _settings.copyWith(connectionMode: value);
    setState(() { _connectionOk = null; _connectionMessage = 'لم يتم اختبار الاتصال بعد'; });
    await _persistSettingsSilently(next);
    if (value == 'direct' && next.directTransport != 'network') {
      await _refreshDirectDevices(requestPermission: false);
    }
  }

  Future<void> _setDirectTransport(String value) async {
    final next = _settings.copyWith(
      directTransport: value,
      clearDirectDevice: true,
    );
    setState(() {
      _settings = next;
      _directDevices = const [];
      _connectionOk = null;
      _connectionMessage = 'لم يتم اختبار الاتصال بعد';
    });
    await _persistSettingsSilently(next);
    if (value != 'network') {
      await _refreshDirectDevices(requestPermission: false);
    }
  }

  Future<void> _refreshDirectDevices({bool requestPermission = true}) async {
    if (_settings.directTransport == 'network') return;
    setState(() => _directLoading = true);
    if ((_settings.directTransport == 'bluetooth' || _settings.directTransport == 'ble') && requestPermission) {
      await DirectThermalPrinterService.instance.requestBluetoothPermission();
    }
    final devices = await DirectThermalPrinterService.instance.listDevices(_settings.directTransport);
    if (!mounted) return;
    setState(() {
      _directDevices = devices;
      _directLoading = false;
    });
  }

  Future<void> _selectDirectPrinter(String? id) async {
    if (id == null) {
      await _persistSettingsSilently(_settings.copyWith(clearDirectDevice: true));
      return;
    }
    final device = _directDevices.firstWhere((e) => e.id == id);
    await _persistSettingsSilently(
      _settings.copyWith(directDeviceId: device.id, directDeviceName: device.name),
    );
    if (mounted) setState(() { _connectionOk = null; _connectionMessage = 'لم يتم اختبار الاتصال بعد'; });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ الطابعة المباشرة: ${device.name}')),
    );
  }

  Future<void> _openBluetoothSettings() async {
    await DirectThermalPrinterService.instance.openBluetoothSettings();
  }

  Future<void> _testConnection() async {
    if (_checkingConnection) return;
    await _save(showMessage: false);
    if (!mounted) return;
    setState(() {
      _checkingConnection = true;
      _connectionOk = null;
      _connectionMessage = 'جاري اختبار الاتصال...';
    });
    final result = await ReceiptPrinterService.instance.testConnection();
    if (!mounted) return;
    setState(() {
      _checkingConnection = false;
      _connectionOk = result.success;
      _connectionMessage = result.message;
    });
  }

  Future<void> _testPrint() async {
    if (_testing) return;
    await _save(showMessage: false);
    if (!mounted) return;
    setState(() => _testing = true);
    final result = await ReceiptPrinterService.instance.printOrder(
      order: {
        'id': 'test-print',
        'order_number': 'TEST',
        'created_at': DateTime.now().toIso8601String(),
        'customer_name': 'زبون تجريبي',
        'delivery_address': 'عنوان تجريبي',
        'total': 15000,
        'notes': 'هذه ورقة اختبار للطابعة',
        'order_items': [
          {'product_name': 'وجبة تجريبية', 'quantity': 2, 'unit_price': 5000, 'notes': 'بدون بصل'},
          {'product_name': 'مشروب', 'quantity': 1, 'unit_price': 5000},
        ],
      },
      store: widget.store,
      appLanguage: widget.currentLocale.languageCode,
      allowPrinterDialog: true,
      testPrint: true,
    );
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EAEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  String _currentPrinterLabel() {
    if (_settings.usesDirectPrinter) {
      if (_settings.directTransport == 'network') {
        final host = _networkHost.text.trim();
        return host.isEmpty ? 'لم يتم إدخال IP للطابعة' : '$host:${_networkPort.text.trim().isEmpty ? '9100' : _networkPort.text.trim()}';
      }
      return _settings.directDeviceName?.trim().isNotEmpty == true
          ? _settings.directDeviceName!.trim()
          : 'لم يتم اختيار طابعة مباشرة';
    }
    return _settings.printerName?.trim().isNotEmpty == true
        ? _settings.printerName!.trim()
        : 'لم يتم اختيار طابعة افتراضية';
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final selectedPrinterValue = _printers.any((p) => p.url == _settings.printerUrl)
        ? _settings.printerUrl
        : null;
    final selectedDirectValue = _directDevices.any((p) => p.id == _settings.directDeviceId)
        ? _settings.directDeviceId
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(title: const Text('إعدادات الطابعة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(compact ? 14 : 22),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _section('الطابعة والاتصال', [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('تفعيل الطباعة'),
                            subtitle: const Text('يظهر زر الطباعة للطلبات المقبولة وقيد التنفيذ.'),
                            value: _settings.enabled,
                            onChanged: _setPrintingEnabled,
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: _settings.connectionMode,
                            decoration: const InputDecoration(labelText: 'طريقة الاتصال'),
                            items: const [
                              DropdownMenuItem(value: 'system', child: Text('خدمة الطباعة في الجهاز (متوافقة عامة)')),
                              DropdownMenuItem(value: 'direct', child: Text('اتصال حراري مباشر ESC/POS')),
                            ],
                            onChanged: _settings.enabled ? (v) { if (v != null) _setConnectionMode(v); } : null,
                          ),
                          const SizedBox(height: 10),
                          if (!_settings.usesDirectPrinter) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String?>(
                                    initialValue: selectedPrinterValue,
                                    decoration: const InputDecoration(
                                      labelText: 'الطابعة الافتراضية',
                                      hintText: 'اختر طابعة واحفظها مرة واحدة',
                                    ),
                                    items: [
                                      ..._printers.map((p) => DropdownMenuItem<String?>(
                                            value: p.url,
                                            child: Text('${p.name}${p.isDefault ? ' • افتراضية' : ''}', overflow: TextOverflow.ellipsis),
                                          )),
                                    ],
                                    onChanged: _settings.enabled ? _selectPrinter : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  onPressed: _refreshPrinters,
                                  tooltip: 'تحديث الطابعات',
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'اختر الطابعة مرة واحدة. التطبيق يحاول الطباعة بنقرة واحدة مباشرة. إذا منع Android أو تعريف الطابعة الطباعة الصامتة (كما يحدث مع بعض Canon/Epson العامة)، ستظهر نافذة النظام للتأكيد. الطابعات الحرارية الشبكية ESC/POS عبر IP تطبع مباشرة بدون نافذة.',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                          ] else ...[
                            DropdownButtonFormField<String>(
                              initialValue: _settings.directTransport,
                              decoration: const InputDecoration(labelText: 'نوع الاتصال المباشر'),
                              items: const [
                                DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth Classic حراري (SPP)')),
                                DropdownMenuItem(value: 'ble', child: Text('Bluetooth Low Energy (BLE)')),
                                DropdownMenuItem(value: 'usb', child: Text('USB')),
                                DropdownMenuItem(value: 'network', child: Text('Wi‑Fi / LAN حراري مباشر (IP)')),
                              ],
                              onChanged: _settings.enabled ? (v) { if (v != null) _setDirectTransport(v); } : null,
                            ),
                            const SizedBox(height: 10),
                            if (_settings.directTransport == 'network') ...[
                              TextField(
                                controller: _networkHost,
                                keyboardType: TextInputType.url,
                                decoration: const InputDecoration(
                                  labelText: 'IP الطابعة',
                                  hintText: 'مثال: 192.168.1.50',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _networkPort,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Port',
                                  helperText: 'غالبًا 9100 للطابعات الحرارية الشبكية ESC/POS',
                                ),
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String?>(
                                      initialValue: selectedDirectValue,
                                      decoration: InputDecoration(
                                        labelText: _settings.directTransport == 'bluetooth'
                                            ? 'طابعات Bluetooth Classic المقترنة'
                                            : (_settings.directTransport == 'ble'
                                                ? 'أجهزة Bluetooth Low Energy القريبة'
                                                : 'طابعات USB المتصلة'),
                                      ),
                                      items: [
                                        const DropdownMenuItem<String?>(value: null, child: Text('اختر الطابعة')),
                                        ..._directDevices.map((p) => DropdownMenuItem<String?>(
                                              value: p.id,
                                              child: Text(p.name, overflow: TextOverflow.ellipsis),
                                            )),
                                      ],
                                      onChanged: _settings.enabled ? _selectDirectPrinter : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    onPressed: _directLoading ? null : () => _refreshDirectDevices(),
                                    tooltip: 'السماح والبحث',
                                    icon: _directLoading
                                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Icon(Icons.search_rounded),
                                  ),
                                ],
                              ),
                              if (_settings.directTransport == 'bluetooth' || _settings.directTransport == 'ble') ...[
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: _openBluetoothSettings,
                                  icon: const Icon(Icons.bluetooth_searching_rounded),
                                  label: Text(_settings.directTransport == 'ble'
                                      ? 'فتح إعدادات Bluetooth'
                                      : 'إقران طابعة Bluetooth جديدة'),
                                ),
                              ],
                            ],
                            const SizedBox(height: 8),
                            const Text(
                              'الاتصال المباشر يطبع ESC/POS من داخل هلا طلب بدون نافذة طباعة: Bluetooth Classic (SPP)، أو Bluetooth Low Energy (BLE)، أو USB، أو Wi‑Fi/LAN عبر IP. في BLE يبحث التطبيق عن قناة كتابة قياسية ويجرب أشهر قنوات الطابعات الحرارية تلقائيًا. الطابعات ذات البروتوكول/SDK الخاص بالشركة تبقى على خدمة طباعة النظام أو تعريف الشركة.',
                              style: TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FB),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE8EAEE)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.print_rounded, color: AppColors.orange),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('الطابعة الحالية', style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 2),
                                          Text(_currentPrinterLabel(), style: const TextStyle(fontWeight: FontWeight.w900)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      _connectionOk == true
                                          ? Icons.check_circle_rounded
                                          : (_connectionOk == false ? Icons.error_rounded : Icons.help_outline_rounded),
                                      size: 20,
                                      color: _connectionOk == true
                                          ? Colors.green
                                          : (_connectionOk == false ? Colors.redAccent : AppColors.muted),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(_connectionMessage)),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: !_settings.enabled || _checkingConnection ? null : _testConnection,
                                  icon: _checkingConnection
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.cable_rounded),
                                  label: const Text('اختبار اتصال الطابعة'),
                                ),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        _section('الورق والتنسيق', [
                          DropdownButtonFormField<String>(
                            initialValue: _settings.paperWidth,
                            decoration: const InputDecoration(labelText: 'عرض الورق'),
                            items: const [
                              DropdownMenuItem(value: '58', child: Text('58 mm')),
                              DropdownMenuItem(value: '76', child: Text('76 mm')),
                              DropdownMenuItem(value: '80', child: Text('80 mm')),
                              DropdownMenuItem(value: '112', child: Text('112 mm')),
                              DropdownMenuItem(value: 'custom', child: Text('مخصص')),
                            ],
                            onChanged: (v) { if (v != null) setState(() => _settings = _settings.copyWith(paperWidth: v)); },
                          ),
                          if (_settings.paperWidth == 'custom') ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: _customWidth,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'العرض المخصص بالـ mm', helperText: 'من 40 إلى 150 mm'),
                            ),
                          ],
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _settings.fontSize,
                            decoration: const InputDecoration(labelText: 'حجم الخط'),
                            items: const [
                              DropdownMenuItem(value: 'small', child: Text('صغير')),
                              DropdownMenuItem(value: 'medium', child: Text('متوسط')),
                              DropdownMenuItem(value: 'large', child: Text('كبير')),
                            ],
                            onChanged: (v) { if (v != null) setState(() => _settings = _settings.copyWith(fontSize: v)); },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<int>(
                            initialValue: _settings.copyCount,
                            decoration: const InputDecoration(labelText: 'عدد النسخ لكل نوع'),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text('نسخة واحدة')),
                              DropdownMenuItem(value: 2, child: Text('نسختان')),
                              DropdownMenuItem(value: 3, child: Text('3 نسخ')),
                            ],
                            onChanged: (v) { if (v != null) setState(() => _settings = _settings.copyWith(copyCount: v)); },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _settings.language,
                            decoration: const InputDecoration(labelText: 'لغة الطباعة'),
                            items: const [
                              DropdownMenuItem(value: 'store', child: Text('حسب لغة المتجر')),
                              DropdownMenuItem(value: 'ar', child: Text('العربية')),
                              DropdownMenuItem(value: 'en', child: Text('English')),
                            ],
                            onChanged: (v) { if (v != null) setState(() => _settings = _settings.copyWith(language: v)); },
                          ),
                        ]),
                        const SizedBox(height: 14),
                        _section('نسخ المطبخ والكاشير', [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('نسخة المطبخ'),
                            subtitle: const Text('تركّز على الأصناف والإضافات والملاحظات.'),
                            value: _settings.kitchenCopy,
                            onChanged: (v) => setState(() => _settings = _settings.copyWith(kitchenCopy: v ?? false)),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('نسخة الكاشير'),
                            subtitle: const Text('تتضمن الأسعار والإجمالي حسب الإعدادات.'),
                            value: _settings.cashierCopy,
                            onChanged: (v) => setState(() => _settings = _settings.copyWith(cashierCopy: v ?? false)),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('إخفاء الأسعار من نسخة المطبخ'),
                            value: _settings.hideKitchenPrices,
                            onChanged: (v) => setState(() => _settings = _settings.copyWith(hideKitchenPrices: v)),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        _section('محتوى الورقة', [
                          _printOption('رقم الطلب', _settings.showOrderNumber, (v) => _settings = _settings.copyWith(showOrderNumber: v)),
                          _printOption('اسم الزبون', _settings.showCustomer, (v) => _settings = _settings.copyWith(showCustomer: v)),
                          _printOption('الأصناف والكميات', _settings.showItems, (v) => _settings = _settings.copyWith(showItems: v)),
                          _printOption('الإضافات والخيارات', _settings.showExtras, (v) => _settings = _settings.copyWith(showExtras: v)),
                          _printOption('الملاحظات', _settings.showNotes, (v) => _settings = _settings.copyWith(showNotes: v)),
                          _printOption('الأسعار', _settings.showPrices, (v) => _settings = _settings.copyWith(showPrices: v)),
                          _printOption('العنوان', _settings.showAddress, (v) => _settings = _settings.copyWith(showAddress: v)),
                          _printOption('اسم المتجر أعلى الورقة', _settings.printStoreName, (v) => _settings = _settings.copyWith(printStoreName: v)),
                          _printOption('شعار المتجر (عند توفره)', _settings.printStoreLogo, (v) => _settings = _settings.copyWith(printStoreLogo: v)),
                        ]),
                        const SizedBox(height: 14),
                        _section('الأتمتة وميزات الطابعة', [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('طباعة تلقائية بعد قبول الطلب'),
                            subtitle: Text(_settings.usesDirectPrinter
                                ? 'تتطلب اختيار طابعة مباشرة أو إدخال IP صحيح.'
                                : 'تتطلب اختيار طابعة ثابتة أعلاه.'),
                            value: _settings.autoPrintAfterAccept,
                            onChanged: (v) => setState(() => _settings = _settings.copyWith(autoPrintAfterAccept: v)),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('قص الورق تلقائيًا إذا كان مدعومًا'),
                            subtitle: Text(_settings.usesDirectPrinter
                                ? 'يُرسل أمر القص ESC/POS مباشرة للطابعة.'
                                : 'يعتمد التنفيذ الفعلي على تعريف الطابعة.'),
                            value: _settings.autoCut,
                            onChanged: (v) => setState(() => _settings = _settings.copyWith(autoCut: v)),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('جرس/تنبيه الطابعة إذا كان مدعومًا'),
                            subtitle: Text(_settings.usesDirectPrinter
                                ? 'يُرسل أمر تنبيه ESC/POS، وبعض الطابعات قد تتجاهله.'
                                : 'يعتمد التنفيذ الفعلي على تعريف الطابعة.'),
                            value: _settings.beep,
                            onChanged: (v) => setState(() => _settings = _settings.copyWith(beep: v)),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _testing ? null : _testPrint,
                          icon: _testing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.print_outlined),
                          label: const Text('طباعة اختبار'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _saving ? null : () => _save(popAfter: true),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('حفظ إعدادات الطابعة'),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _printOption(String title, bool value, ValueChanged<bool> setter) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: (v) => setState(() => setter(v)),
    );
  }
}
