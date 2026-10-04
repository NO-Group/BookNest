-- ============================================================================
-- BookNest 2.31 · Lock privileged columns against client writes
-- ============================================================================
-- The "update own row" RLS policies let a signed-in reader change ANY column
-- of their own rows straight through the public API (anon key + their JWT):
--   • profiles.gems              → free gems (gems are sold for real money)
--   • club_books.moderation_status → self-approve a book past moderation
--   • organizations/schools.is_verified → self-award the verified badge
--   • *_members.role             → self-promote to owner/admin
--
-- Fix: a BEFORE INSERT/UPDATE trigger that, for end-user roles only
-- (anon / authenticated), pins those columns — on UPDATE they keep their old
-- value, on INSERT they get the safe default. The edge function (service
-- role), the dashboard and SQL editor (postgres) are untouched, so gem
-- grants, purchases and moderation keep working exactly as before.
--
-- Silent pinning (instead of raising) keeps every legitimate client write
-- working: a profile save that happens to carry `gems` still saves the name.
--
-- Idempotent: safe to run any number of times, on any starting state
-- (tables that do not exist are skipped).
-- ============================================================================

create or replace function public.bn_lock_columns()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  i     int := 0;
  col   text;
  dflt  text;
  patch jsonb := '{}'::jsonb;
begin
  -- Only end users are restricted. service_role (edge function) and
  -- postgres (dashboard, migrations, security-definer triggers) pass.
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;

  -- TG_ARGV holds pairs: (column, insert_default_as_json | 'keep').
  while i < tg_nargs loop
    col  := tg_argv[i];
    dflt := tg_argv[i + 1];
    if tg_op = 'UPDATE' then
      patch := patch || jsonb_build_object(col, to_jsonb(old) -> col);
    elsif dflt <> 'keep' then
      patch := patch || jsonb_build_object(col, dflt::jsonb);
    end if;
    i := i + 2;
  end loop;

  -- Unknown keys are ignored, so a column missing on an older schema is
  -- harmless.
  return jsonb_populate_record(new, patch);
end;
$$;

do $$
declare
  spec record;
begin
  for spec in
    select * from (values
      ('profiles',             array['gems', '77', 'id', 'keep', 'created_at', 'keep']),
      ('club_books',           array['moderation_status', '"pending"']),
      ('organizations',        array['is_verified', 'false']),
      ('schools',              array['is_verified', 'false']),
      ('club_members',         array['role', '"member"']),
      ('community_members',    array['role', '"member"']),
      ('organization_members', array['role', '"member"']),
      ('school_members',       array['role', '"member"'])
    ) as t(tbl, args)
  loop
    if to_regclass('public.' || spec.tbl) is null then
      continue;
    end if;
    execute format('drop trigger if exists bn_lock_columns on public.%I', spec.tbl);
    execute format(
      'create trigger bn_lock_columns before insert or update on public.%I '
      'for each row execute function public.bn_lock_columns(%s)',
      spec.tbl,
      (select string_agg(quote_literal(a), ', ') from unnest(spec.args) as a)
    );
  end loop;
end;
$$;

select 'BookNest privileged columns locked' as status;
