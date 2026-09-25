import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'direct_thermal_printer_service.dart';
import '../utils/order_item_variant.dart';

class ReceiptPrinterSettings {
  const ReceiptPrinterSettings({
    this.enabled = true,
    this.paperWidth = '80',
    this.customPaperWidthMm = 80,
    this.fontSize = 'medium',
    this.copyCount = 1,
    this.kitchenCopy = true,
    this.cashierCopy = false,
    this.showOrderNumber = true,
    this.showCustomer = true,
    this.showItems = true,
    this.showExtras = true,
    this.showNotes = true,
    this.showPrices = true,
    this.showAddress = true,
    this.hideKitchenPrices = true,
    this.autoPrintAfterAccept = false,
    this.autoCut = true,
    this.beep = false,
    this.printStoreName = true,
    this.printStoreLogo = false,
    this.language = 'store',
    this.connectionMode = 'system',
    this.directTransport = 'bluetooth',
    this.directDeviceId,
    this.directDeviceName,
    this.networkHost,
    this.networkPort = 9100,
    this.printerUrl,
    this.printerName,
  });

  final bool enabled;
  final String paperWidth;
  final double customPaperWidthMm;
  final String fontSize;
  final int copyCount;
  final bool kitchenCopy;
  final bool cashierCopy;
  final bool showOrderNumber;
  final bool showCustomer;
  final bool showItems;
  final bool showExtras;
  final bool showNotes;
  final bool showPrices;
  final bool showAddress;
  final bool hideKitchenPrices;
  final bool autoPrintAfterAccept;
  final bool autoCut;
  final bool beep;
  final bool printStoreName;
  final bool printStoreLogo;
  final String language;
  final String connectionMode;
  final String directTransport;
  final String? directDeviceId;
  final String? directDeviceName;
  final String? networkHost;
  final int networkPort;
  final String? printerUrl;
  final String? printerName;

  double get effectivePaperWidthMm {
    if (paperWidth == 'custom') {
      return customPaperWidthMm.clamp(40, 150).toDouble();
    }
    return double.tryParse(paperWidth) ?? 80;
  }

  bool get usesDirectPrinter => connectionMode == 'direct';

