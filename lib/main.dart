import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/hala_talab_partners_app.dart';
import 'core/build_config.dart';
import 'core/supabase_config.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Stage 154 runtime safety net: keep unexpected widget failures local and
  // non-blocking during QA. The real exception remains in the debug console;
  // users never get a full-page technical/error message.
  ErrorWidget.builder = (details) {
    debugPrint('Hala Talab Partners widget error: ${details.exceptionAsString()}');
    debugPrintStack(stackTrace: details.stack);
    return const Material(
      color: Color(0xFFFAFAFB),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'تعذر عرض هذا الجزء مؤقتًا. ارجع وحاول مرة أخرى.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  };
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
  };
  const mapboxAccessToken = BuildConfig.mapboxAccessToken;
  final supportsMapbox = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (supportsMapbox && mapboxAccessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(mapboxAccessToken);
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  await PushNotificationService.instance.initialize();
  runApp(const HalaTalabPartnersApp());
}
