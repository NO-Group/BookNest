-- BookNest fresh Supabase schema
-- Run this file in a new Supabase project after enabling Auth.
-- It is intentionally self-contained and matches the current Flutter codebase.
-- The official BookNest account is marked with profiles.is_official_system = true.

create extension if not exists pgcrypto;
create extension if not exists citext;

do $$ begin create type public.member_role as enum ('owner','vice_moderator','moderator','teacher','member'); exception when duplicate_object then null; end $$;
do $$ begin create type public.post_type as enum ('quote','news','poll','event','reel','article','text'); exception when duplicate_object then null; end $$;
do $$ begin create type public.moderation_status as enum ('pending','approved','rejected'); exception when duplicate_object then null; end $$;
do $$ begin create type public.chat_type as enum ('dm','club','organization','school','community_announcement','nexus'); exception when duplicate_object then null; end $$;
do $$ begin create type public.chat_message_type as enum ('text','image','file','quote','poll','system'); exception when duplicate_object then null; end $$;

-- Identity/profile data. Auth remains the source of truth for credentials.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username citext not null unique,
  display_name text not null,
  phone_number text,
  avatar_url text,
  bio text,
  status text not null default 'offline' check (status in ('online','offline','away')),
  last_seen timestamptz not null default now(),
  gems integer not null default 77 check (gems >= 0),
  is_official_system boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- The single official system identity is separate from mutable profile data.
