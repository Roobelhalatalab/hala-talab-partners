part of 'partner_dashboard.dart';

class DriverEmailVerificationScreen extends StatefulWidget {
  const DriverEmailVerificationScreen({
    required this.currentLocale,
    required this.onLocaleChanged,
    required this.profile,
    required this.onVerified,
    required this.onLogout,
    super.key,
  });

  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final Map<String, dynamic>? profile;
  final Future<void> Function() onVerified;
  final Future<void> Function() onLogout;

  @override
  State<DriverEmailVerificationScreen> createState() => _DriverEmailVerificationScreenState();
}

class _DriverEmailVerificationScreenState extends State<DriverEmailVerificationScreen> {
    final _codeControllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  Timer? _timer;
  int _secondsLeft = 0;
  bool _sending = false;
  bool _verifying = false;
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _codeControllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _sendCode() async {
    if (_sending) return;
    final s = AppStrings.of(context);
    setState(() => _sending = true);
    try {
      await AuthService.instance.requestDriverEmailVerification();
      if (!mounted) return;
      setState(() => _codeSent = true);
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('driverOtpSent'))));
      _focusNodes.first.requestFocus();
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('driverOtpSendFailed'))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resendCode() async {
    if (_secondsLeft > 0 || _sending) return;
    setState(() => _sending = true);
    try {
      await AuthService.instance.resendDriverEmailVerification();
      if (!mounted) return;
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.of(context).t('driverOtpSent'))));
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_verifying || !_codeSent) return;
    final code = _codeControllers.map((controller) => controller.text).join();
    final s = AppStrings.of(context);
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('driverOtpInvalid'))));
      return;
    }
    setState(() => _verifying = true);
    try {
      await AuthService.instance.verifyDriverEmailOtp(token: code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('driverEmailVerified'))));
      await widget.onVerified();
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('driverOtpInvalid'))));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Widget _otpBox(int index) {
    return SizedBox(
      width: 54,
      child: TextField(
        controller: _codeControllers[index],
        focusNode: _focusNodes[index],
        enabled: _codeSent && !_verifying,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLength: 1,
        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E3E8))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.orange, width: 1.7)),
          disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE9EAEE))),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
          if (index == 5 && value.isNotEmpty) {
            FocusScope.of(context).unfocus();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return SingleChildScrollView(
              padding: EdgeInsets.all(wide ? 28 : 14),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 720 : 620),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: wide ? 38 : 20, vertical: wide ? 32 : 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFFE8E8E8)),
                      boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 28, offset: Offset(0, 12))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(onPressed: widget.onLogout, tooltip: s.t('logout'), icon: const Icon(Icons.logout_rounded)),
                            const Spacer(),
                            Text(s.t('driverEmailVerificationTitle'), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                              decoration: BoxDecoration(color: const Color(0xFFFFF0E5), borderRadius: BorderRadius.circular(15)),
                              child: Text(s.t('driverVerificationStep'), style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(s.t('driverEmailVerificationSubtitle'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.5)),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
                          decoration: BoxDecoration(color: const Color(0xFFFFF7F0), borderRadius: BorderRadius.circular(24)),
                          child: const Icon(Icons.mark_email_read_outlined, size: 92, color: AppColors.orange),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFAF6),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFFFE2CF)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.email_outlined, color: AppColors.orange),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.t('email'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                    const SizedBox(height: 3),
                                    Text(
                                      Supabase.instance.client.auth.currentUser?.email ?? '-',
                                      textDirection: TextDirection.ltr,
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_codeSent)
                                TextButton(
                                  onPressed: _sending ? null : _sendCode,
                                  child: Text(_sending ? s.t('sending') : s.t('driverSendCode')),
                                )
                              else
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF22A447)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),
                        Text(s.t('driverVerificationCode'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 9,
                          runSpacing: 9,
                          textDirection: TextDirection.ltr,
                          children: List.generate(6, _otpBox),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(s.t('driverDidNotReceive'), style: const TextStyle(color: AppColors.muted)),
                            TextButton(
                              onPressed: _codeSent && _secondsLeft == 0 ? _resendCode : null,
                              child: Text(s.t('driverResendCode'), style: const TextStyle(fontWeight: FontWeight.w900)),
                            ),
                            if (_secondsLeft > 0)
                              Text('00:${_secondsLeft.toString().padLeft(2, '0')}', textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: const Color(0xFFFFF7F0), borderRadius: BorderRadius.circular(16)),
                          child: Row(children: [
                            const Icon(Icons.shield_outlined, color: AppColors.orange),
                            const SizedBox(width: 10),
                            Expanded(child: Text(s.t('driverOtpSecurityHint'), style: const TextStyle(color: AppColors.muted, height: 1.5))),
                          ]),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          key: const Key('driver-verify-phone-button'),
                          onPressed: _codeSent && !_verifying ? _verifyCode : null,
                          icon: _verifying
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                              : const Icon(Icons.verified_user_outlined),
                          label: Text(s.t('driverVerifyCode'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        ),
                        const SizedBox(height: 12),
                        Text(s.t('driverEmailOtpStageNote'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
