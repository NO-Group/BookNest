-- BookNest monetization catalog and entitlements.
-- Prices are integer cents/kobo. Never use floating point for money.

do $$ begin create type public.product_kind as enum ('gem_pack','subscription'); exception when duplicate_object then null; end $$;
do $$ begin create type public.billing_period as enum ('one_time','monthly','six_month','yearly'); exception when duplicate_object then null; end $$;
do $$ begin create type public.gem_ledger_reason as enum ('purchase','book_unlock','subscription_allowance','refund','admin_grant','admin_adjustment'); exception when duplicate_object then null; end $$;

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check(code in ('reader','bookworm')),
  name text not null,
  description text not null default '',
  accent_start text not null,
  accent_end text not null,
  max_unlimited_books integer not null check(max_unlimited_books between 0 and 10),
  gem_discount_percent integer not null default 20 check(gem_discount_percent between 0 and 100),
  monthly_allowance_enabled boolean not null default false,
  premium_features jsonb not null default '[]'::jsonb,
  is_active boolean not null default true
);
create table if not exists public.catalog_products (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  kind public.product_kind not null,
  plan_id uuid references public.subscription_plans(id),
  billing_period public.billing_period not null,
  gem_amount integer check(gem_amount is null or gem_amount > 0),
  price_usd_cents integer not null check(price_usd_cents > 0),
  price_ngn_kobo integer not null check(price_ngn_kobo > 0),
  paystack_plan_code text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check((kind='gem_pack' and gem_amount is not null and plan_id is null and billing_period='one_time') or (kind='subscription' and gem_amount is null and plan_id is not null and billing_period<>'one_time'))
);

insert into public.subscription_plans(code,name,description,accent_start,accent_end,max_unlimited_books,gem_discount_percent,monthly_allowance_enabled,premium_features)
values
 ('reader','Reader','Premium reading features with selected unlimited books.','#00D4FF','#FFD000',5,20,false,'["premium_features","selected_unlimited_books"]'),
 ('bookworm','BookWorm','Premium reading, monthly reading allowance, and selected unlimited books.','#FFD000','#FF6A00',10,20,true,'["premium_features","selected_unlimited_books","monthly_gem_allowance"]')
on conflict(code) do update set name=excluded.name,description=excluded.description,accent_start=excluded.accent_start,accent_end=excluded.accent_end,max_unlimited_books=excluded.max_unlimited_books,gem_discount_percent=excluded.gem_discount_percent,monthly_allowance_enabled=excluded.monthly_allowance_enabled,premium_features=excluded.premium_features;

-- Gem prices use the supplied USD catalog and the current ₦13.62 per Gem rate.
insert into public.catalog_products(code,kind,billing_period,gem_amount,price_usd_cents,price_ngn_kobo)
values
 ('gems_100','gem_pack','one_time',100,100,136200),
 ('gems_500','gem_pack','one_time',500,475,646950),
 ('gems_1000','gem_pack','one_time',1000,900,1225800),
 ('gems_5000','gem_pack','one_time',5000,4899,6672438),
 ('gems_10000','gem_pack','one_time',10000,9666,13165092)
on conflict(code) do update set gem_amount=excluded.gem_amount,price_usd_cents=excluded.price_usd_cents,price_ngn_kobo=excluded.price_ngn_kobo;
insert into public.catalog_products(code,kind,plan_id,billing_period,price_usd_cents,price_ngn_kobo)
select v.code,'subscription',p.id,v.period::public.billing_period,v.usd,v.ngn
from (values
 ('reader_monthly','reader','monthly',833,1135121),('reader_six_month','reader','six_month',4998,6810725),('reader_yearly','reader','yearly',9999,13625537),
 ('bookworm_monthly','bookworm','monthly',1266,1725267),('bookworm_six_month','bookworm','six_month',7594,10348799),('bookworm_yearly','bookworm','yearly',14999,20440037)
) v(code,plan,period,usd,ngn) join public.subscription_plans p on p.code=v.plan
on conflict(code) do update set plan_id=excluded.plan_id,billing_period=excluded.billing_period,price_usd_cents=excluded.price_usd_cents,price_ngn_kobo=excluded.price_ngn_kobo;

alter table public.payment_transactions add column if not exists product_id uuid references public.catalog_products(id);
alter table public.payment_transactions add column if not exists order_id uuid;

