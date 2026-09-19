-- Hala Talab Partners - Driver Stage 15
-- End-to-end customer/store/driver integration bridge.
-- Safe to run more than once.
--
-- What this adds:
-- 1) A customer-only RPC that exposes the 4-digit delivery handoff code only
--    after the driver has actually picked up the order.
-- 2) A customer-only RPC for securely submitting/updating a driver rating for
--    a delivered order, deriving the driver/customer from the order itself.
-- 3) A compact customer delivery snapshot RPC for realtime/order-details UI.
-- 4) Realtime publication for driver notifications/reviews when available.
-- 5) Customer picked-up notification now tells the customer that the handoff
--    code is available in order details.

create extension if not exists pgcrypto;

alter table public.orders add column if not exists delivery_confirmation_code text;
alter table public.orders add column if not exists delivery_proof_path text;
alter table public.orders add column if not exists delivery_proof_method text;

create table if not exists public.driver_reviews (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid references auth.users(id) on delete set null,
  customer_name text,
  order_id uuid references public.orders(id) on delete set null,
  rating numeric(2,1) not null check (rating >= 1 and rating <= 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (order_id, customer_id)
);

alter table public.driver_reviews add column if not exists customer_name text;
create index if not exists driver_reviews_driver_created_idx
  on public.driver_reviews(driver_id, created_at desc);
create unique index if not exists driver_reviews_unique_customer_order
  on public.driver_reviews(order_id, customer_id)
  where order_id is not null and customer_id is not null;

alter table public.driver_reviews enable row level security;

drop policy if exists "driver_reviews_select_own_driver" on public.driver_reviews;
create policy "driver_reviews_select_own_driver"
on public.driver_reviews for select to authenticated
using (driver_id = auth.uid());

drop policy if exists "driver_reviews_customer_select_own" on public.driver_reviews;
create policy "driver_reviews_customer_select_own"
on public.driver_reviews for select to authenticated
using (customer_id = auth.uid());

-- Customer order snapshot. The handoff code is deliberately hidden until
-- picked_up. It remains visible after delivered so the customer can understand
-- how that delivery was confirmed, but it is never available to another user.
create or replace function public.get_my_order_delivery_snapshot(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_can_rate boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
    and customer_id = auth.uid();

  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  v_can_rate := v_order.status = 'delivered'
                and v_order.driver_id is not null;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_number', v_order.order_number,
    'status', v_order.status,
    'driver_id', v_order.driver_id,
    'delivery_confirmation_code',
      case
        when v_order.status in ('picked_up', 'delivered')
          then v_order.delivery_confirmation_code
        else null
      end,
    'show_delivery_code',
      (v_order.status in ('picked_up', 'delivered')
       and v_order.delivery_confirmation_code is not null),
    'delivery_proof_method',
      case when v_order.status = 'delivered' then v_order.delivery_proof_method else null end,
    'picked_up_at', v_order.picked_up_at,
    'delivered_at', v_order.delivered_at,
    'can_rate_driver', v_can_rate,
    'driver_review', (
      select jsonb_build_object(
        'rating', dr.rating,
        'comment', dr.comment,
        'created_at', dr.created_at
      )
      from public.driver_reviews dr
      where dr.order_id = v_order.id
        and dr.customer_id = auth.uid()
      order by dr.created_at desc
      limit 1
    )
  );
end;
$$;

revoke all on function public.get_my_order_delivery_snapshot(uuid) from public;
grant execute on function public.get_my_order_delivery_snapshot(uuid) to authenticated;

-- A smaller dedicated handoff RPC for the client order page.
create or replace function public.get_my_order_delivery_handoff_code(p_order_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select o.delivery_confirmation_code
    into v_code
  from public.orders o
  where o.id = p_order_id
    and o.customer_id = auth.uid()
    and o.driver_id is not null
    and o.status in ('picked_up', 'delivered');

  return v_code;
end;
$$;

revoke all on function public.get_my_order_delivery_handoff_code(uuid) from public;
grant execute on function public.get_my_order_delivery_handoff_code(uuid) to authenticated;

-- Secure customer-side driver rating. The caller does not choose driver_id or
-- customer_id; both are derived from the delivered order to prevent spoofing.
create or replace function public.submit_my_driver_review(
  p_order_id uuid,
  p_rating numeric,
  p_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_customer_name text;
  v_review public.driver_reviews%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception using message = 'Rating must be between 1 and 5', errcode = '22023';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
    and customer_id = auth.uid()
    and status = 'delivered'
    and driver_id is not null;

  if v_order.id is null then
    raise exception 'Only a delivered order with an assigned driver can be rated';
  end if;

  v_customer_name := coalesce(
    nullif(btrim(v_order.customer_name), ''),
    nullif(btrim((auth.jwt() -> 'user_metadata' ->> 'full_name')), ''),
    nullif(btrim((auth.jwt() -> 'user_metadata' ->> 'name')), '')
  );

  insert into public.driver_reviews(
    driver_id, customer_id, customer_name, order_id, rating, comment
  ) values (
    v_order.driver_id,
    auth.uid(),
    v_customer_name,
    v_order.id,
    round(p_rating::numeric, 1),
    nullif(btrim(p_comment), '')
  )
  on conflict (order_id, customer_id)
  do update set
    rating = excluded.rating,
    comment = excluded.comment,
    customer_name = coalesce(excluded.customer_name, public.driver_reviews.customer_name)
  returning * into v_review;

  return jsonb_build_object(
    'id', v_review.id,
    'order_id', v_review.order_id,
    'driver_id', v_review.driver_id,
    'rating', v_review.rating,
    'comment', v_review.comment,
    'created_at', v_review.created_at
  );
end;
$$;

revoke all on function public.submit_my_driver_review(uuid, numeric, text) from public;
grant execute on function public.submit_my_driver_review(uuid, numeric, text) to authenticated;

-- Keep the existing lifecycle notification behavior, but make the pickup
-- notification useful for the handoff-code flow.
create or replace function public.notify_customer_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  order_label text := coalesce(new.order_number::text, left(new.id::text, 8));
  notification_title text;
  notification_body text;
  notification_type text;
begin
  if old.status is not distinct from new.status or new.customer_id is null then
    return new;
  end if;

  case new.status
    when 'accepted' then
      notification_type := 'order_accepted';
      notification_title := 'تم قبول طلبك #' || order_label;
      notification_body := 'وافق المتجر على طلبك.';
    when 'preparing' then
      notification_type := 'order_preparing';
      notification_title := 'طلبك قيد التحضير #' || order_label;
      notification_body := 'بدأ المتجر بتجهيز طلبك.';
    when 'ready' then
      notification_type := 'order_ready';
      notification_title := 'طلبك جاهز #' || order_label;
      notification_body := 'أصبح طلبك جاهزًا للتسليم للسائق.';
    when 'assigned' then
      notification_type := 'driver_assigned';
      notification_title := 'تم تعيين سائق لطلبك #' || order_label;
      notification_body := 'سيتم استلام الطلب من المتجر قريبًا.';
    when 'picked_up' then
      notification_type := 'order_picked_up';
      notification_title := 'طلبك في الطريق #' || order_label;
      notification_body := 'استلم السائق طلبك من المتجر. رمز الاستلام متاح الآن داخل تفاصيل طلبك.';
    when 'delivered' then
      notification_type := 'order_delivered';
      notification_title := 'تم تسليم طلبك #' || order_label;
      notification_body := 'تم تسليم الطلب بنجاح. يمكنك الآن تقييم المتجر والمنتجات والسائق.';
    when 'rejected' then
      notification_type := 'order_rejected';
      notification_title := 'تعذر قبول طلبك #' || order_label;
      notification_body := 'اعتذر المتجر عن قبول الطلب.';
    when 'cancelled' then
      notification_type := 'order_cancelled';
      notification_title := 'تم إلغاء طلبك #' || order_label;
      notification_body := 'تم إلغاء الطلب.';
    else
      return new;
  end case;

  insert into public.customer_notifications(
    customer_id, order_id, type, title, body, data
  ) values (
    new.customer_id,
    new.id,
    notification_type,
    notification_title,
    notification_body,
    jsonb_build_object(
      'order_id', new.id,
      'order_number', new.order_number,
      'store_id', new.store_id,
      'driver_id', new.driver_id,
      'status', new.status,
      'delivery_code_available',
        (new.status = 'picked_up' and new.delivery_confirmation_code is not null)
    )
  );
  return new;
end;
$$;

-- Make realtime delivery lifecycle updates available where the tables exist.
do $$
begin
  if to_regclass('public.driver_notifications') is not null and not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'driver_notifications'
  ) then
    alter publication supabase_realtime add table public.driver_notifications;
  end if;

  if to_regclass('public.driver_reviews') is not null and not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'driver_reviews'
  ) then
    alter publication supabase_realtime add table public.driver_reviews;
  end if;
end $$;

notify pgrst, 'reload schema';

select
  to_regprocedure('public.get_my_order_delivery_snapshot(uuid)') as customer_delivery_snapshot_rpc,
  to_regprocedure('public.get_my_order_delivery_handoff_code(uuid)') as customer_handoff_code_rpc,
  to_regprocedure('public.submit_my_driver_review(uuid,numeric,text)') as customer_driver_review_rpc,
  to_regclass('public.driver_reviews') as driver_reviews_table,
  to_regclass('public.driver_notifications') as driver_notifications_table;
