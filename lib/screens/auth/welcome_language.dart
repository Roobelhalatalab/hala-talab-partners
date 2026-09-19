part of 'auth_flow.dart';

class PartnerRoleSelectionScreen extends StatelessWidget {
  const PartnerRoleSelectionScreen({
    required this.currentLocale,
    required this.onLocaleChanged,
    super.key,
  });

  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;

  void _openSignUp(BuildContext context, PartnerRole role) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PartnerSignUpScreen(
          initialRole: role,
          currentLocale: currentLocale,
          onLocaleChanged: onLocaleChanged,
        ),
      ),
    );
  }

  void _openRole(BuildContext context, PartnerRole role) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PartnerLoginScreen(
          initialRole: role,
          currentLocale: currentLocale,
          onLocaleChanged: onLocaleChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 920;
            if (desktop) {
              return _DesktopWelcomeLayout(
                currentLocale: currentLocale,
                onLocaleChanged: onLocaleChanged,
                onBusinessTap: () => _openRole(context, PartnerRole.business),
                onDriverTap: () => _openRole(context, PartnerRole.driver),
                onCreateAccount: () => _openSignUp(context, PartnerRole.business),
              );
            }
            return _MobileWelcomeLayout(
              currentLocale: currentLocale,
              onLocaleChanged: onLocaleChanged,
              horizontalPadding: constraints.maxWidth >= 600 ? 42 : 20,
              onBusinessTap: () => _openRole(context, PartnerRole.business),
              onDriverTap: () => _openRole(context, PartnerRole.driver),
              onCreateAccount: () => _openSignUp(context, PartnerRole.business),
            );
          },
        ),
      ),
    );
  }
}

