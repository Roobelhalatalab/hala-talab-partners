# Hala Talab Partners architecture

The project is organized by responsibility while preserving the existing Supabase contracts and UI behavior.

- `lib/main.dart`: Flutter/Supabase bootstrap only.
- `lib/app/`: application shell and auth gate.
- `lib/core/`: colors, theme, localization and Supabase configuration.
- `lib/models/`: shared domain types.
- `lib/services/`: authentication/account and shared service integration.
- `lib/repositories/`: feature data-access boundaries for orders, products, offers and reports.
- `lib/screens/auth/`: welcome/language, login and signup flows split into Dart parts.
- `lib/screens/dashboard/`: dashboard shell/navigation, notifications, orders, products/catalog, offers, reports, settings/profile, More/support, and store setup/overview.
- `lib/widgets/`: reserved for reusable cross-feature widgets as the UI grows.

## Stage 53 cleanup

- Removed the unused `cupertino_icons` dependency.
- Removed the unused `AppBreakpoints` foundation file.
- Split the remaining large auth file into focused parts without changing public APIs.
- Split store setup/overview out of the dashboard entry file.
- Kept Supabase schema, realtime, storage, localization and UI behavior unchanged.


## Stage 54
- `repositories/store_operations_repository.dart`: store location, fulfilment and weekly schedule persistence.
- `screens/dashboard/store_operations_settings.dart`: polished restaurant operations settings UI.


## Stage 55
Meal Management remains isolated in `lib/screens/dashboard/products_management.dart`; product persistence and add-on associations are handled by `lib/repositories/products_repository.dart`.
