part of 'auth_flow.dart';

class PartnerSignUpScreen extends StatefulWidget {
  const PartnerSignUpScreen({required this.initialRole, required this.currentLocale, required this.onLocaleChanged, super.key});
  final PartnerRole initialRole;
  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  @override
  State<PartnerSignUpScreen> createState() => _PartnerSignUpScreenState();
}

class _PartnerSignUpScreenState extends State<PartnerSignUpScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  late PartnerRole _role;
  PartnerSystemCategory? _businessCategory;
  List<PartnerSystemCategory> _categories = const [];
  bool _loadingCategories = false;
  bool _acceptedTerms = false;
  bool _busy = false;

  String get _roleName => _role == PartnerRole.driver ? 'driver' : 'business';
  String get _roleLabel => _role == PartnerRole.driver ? 'سائق' : 'متجر';

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    if (_role == PartnerRole.business) _loadCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _loadingCategories = true);
    try {
      final data = await SystemCategoriesRepository.instance.activeCategories();
      if (mounted) setState(() => _categories = data);
    } finally {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString().replaceFirst('Bad state: ', '');
    if (raw.contains('INVALID_IRAQI_PHONE')) return 'أدخل رقم هاتف عراقي صحيح.';
    if (raw.contains('INVALID_PIN')) return 'اختر PIN من 4 أرقام.';
    if (raw.contains('ACCOUNT_ALREADY_EXISTS')) return 'هذا الرقم لديه حساب بالفعل. استخدم تسجيل الدخول.';
    if (raw.contains('ROLE_MISMATCH_CUSTOMER')) return 'هذا الرقم مستخدم في تطبيق العميل.';
    if (raw.contains('ROLE_MISMATCH_BUSINESS')) return 'هذا الرقم مستخدم لحساب متجر.';
    if (raw.contains('ROLE_MISMATCH_DRIVER')) return 'هذا الرقم مستخدم لحساب سائق.';
    if (raw.contains('ACCOUNT_SUSPENDED')) return 'هذا الحساب موقوف إداريًا.';
    return 'تعذر إنشاء الحساب. حاول مرة أخرى.';
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{11}$').hasMatch(_phoneController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('رقم هاتف $_roleLabel يجب أن يتكون من 11 رقمًا.')),
      );
      return;
    }
    if (_nameController.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل الاسم الكامل'))); return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر PIN من 4 أرقام'))); return;
    }
    if (pin != _confirmPinController.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN غير متطابق'))); return;
    }
    if (_role == PartnerRole.business && _businessCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر تصنيف المتجر'))); return;
    }
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب الموافقة على الشروط والأحكام'))); return;
    }

    setState(() => _busy = true);
    try {
      await PhonePinPartnerAuthService.register(
        rawPhone: _phoneController.text,
        pin: pin,
        role: _roleName,
        fullName: _nameController.text,
        businessType: _role == PartnerRole.business ? _businessCategory?.legacyBusinessType : null,
        systemCategoryId: _role == PartnerRole.business ? _businessCategory?.id : null,
      );
      final authoritative = await AuthService.instance.validateCurrentSessionRole(requestedRole: _roleName);
      if (authoritative != _roleName) throw StateError('ROLE_MISMATCH_${authoritative.toUpperCase()}');
      await AuthService.instance.unlockCurrentSession();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      AuthService.instance.refreshAuthGate();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Stack(
            children: [
              const Positioned.fill(child: _BackgroundDecoration()),
              Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                        side: BorderSide(
                          color: AppColors.orange.withValues(alpha: .22),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'طلب انضمام $_roleLabel',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'أنشئ بيانات الدخول برقم الهاتف وPIN من 4 أرقام. حالة المتجر أو السائق تبقى خاضعة لمراجعة الإدارة كما هي.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 20),
                            SegmentedButton<PartnerRole>(
                              segments: const [
                                ButtonSegment(
                                  value: PartnerRole.business,
                                  label: Text('متجر'),
                                  icon: Icon(Icons.storefront),
                                ),
                                ButtonSegment(
                                  value: PartnerRole.driver,
                                  label: Text('سائق'),
                                  icon: Icon(Icons.delivery_dining),
                                ),
                              ],
                              selected: {_role},
                              onSelectionChanged: _busy
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _role = value.first;
                                        _businessCategory = null;
                                      });
                                      if (_role == PartnerRole.business &&
                                          _categories.isEmpty) {
                                        _loadCategories();
                                      }
                                    },
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'الاسم الكامل',
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.ltr,
                              textInputAction: TextInputAction.next,
                              maxLength: 11,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(11),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'رقم الهاتف',
                                hintText: '07XXXXXXXXX',
                                counterText: '',
                                prefixIcon: Icon(Icons.phone_iphone),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _pinController,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              textInputAction: TextInputAction.next,
                              maxLength: 4,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'PIN من 4 أرقام',
                                counterText: '',
                                prefixIcon: Icon(Icons.lock_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _confirmPinController,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              textInputAction: TextInputAction.done,
                              maxLength: 4,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'تأكيد PIN',
                                counterText: '',
                                prefixIcon: Icon(Icons.lock_reset_rounded),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            if (_role == PartnerRole.business) ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<PartnerSystemCategory>(
                                initialValue: _businessCategory,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'تصنيف المتجر',
                                  prefixIcon: Icon(Icons.category_outlined),
                                  border: OutlineInputBorder(),
                                ),
                                items: _categories
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(
                                          c.labelFor(widget.currentLocale),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _loadingCategories
                                    ? null
                                    : (v) => setState(
                                          () => _businessCategory = v,
                                        ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _acceptedTerms,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(
                                        () => _acceptedTerms = v ?? false,
                                      ),
                              title: const Text(
                                'أوافق على الشروط والأحكام وسياسة الخصوصية',
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _busy ? null : _submit,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.person_add_alt_1_rounded),
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  'إرسال طلب الانضمام',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).maybePop(),
                              child: const Text('لدي حساب بالفعل'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 8,
                start: 8,
                child: Material(
                  color: Colors.transparent,
                  child: IconButton.filledTonal(
                    tooltip: 'رجوع',
                    onPressed: _busy
                        ? null
                        : () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            Navigator.of(context).maybePop();
                          },
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