create table if not exists public.orders (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 product_id uuid not null references public.catalog_products(id), reference text not null unique,
 amount_usd_cents integer not null, amount_ngn_kobo integer not null, status public.payment_status not null default 'pending',
 created_at timestamptz not null default now(), paid_at timestamptz
);
create table if not exists public.gem_ledger (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 amount integer not null check(amount<>0), reason public.gem_ledger_reason not null, order_id uuid references public.orders(id), book_id uuid references public.club_books(id), metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create index if not exists gem_ledger_user_idx on public.gem_ledger(user_id,created_at desc);
create table if not exists public.book_unlocks (
 user_id uuid not null references public.profiles(id) on delete cascade, book_id uuid not null references public.club_books(id) on delete cascade,
 gems_spent integer not null check(gems_spent>=0), word_count_at_unlock integer not null check(word_count_at_unlock>=0), unlocked_at timestamptz not null default now(),
 primary key(user_id,book_id)
);
create table if not exists public.user_subscriptions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 plan_id uuid not null references public.subscription_plans(id), order_id uuid references public.orders(id), starts_at timestamptz not null, ends_at timestamptz not null,
 status text not null default 'active' check(status in ('active','expired','cancelled')), created_at timestamptz not null default now(), check(ends_at>starts_at)
);
create table if not exists public.subscription_book_access (
 subscription_id uuid not null references public.user_subscriptions(id) on delete cascade, book_id uuid not null references public.club_books(id) on delete cascade,
 assigned_at timestamptz not null default now(), primary key(subscription_id,book_id)
);
create table if not exists public.reading_sessions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 book_id uuid not null references public.club_books(id) on delete cascade, started_at timestamptz not null, ended_at timestamptz,
 minutes integer not null default 0 check(minutes between 0 and 1440), created_at timestamptz not null default now()
);
create unique index if not exists user_subscription_order_idx on public.user_subscriptions(order_id) where order_id is not null;

-- A successful order is fulfilled once, inside the database transaction.
create or replace function public.fulfill_order(target_order uuid)
returns void language plpgsql security definer set search_path=public as $$
declare o public.orders; p public.catalog_products; s public.subscription_plans; sub_id uuid;
begin
 select * into o from public.orders where id=target_order for update;
 if o.id is null or o.status <> 'success' then return; end if;
 select * into p from public.catalog_products where id=o.product_id;
 if p.kind='gem_pack' then
   insert into public.gem_ledger(user_id,amount,reason,order_id,metadata)
   select o.user_id,p.gem_amount,'purchase',o.id,jsonb_build_object('product_code',p.code)
   where not exists(select 1 from public.gem_ledger where order_id=o.id and reason='purchase');
 elsif p.kind='subscription' then
   select * into s from public.subscription_plans where id=p.plan_id;
   insert into public.user_subscriptions(user_id,plan_id,order_id,starts_at,ends_at)
   select o.user_id,s.id,o.id,now(),case p.billing_period when 'monthly' then now()+interval '1 month' when 'six_month' then now()+interval '6 months' when 'yearly' then now()+interval '1 year' end
   where not exists(select 1 from public.user_subscriptions where order_id=o.id)
   returning id into sub_id;
   if sub_id is not null then
     insert into public.subscription_book_access(subscription_id,book_id)
     select sub_id,b.id from public.club_books b where b.moderation_status='approved' order by md5(b.id::text||sub_id::text) limit s.max_unlimited_books;
   end if;
 end if;
end;
$$;

-- Server-side word pricing. A book stores word_count when publishing is finalized.
alter table public.club_books add column if not exists word_count integer not null default 0 check(word_count>=0);
create or replace function public.book_unlock_cost(target_book uuid) returns integer language sql stable security definer set search_path=public as $$
 select greatest(1,ceil(word_count::numeric/100)::integer) from public.club_books where id=target_book;
$$;
create or replace function public.current_gem_discount() returns integer language sql stable security definer set search_path=public as $$
 select coalesce(max(sp.gem_discount_percent),0) from public.user_subscriptions us join public.subscription_plans sp on sp.id=us.plan_id where us.user_id=auth.uid() and us.status='active' and now() between us.starts_at and us.ends_at;
$$;

alter table public.orders enable row level security;
alter table public.gem_ledger enable row level security;
alter table public.book_unlocks enable row level security;
alter table public.user_subscriptions enable row level security;
alter table public.subscription_book_access enable row level security;
alter table public.reading_sessions enable row level security;
alter table public.catalog_products enable row level security;
alter table public.subscription_plans enable row level security;
create policy catalog_products_read on public.catalog_products for select using(is_active);
create policy subscription_plans_read on public.subscription_plans for select using(is_active);
create policy orders_owner_read on public.orders for select using(user_id=auth.uid());
create policy ledger_owner_read on public.gem_ledger for select using(user_id=auth.uid());
create policy unlocks_owner_read on public.book_unlocks for select using(user_id=auth.uid());
create policy subscriptions_owner_read on public.user_subscriptions for select using(user_id=auth.uid());
create policy subscription_books_owner_read on public.subscription_book_access for select using(exists(select 1 from public.user_subscriptions us where us.id=subscription_id and us.user_id=auth.uid()));
create policy reading_owner_read on public.reading_sessions for select using(user_id=auth.uid());
create policy reading_owner_insert on public.reading_sessions for insert with check(user_id=auth.uid());
