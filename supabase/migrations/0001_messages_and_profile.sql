-- ============================================================================
-- BookNest — Migration 0001: Direct Messaging + Profile fields
-- ============================================================================
-- What this adds:
--   1. `profiles.avatar_url` and `profiles.bio` (used by the Profile screen).
--   2. `conversations`, `conversation_members`, `messages` tables for 1-on-1
--      DMs, with Row Level Security (members only).
--   3. `get_or_create_dm(other_user uuid)` RPC — idempotently finds or creates
--      a direct conversation between the caller and another user.
--   4. `get_my_conversations()` RPC — returns the caller's DM list rows with
--      partner profile, last message and unread count in one query.
--   5. A trigger that bumps `conversations.last_message_at` on every insert
--      into `messages` (drives the DM list ordering without client writes).
--   6. Realtime publication for the three new tables (required by the app's
--      `.stream()` subscriptions).
--
-- Run this once in the Supabase SQL editor (or `supabase db push`). It is
-- written to be re-runnable (DROP ... IF EXISTS guards), so re-running it is
-- harmless.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Profiles — extra columns for the Profile screen
-- ----------------------------------------------------------------------------
alter table profiles add column if not exists avatar_url text;
alter table profiles add column if not exists bio text not null default '';

-- ----------------------------------------------------------------------------
-- 1. conversations
-- ----------------------------------------------------------------------------
create table if not exists conversations (
  id              uuid primary key default gen_random_uuid(),
  type            text not null default 'direct' check (type in ('direct', 'group', 'channel')),
  title           text,
  avatar_url      text,
  created_by      uuid references profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 2. conversation_members
-- ----------------------------------------------------------------------------
create table if not exists conversation_members (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  user_id         uuid not null references profiles(id) on delete cascade,
  role            text not null default 'member' check (role in ('owner', 'moderator', 'member')),
  last_read_at    timestamptz,
  joined_at       timestamptz not null default now(),
  unique (conversation_id, user_id)
);

create index if not exists conversation_members_user_idx
  on conversation_members (user_id);
create index if not exists conversation_members_conversation_idx
  on conversation_members (conversation_id);

-- ----------------------------------------------------------------------------
-- 3. messages
-- ----------------------------------------------------------------------------
create table if not exists messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_id       uuid not null references profiles(id) on delete cascade,
  type            text not null default 'text' check (type in ('text', 'image', 'file', 'system')),
  content         text not null default '',
  metadata        jsonb not null default '{}'::jsonb,
  reply_to        uuid references messages(id) on delete set null,
  edited_at       timestamptz,
  created_at      timestamptz not null default now()
);

create index if not exists messages_conversation_created_idx
  on messages (conversation_id, created_at);

-- Realtime streams filter on non-PK columns (`user_id`, `conversation_id`).
-- Full replica identity makes DELETE events carry the full old row, so the
-- app's `.stream()` filters can drop deleted rows instead of leaving ghosts.
alter table conversation_members replica identity full;
alter table messages replica identity full;

-- ----------------------------------------------------------------------------
-- 4. Row Level Security
-- ----------------------------------------------------------------------------
alter table conversations enable row level security;
alter table conversation_members enable row level security;
alter table messages enable row level security;

-- conversations --------------------------------------------------------------
drop policy if exists "members can view their conversations" on conversations;
create policy "members can view their conversations"
  on conversations for select
  using (
    exists (
      select 1 from conversation_members cm
      where cm.conversation_id = id and cm.user_id = auth.uid()
    )
  );

drop policy if exists "users can start conversations" on conversations;
create policy "users can start conversations"
  on conversations for insert
  with check (auth.uid() = created_by);

drop policy if exists "members can update their conversations" on conversations;
create policy "members can update their conversations"
  on conversations for update
  using (
    exists (
      select 1 from conversation_members cm
      where cm.conversation_id = id and cm.user_id = auth.uid()
    )
  );

-- conversation_members ---------------------------------------------------------
drop policy if exists "members can view memberships of their conversations" on conversation_members;
create policy "members can view memberships of their conversations"
  on conversation_members for select
  using (
    exists (
      select 1 from conversation_members me
      where me.conversation_id = conversation_id and me.user_id = auth.uid()
    )
  );

drop policy if exists "users can join as themselves" on conversation_members;
create policy "users can join as themselves"
  on conversation_members for insert
  with check (auth.uid() = user_id);

drop policy if exists "members can update their own membership" on conversation_members;
create policy "members can update their own membership"
  on conversation_members for update
  using (auth.uid() = user_id);

