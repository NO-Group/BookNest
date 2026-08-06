-- BookNest step 1: make the official account an explicit protected system identity.
-- Official UID supplied by the BookNest owner:
-- 2457ced9-609a-4ea7-b761-225bb0762513
-- Run after the base schema/chat migration.

create table if not exists public.system_accounts (
  account_key text primary key check (account_key = 'booknest'),
  user_id uuid not null unique references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
alter table public.system_accounts enable row level security;
revoke all on public.system_accounts from anon, authenticated;

-- The SELECT guard makes this safe if the Auth account has not been created yet.
insert into public.system_accounts(account_key, user_id)
select 'booknest', '2457ced9-609a-4ea7-b761-225bb0762513'::uuid
where exists (select 1 from auth.users where id = '2457ced9-609a-4ea7-b761-225bb0762513'::uuid)
on conflict (account_key) do update set user_id = excluded.user_id;

update public.profiles
set is_official_system = true
where id = '2457ced9-609a-4ea7-b761-225bb0762513'::uuid;

-- System identity, rather than a mutable profile flag, is now authoritative.
create or replace function public.is_booknest_system_account()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.system_accounts
    where account_key = 'booknest' and user_id = auth.uid()
  );
$$;

create or replace function public.can_post_chat(target_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select
    (
      exists (
        select 1 from public.chat_participants
        where chat_id = target_chat and user_id = auth.uid() and can_post
      )
      and not exists (
        select 1 from public.chats
        where id = target_chat and chat_type in ('nexus', 'community_announcement')
      )
    )
    or (
      public.is_booknest_system_account()
      and exists (select 1 from public.chats where id = target_chat and chat_type = 'nexus')
    )
    or exists (
      select 1
      from public.chats c
      join public.chat_participants cp on cp.chat_id = c.id
      where c.id = target_chat
        and c.chat_type = 'community_announcement'
        and cp.user_id = auth.uid()
        and cp.role in ('owner', 'moderator')
    );
$$;

-- Keep compatibility with the previous chat migration function name.
create or replace function public.is_chat_poster(target_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.can_post_chat(target_chat);
$$;

-- Users may edit their public profile, but never system identity.
create or replace function public.current_profile_is_system()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_official_system from public.profiles where id = auth.uid()), false);
$$;
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update using (id = auth.uid())
with check (id = auth.uid() and is_official_system = public.current_profile_is_system());

-- Replace chat insert policies so all Nexus decisions use the protected account.
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages
for insert with check (sender_id = auth.uid() and public.can_post_chat(chat_id));
drop policy if exists messages_insert_if_allowed on public.messages;
create policy messages_insert_if_allowed on public.messages
for insert with check (sender_id = auth.uid() and public.can_post_chat(chat_id));

-- The official profile flag remains as a compatibility mirror for old clients;
-- system_accounts is the actual authority used by posting policies.
