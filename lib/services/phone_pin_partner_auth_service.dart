import 'package:supabase_flutter/supabase_flutter.dart';

class PhonePinPartnerAuthResult {
  const PhonePinPartnerAuthResult({
    required this.phoneE164,
    required this.role,
    required this.isNewAccount,
  });
  final String phoneE164;
  final String role;
  final bool isNewAccount;
}

class PhonePinPartnerAuthService {
  PhonePinPartnerAuthService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static String normalizeIraqiPhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00964')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (!digits.startsWith('964')) digits = '964$digits';
    if (!RegExp(r'^9647\d{9}$').hasMatch(digits)) {
      throw const FormatException('INVALID_IRAQI_PHONE');
    }
    return '+$digits';
  }

  static Future<PhonePinPartnerAuthResult> login({
    required String rawPhone,
    required String pin,
    required String role,
  }) {
    return _invoke(action: 'login', rawPhone: rawPhone, pin: pin, role: role);
  }

  static Future<PhonePinPartnerAuthResult> register({
    required String rawPhone,
    required String pin,
    required String role,
    required String fullName,
    String? businessType,
    String? systemCategoryId,
  }) {
    final metadata = <String, dynamic>{'full_name': fullName.trim()};
    if (businessType != null) metadata['business_type'] = businessType;
    if (systemCategoryId != null) metadata['system_category_id'] = systemCategoryId;
    return _invoke(
      action: 'register',
      rawPhone: rawPhone,
      pin: pin,
      role: role,
      metadata: metadata,
    );
  }

  static Future<void> requestPinReset({
    required String rawPhone,
    required String role,
  }) async {
    final phone = normalizeIraqiPhone(rawPhone);
    final normalizedRole = role == 'driver' ? 'driver' : 'business';
    final response = await _client.functions.invoke(
      'phone-pin-auth',
      body: {'action': 'request_pin_reset', 'phone': phone, 'role': normalizedRole},
    );
    final data = _asMap(response.data);
    if (response.status < 200 || response.status >= 300 || data['ok'] != true) {
      throw StateError(_errorCode(data));
    }
  }

  static Future<void> resetPinWithAdminCode({
    required String rawPhone,
    required String role,
    required String recoveryCode,
    required String newPin,
  }) async {
    final phone = normalizeIraqiPhone(rawPhone);
    if (!RegExp(r'^\d{6}$').hasMatch(recoveryCode)) throw const FormatException('INVALID_RECOVERY_CODE');
    if (!RegExp(r'^\d{4}$').hasMatch(newPin)) throw const FormatException('INVALID_PIN');
    final normalizedRole = role == 'driver' ? 'driver' : 'business';
    final response = await _client.functions.invoke(
      'phone-pin-auth',
      body: {
        'action': 'reset_pin_with_admin_code',
        'phone': phone,
        'role': normalizedRole,
        'recovery_code': recoveryCode,
        'new_pin': newPin,
      },
    );
    final data = _asMap(response.data);
    if (response.status < 200 || response.status >= 300 || data['ok'] != true) {
      throw StateError(_errorCode(data));
    }
  }

  static Future<PhonePinPartnerAuthResult> _invoke({
    required String action,
    required String rawPhone,
    required String pin,
    required String role,
    Map<String, dynamic>? metadata,
  }) async {
    final phone = normalizeIraqiPhone(rawPhone);
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) throw const FormatException('INVALID_PIN');
    final normalizedRole = role == 'driver' ? 'driver' : 'business';

    final response = await _client.functions.invoke(
      'phone-pin-auth',
      body: {
        'action': action,
        'phone': phone,
        'pin': pin,
        'role': normalizedRole,
        ...?metadata,
      },
    );
    final data = _asMap(response.data);
    if (response.status < 200 || response.status >= 300 || data['ok'] != true) {
      throw StateError(_errorCode(data));
    }
    final tokenHash = (data['token_hash'] as String?)?.trim() ?? '';
    if (tokenHash.isEmpty) throw StateError('AUTH_SESSION_TOKEN_MISSING');
    final auth = await _client.auth.verifyOTP(tokenHash: tokenHash, type: OtpType.magiclink);
    if (auth.session == null) throw StateError('AUTH_SESSION_MISSING');

    return PhonePinPartnerAuthResult(
      phoneE164: (data['phone']?.toString().trim().isNotEmpty ?? false) ? data['phone'].toString().trim() : phone,
      role: (data['role'] ?? normalizedRole).toString(),
      isNewAccount: data['is_new_account'] == true,
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((k, v) => MapEntry('$k', v));
    return const {};
  }

  static String _errorCode(Map<String, dynamic> data) =>
      (data['code'] ?? data['error'] ?? 'PHONE_PIN_AUTH_FAILED').toString();
}
