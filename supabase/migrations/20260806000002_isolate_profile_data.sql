-- BookNest step 2: isolate private/account-controlled profile data.
-- Public profile reads must never expose phone numbers, wallet balance, presence,
-- or system flags.

create table if not exists public.profile_private (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  phone_number text,
  status text not null default 'offline' check (status in ('online','offline','away')),
  last_seen timestamptz not null default now(),
  gems integer not null default 77 check (gems >= 0),
  updated_at timestamptz not null default now()
);

insert into public.profile_private(user_id, phone_number, status, last_seen, gems)
select id, phone_number, status, last_seen, gems from public.profiles
on conflict (user_id) do update set
  phone_number = excluded.phone_number,
  status = excluded.status,
  last_seen = excluded.last_seen,
  gems = excluded.gems;

-- Remove policies that depend on the columns before dropping them.
drop policy if exists profiles_update_self on public.profiles;

-- These columns are no longer duplicated in the public profile table.
alter table public.profiles drop column if exists phone_number;
alter table public.profiles drop column if exists status;
alter table public.profiles drop column if exists last_seen;
alter table public.profiles drop column if exists gems;
alter table public.profiles drop column if exists is_official_system;

alter table public.profile_private enable row level security;
revoke all on public.profile_private from anon, authenticated;
create policy profile_private_owner_read on public.profile_private
for select using (user_id = auth.uid());
create policy profile_private_owner_update on public.profile_private
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Public profile table: only identity/display fields are readable or editable.
revoke all on public.profiles from anon, authenticated;
grant select (id, username, display_name, avatar_url, bio, created_at, updated_at)
on public.profiles to anon, authenticated;
grant update (display_name, avatar_url, bio)
on public.profiles to authenticated;

-- Rebuild the update policy without the removed system flag.
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update using (id = auth.uid()) with check (id = auth.uid());

create or replace function public.update_my_profile(
  p_display_name text default null,
  p_avatar_url text default null,
  p_bio text default null,
  p_phone_number text default null
) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare result public.profiles;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.profiles
  set display_name = coalesce(nullif(trim(p_display_name), ''), display_name),
      avatar_url = p_avatar_url,
      bio = p_bio,
      updated_at = now()
  where id = auth.uid()
  returning * into result;
  insert into public.profile_private(user_id, phone_number)
  values (auth.uid(), p_phone_number)
  on conflict (user_id) do update set phone_number = excluded.phone_number, updated_at = now();
  return result;
end;
$$;
grant execute on function public.update_my_profile(text,text,text,text) to authenticated;

-- Signup creates public and private rows. This replaces older profile triggers.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare username_value text; nexus_id uuid;
begin
  username_value := coalesce(nullif(new.raw_user_meta_data->>'username',''), split_part(new.email,'@',1), 'reader_'||substr(new.id::text,1,8));
  insert into public.profiles(id, username, display_name, avatar_url)
  values(new.id, username_value, coalesce(new.raw_user_meta_data->>'display_name', username_value), new.raw_user_meta_data->>'avatar_url')
  on conflict(id) do nothing;
  insert into public.profile_private(user_id, phone_number)
  values(new.id, new.raw_user_meta_data->>'phone')
  on conflict(user_id) do nothing;
  select id into nexus_id from public.chats where chat_type='nexus' limit 1;
  if nexus_id is not null then
    insert into public.chat_participants(chat_id,user_id,role,can_post)
    values(nexus_id,new.id,'member',false) on conflict(chat_id,user_id) do nothing;
  end if;
  return new;
end;
$$;