-- messages --------------------------------------------------------------------
drop policy if exists "members can read messages" on messages;
create policy "members can read messages"
  on messages for select
  using (
    exists (
      select 1 from conversation_members cm
      where cm.conversation_id = messages.conversation_id
        and cm.user_id = auth.uid()
    )
  );

drop policy if exists "members can send messages" on messages;
create policy "members can send messages"
  on messages for insert
  with check (
    auth.uid() = sender_id
    and exists (
      select 1 from conversation_members cm
      where cm.conversation_id = messages.conversation_id
        and cm.user_id = auth.uid()
    )
  );

drop policy if exists "members can update their own messages" on messages;
create policy "members can update their own messages"
  on messages for update
  using (auth.uid() = sender_id);

-- ----------------------------------------------------------------------------
-- 5. get_or_create_dm(other_user uuid) -> uuid
--    Idempotently finds (or creates) the direct conversation between the
--    caller and [other_user] and returns its id. SECURITY DEFINER is required
--    so the function can insert the *other* user into conversation_members.
-- ----------------------------------------------------------------------------
create or replace function get_or_create_dm(other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  my_id uuid := auth.uid();
  conv  uuid;
begin
  if my_id is null then
    raise exception 'Not authenticated';
  end if;
  if other_user is null or other_user = my_id then
    raise exception 'Invalid conversation partner';
  end if;

  -- Existing direct conversation between the two users?
  select cm1.conversation_id into conv
  from conversation_members cm1
  join conversation_members cm2 on cm2.conversation_id = cm1.conversation_id
  join conversations c on c.id = cm1.conversation_id
  where cm1.user_id = my_id
    and cm2.user_id = other_user
    and c.type = 'direct'
  limit 1;

  if conv is not null then
    return conv;
  end if;

  insert into conversations (type, created_by)
  values ('direct', my_id)
  returning id into conv;

  insert into conversation_members (conversation_id, user_id)
  values (conv, my_id), (conv, other_user);

  return conv;
end;
$$;

revoke all on function get_or_create_dm(uuid) from public;
grant execute on function get_or_create_dm(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 6. get_my_conversations() — one call powers the whole DM list screen:
--    partner profile + last message + unread count, newest conversation first.
-- ----------------------------------------------------------------------------
create or replace function get_my_conversations()
returns table (
  conversation_id        uuid,
  conversation_created_at timestamptz,
  last_message_at        timestamptz,
  last_message           text,
  last_message_type      text,
  last_sender_id         uuid,
  unread_count           bigint,
  partner_user_id        uuid,
  partner_username       text,
  partner_display_name   text,
  partner_avatar_url     text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    c.id,
    c.created_at,
    c.last_message_at,
    lm.content,
    lm.type,
    lm.sender_id,
    (
      select count(*)
      from messages m
      where m.conversation_id = c.id
        and m.sender_id <> auth.uid()
        and m.created_at > coalesce(
              (select cm.last_read_at
               from conversation_members cm
               where cm.conversation_id = c.id and cm.user_id = auth.uid()),
              '-infinity'::timestamptz
            )
    )::bigint,
    p.id,
    p.username,
    p.display_name,
    p.avatar_url
  from conversations c
  join conversation_members me
    on me.conversation_id = c.id and me.user_id = auth.uid()
  join conversation_members partner
    on partner.conversation_id = c.id and partner.user_id <> auth.uid()
  join profiles p on p.id = partner.user_id
  left join lateral (
    select m.content, m.type, m.sender_id
    from messages m
    where m.conversation_id = c.id
    order by m.created_at desc, m.id desc
    limit 1
  ) lm on true
  order by c.last_message_at desc;
$$;

revoke all on function get_my_conversations() from public;
grant execute on function get_my_conversations() to authenticated;

-- ----------------------------------------------------------------------------
-- 7. Trigger: keep conversations.last_message_at fresh on every new message
-- ----------------------------------------------------------------------------
create or replace function touch_conversation_on_message()
returns trigger
language plpgsql
as $$
begin
  update conversations
     set last_message_at = new.created_at
   where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists messages_touch_conversation on messages;
create trigger messages_touch_conversation
  after insert on messages
  for each row execute function touch_conversation_on_message();

-- ----------------------------------------------------------------------------
-- 8. Realtime publication — the app subscribes to these tables with .stream()
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversations'
  ) then
    alter publication supabase_realtime add table conversations;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversation_members'
  ) then
    alter publication supabase_realtime add table conversation_members;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table messages;
  end if;
end $$;
