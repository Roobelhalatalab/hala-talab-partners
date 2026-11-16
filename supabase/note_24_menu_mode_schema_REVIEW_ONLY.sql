-- Note 24: schema only. DO NOT RUN until customer RPC and checkout guards are updated together.
-- Default preserves all existing stores' separate per-shift menus.
ALTER TABLE public.stores
  ADD COLUMN IF NOT EXISTS menu_mode text NOT NULL DEFAULT 'different';
ALTER TABLE public.stores
  DROP CONSTRAINT IF EXISTS stores_menu_mode_check;
ALTER TABLE public.stores
  ADD CONSTRAINT stores_menu_mode_check CHECK (menu_mode IN ('unified', 'different'));
-- This is NOT a complete deployment: customer_store_shift_context and
-- checkout shift validation must honor menu_mode before enabling 'unified'.
