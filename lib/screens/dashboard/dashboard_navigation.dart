part of 'partner_dashboard.dart';

class _DashboardDesktopTopBar extends StatelessWidget {
  const _DashboardDesktopTopBar({
    required this.title,
    required this.storeName,
    required this.currentLocale,
    required this.onLocaleChanged,
    required this.unreadNotifications,
    required this.onNotifications,
  });

  final String title;
  final String storeName;
  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final int unreadNotifications;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      margin: const EdgeInsets.fromLTRB(0, 14, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9EBF0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(storeName, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          LanguageMenu(currentLocale: currentLocale, onChanged: onLocaleChanged),
          const SizedBox(width: 10),
          _DashboardNotificationBell(count: unreadNotifications, onPressed: onNotifications),
        ],
      ),
    );
  }
}

class _DashboardMobileTopBar extends StatelessWidget {
  const _DashboardMobileTopBar({
    required this.title,
    required this.currentLocale,
    required this.onLocaleChanged,
    required this.unreadNotifications,
    required this.onNotifications,
  });

  final String title;
  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final int unreadNotifications;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final veryNarrow = width < 350;
    return Container(
      constraints: BoxConstraints(minHeight: veryNarrow ? 58 : 62),
      padding: EdgeInsets.symmetric(horizontal: veryNarrow ? 8 : 14, vertical: veryNarrow ? 5 : 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EBF0))),
      ),
      child: Row(
        children: [
          Image.asset('assets/images/hala_partner_logo.png', width: veryNarrow ? 26 : 30, height: veryNarrow ? 26 : 30),
          SizedBox(width: veryNarrow ? 5 : 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('appTitle'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.orange, fontSize: veryNarrow ? 13 : 15, fontWeight: FontWeight.w900)),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: veryNarrow ? 9.5 : 10.5, color: AppColors.muted, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          LanguageMenu(currentLocale: currentLocale, onChanged: onLocaleChanged),
          SizedBox(width: veryNarrow ? 2 : 6),
          _DashboardNotificationBell(count: unreadNotifications, onPressed: onNotifications),
        ],
      ),
    );
  }
}

class _DashboardNotificationBell extends StatelessWidget {
  const _DashboardNotificationBell({required this.count, required this.onPressed});
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(14),
          child: IconButton(
            onPressed: onPressed,
            tooltip: s.t('storeNotificationsTitle'),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ),
        if (count > 0)
          PositionedDirectional(
            top: -4,
            end: -4,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, height: 1),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
