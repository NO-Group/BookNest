-- BookNest — Monetization catalog (prices are FIXED catalog values)
--
-- Money rules (do not break them):
--   * Every amount is an INTEGER in minor units: USD cents, NGN kobo.
--     No floating point ever touches a payment calculation.
--   * One row per (product, currency) — prices per currency are set by
--     hand here, never converted at runtime. When the exchange market
--     moves, update the NGN rows here and nothing else changes.
--   * The Flutter app sends only a product id. The Edge Function reads
--     the price from this table and initializes Paystack with it.
--   * If this table has no row for a product, the Edge Function falls
--     back to its built-in fixed catalog with these same values.
--
-- Paste this whole file into: Supabase dashboard → SQL Editor → Run.

create table if not exists monetization_catalog (
  id uuid primary key default gen_random_uuid(),
  product_id text not null,
  label text not null default '',
  kind text not null check (kind in ('gems', 'plan')),
  currency_code varchar(3) not null check (currency_code in ('USD', 'NGN')),
  amount_in_minor_units integer not null check (amount_in_minor_units > 0),
  gems integer not null default 0,
  plan text check (plan in ('reader', 'bookworm') or plan is null),
  period_days integer not null default 0,
  unlimited_books integer not null default 0,
  created_at timestamptz not null default now(),
  unique (product_id, currency_code)
);

-- The catalog is written by the owner only. Row Level Security stays ON
-- with no policies: the service key used by the Edge Function bypasses
-- RLS, while no anon/authenticated client can read or write prices.
alter table monetization_catalog enable row level security;

-- ── Gem packages ────────────────────────────────────────────────────────────
insert into monetization_catalog
  (product_id, label, kind, currency_code, amount_in_minor_units, gems)
values
  ('gems_100',   '100 Gems',   'gems', 'USD',     100,     100),
  ('gems_100',   '100 Gems',   'gems', 'NGN',  136200,     100),
  ('gems_500',   '500 Gems',   'gems', 'USD',     475,     500),
  ('gems_500',   '500 Gems',   'gems', 'NGN',  646950,     500),
  ('gems_1000',  '1,000 Gems', 'gems', 'USD',     900,    1000),
  ('gems_1000',  '1,000 Gems', 'gems', 'NGN', 1225800,    1000),
  ('gems_5000',  '5,000 Gems', 'gems', 'USD',    4899,    5000),
  ('gems_5000',  '5,000 Gems', 'gems', 'NGN', 6672438,    5000),
  ('gems_10000', '10,000 Gems','gems', 'USD',    9666,   10000),
  ('gems_10000', '10,000 Gems','gems', 'NGN', 13165092,  10000)
on conflict (product_id, currency_code) do update
  set label = excluded.label,
      amount_in_minor_units = excluded.amount_in_minor_units,
      gems = excluded.gems;

-- ── Reader plan (cyan/yellow star, 20% off unlocks, 5 unlimited books) ─────
insert into monetization_catalog
  (product_id, label, kind, currency_code, amount_in_minor_units, plan, period_days, unlimited_books)
values
  ('reader_monthly',    'Reader · Monthly',  'plan', 'USD',   833, 'reader',  30, 5),
  ('reader_monthly',    'Reader · Monthly',  'plan', 'NGN', 1135121, 'reader',  30, 5),
  ('reader_six_month',  'Reader · 6 Months', 'plan', 'USD',  4998, 'reader', 182, 5),
  ('reader_six_month',  'Reader · 6 Months', 'plan', 'NGN', 6810725, 'reader', 182, 5),
  ('reader_yearly',     'Reader · Yearly',   'plan', 'USD',  9999, 'reader', 365, 5),
  ('reader_yearly',     'Reader · Yearly',   'plan', 'NGN', 13625537, 'reader', 365, 5)
on conflict (product_id, currency_code) do update
  set label = excluded.label,
      amount_in_minor_units = excluded.amount_in_minor_units,
      plan = excluded.plan,
      period_days = excluded.period_days,
      unlimited_books = excluded.unlimited_books;

-- ── BookWorm plan (yellow/orange star, 20% off unlocks, 10 unlimited
--    books, monthly reading-time gem allowance: minutes ÷ 12) ──────────────
insert into monetization_catalog
  (product_id, label, kind, currency_code, amount_in_minor_units, plan, period_days, unlimited_books)
values
  ('bookworm_monthly',    'BookWorm · Monthly',  'plan', 'USD',   1266, 'bookworm',  30, 10),
  ('bookworm_monthly',    'BookWorm · Monthly',  'plan', 'NGN', 1725267, 'bookworm',  30, 10),
  ('bookworm_six_month',  'BookWorm · 6 Months', 'plan', 'USD',   7594, 'bookworm', 182, 10),
  ('bookworm_six_month',  'BookWorm · 6 Months', 'plan', 'NGN', 10348799, 'bookworm', 182, 10),
  ('bookworm_yearly',     'BookWorm · Yearly',   'plan', 'USD',  14999, 'bookworm', 365, 10),
  ('bookworm_yearly',     'BookWorm · Yearly',   'plan', 'NGN', 20440037, 'bookworm', 365, 10)
on conflict (product_id, currency_code) do update
  set label = excluded.label,
      amount_in_minor_units = excluded.amount_in_minor_units,
      plan = excluded.plan,
      period_days = excluded.period_days,
      unlimited_books = excluded.unlimited_books;
