import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

class DirectPrinterDevice {
  const DirectPrinterDevice({
    required this.id,
    required this.name,
    required this.transport,
    this.address,
    this.vendorId,
    this.productId,
  });

  final String id;
  final String name;
  final String transport;
  final String? address;
  final int? vendorId;
  final int? productId;

  factory DirectPrinterDevice.fromMap(Map<dynamic, dynamic> map) {
    return DirectPrinterDevice(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Printer',
      transport: map['transport']?.toString() ?? '',
      address: map['address']?.toString(),
      vendorId: map['vendorId'] is num ? (map['vendorId'] as num).toInt() : null,
      productId: map['productId'] is num ? (map['productId'] as num).toInt() : null,
    );
  }
}

class DirectPrintResult {
  const DirectPrintResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class DirectThermalPrinterService {
  DirectThermalPrinterService._();
  static final DirectThermalPrinterService instance = DirectThermalPrinterService._();

  static const MethodChannel _channel = MethodChannel('com.halatalab.partners/direct_printer');

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> requestBluetoothPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestBluetoothPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openBluetoothSettings() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('openBluetoothSettings');
  }

  Future<List<DirectPrinterDevice>> listDevices(String transport) async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeListMethod<dynamic>('listPrinters', {'transport': transport});
      return (raw ?? const [])
          .whereType<Map>()
          .map((e) => DirectPrinterDevice.fromMap(e))
          .where((e) => e.id.isNotEmpty)
          .toList(growable: false);
    } on PlatformException {
      return const [];
    }
  }

  Future<DirectPrintResult> testConnection({
    required String transport,
    required String? deviceId,
    required String? host,
    required int port,
  }) async {
    if (!supported) {
      return const DirectPrintResult(
        success: false,
        message: 'اختبار الاتصال المباشر متاح حاليًا على Android فقط',
      );
    }
    if (transport != 'network' && (deviceId == null || deviceId.trim().isEmpty)) {
      return const DirectPrintResult(success: false, message: 'اختر الطابعة الافتراضية أولًا');
    }
    if (transport == 'network' && (host == null || host.trim().isEmpty)) {
      return const DirectPrintResult(success: false, message: 'أدخل عنوان IP للطابعة');
    }
    try {
      final ok = await _channel.invokeMethod<bool>('testConnection', {
            'transport': transport,
            'deviceId': deviceId,
            'host': host?.trim(),
            'port': port,
          }) ??
          false;
      return DirectPrintResult(
        success: ok,
        message: ok
            ? (transport == 'usb'
                ? 'اتصال USB متاح. هذا يؤكد الاتصال فقط؛ للطباعة المباشرة يجب أن تكون الطابعة حرارية وتدعم ESC/POS. للطابعات العامة استخدم خدمة الطباعة في الجهاز.'
                : (transport == 'ble'
                    ? 'تم الاتصال بجهاز Bluetooth Low Energy والعثور على قناة كتابة للطباعة'
                    : 'الطابعة متصلة وجاهزة'))
            : 'تعذر الاتصال بالطابعة',
      );
    } on PlatformException catch (e) {
      if (e.code == 'BLUETOOTH_PERMISSION_REQUIRED') {
        return const DirectPrintResult(success: false, message: 'اسمح للتطبيق بالوصول إلى Bluetooth ثم أعد الاختبار');
      }
      if (e.code == 'USB_PERMISSION_REQUIRED') {
        return const DirectPrintResult(success: false, message: 'وافق على صلاحية USB ثم أعد الاختبار');
      }
      if (e.code == 'DEVICE_NOT_FOUND') {
        return const DirectPrintResult(success: false, message: 'الطابعة الافتراضية غير متصلة حاليًا');
      }
      return DirectPrintResult(success: false, message: e.message ?? 'تعذر الاتصال بالطابعة');
    } catch (e) {
      return DirectPrintResult(success: false, message: 'تعذر الاتصال بالطابعة: $e');
    }
  }

  Future<DirectPrintResult> printPdf({
    required Uint8List pdfBytes,
    required String transport,
    required String? deviceId,
    required String? host,
    required int port,
    required double paperWidthMm,
    required bool autoCut,
    required bool beep,
  }) async {
    if (!supported) {
      return const DirectPrintResult(
        success: false,
        message: 'الطباعة الحرارية المباشرة متاحة حاليًا على Android فقط. استخدم طباعة النظام على هذا الجهاز.',
      );
    }

    if (transport != 'network' && (deviceId == null || deviceId.trim().isEmpty)) {
      return const DirectPrintResult(success: false, message: 'اختر طابعة مباشرة أولًا');
    }
    if (transport == 'network' && (host == null || host.trim().isEmpty)) {
      return const DirectPrintResult(success: false, message: 'أدخل عنوان IP للطابعة');
    }

    final images = <Uint8List>[];
    try {
      await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
        images.add(await page.toPng());
      }
      if (images.isEmpty) {
        return const DirectPrintResult(success: false, message: 'تعذر تجهيز ورقة الطباعة');
      }

      final widthPx = _targetWidthPixels(paperWidthMm);
      final ok = await _channel.invokeMethod<bool>('printRaster', {
            'transport': transport,
            'deviceId': deviceId,
            'host': host?.trim(),
            'port': port,
            'widthPx': widthPx,
            'autoCut': autoCut,
            'beep': beep,
            'images': images,
          }) ??
          false;
      return DirectPrintResult(
        success: ok,
        message: ok ? 'تم إرسال الطلب للطابعة الحرارية مباشرة' : 'لم تكتمل الطباعة المباشرة',
      );
    } on PlatformException catch (e) {
      final code = e.code;
      if (code == 'BLUETOOTH_PERMISSION_REQUIRED') {
        return const DirectPrintResult(success: false, message: 'اسمح للتطبيق بالوصول إلى أجهزة Bluetooth ثم أعد المحاولة');
      }
      if (code == 'USB_PERMISSION_REQUIRED') {
        return const DirectPrintResult(success: false, message: 'تم طلب صلاحية طابعة USB. وافق عليها ثم أعد الطباعة');
      }
      if (code == 'DEVICE_NOT_FOUND') {
        return const DirectPrintResult(success: false, message: 'الطابعة المختارة غير متصلة حاليًا');
      }
      if (code == 'PRINT_FAILED' && transport == 'usb') {
        return DirectPrintResult(
          success: false,
          message: '${e.message ?? 'فشلت الطباعة المباشرة'}. إذا كانت الطابعة ليست حرارية ESC/POS (مثل الطابعات المكتبية)، استخدم خدمة الطباعة في الجهاز.',
        );
      }
      return DirectPrintResult(success: false, message: e.message ?? 'فشلت الطباعة المباشرة');
    } catch (e) {
      return DirectPrintResult(success: false, message: 'فشلت الطباعة المباشرة: $e');
    }
  }

  int _targetWidthPixels(double mm) {
    if (mm <= 60) return 384;
    if (mm <= 77) return 512;
    if (mm <= 82) return 576;
    if (mm <= 115) return 832;
    return (mm * 7.2).round().clamp(280, 1024).toInt();
  }
}
