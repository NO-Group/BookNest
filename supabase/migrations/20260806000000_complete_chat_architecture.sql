-- BookNest Limitation 1: complete messaging architecture.
-- Apply after the existing profiles table exists. The Nexus account must be
-- marked with profiles.is_official_system = true once its UUID is known.

create extension if not exists pgcrypto;

do $$ begin
  create type public.chat_type as enum ('dm', 'club', 'organization', 'school', 'community_announcement', 'nexus');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.chat_member_role as enum ('owner', 'vice_moderator', 'moderator', 'teacher', 'member');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.chat_message_type as enum ('text', 'image', 'file', 'quote', 'poll', 'system');
exception when duplicate_object then null; end $$;

alter table public.profiles add column if not exists is_official_system boolean not null default false;

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  chat_type public.chat_type not null,
  title text not null,
  description text,
  avatar_url text,
  created_by uuid references public.profiles(id) on delete set null,
  system_account_id uuid references public.profiles(id) on delete restrict,
  entity_id uuid,
  entity_kind text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint nexus_has_no_parent check (chat_type <> 'nexus' or entity_id is null)
);

create unique index if not exists one_nexus_chat on public.chats(chat_type) where chat_type = 'nexus';
create index if not exists chats_entity_idx on public.chats(entity_kind, entity_id);

create table if not exists public.chat_participants (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.chat_member_role not null default 'member',
  can_post boolean not null default true,
  joined_at timestamptz not null default now(),
  last_read_message_id uuid,
  last_read_at timestamptz,
  unique(chat_id, user_id)
);
create index if not exists chat_participants_user_idx on public.chat_participants(user_id, joined_at desc);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null,
  message_type public.chat_message_type not null default 'text',
  body text,
  metadata jsonb not null default '{}'::jsonb,
  reply_to uuid references public.messages(id) on delete set null,
  is_pinned boolean not null default false,
  edited_at timestamptz,
  created_at timestamptz not null default now(),
  constraint message_has_body check (body is not null or metadata <> '{}'::jsonb)
);
create index if not exists messages_chat_created_idx on public.messages(chat_id, created_at desc);

create table if not exists public.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  unique(message_id, user_id, emoji)
);

create table if not exists public.poll_votes (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  option_id text not null,
  created_at timestamptz not null default now(),
  unique(message_id, user_id)
);

-- Seed the single mandatory Nexus room. Set system_account_id after creating
-- the official BookNest profile; normal users can never write to this room.
insert into public.chats (chat_type, title, description)
select 'nexus', 'The Nexus', 'Official BookNest announcements and polls'
where not exists (select 1 from public.chats where chat_type = 'nexus');

create or replace function public.is_chat_member(target_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.chat_participants where chat_id = target_chat and user_id = auth.uid());
$$;

create or replace function public.is_chat_poster(target_chat uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chat_participants cp
    where cp.chat_id = target_chat and cp.user_id = auth.uid() and cp.can_post
  ) and not exists (
    select 1 from public.chats c where c.id = target_chat and c.chat_type in ('nexus', 'community_announcement')
  )
  or exists (
    select 1 from public.chats c join public.profiles p on p.id = auth.uid()
    where c.id = target_chat and p.is_official_system and c.chat_type = 'nexus'
  )
  or exists (
    select 1 from public.chats c
    where c.id = target_chat and c.chat_type = 'community_announcement'
      and exists (select 1 from public.chat_participants cp where cp.chat_id = c.id and cp.user_id = auth.uid() and cp.role in ('owner', 'moderator'))
  );
$$;

