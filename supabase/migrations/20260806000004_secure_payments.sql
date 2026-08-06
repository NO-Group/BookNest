-- Payment records contain no secrets. Paystack secret keys stay in Edge Function secrets.
do $$ begin create type public.payment_status as enum ('pending','success','failed','cancelled'); exception when duplicate_object then null; end $$;
create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  reference text not null unique,
  amount_kobo integer not null check (amount_kobo between 100 and 10000000),
  currency text not null default 'NGN' check (currency='NGN'),
  purpose text not null,
  status public.payment_status not null default 'pending',
  metadata jsonb not null default '{}'::jsonb,
  gateway_access_code text,
  gateway_response jsonb,
  created_at timestamptz not null default now(),
  verified_at timestamptz
);
alter table public.payment_transactions enable row level security;
revoke all on public.payment_transactions from anon, authenticated;
create policy payment_owner_read on public.payment_transactions for select using(user_id=auth.uid());
create index if not exists payment_user_idx on public.payment_transactions(user_id,created_at desc);
