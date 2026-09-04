-- ============================================================================
-- BookNest · COMPLETE SETUP — the ONLY database file you need
-- Paste into Dashboard → SQL Editor → New query → Run.
-- Works on ANY project state: brand-new, half-finished, or already running.
-- (Everything below is guarded and safe to re-run as many times as you like.)
-- ============================================================================
-- Order matters and is handled for you:
--   PART 1 creates every table the app uses,
--   PART 2 installs the signup automation + the full security rulebook,
--   PART 3 verifies — you are done when you see 'BookNest database ready'.
-- ============================================================================

create extension if not exists pgcrypto;

-- ─────────────────────────────────────────────────────────────────────────────
-- PERMANENT · profiles (1:1 with auth users)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  username     text unique,
  display_name text,
  avatar_url   text,
  cover_url    text,
  phone_number text,
  gems         integer not null default 77,
  created_at   timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists "profiles are readable" on public.profiles;
create policy "profiles are readable"   on public.profiles for select using (true);
drop policy if exists "profiles insert own" on public.profiles;
create policy "profiles insert own"     on public.profiles for insert with check (auth.uid() = id);
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own"     on public.profiles for update using (auth.uid() = id);

-- Helper policy pattern: owner columns reference profiles so PostgREST can
-- embed `profiles(...)` in selects (the feed does exactly that).

