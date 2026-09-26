import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:printing/printing.dart' show Printer;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/localization/app_strings.dart';
import '../../repositories/orders_repository.dart';
import '../../repositories/driver_delivery_repository.dart';
import '../../repositories/products_repository.dart';
import '../../repositories/offers_repository.dart';
import '../../repositories/reports_repository.dart';
import '../../repositories/ratings_repository.dart';
import '../../repositories/store_operations_repository.dart';
import '../../services/auth_service.dart';
import '../../services/phone_pin_partner_auth_service.dart';
import '../../services/maps_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/receipt_printer_service.dart';
import '../../services/direct_thermal_printer_service.dart';
import '../../widgets/mapbox_location_preview.dart';
import '../../widgets/image_crop_editor.dart'; 
import '../../widgets/partner_photo_picker.dart';
import '../../widgets/persistent_network_image.dart';
import '../../utils/order_item_variant.dart';
import '../auth/auth_flow.dart' show LanguageMenu;

part 'dashboard_shell.dart';
part 'dashboard_navigation.dart';
part 'store_notifications.dart';
part 'orders_management.dart';
part 'product_catalog_management.dart';
part 'ratings_management.dart';
part 'products_management.dart';
part 'offers_management.dart';
part 'reports_analytics.dart';
part 'more_support.dart';
part 'settings_profile.dart';
part 'store_operations_settings.dart';
part 'store_setup_overview.dart';
part 'printer_settings.dart';
part 'driver_email_verification.dart';
part 'driver_quick_setup.dart';
part 'driver_assigned_order.dart';
part 'driver_earnings_wallet.dart';
part 'driver_delivery_history.dart';
part 'driver_account_center.dart';
part 'driver_ratings.dart';


/// Shared image picker used by merchant product/store image flows.
/// Keeping it in the dashboard library makes it available to all `part` files.
Future<PlatformFile?> pickPartnerPhoto() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    withData: true,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return null;
  return result.files.single;
}


String _partnerLocalIraqiPhone(dynamic value) {
  var digits = (value ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00964')) digits = digits.substring(2);
  if (digits.startsWith('964') && digits.length == 13) {
    return '0${digits.substring(3)}';
  }
  if (digits.startsWith('7') && digits.length == 10) return '0$digits';
  return digits;
}

bool _isValidPartnerLocalPhone(String value) => RegExp(r'^07\d{9}$').hasMatch(_partnerLocalIraqiPhone(value));

Future<String> _currentPartnerLoginPhone() async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  final profile = await AuthService.instance.getCurrentProfile();
  final candidates = <dynamic>[
    profile?['phone'],
    user?.userMetadata?['phone'],
    user?.phone,
  ];
  for (final candidate in candidates) {
    final local = _partnerLocalIraqiPhone(candidate);
    if (_isValidPartnerLocalPhone(local)) return local;
  }
  final email = user?.email?.trim().toLowerCase() ?? '';
  if (email.endsWith('@phone.halatalab.invalid')) {
    final local = _partnerLocalIraqiPhone(email.split('@').first);
    if (_isValidPartnerLocalPhone(local)) return local;
  }
  throw StateError('PARTNER_PHONE_NOT_FOUND');
}