  ReceiptPrinterSettings copyWith({
    bool? enabled,
    String? paperWidth,
    double? customPaperWidthMm,
    String? fontSize,
    int? copyCount,
    bool? kitchenCopy,
    bool? cashierCopy,
    bool? showOrderNumber,
    bool? showCustomer,
    bool? showItems,
    bool? showExtras,
    bool? showNotes,
    bool? showPrices,
    bool? showAddress,
    bool? hideKitchenPrices,
    bool? autoPrintAfterAccept,
    bool? autoCut,
    bool? beep,
    bool? printStoreName,
    bool? printStoreLogo,
    String? language,
    String? connectionMode,
    String? directTransport,
    String? directDeviceId,
    String? directDeviceName,
    String? networkHost,
    int? networkPort,
    String? printerUrl,
    String? printerName,
    bool clearPrinter = false,
    bool clearDirectDevice = false,
  }) {
    return ReceiptPrinterSettings(
      enabled: enabled ?? this.enabled,
      paperWidth: paperWidth ?? this.paperWidth,
      customPaperWidthMm: customPaperWidthMm ?? this.customPaperWidthMm,
      fontSize: fontSize ?? this.fontSize,
      copyCount: copyCount ?? this.copyCount,
      kitchenCopy: kitchenCopy ?? this.kitchenCopy,
      cashierCopy: cashierCopy ?? this.cashierCopy,
      showOrderNumber: showOrderNumber ?? this.showOrderNumber,
      showCustomer: showCustomer ?? this.showCustomer,
      showItems: showItems ?? this.showItems,
      showExtras: showExtras ?? this.showExtras,
      showNotes: showNotes ?? this.showNotes,
      showPrices: showPrices ?? this.showPrices,
      showAddress: showAddress ?? this.showAddress,
      hideKitchenPrices: hideKitchenPrices ?? this.hideKitchenPrices,
      autoPrintAfterAccept: autoPrintAfterAccept ?? this.autoPrintAfterAccept,
      autoCut: autoCut ?? this.autoCut,
      beep: beep ?? this.beep,
      printStoreName: printStoreName ?? this.printStoreName,
      printStoreLogo: printStoreLogo ?? this.printStoreLogo,
      language: language ?? this.language,
      connectionMode: connectionMode ?? this.connectionMode,
      directTransport: directTransport ?? this.directTransport,
      directDeviceId: clearDirectDevice ? null : (directDeviceId ?? this.directDeviceId),
      directDeviceName: clearDirectDevice ? null : (directDeviceName ?? this.directDeviceName),
      networkHost: networkHost ?? this.networkHost,
      networkPort: networkPort ?? this.networkPort,
      printerUrl: clearPrinter ? null : (printerUrl ?? this.printerUrl),
      printerName: clearPrinter ? null : (printerName ?? this.printerName),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'paperWidth': paperWidth,
        'customPaperWidthMm': customPaperWidthMm,
        'fontSize': fontSize,
        'copyCount': copyCount,
        'kitchenCopy': kitchenCopy,
        'cashierCopy': cashierCopy,
        'showOrderNumber': showOrderNumber,
        'showCustomer': showCustomer,
        'showItems': showItems,
        'showExtras': showExtras,
        'showNotes': showNotes,
        'showPrices': showPrices,
        'showAddress': showAddress,
        'hideKitchenPrices': hideKitchenPrices,
        'autoPrintAfterAccept': autoPrintAfterAccept,
        'autoCut': autoCut,
        'beep': beep,
        'printStoreName': printStoreName,
        'printStoreLogo': printStoreLogo,
        'language': language,
        'connectionMode': connectionMode,
        'directTransport': directTransport,
        'directDeviceId': directDeviceId,
        'directDeviceName': directDeviceName,
        'networkHost': networkHost,
        'networkPort': networkPort,
        'printerUrl': printerUrl,
        'printerName': printerName,
      };

  factory ReceiptPrinterSettings.fromJson(Map<String, dynamic> json) {
    bool b(String key, bool fallback) => json[key] is bool ? json[key] as bool : fallback;
    return ReceiptPrinterSettings(
      enabled: b('enabled', true),
      paperWidth: json['paperWidth']?.toString() ?? '80',
      customPaperWidthMm: (json['customPaperWidthMm'] as num?)?.toDouble() ?? 80,
      fontSize: json['fontSize']?.toString() ?? 'medium',
      copyCount: ((json['copyCount'] as num?)?.toInt() ?? 1).clamp(1, 3),
      kitchenCopy: b('kitchenCopy', true),
      cashierCopy: b('cashierCopy', false),
      showOrderNumber: b('showOrderNumber', true),
      showCustomer: b('showCustomer', true),
      showItems: b('showItems', true),
      showExtras: b('showExtras', true),
      showNotes: b('showNotes', true),
      showPrices: b('showPrices', true),
      showAddress: b('showAddress', true),
      hideKitchenPrices: b('hideKitchenPrices', true),
      autoPrintAfterAccept: b('autoPrintAfterAccept', false),
      autoCut: b('autoCut', true),
      beep: b('beep', false),
      printStoreName: b('printStoreName', true),
      printStoreLogo: b('printStoreLogo', false),
      language: json['language']?.toString() ?? 'store',
      connectionMode: json['connectionMode']?.toString() ?? 'system',
      directTransport: json['directTransport']?.toString() ?? 'bluetooth',
      directDeviceId: json['directDeviceId']?.toString(),
      directDeviceName: json['directDeviceName']?.toString(),
      networkHost: json['networkHost']?.toString(),
      networkPort: (json['networkPort'] as num?)?.toInt() ?? 9100,
      printerUrl: json['printerUrl']?.toString(),
      printerName: json['printerName']?.toString(),
    );
  }
}

class ReceiptPrintResult {
  const ReceiptPrintResult({required this.success, required this.message});
  final bool success;
  final String message;
}

class ReceiptPrinterService {
  ReceiptPrinterService._();
  static final ReceiptPrinterService instance = ReceiptPrinterService._();