create or replace function public.join_nexus_on_signup()
returns trigger language plpgsql security definer set search_path = public as $$
declare nexus_id uuid;
begin
  select id into nexus_id from public.chats where chat_type = 'nexus' limit 1;
  if nexus_id is not null then
    insert into public.chat_participants(chat_id, user_id, role, can_post)
    values (nexus_id, new.id, 'member', false)
    on conflict (chat_id, user_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists on_profile_join_nexus on public.profiles;
create trigger on_profile_join_nexus after insert on public.profiles
for each row execute function public.join_nexus_on_signup();

-- Community announcement groups become one-way chat channels automatically.
create or replace function public.create_community_announcement_chat()
returns trigger language plpgsql security definer set search_path = public as $$
declare chat_id uuid; owner_id uuid;
begin
  insert into public.chats(chat_type, title, entity_id, entity_kind)
  values ('community_announcement', new.name, new.id, 'announcement_group')
  on conflict do nothing returning id into chat_id;
  if chat_id is null then
    select id into chat_id from public.chats where entity_id = new.id and entity_kind = 'announcement_group';
  end if;
  select c.owner_id into owner_id from public.communities c where c.id = new.community_id;
  if owner_id is not null then
    insert into public.chat_participants(chat_id, user_id, role, can_post)
    values (chat_id, owner_id, 'owner', true) on conflict (chat_id, user_id) do update set can_post = true, role = 'owner';
  end if;
  return new;
end;
$$;
drop trigger if exists announcement_group_creates_chat on public.announcement_groups;
create trigger announcement_group_creates_chat after insert on public.announcement_groups
for each row execute function public.create_community_announcement_chat();

create or replace function public.enroll_community_member_in_announcement()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.chat_participants(chat_id, user_id, role, can_post)
  select c.id, new.user_id,
    case when new.role in ('owner', 'moderator') then new.role::public.chat_member_role else 'member'::public.chat_member_role end,
    new.role in ('owner', 'moderator')
  from public.chats c where c.entity_kind = 'announcement_group'
    and c.entity_id in (select ag.id from public.announcement_groups ag where ag.community_id = new.community_id)
  on conflict (chat_id, user_id) do update set role = excluded.role, can_post = excluded.can_post;
  return new;
end;
$$;
drop trigger if exists community_member_joins_announcement on public.community_members;
create trigger community_member_joins_announcement after insert or update on public.community_members
for each row execute function public.enroll_community_member_in_announcement();

-- Also repairs existing accounts and existing community announcements.
insert into public.chat_participants(chat_id, user_id, can_post)
select c.id, p.id, false from public.chats c cross join public.profiles p
where c.chat_type = 'nexus' on conflict (chat_id, user_id) do nothing;
insert into public.chats(chat_type, title, entity_id, entity_kind)
select 'community_announcement', ag.name, ag.id, 'announcement_group'
from public.announcement_groups ag
where not exists (select 1 from public.chats c where c.entity_kind = 'announcement_group' and c.entity_id = ag.id);
insert into public.chat_participants(chat_id, user_id, role, can_post)
select c.id, cm.user_id,
  case when cm.role in ('owner', 'moderator') then cm.role::public.chat_member_role else 'member'::public.chat_member_role end,
  cm.role in ('owner', 'moderator')
from public.chats c
join public.announcement_groups ag on ag.id = c.entity_id
join public.community_members cm on cm.community_id = ag.community_id
on conflict (chat_id, user_id) do update set role = excluded.role, can_post = excluded.can_post;

create or replace function public.prevent_nexus_leave() returns trigger language plpgsql as $$
begin
  if exists (select 1 from public.chats where id = old.chat_id and chat_type = 'nexus') then
    raise exception 'The Nexus is mandatory and cannot be left';
  end if;
  return old;
end; $$;
drop trigger if exists prevent_nexus_leave_trigger on public.chat_participants;
create trigger prevent_nexus_leave_trigger before delete on public.chat_participants
for each row execute function public.prevent_nexus_leave();

alter table public.chats enable row level security;
alter table public.chat_participants enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.poll_votes enable row level security;

drop policy if exists chats_read_if_member on public.chats;
drop policy if exists participants_read_own_chats on public.chat_participants;
drop policy if exists participants_join_self on public.chat_participants;
drop policy if exists participants_update_self on public.chat_participants;
drop policy if exists messages_read_if_member on public.messages;
drop policy if exists messages_insert_if_allowed on public.messages;
drop policy if exists messages_update_own on public.messages;
drop policy if exists reactions_read_if_member on public.message_reactions;
drop policy if exists reactions_insert_member on public.message_reactions;
drop policy if exists reactions_delete_own on public.message_reactions;
drop policy if exists poll_votes_member on public.poll_votes;

create policy chats_read_if_member on public.chats for select using (public.is_chat_member(id));
create policy participants_read_own_chats on public.chat_participants for select using (public.is_chat_member(chat_id));
create policy participants_join_self on public.chat_participants for insert with check (
  user_id = auth.uid()
  and role = 'member'
  and exists (select 1 from public.chats c where c.id = chat_id and c.chat_type <> 'nexus')
  and can_post = exists (
    select 1 from public.chats c
    where c.id = chat_id and c.chat_type in ('dm', 'club', 'organization')
  )
);
create policy participants_update_self on public.chat_participants for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy messages_read_if_member on public.messages for select using (public.is_chat_member(chat_id));
create policy messages_insert_if_allowed on public.messages for insert with check (sender_id = auth.uid() and public.is_chat_poster(chat_id));
create policy messages_update_own on public.messages for update using (sender_id = auth.uid()) with check (sender_id = auth.uid());
create policy reactions_read_if_member on public.message_reactions for select using (exists (select 1 from public.messages m where m.id = message_id and public.is_chat_member(m.chat_id)));
create policy reactions_insert_member on public.message_reactions for insert with check (user_id = auth.uid() and exists (select 1 from public.messages m where m.id = message_id and public.is_chat_member(m.chat_id)));
create policy reactions_delete_own on public.message_reactions for delete using (user_id = auth.uid());
create policy poll_votes_member on public.poll_votes for all using (user_id = auth.uid() and exists (select 1 from public.messages m where m.id = message_id and public.is_chat_member(m.chat_id))) with check (user_id = auth.uid() and exists (select 1 from public.messages m where m.id = message_id and public.is_chat_member(m.chat_id)));

do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'message_reactions') then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
end $$;
