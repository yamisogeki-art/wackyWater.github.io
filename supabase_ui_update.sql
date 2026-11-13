-- WackySmart UI update: run once in the Supabase SQL editor.
-- Every statement is idempotent, so re-running is safe.
-- The app still works without this file (it falls back gracefully),
-- but the driver screens will not show customer names/phones,
-- "delivered_at" timestamps or delivery notes until it is applied.

-- 1) Customer contact number (shown to the driver on Delivery Details)
alter table public.profiles add column if not exists phone text;

-- 2) Delivery timestamp + optional driver note on each request
alter table public.delivery_requests add column if not exists delivered_at timestamptz;
alter table public.delivery_requests add column if not exists notes text;

-- 3) Customers save their own contact number through an RPC or direct update
create or replace function public.set_my_phone(p_phone text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.profiles
     set phone = nullif(trim(p_phone), '')
   where id = auth.uid();
$$;
grant execute on function public.set_my_phone(text) to authenticated;

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- 4) Drivers may read the name/phone of customers they are assigned to.
--    A security-definer helper avoids RLS recursion between
--    profiles <-> delivery_requests.
create or replace function public.driver_serves_customer(cust uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.delivery_requests
     where customer_id = cust and driver_id = auth.uid()
  );
$$;

drop policy if exists "Drivers can read their customers' profiles" on public.profiles;
create policy "Drivers can read their customers' profiles"
  on public.profiles for select
  using (public.driver_serves_customer(id));

-- 5) Secure forecasts table:
--    Enable Row Level Security (RLS).
--    Allow SELECT for authenticated users (Admin / App UI).
--    Restrict INSERT/UPDATE so only the Python FastAPI backend server
--    (using SUPABASE_SERVICE_KEY, which bypasses RLS) can write forecast records.
alter table public.forecasts enable row level security;

drop policy if exists "Authenticated users can read forecasts" on public.forecasts;
create policy "Authenticated users can read forecasts"
  on public.forecasts for select
  to authenticated
  using (true);