  // Printer preferences are intentionally scoped to the signed-in store account.
  // The database guarantees one store per owner account, so using the authenticated
  // user id keeps printer/receipt configuration isolated between stores even when
  // multiple merchants use the same Android device.
  static const _legacySettingsKey = 'hala_partner_receipt_printer_settings_v1';
  static const _settingsKeyPrefix = 'hala_partner_receipt_printer_settings_v2_';
  static const _printStatePrefix = 'hala_partner_order_print_state_';

  String _settingsKeyForCurrentAccount() {
    final userId = Supabase.instance.client.auth.currentUser?.id.trim();
    if (userId == null || userId.isEmpty) return '${_settingsKeyPrefix}signed_out';
    return '$_settingsKeyPrefix$userId';
  }

  Future<ReceiptPrinterSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = _settingsKeyForCurrentAccount();
    var raw = prefs.getString(scopedKey);

    // One-time compatibility migration from Stage 208 and earlier. This preserves
    // the current merchant's printer configuration, then all future writes stay
    // isolated under that merchant account.
    if ((raw == null || raw.isEmpty) && scopedKey != '${_settingsKeyPrefix}signed_out') {
      final legacy = prefs.getString(_legacySettingsKey);
      if (legacy != null && legacy.isNotEmpty) {
        raw = legacy;
        await prefs.setString(scopedKey, legacy);
      }
    }

    if (raw == null || raw.isEmpty) return const ReceiptPrinterSettings();
    try {
      return ReceiptPrinterSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const ReceiptPrinterSettings();
    }
  }