Future<bool> _confirmPartnerAccountDeletion({
  required BuildContext context,
  required String role,
  required String language,
}) async {
  String pick(String ar, String ku, String en) => language == 'en' ? en : language == 'ku' ? ku : ar;
  final roleName = role == 'driver'
      ? pick('السائق', 'شۆفێر', 'driver')
      : pick('المتجر', 'فرۆشگا', 'store');

  final first = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
        const SizedBox(width: 10),
        Expanded(child: Text(pick('حذف الحساب', 'سڕینەوەی هەژمار', 'Delete account'))),
      ]),
      content: Text(pick(
        'سيتم حذف حساب $roleName نهائيًا وبياناته الشخصية. هذه العملية لا يمكن التراجع عنها. للمتابعة سنطلب PIN الحساب أولًا.',
        'هەژماری $roleName و زانیارییە کەسییەکانی بە هەمیشەیی دەسڕێتەوە. ئەم کردارە پاشگەز نابێتەوە و بۆ بەردەوامبوون PIN داوا دەکرێت.',
        'The $roleName account and its personal data will be permanently deleted. This cannot be undone. Your account PIN is required to continue.',
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(pick('إلغاء', 'پاشگەزبوونەوە', 'Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(pick('متابعة', 'بەردەوامبوون', 'Continue')),
        ),
      ],
    ),
  );
  if (first != true || !context.mounted) return false;

  final phone = await _currentPartnerLoginPhone();
  if (!context.mounted) return false;

  final pinController = TextEditingController();
  String? pinError;
  var verifying = false;
  final verified = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(pick('تأكيد PIN', 'پشتڕاستکردنەوەی PIN', 'Confirm PIN')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(pick('أدخل PIN الحساب المكوّن من 4 أرقام.', 'PIN ـی 4 ژمارەی هەژمارەکە بنووسە.', 'Enter the 4-digit account PIN.')),
          const SizedBox(height: 12),
          TextField(
            controller: pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            decoration: InputDecoration(
              labelText: 'PIN',
              errorText: pinError,
              prefixIcon: const Icon(Icons.pin_outlined),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: verifying ? null : () => Navigator.pop(dialogContext, false), child: Text(pick('إلغاء', 'پاشگەزبوونەوە', 'Cancel'))),
          FilledButton(
            onPressed: verifying ? null : () async {
              final pin = pinController.text.trim();
              if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
                setLocal(() => pinError = pick('أدخل PIN من 4 أرقام', 'PIN ـی 4 ژمارە بنووسە', 'Enter a 4-digit PIN'));
                return;
              }
              setLocal(() { verifying = true; pinError = null; });
              try {
                await PhonePinPartnerAuthService.login(rawPhone: phone, pin: pin, role: role);
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (_) {
                if (!dialogContext.mounted) return;
                setLocal(() {
                  verifying = false;
                  pinError = pick('PIN غير صحيح', 'PIN هەڵەیە', 'Incorrect PIN');
                });
              }
            },
            child: verifying
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(pick('تحقق', 'پشتڕاستکردنەوە', 'Verify')),
          ),
        ],
      ),
    ),
  );
  pinController.dispose();
  if (verified != true || !context.mounted) return false;

  final finalConfirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(pick('التأكيد النهائي', 'پشتڕاستکردنەوەی کۆتایی', 'Final confirmation')),
      content: Text(pick(
        'تم التحقق من PIN. هل تريد حذف الحساب نهائيًا الآن؟',
        'PIN پشتڕاست کرایەوە. دەتەوێت هەژمارەکە ئێستا بە هەمیشەیی بسڕیتەوە؟',
        'PIN verified. Permanently delete the account now?',
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(pick('إلغاء', 'پاشگەزبوونەوە', 'Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(pick('حذف الحساب نهائيًا', 'سڕینەوەی هەژمار بە هەمیشەیی', 'Delete account permanently')),
        ),
      ],
    ),
  );
  return finalConfirm == true;
}

// Stage 153: shared cross-device responsive helpers.  These use logical
// pixels rather than device brands, so the same layouts adapt to small
// Android phones, large phones, tablets and iPad-sized screens.
double _adaptivePagePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 350) return 10;
  if (width < 600) return 14;
  if (width < 900) return 20;
  return 28;
}

double _adaptiveDialogWidth(BuildContext context, {double maxWidth = 540}) {
  final width = MediaQuery.sizeOf(context).width;
  final horizontal = width < 350 ? 24.0 : width < 600 ? 40.0 : 64.0;
  return (width - horizontal).clamp(240.0, maxWidth).toDouble();
}

int _adaptiveGridColumns(double width, {int phone = 2, int tablet = 3, int desktop = 6}) {
  if (width < 600) return width < 350 ? 1 : phone;
  if (width < 1000) return tablet;
  return desktop;
}

class PartnerDashboardScreen extends StatefulWidget {
  const PartnerDashboardScreen({
    required this.currentLocale,
    required this.onLocaleChanged,
    this.activeRole,
    super.key,
  });

  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final String? activeRole;