-- ─────────────────────────────────────────────────────────────────────────────
-- TRANSITIONAL · feed posts  (drop after MongoDB feed cutover)
-- Columns match the app exactly: type/title/content/metadata/created_by.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.posts (
  id         uuid primary key default gen_random_uuid(),
  type       text not null default 'post',      -- post | quote | news | poll | event | reel
  title      text,
  content    text not null default '',
  metadata   jsonb not null default '{}'::jsonb,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.posts enable row level security;
drop policy if exists "posts are readable" on public.posts;
create policy "posts are readable"  on public.posts for select using (true);
drop policy if exists "posts insert own" on public.posts;
create policy "posts insert own"    on public.posts for insert with check (auth.uid() = created_by);

-- ─────────────────────────────────────────────────────────────────────────────
-- TRANSITIONAL · groups (clubs / communities / organizations / schools)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.clubs (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  description       text not null default '',
  genre_tags        text[] not null default '{}',
  is_private        boolean not null default false,
  owner_id          uuid not null references public.profiles (id) on delete cascade,
  vice_moderator_id uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now()
);
create table if not exists public.club_members (
  club_id   uuid not null references public.clubs (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  role      text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (club_id, user_id)
);

create table if not exists public.communities (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  description       text not null default '',
  owner_id          uuid not null references public.profiles (id) on delete cascade,
  vice_moderator_id uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now()
);
create table if not exists public.announcement_groups (
  id           uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities (id) on delete cascade,
  name         text not null,
  created_at   timestamptz not null default now()
);
create table if not exists public.community_members (
  community_id uuid not null references public.communities (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  role         text not null default 'member',
  joined_at    timestamptz not null default now(),
  primary key (community_id, user_id)
);

create table if not exists public.organizations (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  description       text not null default '',
  mission           text not null default '',
  org_type          text,
  is_private        boolean not null default false,
  is_verified       boolean not null default false,
  owner_id          uuid not null references public.profiles (id) on delete cascade,
  vice_moderator_id uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now()
);
create table if not exists public.organization_members (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id         uuid not null references public.profiles (id) on delete cascade,
  role            text not null default 'member',
  joined_at       timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create table if not exists public.schools (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  description       text not null default '',
  location          text,
  website           text,
  school_type       text,
  owner_id          uuid not null references public.profiles (id) on delete cascade,
  vice_moderator_id uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now()
);
create table if not exists public.school_members (
  school_id uuid not null references public.schools (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  role      text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (school_id, user_id)
);

-- Readable + owner-writable for every group table.
do $$
declare t text;
begin
  foreach t in array array['clubs','communities','organizations','schools'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "%s readable" on public.%I;', t, t);
    execute format('create policy "%s readable" on public.%I for select using (true);', t, t);
    execute format('drop policy if exists "%s manage own" on public.%I;', t, t);
    execute format('create policy "%s manage own" on public.%I for insert with check (auth.uid() = owner_id);', t, t);
    execute format('drop policy if exists "%s update own" on public.%I;', t, t);
    execute format('create policy "%s update own" on public.%I for update using (auth.uid() = owner_id);', t, t);
  end loop;
end $$;

do $$
declare t text; c text; owner text;
begin
  -- member tables: readable + join-as-yourself
  foreach t in array array['club_members','community_members','organization_members','school_members'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "%s readable" on public.%I;', t, t);
    execute format('create policy "%s readable" on public.%I for select using (true);', t, t);
    execute format('drop policy if exists "%s join self" on public.%I;', t, t);
    execute format('create policy "%s join self" on public.%I for insert with check (auth.uid() = user_id);', t, t);
  end loop;
  -- auxiliaries
  foreach t in array array['announcement_groups'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "%s readable" on public.%I;', t, t);
    execute format('create policy "%s readable" on public.%I for select using (true);', t, t);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- TRANSITIONAL · books (drop after MongoDB library cutover)
-- Matches book_editor_screen.dart + books_library_screen.dart exactly,
-- plus the new `genre` + `cover_url` columns the filter sheet reads.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.club_books (
  id                uuid primary key default gen_random_uuid(),
  club_id           uuid references public.clubs (id) on delete set null,
  title             text not null,
  author            text not null default 'Unknown',
  description       text not null default '',
  genre             text,
  cover_url         text,
  content_format    text not null default 'markdown',
  moderation_status text not null default 'pending',
  added_by          uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now()
);
alter table public.club_books enable row level security;
drop policy if exists "club_books readable" on public.club_books;
create policy "club_books readable"  on public.club_books for select using (true);
drop policy if exists "club_books insert own" on public.club_books;
create policy "club_books insert own" on public.club_books for insert with check (auth.uid() = added_by);

create table if not exists public.book_chapters (
  id             uuid primary key default gen_random_uuid(),
  club_book_id   uuid not null references public.club_books (id) on delete cascade,
  chapter_number integer not null default 1,
  title          text not null default 'Chapter 1',
  content        text not null default '',
  created_at     timestamptz not null default now(),
  unique (club_book_id, chapter_number)
);
alter table public.book_chapters enable row level security;
drop policy if exists "book_chapters readable" on public.book_chapters;
create policy "book_chapters readable" on public.book_chapters for select using (true);
drop policy if exists "book_chapters insert own" on public.book_chapters;
create policy "book_chapters insert own" on public.book_chapters for insert with check (
  exists (select 1 from public.club_books b where b.id = club_book_id and b.added_by = auth.uid())
);

-- ============================================================================
-- PART 2 · Signup automation + the full security rulebook
-- ============================================================================

create extension if not exists pgcrypto;

-- 1 · profiles: auto-create a row for every new signup + backfill existing ---
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'username', ''), split_part(new.email, '@', 1), 'reader_' || substr(new.id::text, 1, 8)),
    coalesce(nullif(new.raw_user_meta_data->>'username', ''), split_part(new.email, '@', 1), 'Reader')
  )
  on conflict (id) do nothing;
  return new;
exception
  when unique_violation then
    -- Someone else already holds that username (e.g. same email prefix).
    -- Never fail a signup for a name clash: fall back to a guaranteed-
    -- unique handle built from the full user id instead.
    insert into public.profiles (id, username, display_name)
    values (
      new.id,
      'reader_' || replace(new.id::text, '-', ''),
      coalesce(nullif(new.raw_user_meta_data->>'username', ''), split_part(new.email, '@', 1), 'Reader')
    )
    on conflict do nothing;
    return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill anyone who signed up before this trigger existed.
insert into public.profiles (id, username, display_name)
select u.id,
       coalesce(nullif(u.raw_user_meta_data->>'username', ''), split_part(u.email, '@', 1), 'reader_' || substr(u.id::text, 1, 8)),
       coalesce(nullif(u.raw_user_meta_data->>'username', ''), split_part(u.email, '@', 1), 'Reader')
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict do nothing;

alter table public.profiles enable row level security;
drop policy if exists "profiles are readable" on public.profiles;
create policy "profiles are readable" on public.profiles for select using (true);
drop policy if exists "profiles insert own" on public.profiles;
create policy "profiles insert own" on public.profiles for insert with check (auth.uid() = id);
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

-- 2 · posts -------------------------------------------------------------------
alter table public.posts enable row level security;
drop policy if exists "posts are readable" on public.posts;
create policy "posts are readable" on public.posts for select using (true);
drop policy if exists "posts insert own" on public.posts;
create policy "posts insert own" on public.posts for insert with check (auth.uid() = created_by);
drop policy if exists "posts update own" on public.posts;
create policy "posts update own" on public.posts for update using (auth.uid() = created_by) with check (auth.uid() = created_by);
drop policy if exists "posts delete own" on public.posts;
create policy "posts delete own" on public.posts for delete using (auth.uid() = created_by);

-- 3 · groups: readable + owner-writable (add cover_url while we're here) ------
alter table public.clubs        add column if not exists cover_url text;
alter table public.communities  add column if not exists cover_url text;
alter table public.organizations add column if not exists cover_url text;
alter table public.schools      add column if not exists cover_url text;

do $$
declare t text;
begin
  foreach t in array array['clubs','communities','organizations','schools'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "%s readable" on public.%I;', t, t);
    execute format('create policy "%s readable" on public.%I for select using (true);', t, t);
    execute format('drop policy if exists "%s insert own" on public.%I;', t, t);
    execute format('create policy "%s insert own" on public.%I for insert with check (auth.uid() = owner_id);', t, t);
    execute format('drop policy if exists "%s update own" on public.%I;', t, t);
    execute format('create policy "%s update own" on public.%I for update using (auth.uid() = owner_id) with check (auth.uid() = owner_id);', t, t);
    execute format('drop policy if exists "%s delete own" on public.%I;', t, t);
    execute format('create policy "%s delete own" on public.%I for delete using (auth.uid() = owner_id);', t, t);
  end loop;
end $$;

-- 4 · member tables: readable + join-as-yourself + leave-yourself -------------
do $$
declare t text; c text;
begin
  foreach t in array array['club_members','community_members','organization_members','school_members'] loop
    c := regexp_replace(t, '_members$', '_id');
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "%s readable" on public.%I;', t, t);
    execute format('create policy "%s readable" on public.%I for select using (true);', t, t);
    execute format('drop policy if exists "%s join self" on public.%I;', t, t);
    execute format('create policy "%s join self" on public.%I for insert with check (auth.uid() = user_id);', t, t);
    execute format('drop policy if exists "%s leave self" on public.%I;', t, t);
    execute format('create policy "%s leave self" on public.%I for delete using (auth.uid() = user_id);', t, t);
  end loop;
end $$;

-- 5 · books + chapters ----------------------------------------------------------
alter table public.club_books enable row level security;
drop policy if exists "club_books readable" on public.club_books;
create policy "club_books readable" on public.club_books for select using (true);
drop policy if exists "club_books insert own" on public.club_books;
create policy "club_books insert own" on public.club_books for insert with check (auth.uid() = added_by);
drop policy if exists "club_books update own" on public.club_books;
create policy "club_books update own" on public.club_books for update using (auth.uid() = added_by) with check (auth.uid() = added_by);
drop policy if exists "club_books delete own" on public.club_books;
create policy "club_books delete own" on public.club_books for delete using (auth.uid() = added_by);

alter table public.book_chapters enable row level security;
drop policy if exists "book_chapters readable" on public.book_chapters;
create policy "book_chapters readable" on public.book_chapters for select using (true);
drop policy if exists "book_chapters insert own" on public.book_chapters;
create policy "book_chapters insert own" on public.book_chapters for insert with check (
  exists (select 1 from public.club_books b where b.id = club_book_id and b.added_by = auth.uid())
);
drop policy if exists "book_chapters update own" on public.book_chapters;
create policy "book_chapters update own" on public.book_chapters for update using (
  exists (select 1 from public.club_books b where b.id = club_book_id and b.added_by = auth.uid())
) with check (
  exists (select 1 from public.club_books b where b.id = club_book_id and b.added_by = auth.uid())
);

-- 6 · announcement groups readable --------------------------------------------
alter table public.announcement_groups enable row level security;
drop policy if exists "announcement_groups readable" on public.announcement_groups;
create policy "announcement_groups readable" on public.announcement_groups for select using (true);

-- Done. Club/school/community/organization creation, book writing and
-- profile-photo saving now pass the permission check for signed-in users.

-- ============================================================================
-- PART 2.5 · Table access grants — the front-door keys
-- Policies decide WHO may do WHAT; grants decide whether the app's roles may
-- touch the tables at all. Both are required. This section guarantees the
-- grants exist no matter how the tables were first created.
-- ============================================================================
grant usage on schema public to anon, authenticated, service_role;
grant select on all tables in schema public to anon, authenticated, service_role;
grant insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to authenticated, service_role;
alter default privileges in schema public grant select on tables to anon, authenticated;
alter default privileges in schema public grant insert, update, delete on tables to authenticated;

-- ============================================================================
-- 7 · VERIFICATION — run is complete when you see 'BookNest database ready'
--     (the result grid below also shows your live policy count per table)
-- ============================================================================
do $$
declare
  policy_count int;
  profile_count int;
begin
  select count(*) into policy_count
  from pg_policies where schemaname = 'public';
  select count(*) into profile_count
  from public.profiles;
  raise notice '================================================';
  raise notice '  BookNest database ready';
  raise notice '  policies installed : %', policy_count;
  raise notice '  profiles in search : %', profile_count;
  raise notice '================================================';
end $$;

select tablename, policyname
from pg_policies
where schemaname = 'public'
order by tablename, policyname;