create table public.system_accounts (
  account_key text primary key check (account_key = 'booknest'),
  user_id uuid not null unique references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
alter table public.system_accounts enable row level security;
revoke all on public.system_accounts from anon, authenticated;

-- Social feed.
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  type public.post_type not null,
  title text,
  content text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid not null references public.profiles(id) on delete cascade,
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index posts_feed_idx on public.posts(created_at desc);
create index posts_type_idx on public.posts(type, created_at desc);

-- Discoverable parent entities.
create table public.clubs (
  id uuid primary key default gen_random_uuid(), name text not null,
  description text not null default '', genre_tags text[] not null default '{}',
  is_private boolean not null default false, owner_id uuid not null references public.profiles(id),
  vice_moderator_id uuid references public.profiles(id), is_verified boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.communities (
  id uuid primary key default gen_random_uuid(), name text not null,
  description text not null default '', owner_id uuid not null references public.profiles(id),
  vice_moderator_id uuid references public.profiles(id), is_verified boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.organizations (
  id uuid primary key default gen_random_uuid(), name text not null,
  description text not null default '', mission text not null default '', org_type text not null default 'Other',
  owner_id uuid not null references public.profiles(id), vice_moderator_id uuid references public.profiles(id),
  is_verified boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.schools (
  id uuid primary key default gen_random_uuid(), name text not null,
  description text not null default '', location text not null default '', website text,
  school_type text not null default 'Other', owner_id uuid not null references public.profiles(id),
  vice_moderator_id uuid references public.profiles(id), is_verified boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- Memberships. Each user can have one role per parent entity.
create table public.club_members (
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.member_role not null default 'member', joined_at timestamptz not null default now(),
  primary key (club_id,user_id)
);
create table public.community_members (
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.member_role not null default 'member', joined_at timestamptz not null default now(),
  primary key (community_id,user_id)
);
create table public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.member_role not null default 'member', joined_at timestamptz not null default now(),
  primary key (organization_id,user_id)
);
create table public.school_members (
  school_id uuid not null references public.schools(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.member_role not null default 'member', joined_at timestamptz not null default now(),
  primary key (school_id,user_id)
);

-- Communities always have a broadcast parent channel. Schools can have many channels.
create table public.announcement_groups (
  id uuid primary key default gen_random_uuid(), community_id uuid not null references public.communities(id) on delete cascade,
  name text not null, created_at timestamptz not null default now(), unique(community_id,name)
);
create table public.school_channels (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id) on delete cascade,
  name text not null, description text not null default '', subject text, grade text,
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), unique(school_id,name)
);

-- Books/library.
create table public.club_books (
  id uuid primary key default gen_random_uuid(), club_id uuid references public.clubs(id) on delete set null,
  title text not null, author text not null, description text not null default '', cover_url text,
  content_format text not null default 'markdown' check (content_format = 'markdown'),
  genre_tags text[] not null default '{}', moderation_status public.moderation_status not null default 'pending',
  added_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.book_chapters (
  id uuid primary key default gen_random_uuid(), club_book_id uuid not null references public.club_books(id) on delete cascade,
  chapter_number integer not null check (chapter_number > 0), title text not null, content text not null,
  created_at timestamptz not null default now(), unique(club_book_id,chapter_number)
);

-- All six chat modes.
create table public.chats (
  id uuid primary key default gen_random_uuid(), chat_type public.chat_type not null, title text not null,
  description text, avatar_url text, created_by uuid references public.profiles(id) on delete set null,
  system_account_id uuid references public.profiles(id) on delete restrict,
  entity_id uuid, entity_kind text, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (chat_type <> 'nexus' or entity_id is null)
);
create unique index chats_one_nexus_idx on public.chats(chat_type) where chat_type = 'nexus';
create unique index chats_entity_idx on public.chats(entity_kind,entity_id) where entity_id is not null;
create table public.chat_participants (
  id uuid primary key default gen_random_uuid(), chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade, role public.member_role not null default 'member',
  can_post boolean not null default true, joined_at timestamptz not null default now(),
  last_read_message_id uuid, last_read_at timestamptz, unique(chat_id,user_id)
);
create index chat_participants_user_idx on public.chat_participants(user_id,joined_at desc);
create table public.messages (
  id uuid primary key default gen_random_uuid(), chat_id uuid not null references public.chats(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null, message_type public.chat_message_type not null default 'text',
  body text, metadata jsonb not null default '{}'::jsonb, reply_to uuid references public.messages(id) on delete set null,
  is_pinned boolean not null default false, edited_at timestamptz, created_at timestamptz not null default now(),
  check (body is not null or metadata <> '{}'::jsonb)
);
create index messages_chat_created_idx on public.messages(chat_id,created_at desc);
create table public.message_reactions (
  id uuid primary key default gen_random_uuid(), message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade, emoji text not null check(length(emoji) between 1 and 16),
  created_at timestamptz not null default now(), unique(message_id,user_id,emoji)
);
create table public.poll_votes (
  id uuid primary key default gen_random_uuid(), message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade, option_id text not null,
  created_at timestamptz not null default now(), unique(message_id,user_id)
);

-- Helper authorization functions (security definer avoids recursive RLS checks).
create or replace function public.is_booknest_system_account() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.system_accounts where account_key='booknest' and user_id=auth.uid()); $$;
create or replace function public.is_member(target_chat uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.chat_participants where chat_id=target_chat and user_id=auth.uid()); $$;
create or replace function public.can_post_chat(target_chat uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.chat_participants where chat_id=target_chat and user_id=auth.uid() and can_post)
 and not exists(select 1 from public.chats where id=target_chat and chat_type in ('nexus','community_announcement'))
or exists(select 1 from public.chats c where c.id=target_chat and c.chat_type='nexus' and public.is_booknest_system_account())
or exists(select 1 from public.chats c join public.chat_participants cp on cp.chat_id=c.id where c.id=target_chat and c.chat_type='community_announcement' and cp.user_id=auth.uid() and cp.role in ('owner','moderator')); $$;

-- Signup creates the profile and mandatory Nexus membership atomically.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare nexus_id uuid; username_value text;
begin
 username_value := coalesce(nullif(new.raw_user_meta_data->>'username',''), split_part(new.email,'@',1), 'reader_'||substr(new.id::text,1,8));
 insert into public.profiles(id,username,display_name,phone_number) values(new.id,username_value,coalesce(new.raw_user_meta_data->>'display_name',username_value),new.raw_user_meta_data->>'phone') on conflict(id) do nothing;
 select id into nexus_id from public.chats where chat_type='nexus' limit 1;
 insert into public.chat_participants(chat_id,user_id,role,can_post) values(nexus_id,new.id,'member',false) on conflict(chat_id,user_id) do nothing;
 return new;
end; $$;

-- Entity chat creation and community announcement enrollment.
create or replace function public.create_entity_chat() returns trigger language plpgsql security definer set search_path=public as $$
declare new_chat uuid;
begin
 insert into public.chats(chat_type,title,created_by,entity_id,entity_kind) values(TG_ARGV[0]::public.chat_type,new.name,new.owner_id,new.id,TG_ARGV[1]) returning id into new_chat;
 insert into public.chat_participants(chat_id,user_id,role,can_post) values(new_chat,new.owner_id,'owner',true);
 return new;
end; $$;
create trigger clubs_chat after insert on public.clubs for each row execute function public.create_entity_chat('club','club');
create trigger organizations_chat after insert on public.organizations for each row execute function public.create_entity_chat('organization','organization');
create trigger schools_chat after insert on public.schools for each row execute function public.create_entity_chat('school','school');

create or replace function public.create_announcement_chat() returns trigger language plpgsql security definer set search_path=public as $$
declare cid uuid; owner_id uuid;
begin
 insert into public.chats(chat_type,title,entity_id,entity_kind) values('community_announcement',new.name,new.id,'announcement_group') returning id into cid;
 select owner_id into owner_id from public.communities where id=new.community_id;
 insert into public.chat_participants(chat_id,user_id,role,can_post) values(cid,owner_id,'owner',true);
 return new;
end; $$;
create trigger announcement_chat after insert on public.announcement_groups for each row execute function public.create_announcement_chat();

create or replace function public.enroll_community_chat() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.chat_participants(chat_id,user_id,role,can_post)
 select c.id,new.user_id,case when new.role in ('owner','moderator') then new.role else 'member' end::public.member_role,new.role in ('owner','moderator')
 from public.chats c join public.announcement_groups ag on ag.id=c.entity_id
 where c.chat_type='community_announcement' and ag.community_id=new.community_id
 on conflict(chat_id,user_id) do update set role=excluded.role,can_post=excluded.can_post;
 return new;
end; $$;
create trigger community_member_announcement after insert or update on public.community_members for each row execute function public.enroll_community_chat();

insert into public.chats(chat_type,title,description) values('nexus','The Nexus','Official BookNest announcements and polls');
insert into public.system_accounts(account_key,user_id)
select 'booknest','2457ced9-609a-4ea7-b761-225bb0762513'::uuid
where exists(select 1 from auth.users where id='2457ced9-609a-4ea7-b761-225bb0762513'::uuid)
on conflict(account_key) do update set user_id=excluded.user_id;
update public.profiles set is_official_system=true where id='2457ced9-609a-4ea7-b761-225bb0762513'::uuid;
create or replace function public.prevent_nexus_leave() returns trigger language plpgsql as $$ begin if exists(select 1 from public.chats where id=old.chat_id and chat_type='nexus') then raise exception 'The Nexus cannot be left'; end if; return old; end; $$;
create trigger nexus_no_leave before delete on public.chat_participants for each row execute function public.prevent_nexus_leave();
create trigger auth_user_profile after insert on auth.users for each row execute function public.handle_new_user();

-- RLS: the client never receives service-role privileges.
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.clubs enable row level security;
alter table public.communities enable row level security;
alter table public.organizations enable row level security;
alter table public.schools enable row level security;
alter table public.club_members enable row level security;
alter table public.community_members enable row level security;
alter table public.organization_members enable row level security;
alter table public.school_members enable row level security;
alter table public.club_books enable row level security;
alter table public.book_chapters enable row level security;
alter table public.chats enable row level security;
alter table public.chat_participants enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.poll_votes enable row level security;

create policy profiles_read on public.profiles for select using(true);
create policy profiles_update_self on public.profiles for update using(id=auth.uid()) with check(id=auth.uid() and is_official_system=false);
create policy posts_read on public.posts for select using(is_published or created_by=auth.uid());
create policy posts_insert on public.posts for insert with check(created_by=auth.uid());
create policy posts_update_own on public.posts for update using(created_by=auth.uid()) with check(created_by=auth.uid());
create policy entity_read on public.clubs for select using(not is_private or owner_id=auth.uid() or exists(select 1 from public.club_members where club_id=id and user_id=auth.uid()));
create policy communities_read on public.communities for select using(true);
create policy organizations_read on public.organizations for select using(true);
create policy schools_read on public.schools for select using(true);
create policy club_create on public.clubs for insert with check(owner_id=auth.uid());
create policy community_create on public.communities for insert with check(owner_id=auth.uid());
create policy organization_create on public.organizations for insert with check(owner_id=auth.uid());
create policy school_create on public.schools for insert with check(owner_id=auth.uid());
create policy membership_read on public.club_members for select using(true);
create policy membership_self_join on public.club_members for insert with check(user_id=auth.uid());
create policy community_members_read on public.community_members for select using(true);
create policy community_members_join on public.community_members for insert with check(user_id=auth.uid());
create policy org_members_read on public.organization_members for select using(true);
create policy org_members_join on public.organization_members for insert with check(user_id=auth.uid());
create policy school_members_read on public.school_members for select using(true);
create policy school_members_join on public.school_members for insert with check(user_id=auth.uid());
create policy books_read on public.club_books for select using(moderation_status='approved' or added_by=auth.uid());
create policy books_insert on public.club_books for insert with check(added_by=auth.uid());
create policy chapters_read on public.book_chapters for select using(exists(select 1 from public.club_books b where b.id=club_book_id and (b.moderation_status='approved' or b.added_by=auth.uid())));
create policy chapters_insert on public.book_chapters for insert with check(exists(select 1 from public.club_books b where b.id=club_book_id and b.added_by=auth.uid()));
create policy chats_read on public.chats for select using(public.is_member(id));
create policy participants_read on public.chat_participants for select using(public.is_member(chat_id));
create policy participants_join on public.chat_participants for insert with check(user_id=auth.uid() and role='member' and exists(select 1 from public.chats c where c.id=chat_id and c.chat_type<>'nexus'));
create policy participants_read_update on public.chat_participants for update using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy messages_read on public.messages for select using(public.is_member(chat_id));
create policy messages_insert on public.messages for insert with check(sender_id=auth.uid() and public.can_post_chat(chat_id));
create policy messages_update_own on public.messages for update using(sender_id=auth.uid()) with check(sender_id=auth.uid());
create policy reactions_read on public.message_reactions for select using(exists(select 1 from public.messages m where m.id=message_id and public.is_member(m.chat_id)));
create policy reactions_write on public.message_reactions for all using(user_id=auth.uid()) with check(user_id=auth.uid() and exists(select 1 from public.messages m where m.id=message_id and public.is_member(m.chat_id)));
create policy votes_member on public.poll_votes for all using(user_id=auth.uid()) with check(user_id=auth.uid() and exists(select 1 from public.messages m where m.id=message_id and public.is_member(m.chat_id)));

alter publication supabase_realtime add table public.posts;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.message_reactions;

-- After the official account is created, run:
-- update public.profiles set is_official_system=true where id='BOOKNEST_SYSTEM_PROFILE_UUID';
