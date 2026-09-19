part of 'auth_flow.dart';

class PartnerLoginScreen extends StatefulWidget {
  const PartnerLoginScreen({
    required this.initialRole,
    required this.currentLocale,
    required this.onLocaleChanged,
    super.key,
  });

  final PartnerRole initialRole;
  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<PartnerLoginScreen> createState() => _PartnerLoginScreenState();
}

class _PartnerLoginScreenState extends State<PartnerLoginScreen> {
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _recoveryPhoneController = TextEditingController();
  final _recoveryCodeController = TextEditingController();
  final _recoveryNewPinController = TextEditingController();
  final _recoveryConfirmPinController = TextEditingController();
  bool _busy = false;

  PartnerRole get _role => widget.initialRole;
  String get _roleName => _role == PartnerRole.driver ? 'driver' : 'business';
  String get _roleLabel => _role == PartnerRole.driver ? 'السائق' : 'المتجر';
  bool _validPhone(String value) => RegExp(r'^\d{11}$').hasMatch(value.trim());

  bool _requirePhone(String value) {
    if (_validPhone(value)) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('رقم هاتف $_roleLabel يجب أن يتكون من 11 رقمًا.')),
    );
    return false;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    _recoveryPhoneController.dispose();
    _recoveryCodeController.dispose();
    _recoveryNewPinController.dispose();
    _recoveryConfirmPinController.dispose();
    super.dispose();
  }

  String _friendlyError(Object error) {
    final raw = error.toString().replaceFirst('Bad state: ', '');
    if (raw.contains('INVALID_IRAQI_PHONE')) return 'أدخل رقم هاتف عراقي صحيح، مثال: 07XXXXXXXXX';
    if (raw.contains('INVALID_PIN')) return 'أدخل PIN من 4 أرقام';
    if (raw.contains('ACCOUNT_NOT_FOUND')) return 'لا يوجد حساب بهذا الرقم. استخدم طلب الانضمام أولًا.';
    if (raw.contains('ROLE_MISMATCH_CUSTOMER')) return 'هذا الرقم مخصص لتطبيق العميل.';
    if (raw.contains('ROLE_MISMATCH_BUSINESS')) return 'هذا الرقم مخصص لحساب متجر.';
    if (raw.contains('ROLE_MISMATCH_DRIVER')) return 'هذا الرقم مخصص لحساب سائق.';
    if (raw.contains('ACCOUNT_SUSPENDED')) return 'هذا الحساب موقوف إداريًا. تواصل مع دعم هلا طلب.';
    if (raw.contains('PIN_INCORRECT')) return 'رقم الهاتف أو PIN غير صحيح.';
    if (raw.contains('PIN_LOCKED')) return 'محاولات كثيرة. انتظر قليلًا ثم حاول مرة أخرى.';
    if (raw.contains('PIN_NOT_SET_USE_RECOVERY')) return 'هذا حساب قديم ولم يُحدد له PIN بعد. استخدم «نسيت PIN؟» لتعيينه بأمان.';
    if (raw.contains('RESET_CODE_NOT_ISSUED')) return 'الإدارة لم تصدر رمز الاسترجاع بعد.';
    if (raw.contains('RESET_CODE_EXPIRED')) return 'انتهت صلاحية رمز الاسترجاع. أرسل طلبًا جديدًا.';
    if (raw.contains('RESET_CODE_INCORRECT')) return 'رمز الاسترجاع غير صحيح.';
    if (raw.contains('RESET_CODE_LOCKED')) return 'تم إيقاف رمز الاسترجاع بعد محاولات كثيرة. أرسل طلبًا جديدًا.';
    if (raw.contains('INVALID_RECOVERY_CODE')) return 'أدخل رمز الاسترجاع من 6 أرقام.';
    if (raw.contains('SERVER_AUTH_NOT_CONFIGURED')) return 'إعداد تسجيل الدخول على الخادم غير مكتمل.';
    return 'تعذر إكمال تسجيل الدخول. حاول مرة أخرى.';
  }

  Future<void> _signIn() async {
    if (_busy) return;
    if (!_requirePhone(_phoneController.text)) return;
    if (!RegExp(r'^\d{4}$').hasMatch(_pinController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل PIN من 4 أرقام')));
      return;
    }
    setState(() => _busy = true);
    try {
      await PhonePinPartnerAuthService.login(
        rawPhone: _phoneController.text,
        pin: _pinController.text,
        role: _roleName,
      );
      final authoritative = await AuthService.instance.validateCurrentSessionRole(requestedRole: _roleName);
      if (authoritative != _roleName) throw StateError('ROLE_MISMATCH_${authoritative.toUpperCase()}');
      await AuthService.instance.unlockCurrentSession();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      AuthService.instance.refreshAuthGate();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _showPinRecoveryDialog() async {
    final phone = _recoveryPhoneController..text = _phoneController.text;
    final code = _recoveryCodeController..clear();
    final newPin = _recoveryNewPinController..clear();
    final confirmPin = _recoveryConfirmPinController..clear();
    var requested = false;
    var busy = false;
    String? message;

    await showDialog<void>(
      context: context,
      barrierDismissible: !busy,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> request() async {
            if (busy) return;
            if (!_validPhone(phone.text)) {
              setLocal(() => message = 'رقم هاتف $_roleLabel يجب أن يتكون من 11 رقمًا.');
              return;
            }
            setLocal(() { busy = true; message = null; });
            try {
              await PhonePinPartnerAuthService.requestPinReset(rawPhone: phone.text, role: _roleName);
              if (!dialogContext.mounted) return;
              setLocal(() {
                requested = true;
                message = 'وصل طلب الاسترجاع إلى لوحة الإدارة. بعد التحقق سيعطيك الدعم رمزًا من 6 أرقام صالحًا لمدة 30 دقيقة.';
              });
            } catch (e) {
              if (dialogContext.mounted) setLocal(() => message = _friendlyError(e));
            } finally {
              if (dialogContext.mounted) setLocal(() => busy = false);
            }
          }

          Future<void> confirm() async {
            if (busy) return;
            var completed = false;
            if (!RegExp(r'^\d{6}$').hasMatch(code.text.trim())) {
              setLocal(() => message = 'أدخل رمز الاسترجاع من 6 أرقام.');
              return;
            }
            if (!RegExp(r'^\d{4}$').hasMatch(newPin.text.trim())) {
              setLocal(() => message = 'اختر PIN جديدًا من 4 أرقام.');
              return;
            }
            if (newPin.text.trim() != confirmPin.text.trim()) {
              setLocal(() => message = 'تأكيد PIN غير مطابق.');
              return;
            }
            setLocal(() { busy = true; message = null; });
            try {
              await PhonePinPartnerAuthService.resetPinWithAdminCode(
                rawPhone: phone.text,
                role: _roleName,
                recoveryCode: code.text.trim(),
                newPin: newPin.text.trim(),
              );
              if (!dialogContext.mounted) return;
              completed = true;
              Navigator.of(dialogContext).pop();
              _phoneController.text = phone.text;
              _pinController.clear();
              if (!mounted) return;
              ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('تم تغيير PIN لنفس الحساب. سجل الدخول بالرمز الجديد.')));
            } catch (e) {
              if (dialogContext.mounted) setLocal(() => message = _friendlyError(e));
            } finally {
              if (!completed && dialogContext.mounted) setLocal(() => busy = false);
            }
          }

          return AlertDialog(
            title: Text('استرجاع PIN — $_roleLabel'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('لا يتم إنشاء حساب جديد. الطلب يرتبط بنفس رقم الحساب ونفس بياناته وطلباته.'),
                  const SizedBox(height: 14),
                  TextField(controller: phone, enabled: !requested && !busy, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, maxLength: 11, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)], decoration: const InputDecoration(labelText: 'رقم الهاتف', hintText: '07XXXXXXXXX', counterText: '', border: OutlineInputBorder())),
                  if (requested) ...[
                    const SizedBox(height: 14),
                    const Text('بعد أن تتحقق الإدارة من الطلب، خذ منها رمز الاسترجاع المكوّن من 6 أرقام. الرمز صالح 30 دقيقة ويُستخدم مرة واحدة.'),
                    const SizedBox(height: 12),
                    TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)], decoration: const InputDecoration(labelText: 'رمز الاسترجاع من الإدارة', counterText: '', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    TextField(controller: newPin, obscureText: true, keyboardType: TextInputType.number, maxLength: 4, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)], decoration: const InputDecoration(labelText: 'PIN جديد من 4 أرقام', counterText: '', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    TextField(controller: confirmPin, obscureText: true, keyboardType: TextInputType.number, maxLength: 4, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)], decoration: const InputDecoration(labelText: 'تأكيد PIN الجديد', counterText: '', border: OutlineInputBorder())),
                  ],
                  if (message != null) ...[const SizedBox(height: 12), Text(message!, style: const TextStyle(fontWeight: FontWeight.w700))],
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.of(dialogContext).pop(), child: const Text('إلغاء')),
              if (!requested) FilledButton(onPressed: busy ? null : request, child: Text(busy ? 'جارٍ الإرسال...' : 'إرسال الطلب للإدارة')),
              if (requested) FilledButton(onPressed: busy ? null : confirm, child: Text(busy ? 'جارٍ التحقق...' : 'تغيير PIN')),
            ],
          );
        },
      ),
    );

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
                    constraints: const BoxConstraints(maxWidth: 560),
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
                            Icon(
                              _role == PartnerRole.driver
                                  ? Icons.delivery_dining_rounded
                                  : Icons.storefront_rounded,
                              size: 58,
                              color: AppColors.orange,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'تسجيل دخول $_roleLabel',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'استخدم رقم الهاتف وPIN من 4 أرقام. بعد نجاح الدخول يفتح التطبيق تلقائيًا في المرات القادمة.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 22),
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
                            const SizedBox(height: 14),
                            TextField(
                              controller: _pinController,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              maxLength: 4,
                              textInputAction: TextInputAction.done,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              onSubmitted: (_) => _signIn(),
                              decoration: const InputDecoration(
                                labelText: 'PIN من 4 أرقام',
                                hintText: '••••',
                                counterText: '',
                                prefixIcon: Icon(Icons.lock_outline_rounded),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _busy ? null : _signIn,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.login_rounded),
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  'تسجيل الدخول',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => PartnerSignUpScreen(
                                            initialRole: _role,
                                            currentLocale: widget.currentLocale,
                                            onLocaleChanged:
                                                widget.onLocaleChanged,
                                          ),
                                        ),
                                      ),
                              child: Text('طلب انضمام كـ $_roleLabel'),
                            ),
                            TextButton(
                              onPressed:
                                  _busy ? null : _showPinRecoveryDialog,
                              child: const Text('نسيت PIN؟'),
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
                    tooltip: 'رجوع لاختيار المتجر أو السائق',
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
