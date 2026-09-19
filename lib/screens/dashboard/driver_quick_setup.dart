part of 'partner_dashboard.dart';

class DriverQuickSetupScreen extends StatefulWidget {
  const DriverQuickSetupScreen({
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
  State<DriverQuickSetupScreen> createState() => _DriverQuickSetupScreenState();
}

class _DriverQuickSetupScreenState extends State<DriverQuickSetupScreen> {
  String _vehicleType = 'motorcycle';
  final _plateController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await AuthService.instance.saveDriverBasicProfile(
        vehicleType: _vehicleType,
        plateNumber: _plateController.text,
      );
      if (!mounted) return;
      await widget.onSaved();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ معلومات السائق: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ معلومات السائق. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    final name = widget.profile?['full_name']?.toString().trim();
    final phone = widget.profile?['phone']?.toString().trim();
    final email = widget.profile?['email']?.toString().trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.all(compact ? 14 : 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Container(
                padding: EdgeInsets.all(compact ? 18 : 30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFE8E8E8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: widget.onLogout,
                          tooltip: 'تسجيل الخروج',
                          icon: const Icon(Icons.logout_rounded),
                        ),
                        const Spacer(),
                        const Icon(Icons.delivery_dining_rounded, color: AppColors.orange, size: 34),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'معلومات السائق الأساسية',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'خطوة واحدة فقط قبل البدء. لا نطلب صورًا أو مستندات أو رقم شاصي.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, height: 1.5),
                    ),
                    const SizedBox(height: 22),
                    _InfoLine(icon: Icons.person_outline_rounded, label: 'الاسم', value: name?.isNotEmpty == true ? name! : '—'),
                    const SizedBox(height: 10),
                    _InfoLine(icon: Icons.phone_outlined, label: 'الهاتف', value: phone?.isNotEmpty == true ? phone! : '—'),
                    const SizedBox(height: 10),
                    _InfoLine(icon: Icons.email_outlined, label: 'البريد', value: email?.isNotEmpty == true ? email! : (Supabase.instance.client.auth.currentUser?.email ?? '—')),
                    const SizedBox(height: 22),
                    DropdownButtonFormField<String>(
                      initialValue: _vehicleType,
                      decoration: const InputDecoration(
                        labelText: 'نوع المركبة',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.two_wheeler_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'motorcycle', child: Text('دراجة نارية')),
                        DropdownMenuItem(value: 'car', child: Text('سيارة')),
                        DropdownMenuItem(value: 'bicycle', child: Text('دراجة هوائية')),
                      ],
                      onChanged: (value) => setState(() => _vehicleType = value ?? 'motorcycle'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _plateController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'رقم المركبة / اللوحة (اختياري)',
                        hintText: 'يمكن تركه فارغًا',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.pin_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7F0),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'يمكن تعديل نوع المركبة أو رقم اللوحة لاحقًا من الحساب. التوثيق الكامل يمكن إضافته مستقبلًا عند الحاجة.',
                        style: TextStyle(color: Color(0xFF8A4A20), height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_outline_rounded),
                      label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ وبدء العمل'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DriverApprovalPendingScreen extends StatelessWidget {
  const DriverApprovalPendingScreen({
    required this.currentLocale,
    required this.reviewStatus,
    required this.approvalRequired,
    required this.onRefresh,
    required this.onLogout,
    super.key,
  });

  final Locale currentLocale;
  final String reviewStatus;
  final bool approvalRequired;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final rejected = reviewStatus == 'rejected';
    final suspended = reviewStatus == 'suspended';
    final title = rejected
        ? 'تم رفض طلب السائق'
        : suspended
            ? 'حساب السائق موقوف'
            : 'الحساب بانتظار موافقة الإدارة';
    final body = rejected
        ? 'راجع الإدارة أو الدعم لمعرفة سبب الرفض وإعادة التقديم عند الحاجة.'
        : suspended
            ? 'لا يمكن استخدام حساب السائق حاليًا. تواصل مع الإدارة أو الدعم.'
            : 'موافقة السائقين مفعّلة حاليًا من لوحة الإدارة. عند الموافقة يمكنك الدخول مباشرة بدون تسجيل جديد.';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFE8E8E8)),
                ),
                child: Column(
                  children: [
                    Icon(rejected || suspended ? Icons.block_rounded : Icons.hourglass_top_rounded, size: 54, color: AppColors.orange),
                    const SizedBox(height: 16),
                    Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    Text(body, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.55)),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('تحديث الحالة'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.orange, minimumSize: const Size.fromHeight(52)),
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: onLogout, child: const Text('تسجيل الخروج')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEAEAEA)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.orange),
            const SizedBox(width: 10),
            SizedBox(width: 72, child: Text(label, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800))),
          ],
        ),
      );
}