  Future<void> saveSettings(ReceiptPrinterSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _settingsKeyForCurrentAccount(),
      jsonEncode(settings.toJson()),
    );
  }

  Future<List<Printer>> listPrinters() async {
    try {
      final printers = await Printing.listPrinters();
      printers.sort((a, b) {
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return printers;
    } catch (_) {
      return const <Printer>[];
    }
  }

  Future<Printer?> selectedPrinter(ReceiptPrinterSettings settings) async {
    final printers = await listPrinters();
    if (printers.isEmpty) return null;
    for (final printer in printers) {
      if (settings.printerUrl != null && printer.url == settings.printerUrl) {
        return printer;
      }
    }
    for (final printer in printers) {
      if (settings.printerName != null && printer.name == settings.printerName) {
        return printer;
      }
    }
    // Some Android print services recreate the printer URL between sessions.
    // When that happens, prefer the current system default (or the only printer)
    // so one-tap printing can still be attempted before opening the print dialog.
    for (final printer in printers) {
      if (printer.isDefault) return printer;
    }
    if (printers.length == 1) return printers.first;
    return null;
  }

  Future<ReceiptPrintResult> testConnection() async {
    final settings = await loadSettings();
    if (!settings.enabled) {
      return const ReceiptPrintResult(success: false, message: 'فعّل الطباعة أولًا');
    }
    if (settings.usesDirectPrinter) {
      final result = await DirectThermalPrinterService.instance.testConnection(
        transport: settings.directTransport,
        deviceId: settings.directDeviceId,
        host: settings.networkHost,
        port: settings.networkPort,
      );
      return ReceiptPrintResult(success: result.success, message: result.message);
    }
    final printer = await selectedPrinter(settings);
    if (printer == null) {
      return const ReceiptPrintResult(
        success: false,
        message: 'اختر طابعة افتراضية من الإعدادات أولًا',
      );
    }
    return ReceiptPrintResult(
      success: true,
      message: 'الطابعة الافتراضية متاحة: ${printer.name}',
    );
  }

  Future<Map<String, dynamic>?> getLastPrintState(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_printStatePrefix$orderId');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _setPrintState(
    String orderId, {
    required bool success,
    required String message,
  }) async {
    if (orderId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_printStatePrefix$orderId',
      jsonEncode({
        'success': success,
        'message': message,
        'printedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<ReceiptPrintResult> printOrder({
    required Map<String, dynamic> order,
    required Map<String, dynamic>? store,
    required String appLanguage,
    bool allowPrinterDialog = true,
    bool testPrint = false,
  }) async {
    final settings = await loadSettings();
    final orderId = order['id']?.toString() ?? '';
    if (!settings.enabled) {
      const result = ReceiptPrintResult(success: false, message: 'الطباعة معطلة من الإعدادات');
      await _setPrintState(orderId, success: false, message: result.message);
      return result;
    }
    if (!settings.kitchenCopy && !settings.cashierCopy) {
      const result = ReceiptPrintResult(success: false, message: 'اختر نسخة المطبخ أو الكاشير من إعدادات الطابعة');
      await _setPrintState(orderId, success: false, message: result.message);
      return result;
    }

    try {
      final bytes = await _buildReceiptPdf(
        order: order,
        store: store,
        settings: settings,
        appLanguage: appLanguage,
        testPrint: testPrint,
      );
      bool printed = false;
      String message = 'تعذرت الطباعة';
      final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

      // Keep every existing Android direct-thermal path unchanged. On iPhone/iPad,
      // use Apple's native system print sheet (AirPrint / installed printer support)
      // for manual printing from the order screen. iOS intentionally does not use
      // the Android ESC/POS MethodChannel transports.
      if (settings.usesDirectPrinter && !isIOS) {
        final direct = await DirectThermalPrinterService.instance.printPdf(
          pdfBytes: bytes,
          transport: settings.directTransport,
          deviceId: settings.directDeviceId,
          host: settings.networkHost,
          port: settings.networkPort,
          paperWidthMm: settings.effectivePaperWidthMm,
          autoCut: settings.autoCut,
          beep: settings.beep,
        );
        printed = direct.success;
        message = testPrint && direct.success ? 'تم إرسال صفحة الاختبار للطابعة الحرارية مباشرة' : direct.message;
      } else if (isIOS) {
        // On iOS we deliberately require the user to press Print and choose/confirm
        // the printer in the native print sheet. This is safer than trying to mimic
        // Android background/silent thermal printing and works with AirPrint-capable
        // printers and printer support exposed by iOS.
        if (!allowPrinterDialog) {
          printed = false;
          message = 'على iPhone وiPad استخدم زر طباعة داخل الطلب لاختيار الطابعة من نافذة iOS.';
        } else {
          try {
            printed = await Printing.layoutPdf(
              onLayout: (_) async => bytes,
              name: testPrint ? 'Hala Talab Test' : 'Hala Talab Order',
            );
            message = printed
                ? (testPrint
                    ? 'تم إرسال صفحة الاختبار عبر طباعة iPhone/iPad'
                    : 'تم إرسال الطلب عبر طباعة iPhone/iPad')
                : 'تم إلغاء نافذة الطباعة قبل إرسال الورقة';
          } catch (error) {
            if (kDebugMode) debugPrint('iOS system print dialog failed: $error');
            message = 'تعذرت الطباعة عبر خدمة الطباعة في iPhone/iPad: $error';
          }
        }
      } else {
        // System printing supports general printers (inkjet/laser/thermal drivers).
        // Try the saved printer first. If Android/driver refuses silent direct
        // printing, manual/test printing can safely fall back to the native
        // print dialog instead of reporting a USB/ESC-POS failure.
        final printer = await selectedPrinter(settings);
        printed = false;
        String? directFailureMessage;

        if (printer != null) {
          try {
            printed = await Printing.directPrintPdf(
              printer: printer,
              onLayout: (_) async => bytes,
              name: testPrint ? 'Hala Talab Test' : 'Hala Talab Order',
            );
          } catch (error) {
            directFailureMessage = error.toString();
            if (kDebugMode) {
              debugPrint('Direct system print failed, fallback may be used: $error');
            }
          }
        }

        if (!printed && allowPrinterDialog) {
          try {
            printed = await Printing.layoutPdf(
              onLayout: (_) async => bytes,
              name: testPrint ? 'Hala Talab Test' : 'Hala Talab Order',
            );
            message = printed
                ? (testPrint
                    ? 'تم إرسال صفحة الاختبار عبر خدمة الطباعة في الجهاز'
                    : 'تم إرسال الطلب عبر خدمة الطباعة في الجهاز')
                : 'تم إلغاء نافذة الطباعة قبل إرسال الورقة';
          } catch (error) {
            if (kDebugMode) debugPrint('System print dialog failed: $error');
            message = 'تعذرت الطباعة عبر خدمة الطباعة في الجهاز: $error';
          }
        } else if (printed) {
          message = testPrint
              ? 'تم إرسال صفحة الاختبار للطابعة الافتراضية'
              : 'تم إرسال الطلب للطابعة الافتراضية';
        } else if (printer == null) {
          message = allowPrinterDialog
              ? 'اختر طابعة من نافذة الطباعة في الجهاز'
              : 'لم يتم اختيار طابعة افتراضية؛ استخدم زر الطباعة اليدوي لاختيار الطابعة';
        } else {
          message = directFailureMessage == null
              ? 'تعذرت الطباعة المباشرة على ${printer.name}. استخدم زر الطباعة اليدوي لفتح خدمة الطباعة في الجهاز.'
              : 'تعذرت الطباعة المباشرة على ${printer.name}. استخدم زر الطباعة اليدوي لفتح خدمة الطباعة في الجهاز.';
        }
      }
      await _setPrintState(orderId, success: printed, message: message);
      return ReceiptPrintResult(success: printed, message: message);
    } catch (error, stack) {
      if (kDebugMode) debugPrint('Receipt printing failed: $error\n$stack');
      final message = 'فشلت الطباعة: $error';
      await _setPrintState(orderId, success: false, message: message);
      return ReceiptPrintResult(success: false, message: message);
    }
  }

  Future<Uint8List> _buildReceiptPdf({
    required Map<String, dynamic> order,
    required Map<String, dynamic>? store,
    required ReceiptPrinterSettings settings,
    required String appLanguage,
    required bool testPrint,
  }) async {
    final document = pw.Document();
    final language = settings.language == 'store' ? appLanguage : settings.language;
    final isArabicLike = language != 'en';
    pw.Font? arabicFont;
    pw.Font? latinFont;
    try {
      arabicFont = await PdfGoogleFonts.notoSansArabicRegular();
    } catch (_) {
      arabicFont = null;
    }
    try {
      latinFont = await PdfGoogleFonts.notoSansRegular();
    } catch (_) {
      latinFont = null;
    }
    // Keep Arabic/Kurdish shaping while also supporting English product names,
    // order codes and mixed-language receipts without square placeholder glyphs.
    final baseFont = isArabicLike
        ? (arabicFont ?? latinFont ?? pw.Font.helvetica())
        : (latinFont ?? arabicFont ?? pw.Font.helvetica());
    final fallbackFonts = <pw.Font>[
      if (arabicFont != null && !identical(arabicFont, baseFont)) arabicFont,
      if (latinFont != null && !identical(latinFont, baseFont)) latinFont,
    ];
    pw.ImageProvider? storeLogo;
    final logoUrl = store?['logo_url']?.toString().trim() ?? '';
    if (settings.printStoreLogo && logoUrl.isNotEmpty) {
      try {
        storeLogo = await networkImage(logoUrl);
      } catch (_) {
        storeLogo = null;
      }
    }
    pw.ImageProvider? halaReceiptLogo;
    try {
      final logoBytes = await rootBundle.load('assets/images/hala_receipt_logo_bw.png');
      halaReceiptLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {
      halaReceiptLogo = null;
    }
    final fontSize = switch (settings.fontSize) {
      'small' => 8.5,
      'large' => 12.0,
      _ => 10.0,
    };
    final widthMm = settings.effectivePaperWidthMm;
    final items = List<Map<String, dynamic>>.from(
      order['order_items'] as List? ?? const [],
    );
    final copiesPerTemplate = settings.copyCount.clamp(1, 3);
    final templates = <String>[
      if (settings.kitchenCopy) 'kitchen',
      if (settings.cashierCopy) 'cashier',
    ];

    for (final template in templates) {
      for (var copy = 0; copy < copiesPerTemplate; copy++) {
        final estimatedMm = 58 + (items.length * 13) +
            (settings.showAddress ? 10 : 0) +
            (settings.showNotes ? 12 : 0) +
            (template == 'cashier' ? 18 : 8);

        if (settings.usesDirectPrinter) {
          // Thermal roll: keep a readable font and let the receipt grow vertically.
          // Do not shrink long orders just to force them onto a fixed sheet.
          final pageHeightMm = estimatedMm.clamp(80, 700).toDouble();
          final format = PdfPageFormat(
            widthMm * PdfPageFormat.mm,
            pageHeightMm * PdfPageFormat.mm,
            marginAll: 2.5 * PdfPageFormat.mm,
          );
          document.addPage(
            pw.Page(
              pageFormat: format,
              theme: pw.ThemeData.withFont(base: baseFont, bold: baseFont),
              build: (context) => pw.Directionality(
                textDirection: isArabicLike ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                child: _receiptBody(
                  order: order,
                  store: store,
                  settings: settings,
                  template: template,
                  fontSize: fontSize,
                  testPrint: testPrint,
                  copyIndex: copy + 1,
                  storeLogo: storeLogo,
                  halaReceiptLogo: halaReceiptLogo,
                  language: language,
                  fallbackFonts: fallbackFonts,
                ),
              ),
            ),
          );
        } else {
          // General Android print service / fixed-sheet printers:
          // paginate long orders instead of creating one extremely tall PDF page.
          // A very tall page gets scaled down by drivers such as Canon/Epson,
          // which makes the receipt text tiny. 80x140 mm stays readable and can
          // expand to page 2, 3, ... automatically when the order is long.
          final fixedPageHeightMm = widthMm <= 80 ? 140.0 : 190.0;
          final format = PdfPageFormat(
            widthMm * PdfPageFormat.mm,
            fixedPageHeightMm * PdfPageFormat.mm,
          );
          document.addPage(
            pw.MultiPage(
              pageFormat: format,
              margin: pw.EdgeInsets.all(3 * PdfPageFormat.mm),
              theme: pw.ThemeData.withFont(base: baseFont, bold: baseFont),
              maxPages: 30,
              build: (context) => _receiptWidgets(
                order: order,
                store: store,
                settings: settings,
                template: template,
                fontSize: fontSize,
                testPrint: testPrint,
                copyIndex: copy + 1,
                storeLogo: storeLogo,
                halaReceiptLogo: halaReceiptLogo,
                language: language,
                fallbackFonts: fallbackFonts,
              )
                  .map(
                    (widget) => pw.Directionality(
                      textDirection:
                          isArabicLike ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                      child: widget,
                    ),
                  )
                  .toList(),
            ),
          );
        }
      }
    }
    return document.save();
  }

  List<pw.Widget> _receiptWidgets({
    required Map<String, dynamic> order,
    required Map<String, dynamic>? store,
    required ReceiptPrinterSettings settings,
    required String template,
    required double fontSize,
    required bool testPrint,
    required int copyIndex,
    required pw.ImageProvider? storeLogo,
    required pw.ImageProvider? halaReceiptLogo,
    required String language,
    required List<pw.Font> fallbackFonts,
  }) {
    final items = List<Map<String, dynamic>>.from(
      order['order_items'] as List? ?? const [],
    );
    final orderId = order['id']?.toString() ?? '';
    final number = _cleanReceiptText(order['order_number']?.toString() ??
        (orderId.length >= 6 ? orderId.substring(0, 6) : orderId));
    final storeName = _cleanReceiptText(store?['name']?.toString().trim() ?? 'هلا طلب');
    final customer = _cleanReceiptText((order['customer_name'] ?? '-').toString());
    final address = _cleanReceiptText((order['delivery_address'] ?? '-').toString());
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final note = _cleanReceiptText(_firstText(order, const ['notes', 'note', 'customer_note', 'order_note']));
    final created = DateTime.tryParse(order['created_at']?.toString() ?? '')?.toLocal();
    final isKitchen = template == 'kitchen';
    final copiesPerTemplate = settings.copyCount.clamp(1, 3);
    String tr(String ar, String en, String ku) => language == 'en' ? en : (language == 'ku' ? ku : ar);
    final showPrices = settings.showPrices && !(isKitchen && settings.hideKitchenPrices);
    final lineColor = PdfColors.grey600;

    pw.Widget text(String value, {double? size, bool bold = false, pw.TextAlign? align}) =>
        pw.Text(
          value,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: size ?? fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            fontFallback: fallbackFonts,
          ),
        );

    final rows = <pw.Widget>[];
    final headerLogoWidthMm = settings.effectivePaperWidthMm <= 58 ? 16.0 : 20.0;

    rows.add(
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (halaReceiptLogo != null)
                pw.Container(
                  width: headerLogoWidthMm * PdfPageFormat.mm,
                  height: headerLogoWidthMm * PdfPageFormat.mm,
                  child: pw.Image(halaReceiptLogo, fit: pw.BoxFit.contain),
                )
              else
                pw.Container(
                  width: headerLogoWidthMm * PdfPageFormat.mm,
                  height: headerLogoWidthMm * PdfPageFormat.mm,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1),
                    shape: pw.BoxShape.circle,
                  ),
                  child: text('HT', size: fontSize + 1, bold: true, align: pw.TextAlign.center),
                ),
              pw.SizedBox(height: 1.2 * PdfPageFormat.mm),
              text(language == 'en' ? 'Hala Talab' : 'هلا طلب', size: fontSize + 0.3, bold: true, align: pw.TextAlign.center),
            ],
          ),
          pw.SizedBox(width: 2.5 * PdfPageFormat.mm),
          pw.Container(width: 0.5 * PdfPageFormat.mm, height: 18 * PdfPageFormat.mm, color: lineColor),
          pw.SizedBox(width: 2.5 * PdfPageFormat.mm),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                if (storeLogo != null)
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 8 * PdfPageFormat.mm,
                        height: 8 * PdfPageFormat.mm,
                        child: pw.Image(storeLogo, fit: pw.BoxFit.contain),
                      ),
                      pw.SizedBox(width: 2 * PdfPageFormat.mm),
                      pw.Expanded(
                        child: text(
                          settings.printStoreName ? storeName : (language == 'en' ? 'Store' : 'المتجر'),
                          size: fontSize + 3,
                          bold: true,
                        ),
                      ),
                    ],
                  )
                else
                  text(
                    settings.printStoreName ? storeName : (language == 'en' ? 'Store' : 'المتجر'),
                    size: fontSize + 3,
                    bold: true,
                  ),
                pw.SizedBox(height: 1.1 * PdfPageFormat.mm),
                text(
                  testPrint
                      ? tr('اختبار طباعة هلا طلب', 'Hala Talab print test', 'تاقیکردنەوەی چاپی هەلا تەلەب')
                      : (isKitchen
                          ? tr('نسخة المطبخ', 'Kitchen copy', 'کۆپی چێشتخانە')
                          : tr('نسخة الكاشير', 'Cashier copy', 'کۆپی کاشێر')),
                  size: fontSize + 2,
                  bold: false,
                ),
                if (copiesPerTemplate > 1)
                  text('${tr('نسخة', 'Copy', 'کۆپی')} $copyIndex', size: fontSize - 0.2),
              ],
            ),
          ),
        ],
      ),
    );
    rows.add(pw.SizedBox(height: 2 * PdfPageFormat.mm));
    rows.add(pw.Divider(color: lineColor));
    if (settings.showOrderNumber) {
      rows.add(text('${tr('رقم الطلب', 'Order', 'ژمارەی داواکاری')} $number', size: fontSize + 3, bold: true, align: pw.TextAlign.center));
    }
    if (created != null) {
      rows.add(text('${created.year}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')}  ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}', align: pw.TextAlign.center));
    }
    if (settings.showCustomer) rows.add(_receiptLabelValue(tr('الزبون', 'Customer', 'کڕیار'), customer, text));
    if (settings.showAddress && address.trim().isNotEmpty && address != '-') {
      rows.add(_receiptLabelValue(tr('العنوان', 'Address', 'ناونیشان'), address, text));
    }
    rows.add(pw.Divider(color: lineColor));

    if (settings.showItems) {
      for (final item in items) {
        final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
        final name = _cleanReceiptText(orderItemDisplayName(item));
        final price = ((item['unit_price'] ?? item['price']) as num?)?.toDouble() ?? 0;
        rows.add(
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Keep the line simple and glyph-safe: quantity + product name,
              // without x/× separators that some printer fonts render as squares.
              pw.Expanded(child: text('$quantity  $name', size: fontSize + 1, bold: true)),
              if (showPrices) text('${(price * quantity).toStringAsFixed(0)} د.ع', bold: true),
            ],
          ),
        );
        if (settings.showExtras) {
          final extras = _cleanReceiptText(_itemExtras(item));
          if (extras.isNotEmpty) {
            rows.add(pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2, bottom: 2),
              child: text('${tr('الإضافات', 'Extras', 'زیادکراوەکان')}: $extras', size: fontSize - 1),
            ));
          }
        }
        if (settings.showNotes) {
          final itemNote = _cleanReceiptText(_firstText(item, const ['notes', 'note', 'special_instructions']));
          if (itemNote.isNotEmpty) {
            rows.add(text('${tr('ملاحظة', 'Note', 'تێبینی')}: $itemNote', size: fontSize - 1, bold: true));
          }
        }
        rows.add(pw.SizedBox(height: 5));
      }
    }

    if (settings.showNotes && note.isNotEmpty) {
      rows.add(pw.Divider(color: lineColor));
      rows.add(text('${tr('ملاحظة الطلب', 'Order note', 'تێبینی داواکاری')}: $note', size: fontSize + 1, bold: true));
    }
    if (!isKitchen && showPrices) {
      rows.add(pw.Divider(color: lineColor));
      rows.add(_receiptLabelValue(tr('الإجمالي', 'Total', 'کۆی گشتی'), '${total.toStringAsFixed(0)} د.ع', text, bold: true));
    }

    return rows;
  }

  pw.Widget _receiptBody({
    required Map<String, dynamic> order,
    required Map<String, dynamic>? store,
    required ReceiptPrinterSettings settings,
    required String template,
    required double fontSize,
    required bool testPrint,
    required int copyIndex,
    required pw.ImageProvider? storeLogo,
    required pw.ImageProvider? halaReceiptLogo,
    required String language,
    required List<pw.Font> fallbackFonts,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: _receiptWidgets(
        order: order,
        store: store,
        settings: settings,
        template: template,
        fontSize: fontSize,
        testPrint: testPrint,
        copyIndex: copyIndex,
        storeLogo: storeLogo,
        halaReceiptLogo: halaReceiptLogo,
        language: language,
        fallbackFonts: fallbackFonts,
      ),
    );
  }

  pw.Widget _receiptLabelValue(
    String label,
    String value,
    pw.Widget Function(String, {double? size, bool bold, pw.TextAlign? align}) text, {
    bool bold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          text('$label:', bold: true),
          pw.SizedBox(width: 4),
          pw.Expanded(child: text(value, bold: bold)),
        ],
      ),
    );
  }

  String _cleanReceiptText(String value) {
    return value
        .replaceAll('\uFFFD', '')
        .replaceAll('□', '')
        .replaceAll('×', ' ')
        .replaceAll('✕', ' ')
        .replaceAll('•', '-')
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _firstText(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value != 'null') return value;
    }
    return '';
  }

  String _itemExtras(Map<String, dynamic> item) {
    for (final key in const ['extras', 'additions', 'options', 'selected_options', 'variants']) {
      final raw = item[key];
      if (raw is List && raw.isNotEmpty) {
        return raw.map((e) {
          if (e is Map) return (e['name'] ?? e['title'] ?? e['label'] ?? e).toString();
          return e.toString();
        }).join('، ');
      }
      if (raw is Map && raw.isNotEmpty) {
        return raw.entries.map((e) => '${e.key}: ${e.value}').join('، ');
      }
      if (raw != null && raw.toString().trim().isNotEmpty) return raw.toString();
    }
    return '';
  }
}