class _DesktopWelcomeLayout extends StatelessWidget {
  const _DesktopWelcomeLayout({
    required this.currentLocale,
    required this.onLocaleChanged,
    required this.onBusinessTap,
    required this.onDriverTap,
    required this.onCreateAccount,
  });

  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final VoidCallback onBusinessTap;
  final VoidCallback onDriverTap;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _BackgroundDecoration()),
        PositionedDirectional(
          top: 16,
          end: 20,
          child: LanguageMenu(
            currentLocale: currentLocale,
            onChanged: onLocaleChanged,
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1260),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(34, 66, 34, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(flex: 11, child: _DesktopHeroPanel()),
                  const SizedBox(width: 34),
                  Expanded(
                    flex: 9,
                    child: SingleChildScrollView(
                      child: _EntryPanel(
                        compact: false,
                        onBusinessTap: onBusinessTap,
                        onDriverTap: onDriverTap,
                        onCreateAccount: onCreateAccount,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileWelcomeLayout extends StatelessWidget {
  const _MobileWelcomeLayout({
    required this.currentLocale,
    required this.onLocaleChanged,
    required this.horizontalPadding,
    required this.onBusinessTap,
    required this.onDriverTap,
    required this.onCreateAccount,
  });

  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final double horizontalPadding;
  final VoidCallback onBusinessTap;
  final VoidCallback onDriverTap;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _BackgroundDecoration()),
        Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              14,
              horizontalPadding,
              26,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Column(
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: LanguageMenu(
                      currentLocale: currentLocale,
                      onChanged: onLocaleChanged,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const _BrandHeader(compact: true),
                  const SizedBox(height: 18),
                  _EntryPanel(
                    compact: true,
                    showBrand: false,
                    onBusinessTap: onBusinessTap,
                    onDriverTap: onDriverTap,
                    onCreateAccount: onCreateAccount,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopHeroPanel extends StatelessWidget {
  const _DesktopHeroPanel();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFFFFAF6), Color(0xFFFFEFE2)],
        ),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: const Color(0xFFFFE0CC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16B94700),
            blurRadius: 34,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const _BrandHeader(compact: false),
            const SizedBox(height: 12),
            Text(
              s.t('heroLine'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.orangeDark,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Expanded(child: _HeroIllustration(maxHeight: 440)),
          ],
        ),
      ),
    );
  }
}

class _EntryPanel extends StatelessWidget {
  const _EntryPanel({
    required this.compact,
    required this.onBusinessTap,
    required this.onDriverTap,
    required this.onCreateAccount,
    this.showBrand = true,
  });

  final bool compact;
  final VoidCallback onBusinessTap;
  final VoidCallback onDriverTap;
  final VoidCallback onCreateAccount;
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBrand) ...[
          const _MiniBrand(),
          const SizedBox(height: 22),
        ],
        Text(
          s.t('welcome'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 27 : 34,
            height: 1.22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 50,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(50),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          s.t('chooseRole'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        _RoleCard(
          key: const Key('business-role-card'),
          title: s.t('businessLogin'),
          subtitle: s.t('businessSubtitle'),
          badge: s.t('allActivities'),
          icon: Icons.storefront_rounded,
          accent: AppColors.orange,
          background: const Color(0xFFFFF6EF),
          border: const Color(0xFFFFD5B8),
          onTap: onBusinessTap,
        ),
        const SizedBox(height: 14),
        _RoleCard(
          key: const Key('driver-role-card'),
          title: s.t('driverLogin'),
          subtitle: s.t('driverSubtitle'),
          badge: s.t('drivers'),
          icon: Icons.delivery_dining_rounded,
          accent: AppColors.green,
          background: const Color(0xFFF2FBF5),
          border: const Color(0xFFC8EAD2),
          onTap: onDriverTap,
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(s.t('noAccount'), style: const TextStyle(color: AppColors.muted)),
            TextButton(
              onPressed: onCreateAccount,
              child: Text(
                s.t('createAccount'),
                style: const TextStyle(
                  color: AppColors.orange,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        Text(
          s.t('version'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
        ),
      ],
    );
  }
}

class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.accent,
    required this.background,
    required this.border,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final Color accent;
  final Color background;
  final Color border;
  final VoidCallback onTap;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: hovered ? 1.012 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(24),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: widget.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: widget.border),
                boxShadow: [
                  BoxShadow(
                    color: widget.accent.withValues(alpha: hovered ? .16 : .08),
                    blurRadius: hovered ? 24 : 15,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(color: Color(0x13000000), blurRadius: 12),
                      ],
                    ),
                    child: Icon(widget.icon, color: widget.accent, size: 29),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            color: AppColors.muted,
                            height: 1.45,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            child: Text(
                              widget.badge,
                              style: TextStyle(
                                color: widget.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: widget.accent.withValues(alpha: .11),
                    child: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      color: widget.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Column(
      children: [
        Image.asset(
          'assets/images/hala_partner_logo.png',
          width: compact ? 66 : 78,
          height: compact ? 66 : 78,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 4),
        Text(
          s.t('appTitle'),
          style: TextStyle(
            fontSize: compact ? 31 : 38,
            fontWeight: FontWeight.w900,
            color: AppColors.orange,
          ),
        ),
        Text(
          s.t('appSubtitle'),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _MiniBrand extends StatelessWidget {
  const _MiniBrand();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/hala_partner_logo.png', width: 38, height: 38),
        const SizedBox(width: 9),
        Text(
          s.t('appTitle'),
          style: const TextStyle(
            color: AppColors.orange,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration({required this.maxHeight});

  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Image.asset(
          'assets/images/hala_partner_hero_final.jpg',
          width: double.infinity,
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
    );
  }
}

class _BackgroundDecoration extends StatelessWidget {
  const _BackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFFFFAF5), Color(0xFFFFFFFF)],
        ),
      ),
      child: const Stack(
        children: [
          PositionedDirectional(top: -80, start: -70, child: _SoftBubble(size: 210)),
          PositionedDirectional(bottom: -100, end: -80, child: _SoftBubble(size: 260)),
        ],
      ),
    );
  }
}

class _SoftBubble extends StatelessWidget {
  const _SoftBubble({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [Color(0x22FF7A2B), Color(0x00FF7A2B)],
        ),
      ),
    );
  }
}

class LanguageMenu extends StatelessWidget {
  const LanguageMenu({
    required this.currentLocale,
    required this.onChanged,
    super.key,
  });

  final Locale currentLocale;
  final ValueChanged<Locale> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final compact = MediaQuery.sizeOf(context).width < 390;
    return PopupMenuButton<String>(
      key: const Key('language-menu'),
      tooltip: s.t('chooseLanguage'),
      onSelected: (value) async {
        await WidgetsBinding.instance.endOfFrame;
        if (!context.mounted) return;
        onChanged(Locale(value));
      },
      itemBuilder: (_) => [
        _languageItem('ar', s.t('arabic')),
        _languageItem('ku', s.t('kurdish')),
        _languageItem('en', s.t('english')),
      ],
      child: Container(
        padding: compact
            ? const EdgeInsets.all(9)
            : const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 5)),
          ],
        ),
        child: compact
            ? const Icon(Icons.language_rounded, size: 20)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language_rounded, size: 20),
                  const SizedBox(width: 7),
                  Text(
                    _languageLabel(
                      AppLanguageScope.maybeOf(context)?.languageCode ??
                          currentLocale.languageCode,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                ],
              ),
      ),
    );
  }

  PopupMenuItem<String> _languageItem(String code, String label) {
    return PopupMenuItem(value: code, child: Text(label));
  }

  String _languageLabel(String code) {
    switch (code) {
      case 'ku':
        return 'کوردی';
      case 'en':
        return 'English';
      default:
        return 'العربية';
    }
  }
}
