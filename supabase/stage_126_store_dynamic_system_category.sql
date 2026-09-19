-- Hala Talab Partners Stage 126
-- Link each business account/store to the admin-managed public.system_categories row.

alter table public.partner_profiles
  add column if not exists system_category_id uuid references public.system_categories(id) on delete set null;

alter table public.stores
  add column if not exists system_category_id uuid references public.system_categories(id) on delete set null;

create index if not exists partner_profiles_system_category_id_idx
  on public.partner_profiles(system_category_id);
create index if not exists stores_system_category_id_idx
  on public.stores(system_category_id);

-- business_type remains only as a legacy product-form hint. Dynamic category identity is system_category_id.
alter table public.partner_profiles
  drop constraint if exists partner_profiles_business_type_check;

-- Keep the auth trigger compatible with OTP metadata and persist the selected admin category.
create or replace function public.handle_new_partner_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category_id uuid;
begin
  begin
    v_category_id := nullif(new.raw_user_meta_data ->> 'system_category_id','')::uuid;
  exception when others then
    v_category_id := null;
  end;

  insert into public.partner_profiles (
    id, full_name, phone, email, role, business_type, system_category_id
  ) values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name',''),
    nullif(new.raw_user_meta_data ->> 'phone',''),
    new.email,
    coalesce(nullif(new.raw_user_meta_data ->> 'role',''),'business'),
    nullif(new.raw_user_meta_data ->> 'business_type',''),
    v_category_id
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    phone = excluded.phone,
    email = excluded.email,
    business_type = coalesce(excluded.business_type, public.partner_profiles.business_type),
    system_category_id = coalesce(excluded.system_category_id, public.partner_profiles.system_category_id),
    updated_at = now();
  return new;
end;
$$;

-- Backfill the original eight categories for existing business profiles/stores when possible.
update public.partner_profiles p
set system_category_id = c.id
from public.system_categories c
where p.role='business'
  and p.system_category_id is null
  and c.category_key = case p.business_type
    when 'restaurant' then 'restaurants'
    when 'grocery' then 'grocery'
    when 'sweets' then 'desserts'
    when 'pharmacy' then 'pharmacies'
    when 'cafe' then 'cafes'
    when 'hookah' then 'hookah'
    when 'beverages' then 'beverages'
    when 'flowers' then 'flowers'
    else null end;

update public.stores s
set system_category_id = p.system_category_id
from public.partner_profiles p
where s.owner_id=p.id
  and s.system_category_id is null
  and p.system_category_id is not null;

select
  'store_dynamic_category_ready' as check_name,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='system_category_id') as stores_ready,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='partner_profiles' and column_name='system_category_id') as profiles_ready;
