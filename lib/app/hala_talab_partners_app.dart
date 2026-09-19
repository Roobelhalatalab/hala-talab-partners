import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_theme.dart';
import '../core/localization/app_strings.dart';
import '../models/partner_role.dart';
import '../screens/auth/auth_flow.dart';
import '../screens/dashboard/partner_dashboard.dart';
import '../services/auth_service.dart';


class HalaTalabPartnersApp extends StatefulWidget {
  const HalaTalabPartnersApp({super.key});

  @override
  State<HalaTalabPartnersApp> createState() => _HalaTalabPartnersAppState();
}

class _HalaTalabPartnersAppState extends State<HalaTalabPartnersApp> {
  final ValueNotifier<Locale> _localeNotifier = ValueNotifier<Locale>(const Locale('ar'));
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString('partner_language') ?? 'ar';
    if (!mounted) return;
    setState(() {
      _localeNotifier.value = AppStrings.supportedLocales.any((l) => l.languageCode == language)
          ? Locale(language)
          : const Locale('ar');
      _settingsLoaded = true;
    });
  }

  Future<void> _setLocale(Locale locale) async {
    final current = _localeNotifier.value;
    if (current.languageCode == locale.languageCode || !mounted) return;

    // Stage 179: language changes are intentionally decoupled from MaterialApp.
    // We only update the app-language notifier after persistence. This keeps
    // Navigator, AuthGate, realtime subscriptions and overlay routes alive and
    // avoids rebuilding the root localization stack during RTL/LTR switching.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('partner_language', locale.languageCode);
    } catch (error) {
      debugPrint('Could not persist partner language: $error');
    }

    if (!mounted || _localeNotifier.value.languageCode == locale.languageCode) return;
    _localeNotifier.value = Locale(locale.languageCode);
  }

  @override
  void dispose() {
    _localeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hala Talab Partners',
      // Stage 179: keep Flutter framework localizations stable. App text and
      // direction are driven by AppLanguageScope below, so switching language
      // does not rebuild MaterialApp/Navigator or tear down authenticated state.
      locale: const Locale('ar'),
      supportedLocales: AppStrings.materialSupportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final width = media.size.width;
        final systemScale = media.textScaler.scale(1.0);
        final widthFactor = width <= 360
            ? 0.92
            : width <= 400
                ? 0.95
                : width <= 480
                    ? 0.98
                    : 1.0;
        final effectiveScale =
            (systemScale * widthFactor).clamp(0.90, 1.15).toDouble();

        return ValueListenableBuilder<Locale>(
          valueListenable: _localeNotifier,
          builder: (context, appLocale, _) {
            final direction = AppStrings.isRtl(appLocale.languageCode)
                ? TextDirection.rtl
                : TextDirection.ltr;
            return ColoredBox(
              color: Colors.white,
              child: MediaQuery(
                data: media.copyWith(textScaler: TextScaler.linear(effectiveScale)),
                child: AppLanguageScope(
                  languageCode: appLocale.languageCode,
                  child: Directionality(
                    textDirection: direction,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
        );
      },
      home: ValueListenableBuilder<Locale>(
        valueListenable: _localeNotifier,
        builder: (context, appLocale, _) => AuthGate(
          currentLocale: appLocale,
          onLocaleChanged: _setLocale,
        ),
      ),
    );
  }
}


class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.currentLocale,
    required this.onLocaleChanged,
    super.key,
  });

  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authChanges;
  String? _validatedUserId;
  Future<String>? _roleFuture;
  int? _lockRevision;
  Future<bool>? _lockFuture;
  Future<String?>? _lockedRoleFuture;
  String? _lockedRoleUserId;

  @override
  void initState() {
    super.initState();
    _authChanges = Supabase.instance.client.auth.onAuthStateChange;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AuthService.instance.quickLockRevision,
      builder: (context, revision, _) {
        if (_lockRevision != revision || _lockFuture == null) {
          _lockRevision = revision;
          _lockFuture = AuthService.instance.isQuickLocked();
          _lockedRoleFuture = null;
          _lockedRoleUserId = null;
        }
        return StreamBuilder<AuthState>(
        stream: _authChanges,
        builder: (context, snapshot) {
          final session = snapshot.data?.session ??
              Supabase.instance.client.auth.currentSession;
          if (session != null) {
            return FutureBuilder<bool>(
              future: _lockFuture,
              builder: (context, lockSnapshot) {
                if (lockSnapshot.connectionState != ConnectionState.done) {
                  return const _AuthTransitionScreen();
                }
                if (lockSnapshot.data == true) {
                  final userId = session.user.id;
                  if (_lockedRoleUserId != userId || _lockedRoleFuture == null) {
                    _lockedRoleUserId = userId;
                    _lockedRoleFuture = AuthService.instance
                        .getActivePartnerRole()
                        .timeout(const Duration(seconds: 8), onTimeout: () => null);
                  }
                  return FutureBuilder<String?>(
                    future: _lockedRoleFuture,
                    builder: (context, roleSnapshot) {
                      if (roleSnapshot.connectionState != ConnectionState.done) {
                        return const _AuthTransitionScreen();
                      }
                      final role = roleSnapshot.data;
                      if (role == 'business' || role == 'driver') {
                        return PartnerLoginScreen(
                          initialRole: role == 'driver' ? PartnerRole.driver : PartnerRole.business,
                          currentLocale: widget.currentLocale,
                          onLocaleChanged: widget.onLocaleChanged,
                        );
                      }
                      return PartnerRoleSelectionScreen(
                        currentLocale: widget.currentLocale,
                        onLocaleChanged: widget.onLocaleChanged,
                      );
                    },
                  );
                }

                final userId = session.user.id;
                if (_validatedUserId != userId || _roleFuture == null) {
                  _validatedUserId = userId;
                  _roleFuture = AuthService.instance
                      .validateCurrentSessionRole()
                      .timeout(const Duration(seconds: 12));
                }
                return FutureBuilder<String>(
                  future: _roleFuture,
                  builder: (context, roleSnapshot) {
                    if (roleSnapshot.connectionState != ConnectionState.done) {
                      return const _AuthTransitionScreen();
                    }
                    if (roleSnapshot.hasError || roleSnapshot.data == null) {
                      debugPrint('Role validation failed: ${roleSnapshot.error}');
                      return PartnerRoleSelectionScreen(
                        currentLocale: widget.currentLocale,
                        onLocaleChanged: widget.onLocaleChanged,
                      );
                    }
                    return PartnerDashboardScreen(
                      currentLocale: widget.currentLocale,
                      onLocaleChanged: widget.onLocaleChanged,
                      activeRole: roleSnapshot.data,
                    );
                  },
                );
              },
            );
          }
          _validatedUserId = null;
          _roleFuture = null;
          _lockedRoleUserId = null;
          _lockedRoleFuture = null;
          return PartnerRoleSelectionScreen(
            currentLocale: widget.currentLocale,
            onLocaleChanged: widget.onLocaleChanged,
          );
        },
      );
      },
    );
  }
}



class _AuthTransitionScreen extends StatelessWidget {
  const _AuthTransitionScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFAFAFB),
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}