  @override
  State<PartnerDashboardScreen> createState() => _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState extends State<PartnerDashboardScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _store;
  bool _driverQuickSetupComplete = false;
  bool _driverAccessAllowed = true;
  bool _driverApprovalRequired = false;
  String _driverReviewStatus = 'approved';
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() { _loading = true; _loadError = null; });
    try {
      final startup = await Future.wait<dynamic>([
        AuthService.instance.getCurrentProfile().timeout(const Duration(seconds: 12)),
        if (widget.activeRole == null)
          AuthService.instance.getActivePartnerRole().timeout(const Duration(seconds: 8))
        else
          Future<String?>.value(widget.activeRole),
      ]);
      final loadedProfile = startup[0] as Map<String, dynamic>?;
      final resolvedRole = startup[1] as String?;
      if (loadedProfile == null) {
        throw const AuthException('partner_role_missing');
      }
      _profile = <String, dynamic>{...loadedProfile};
      final profileRole = _profile!['role']?.toString();
      if (profileRole != resolvedRole) {
        await AuthService.instance.signOut();
        throw const AuthException('partner_role_mismatch');
      }
      if (_profile?['role'] == 'business') {
        _store = await AuthService.instance.getCurrentStore().timeout(const Duration(seconds: 12));
        _driverQuickSetupComplete = false;
        _driverAccessAllowed = true;
        _driverApprovalRequired = false;
        _driverReviewStatus = 'approved';
      } else {
        _store = null;
        // Stage 148: legacy driver onboarding (documents / license / chassis / review)
        // is no longer part of the product. Purge its local leftovers before routing.
        await AuthService.instance.purgeLegacyDriverOnboardingState();
        final driverState = await Future.wait<dynamic>([
          AuthService.instance.isDriverBasicProfileComplete().timeout(const Duration(seconds: 10)),
          AuthService.instance.getDriverAccessState().timeout(const Duration(seconds: 10)),
        ]);
        _driverQuickSetupComplete = driverState[0] == true;
        final access = Map<String, dynamic>.from(driverState[1] as Map);
        _driverAccessAllowed = access['allowed'] == true;
        _driverApprovalRequired = access['approval_required'] == true;
        _driverReviewStatus = access['review_status']?.toString() ?? 'pending';
      }
    } catch (error) {
      _loadError = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    // Stage 193: the WhatsApp OTP is required only after an explicit sign-out.
    // Normal app close/reopen keeps the persisted Supabase session and routes
    // straight back into the verified store/driver account.
    await AuthService.instance.fullSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final role = _profile?['role'] as String?;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null && _profile == null) {
      final s = AppStrings.of(context);
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.orange),
                const SizedBox(height: 12),
                Text(s.t('authFailed'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded), label: Text(s.t('retry'))),
              ]),
            ),
          ),
        ),
      );
    }
    if (role == 'driver' && !_driverQuickSetupComplete) {
      return DriverQuickSetupScreen(
        currentLocale: widget.currentLocale,
        onLocaleChanged: widget.onLocaleChanged,
        profile: _profile,
        onSaved: _loadData,
        onLogout: _logout,
      );
    }
    if (role == 'driver' && !_driverAccessAllowed) {
      return DriverApprovalPendingScreen(
        currentLocale: widget.currentLocale,
        reviewStatus: _driverReviewStatus,
        approvalRequired: _driverApprovalRequired,
        onRefresh: _loadData,
        onLogout: _logout,
      );
    }
    if (role == 'business' && _store == null) {
      return StoreSetupScreen(
        currentLocale: widget.currentLocale,
        onLocaleChanged: widget.onLocaleChanged,
        profile: _profile,
        onSaved: _loadData,
        onLogout: _logout,
      );
    }
    return _AccountHomeScreen(
      currentLocale: widget.currentLocale,
      onLocaleChanged: widget.onLocaleChanged,
      profile: _profile,
      store: _store,
      onLogout: _logout,
    );
  }
}

/// Stage 150: a self-contained support dialog. It owns its controller and busy
/// state for the lifetime of the route, so sending a ticket cannot dispose a
/// controller while the dialog is still animating out or replace the whole app
/// with a global loading state.
class _PartnerSupportDialog extends StatefulWidget {
  const _PartnerSupportDialog({required this.storeId, required this.isDriver});

  final String? storeId;
  final bool isDriver;

  @override
  State<_PartnerSupportDialog> createState() => _PartnerSupportDialogState();
}

class _PartnerSupportDialogState extends State<_PartnerSupportDialog> {
  final TextEditingController _message = TextEditingController();
  String _category = 'general';
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw const AuthException('No signed-in user');
      await Supabase.instance.client
          .from('partner_support_tickets')
          .insert({
            'user_id': user.id,
            'store_id': widget.storeId,
            'category': widget.isDriver ? 'driver_$_category' : _category,
            'message': text,
            'status': 'open',
          })
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = AppStrings.of(context).t('supportSendFailed');
      });
      debugPrint('Support ticket send failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.support_agent_rounded, color: AppColors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.isDriver ? s.t('driverContactSupport') : s.t('contactSupport')),
          ),
        ],
      ),
      content: SizedBox(
        width: width < 600 ? width - 48 : 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.t('contactSupportSubtitle'), style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: s.t('supportCategory'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
                items: widget.isDriver
                    ? [
                        DropdownMenuItem(value: 'general', child: Text(s.t('driverSupportCategoryGeneral'))),
                        DropdownMenuItem(value: 'orders', child: Text(s.t('driverSupportCategoryOrders'))),
                        DropdownMenuItem(value: 'payments', child: Text(s.t('driverSupportCategoryPayments'))),
                        DropdownMenuItem(value: 'technical', child: Text(s.t('driverSupportCategoryTechnical'))),
                      ]
                    : const [
                        DropdownMenuItem(value: 'general', child: Text('عام / General')),
                        DropdownMenuItem(value: 'orders', child: Text('الطلبات / Orders')),
                        DropdownMenuItem(value: 'payments', child: Text('الدفع / Payments')),
                        DropdownMenuItem(value: 'technical', child: Text('تقني / Technical')),
                      ],
                onChanged: _busy ? null : (value) => setState(() => _category = value ?? 'general'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _message,
                enabled: !_busy,
                minLines: 4,
                maxLines: 7,
                decoration: InputDecoration(
                  labelText: s.t('supportMessage'),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(s.t('cancel')),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _send,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: Text(s.t('sendSupportRequest')),
        ),
      ],
    );
  }
}
