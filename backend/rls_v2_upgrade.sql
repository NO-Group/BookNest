-- ============================================================================
-- BookNest · RLS v2 upgrade — paste into Dashboard → SQL Editor → New query
-- (idempotent: safe to run even over an existing database)
-- Fixes: error 42501 on creating clubs/schools/books, "uploaded but not
--        saved" profile photos, and users missing from chat/search results.
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
