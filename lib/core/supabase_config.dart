import 'build_config.dart';

class SupabaseConfig {
  SupabaseConfig._();

  static const url = BuildConfig.supabaseUrl;
  static const publishableKey = BuildConfig.supabasePublishableKey;
}
