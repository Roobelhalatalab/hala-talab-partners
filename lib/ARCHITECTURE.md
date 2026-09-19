# Hala Talab Partners architecture

Stage 46 starts the safe modular refactor without changing app behavior or Supabase contracts.

- `core/`: app-wide configuration, theme, localization and layout constants.
- `models/`: domain types shared by features.
- `services/`: Supabase/Auth/Storage/Realtime integration.
- `repositories/`: data access orchestration (moved gradually in later stages).
- `screens/`: feature screens (moved gradually in later stages).
- `widgets/`: reusable UI components (moved gradually in later stages).

The refactor is intentionally incremental. Stage 46 moves only low-risk shared foundations.

## Stage 49
- `screens/dashboard/orders_management.dart`: complete store orders UI, realtime subscription, filters, cards and details.
- `repositories/orders_repository.dart`: order data-access boundary over the existing Supabase/AuthService methods.
- No database schema or behavioral changes.

## Stage 52
Dashboard settings/profile/help live in `screens/dashboard/settings_profile.dart`; More and operational shortcuts live in `screens/dashboard/more_support.dart`.


## Stage 54
- `repositories/store_operations_repository.dart`: store location, fulfilment and weekly schedule persistence.
- `screens/dashboard/store_operations_settings.dart`: polished restaurant operations settings UI.
