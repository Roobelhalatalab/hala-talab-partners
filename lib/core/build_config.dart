class BuildConfig {
  BuildConfig._();

  // Public client-side build configuration.
  // dart-define values still override these defaults when supplied.
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://czoqxshblhgwanwsrudk.supabase.co',
  );

  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_O9snz4RgxKSLCl6XTmoWDw_1dCjzAli',
  );

  static const mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
   defaultValue: '',
  );
}
