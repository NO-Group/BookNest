-- ============================================================================
-- BookNest — Migration 0002: Groups (all entities), community core, roles,
--                            read tracking (Hot 🔥), drafts, storage buckets
-- ============================================================================
-- Adds:
--   1. `club_books.community_id` + `'draft'` moderation status + `views` count.
--   2. `groups` (one per entity type: community/club/organization/school),
--      `group_members` (owner/admin/member), `message_reactions`,
--      `book_reads` (read log), `community_books` (community library reposts).
--   3. Roles: entity Owner (ultimate) vs per-group Admin (delete/pin messages,
--      remove normal members, promote members to admin — never touch the owner).
--   4. Default groups auto-created on entity creation: communities get an
--      Announcements group (admin/owner-only posting) + a normal Chat group;
--      clubs/organizations/schools get a normal Chat group. Owner-only group
--      creation afterwards via the `create_group` RPC.
--   5. Sync triggers: joining/leaving an entity adds/removes the user in all
--      of that entity's groups + group conversations.
--   6. RPCs: `record_book_read` (deduped, powers Hot 🔥), `get_hot_books`,
--      `create_group` (owner-only), `is_entity_member` / `is_entity_owner`
--      helpers.
--   7. Storage buckets `avatars` + `attachments` (public read, authenticated
--      upload) for profile pictures (now) and HD attachments (next session).
--
-- Re-runnable (DROP ... IF EXISTS / IF NOT EXISTS guards).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. club_books: community linkage, draft status, views counter
-- ----------------------------------------------------------------------------
alter table club_books add column if not exists community_id uuid
  references communities(id) on delete set null;
alter table club_books add column if not exists views integer not null default 0;

alter table club_books drop constraint if exists club_books_moderation_status_check;
alter table club_books add constraint club_books_moderation_status_check
  check (moderation_status in ('draft', 'pending', 'approved', 'rejected'));

-- ----------------------------------------------------------------------------
-- 2. conversation_members: add 'admin' role (group admins)
-- ----------------------------------------------------------------------------
alter table conversation_members drop constraint if exists conversation_members_role_check;
alter table conversation_members add constraint conversation_members_role_check
  check (role in ('owner', 'admin', 'moderator', 'member'));

-- ----------------------------------------------------------------------------
-- 3. messages: pinned flag
-- ----------------------------------------------------------------------------
alter table messages add column if not exists is_pinned boolean not null default false;

-- ----------------------------------------------------------------------------
-- 4. New tables
-- ----------------------------------------------------------------------------
create table if not exists groups (
  id              uuid primary key default gen_random_uuid(),
  entity_type     text not null check (entity_type in ('community', 'club', 'organization', 'school')),
  entity_id       uuid not null,
  name            text not null,
  group_type      text not null default 'regular' check (group_type in ('announcement', 'regular')),
  conversation_id uuid not null references conversations(id) on delete cascade,
  is_default      boolean not null default false,
  created_by      uuid references profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  unique (entity_type, entity_id, name)
);

create index if not exists groups_entity_idx on groups (entity_type, entity_id);
create index if not exists groups_conversation_idx on groups (conversation_id);

create table if not exists group_members (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references groups(id) on delete cascade,
  user_id    uuid not null references profiles(id) on delete cascade,
  role       text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at  timestamptz not null default now(),
  unique (group_id, user_id)
);

create index if not exists group_members_user_idx on group_members (user_id);
create index if not exists group_members_group_idx on group_members (group_id);

create table if not exists message_reactions (
  id         uuid primary key default gen_random_uuid(),
  message_id uuid not null references messages(id) on delete cascade,
  user_id    uuid not null references profiles(id) on delete cascade,
  reaction   text not null default 'like',
  created_at timestamptz not null default now(),
  unique (message_id, user_id)
);

create table if not exists book_reads (
  id           uuid primary key default gen_random_uuid(),
  club_book_id uuid not null references club_books(id) on delete cascade,
  user_id      uuid references profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);

create index if not exists book_reads_book_created_idx
  on book_reads (club_book_id, created_at);

create table if not exists community_books (
  id            uuid primary key default gen_random_uuid(),
  community_id  uuid not null references communities(id) on delete cascade,
  club_book_id  uuid not null references club_books(id) on delete cascade,
  added_by      uuid references profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  unique (community_id, club_book_id)
);

-- ----------------------------------------------------------------------------
-- 5. Unique pair constraints on entity member tables (needed by sync triggers
--    and backfill idempotency)
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'community_members_pair') then
    alter table community_members add constraint community_members_pair unique (community_id, user_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'club_members_pair') then
    alter table club_members add constraint club_members_pair unique (club_id, user_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'organization_members_pair') then
    alter table organization_members add constraint organization_members_pair unique (organization_id, user_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'school_members_pair') then
    alter table school_members add constraint school_members_pair unique (school_id, user_id);
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 6. Helper functions: entity membership / ownership
-- ----------------------------------------------------------------------------
create or replace function is_entity_member(e_type text, e_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case e_type
    when 'community'    then exists (select 1 from community_members cm where cm.community_id = e_id and cm.user_id = uid)
    when 'club'         then exists (select 1 from club_members cm where cm.club_id = e_id and cm.user_id = uid)
    when 'organization' then exists (select 1 from organization_members cm where cm.organization_id = e_id and cm.user_id = uid)
    when 'school'       then exists (select 1 from school_members cm where cm.school_id = e_id and cm.user_id = uid)
    else false
  end;
$$;

create or replace function is_entity_owner(e_type text, e_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case e_type
    when 'community'    then exists (select 1 from communities c where c.id = e_id and c.owner_id = uid)
    when 'club'         then exists (select 1 from clubs c where c.id = e_id and c.owner_id = uid)
    when 'organization' then exists (select 1 from organizations c where c.id = e_id and c.owner_id = uid)
    when 'school'       then exists (select 1 from schools c where c.id = e_id and c.owner_id = uid)
    else false
  end;
$$;

create or replace function entity_owner_id(e_type text, e_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select case e_type
    when 'community'    then (select owner_id from communities where id = e_id)
    when 'club'         then (select owner_id from clubs where id = e_id)
    when 'organization' then (select owner_id from organizations where id = e_id)
    when 'school'       then (select owner_id from schools where id = e_id)
  end;
$$;

-- ----------------------------------------------------------------------------
-- 7. Default groups on entity creation + member seeding
-- ----------------------------------------------------------------------------
create or replace function seed_group_members(gid uuid, e_type text, e_id uuid, owner uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Entity members (excluding the owner) become regular members.
  if e_type = 'community' then
    insert into group_members (group_id, user_id, role)
    select gid, cm.user_id, 'member' from community_members cm
    where cm.community_id = e_id and cm.user_id <> owner
    on conflict (group_id, user_id) do nothing;
    insert into conversation_members (conversation_id, user_id)
    select g.conversation_id, cm.user_id
    from groups g cross join community_members cm
    where g.id = gid and cm.community_id = e_id and cm.user_id <> owner
    on conflict (conversation_id, user_id) do nothing;
  elsif e_type = 'club' then
    insert into group_members (group_id, user_id, role)
    select gid, cm.user_id, 'member' from club_members cm
    where cm.club_id = e_id and cm.user_id <> owner
    on conflict (group_id, user_id) do nothing;
    insert into conversation_members (conversation_id, user_id)
    select g.conversation_id, cm.user_id
    from groups g cross join club_members cm
    where g.id = gid and cm.club_id = e_id and cm.user_id <> owner
    on conflict (conversation_id, user_id) do nothing;
  elsif e_type = 'organization' then
    insert into group_members (group_id, user_id, role)
    select gid, cm.user_id, 'member' from organization_members cm
    where cm.organization_id = e_id and cm.user_id <> owner
    on conflict (group_id, user_id) do nothing;
    insert into conversation_members (conversation_id, user_id)
    select g.conversation_id, cm.user_id
    from groups g cross join organization_members cm
    where g.id = gid and cm.organization_id = e_id and cm.user_id <> owner
    on conflict (conversation_id, user_id) do nothing;
  elsif e_type = 'school' then
    insert into group_members (group_id, user_id, role)
    select gid, cm.user_id, 'member' from school_members cm
    where cm.school_id = e_id and cm.user_id <> owner
    on conflict (group_id, user_id) do nothing;
    insert into conversation_members (conversation_id, user_id)
    select g.conversation_id, cm.user_id
    from groups g cross join school_members cm
    where g.id = gid and cm.school_id = e_id and cm.user_id <> owner
    on conflict (conversation_id, user_id) do nothing;
  end if;
end;
$$;

create or replace function ensure_entity_default_groups(p_type text, p_id uuid, p_owner uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  conv uuid;
  gid  uuid;
begin
  -- Communities get an Announcements group (admin/owner-only posting).
  if p_type = 'community' and not exists (
    select 1 from groups where entity_type = p_type and entity_id = p_id and group_type = 'announcement'
  ) then
    insert into conversations (type, title, created_by)
    values ('group', p_name || ' Announcements', p_owner) returning id into conv;
    insert into groups (entity_type, entity_id, name, group_type, conversation_id, is_default, created_by)
    values (p_type, p_id, p_name || ' Announcements', 'announcement', conv, true, p_owner)
    returning id into gid;
    insert into conversation_members (conversation_id, user_id, role) values (conv, p_owner, 'owner');
    insert into group_members (group_id, user_id, role) values (gid, p_owner, 'owner');
    perform seed_group_members(gid, p_type, p_id, p_owner);
  end if;

  -- Every entity gets a default Chat group (everyone can talk).
  if not exists (
    select 1 from groups where entity_type = p_type and entity_id = p_id and is_default and group_type = 'regular'
  ) then
    insert into conversations (type, title, created_by)
    values ('group', p_name || ' Chat', p_owner) returning id into conv;
    insert into groups (entity_type, entity_id, name, group_type, conversation_id, is_default, created_by)
    values (p_type, p_id, p_name || ' Chat', 'regular', conv, true, p_owner)
    returning id into gid;
    insert into conversation_members (conversation_id, user_id, role) values (conv, p_owner, 'owner');
    insert into group_members (group_id, user_id, role) values (gid, p_owner, 'owner');
    perform seed_group_members(gid, p_type, p_id, p_owner);
  end if;
end;
$$;

-- Trigger wrappers per entity table
create or replace function ensure_entity_default_groups_trigger()
returns trigger
language plpgsql
as $$
begin
  perform ensure_entity_default_groups(
    (case when TG_TABLE_NAME = 'communities' then 'community'
          when TG_TABLE_NAME = 'clubs' then 'club'
          when TG_TABLE_NAME = 'organizations' then 'organization'
          when TG_TABLE_NAME = 'schools' then 'school' end),
    new.id,
    new.owner_id,
    coalesce(new.name, 'Community')
  );
  return new;
end;
$$;

drop trigger if exists communities_ensure_default_groups on communities;
create trigger communities_ensure_default_groups
  after insert on communities for each row execute function ensure_entity_default_groups_trigger();

drop trigger if exists clubs_ensure_default_groups on clubs;
create trigger clubs_ensure_default_groups
  after insert on clubs for each row execute function ensure_entity_default_groups_trigger();

drop trigger if exists organizations_ensure_default_groups on organizations;
create trigger organizations_ensure_default_groups
  after insert on organizations for each row execute function ensure_entity_default_groups_trigger();

drop trigger if exists schools_ensure_default_groups on schools;
create trigger schools_ensure_default_groups
  after insert on schools for each row execute function ensure_entity_default_groups_trigger();

-- ----------------------------------------------------------------------------
-- 8. Sync triggers: joining/leaving an entity joins/leaves all its groups
-- ----------------------------------------------------------------------------
create or replace function sync_entity_member_to_groups()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  e_type text;
  e_id   uuid;
  uid    uuid;
begin
  case TG_TABLE_NAME
    when 'community_members' then
      e_type := 'community'; e_id := coalesce(new.community_id, old.community_id); uid := coalesce(new.user_id, old.user_id);
    when 'club_members' then
      e_type := 'club'; e_id := coalesce(new.club_id, old.club_id); uid := coalesce(new.user_id, old.user_id);
    when 'organization_members' then
      e_type := 'organization'; e_id := coalesce(new.organization_id, old.organization_id); uid := coalesce(new.user_id, old.user_id);
    when 'school_members' then
      e_type := 'school'; e_id := coalesce(new.school_id, old.school_id); uid := coalesce(new.user_id, old.user_id);
    else
      return null;
  end case;

  if TG_OP = 'INSERT' then
    insert into group_members (group_id, user_id, role)
    select g.id, uid, 'member' from groups g
    where g.entity_type = e_type and g.entity_id = e_id
    on conflict (group_id, user_id) do nothing;

    insert into conversation_members (conversation_id, user_id, role)
    select g.conversation_id, uid, 'member' from groups g
    where g.entity_type = e_type and g.entity_id = e_id
    on conflict (conversation_id, user_id) do nothing;
  elsif TG_OP = 'DELETE' then
    delete from group_members gm
    using groups g
    where gm.group_id = g.id and g.entity_type = e_type and g.entity_id = e_id
      and gm.user_id = uid and gm.role = 'member';

    delete from conversation_members cm
    using groups g
    where cm.conversation_id = g.conversation_id and g.entity_type = e_type and g.entity_id = e_id
      and cm.user_id = uid;
  end if;

  return null;
end;
$$;

drop trigger if exists sync_community_members_groups on community_members;
create trigger sync_community_members_groups
  after insert or delete on community_members for each row execute function sync_entity_member_to_groups();

drop trigger if exists sync_club_members_groups on club_members;
create trigger sync_club_members_groups
  after insert or delete on club_members for each row execute function sync_entity_member_to_groups();

drop trigger if exists sync_organization_members_groups on organization_members;
create trigger sync_organization_members_groups
  after insert or delete on organization_members for each row execute function sync_entity_member_to_groups();

drop trigger if exists sync_school_members_groups on school_members;
create trigger sync_school_members_groups
  after insert or delete on school_members for each row execute function sync_entity_member_to_groups();

-- ----------------------------------------------------------------------------
-- 9. Owner-only group creation RPC
-- ----------------------------------------------------------------------------
create or replace function create_group(e_type text, e_id uuid, group_name text, g_type text default 'regular')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  gid uuid;
  conv uuid;
  owner uuid;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  if g_type not in ('announcement', 'regular') then
    raise exception 'Invalid group type';
  end if;
  if not is_entity_owner(e_type, e_id, uid) then
    raise exception 'Only the owner can create groups';
  end if;
  if exists (select 1 from groups where entity_type = e_type and entity_id = e_id and name = group_name) then
    raise exception 'A group with this name already exists';
  end if;

  owner := entity_owner_id(e_type, e_id);
  insert into conversations (type, title, created_by)
  values ('group', group_name, uid) returning id into conv;

  insert into groups (entity_type, entity_id, name, group_type, conversation_id, is_default, created_by)
  values (e_type, e_id, group_name, g_type, conv, false, uid)
  returning id into gid;

  insert into conversation_members (conversation_id, user_id, role) values (conv, owner, 'owner');
  insert into group_members (group_id, user_id, role) values (gid, owner, 'owner');
  perform seed_group_members(gid, e_type, e_id, owner);

  return gid;
end;
$$;

revoke all on function create_group(text, uuid, text, text) from public;
grant execute on function create_group(text, uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 10. Read tracking (Hot 🔥)
-- ----------------------------------------------------------------------------
create or replace function record_book_read(book_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into book_reads (club_book_id, user_id)
  select book_id, auth.uid()
  where auth.uid() is not null
    and not exists (
      select 1 from book_reads br
      where br.club_book_id = book_id and br.user_id = auth.uid()
        and br.created_at > now() - interval '1 day'
    );
$$;

revoke all on function record_book_read(uuid) from public;
grant execute on function record_book_read(uuid) to authenticated;

-- Keep club_books.views in sync with the read log (drives Hot 🔥 tie-break
-- and the view counters shown on book cards / profiles).
create or replace function book_reads_bump_views()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update club_books set views = views + 1 where id = new.club_book_id;
  return new;
end;
$$;

drop trigger if exists book_reads_bump_views on book_reads;
create trigger book_reads_bump_views
  after insert on book_reads
  for each row execute function book_reads_bump_views();

create or replace function get_hot_books(days int default 7, max_count int default 30)
returns setof club_books
language sql
stable
security definer
set search_path = public
as $$
  select cb.*
  from club_books cb
  where cb.moderation_status = 'approved'
  order by (
    select count(*) from book_reads br
    where br.club_book_id = cb.id and br.created_at > now() - make_interval(days => days)
  ) desc, cb.views desc, cb.created_at desc
  limit max_count;
$$;

revoke all on function get_hot_books(int, int) from public;
grant execute on function get_hot_books(int, int) to authenticated;

-- ----------------------------------------------------------------------------
-- 11. Row Level Security
-- ----------------------------------------------------------------------------
alter table groups enable row level security;
alter table group_members enable row level security;
alter table message_reactions enable row level security;
alter table book_reads enable row level security;
alter table community_books enable row level security;

-- club_books: approved = public; drafts/pending = author or community members
alter table club_books enable row level security;

drop policy if exists "public reads approved books" on club_books;
create policy "public reads approved books"
  on club_books for select
  using (
    moderation_status = 'approved'
    or added_by = auth.uid()
    or exists (
      select 1 from community_members cm
      where cm.community_id = club_books.community_id and cm.user_id = auth.uid()
    )
  );

drop policy if exists "authors insert books" on club_books;
create policy "authors insert books"
  on club_books for insert
  with check (added_by = auth.uid());

drop policy if exists "authors update their books" on club_books;
create policy "authors update their books"
  on club_books for update
  using (added_by = auth.uid())
  with check (added_by = auth.uid());

drop policy if exists "authors delete their books" on club_books;
create policy "authors delete their books"
  on club_books for delete
  using (added_by = auth.uid());

-- groups ----------------------------------------------------------------------
drop policy if exists "entity members can view groups" on groups;
create policy "entity members can view groups"
  on groups for select
  using (
    is_entity_member(entity_type, entity_id, auth.uid())
    or is_entity_owner(entity_type, entity_id, auth.uid())
    or exists (
      select 1 from group_members gm
      where gm.group_id = groups.id and gm.user_id = auth.uid()
    )
  );

-- group_members ---------------------------------------------------------------
drop policy if exists "group members can view members" on group_members;
create policy "group members can view members"
  on group_members for select
  using (
    exists (
      select 1 from group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
    )
    or is_entity_member(
         (select entity_type from groups g where g.id = group_id),
         (select entity_id from groups g where g.id = group_id),
         auth.uid())
    or is_entity_owner(
         (select entity_type from groups g where g.id = group_id),
         (select entity_id from groups g where g.id = group_id),
         auth.uid())
  );

drop policy if exists "admins can add members" on group_members;
create policy "admins can add members"
  on group_members for insert
  with check (
    exists (
      select 1 from group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
        and gm2.role in ('owner', 'admin')
    )
    and is_entity_member(
          (select entity_type from groups g where g.id = group_id),
          (select entity_id from groups g where g.id = group_id),
          user_id)
  );

drop policy if exists "admins can manage members" on group_members;
create policy "admins can manage members"
  on group_members for update
  using (
    exists (
      select 1 from group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
        and gm2.role in ('owner', 'admin')
    )
    and user_id <> (
      select entity_owner_id(g.entity_type, g.entity_id)
      from groups g where g.id = group_id
    )
  );

drop policy if exists "admins can remove members" on group_members;
create policy "admins can remove members"
  on group_members for delete
  using (
    role = 'member'
    and exists (
      select 1 from group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
        and gm2.role in ('owner', 'admin')
    )
    and user_id <> (
      select entity_owner_id(g.entity_type, g.entity_id)
      from groups g where g.id = group_id
    )
  );

-- messages: announcement groups are owner/admin-only for posting --------------
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
    and (
      not exists (
        select 1 from groups g
        where g.conversation_id = messages.conversation_id
          and g.group_type = 'announcement'
      )
      or exists (
        select 1 from groups g
        join group_members gm on gm.group_id = g.id
        where g.conversation_id = messages.conversation_id
          and g.group_type = 'announcement'
          and gm.user_id = auth.uid()
          and gm.role in ('owner', 'admin')
      )
    )
  );

drop policy if exists "members can delete their own messages" on messages;
create policy "members can delete their own messages"
  on messages for delete
  using (
    auth.uid() = sender_id
    or exists (
      select 1 from groups g
      join group_members gm on gm.group_id = g.id
      where g.conversation_id = messages.conversation_id
        and gm.user_id = auth.uid()
        and gm.role in ('owner', 'admin')
    )
  );

drop policy if exists "admins can update group messages" on messages;
create policy "admins can update group messages"
  on messages for update
  using (
    exists (
      select 1 from groups g
      join group_members gm on gm.group_id = g.id
      where g.conversation_id = messages.conversation_id
        and gm.user_id = auth.uid()
        and gm.role in ('owner', 'admin')
    )
  );

-- Pin guard: only owners/admins of the group may pin messages. (Triggers run
-- with the definer's privileges; check group_members explicitly.)
create or replace function enforce_pin_permission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_pinned is distinct from old.is_pinned then
    if not exists (
      select 1 from groups g
      join group_members gm on gm.group_id = g.id
      where g.conversation_id = new.conversation_id
        and gm.user_id = auth.uid()
        and gm.role in ('owner', 'admin')
    ) then
      raise exception 'Only group admins can pin messages';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists messages_pin_permission on messages;
create trigger messages_pin_permission
  before update of is_pinned on messages
  for each row execute function enforce_pin_permission();

-- message_reactions ------------------------------------------------------------
drop policy if exists "conversation members can react" on message_reactions;
create policy "conversation members can react"
  on message_reactions for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from messages m
      join conversation_members cm on cm.conversation_id = m.conversation_id
      where m.id = message_id and cm.user_id = auth.uid()
    )
  );

drop policy if exists "conversation members can view reactions" on message_reactions;
create policy "conversation members can view reactions"
  on message_reactions for select
  using (
    exists (
      select 1 from messages m
      join conversation_members cm on cm.conversation_id = m.conversation_id
      where m.id = message_id and cm.user_id = auth.uid()
    )
  );

drop policy if exists "users can remove their own reactions" on message_reactions;
create policy "users can remove their own reactions"
  on message_reactions for delete
  using (auth.uid() = user_id);

-- book_reads: private log; only the RPCs touch it -----------------------------
drop policy if exists "users can view their own reads" on book_reads;
create policy "users can view their own reads"
  on book_reads for select
  using (user_id = auth.uid());

-- community_books ---------------------------------------------------------------
drop policy if exists "members can view community books" on community_books;
create policy "members can view community books"
  on community_books for select
  using (
    exists (
      select 1 from community_members cm
      where cm.community_id = community_id and cm.user_id = auth.uid()
    )
    or exists (
      select 1 from communities c where c.id = community_id and c.owner_id = auth.uid()
    )
  );

drop policy if exists "members can add community books" on community_books;
create policy "members can add community books"
  on community_books for insert
  with check (
    exists (
      select 1 from community_members cm
      where cm.community_id = community_id and cm.user_id = auth.uid()
    )
    or exists (
      select 1 from communities c where c.id = community_id and c.owner_id = auth.uid()
    )
  );

drop policy if exists "adders can remove community books" on community_books;
create policy "adders can remove community books"
  on community_books for delete
  using (
    added_by = auth.uid()
    or exists (
      select 1 from communities c where c.id = community_id and c.owner_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 12. DM list: only direct conversations (groups get their own list)
-- ----------------------------------------------------------------------------
create or replace function get_my_conversations()
returns table (
  conversation_id         uuid,
  conversation_created_at timestamptz,
  last_message_at         timestamptz,
  last_message            text,
  last_message_type       text,
  last_sender_id          uuid,
  unread_count            bigint,
  partner_user_id         uuid,
  partner_username        text,
  partner_display_name    text,
  partner_avatar_url      text
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
  where c.type = 'direct'
  order by c.last_message_at desc;
$$;

revoke all on function get_my_conversations() from public;
grant execute on function get_my_conversations() to authenticated;

-- ----------------------------------------------------------------------------
-- 13. Storage buckets: avatars + attachments
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true),
       ('attachments', 'attachments', true)
on conflict (id) do nothing;

drop policy if exists "public read media" on storage.objects;
create policy "public read media"
  on storage.objects for select
  using (bucket_id in ('avatars', 'attachments'));

drop policy if exists "authenticated upload media" on storage.objects;
create policy "authenticated upload media"
  on storage.objects for insert
  with check (
    bucket_id in ('avatars', 'attachments')
    and auth.role() = 'authenticated'
  );

drop policy if exists "owners update media" on storage.objects;
create policy "owners update media"
  on storage.objects for update
  using (
    bucket_id in ('avatars', 'attachments')
    and owner = auth.uid()
  );

-- ----------------------------------------------------------------------------
-- 14. Backfill for existing data
-- ----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  -- Owners into their entity member tables (creates group membership too via
  -- the sync triggers on INSERT).
  for r in select id, owner_id from communities where owner_id is not null loop
    insert into community_members (community_id, user_id, role) values (r.id, r.owner_id, 'owner')
    on conflict (community_id, user_id) do nothing;
  end loop;
  for r in select id, owner_id from clubs where owner_id is not null loop
    insert into club_members (club_id, user_id, role) values (r.id, r.owner_id, 'owner')
    on conflict (club_id, user_id) do nothing;
  end loop;
  for r in select id, owner_id from organizations where owner_id is not null loop
    insert into organization_members (organization_id, user_id, role) values (r.id, r.owner_id, 'owner')
    on conflict (organization_id, user_id) do nothing;
  end loop;
  for r in select id, owner_id from schools where owner_id is not null loop
    insert into school_members (school_id, user_id, role) values (r.id, r.owner_id, 'owner')
    on conflict (school_id, user_id) do nothing;
  end loop;

  -- Default groups for everything that already exists.
  for r in select id, owner_id, name from communities loop
    perform ensure_entity_default_groups('community', r.id, r.owner_id, coalesce(r.name, 'Community'));
  end loop;
  for r in select id, owner_id, name from clubs loop
    perform ensure_entity_default_groups('club', r.id, r.owner_id, coalesce(r.name, 'Club'));
  end loop;
  for r in select id, owner_id, name from organizations loop
    perform ensure_entity_default_groups('organization', r.id, r.owner_id, coalesce(r.name, 'Organization'));
  end loop;
  for r in select id, owner_id, name from schools loop
    perform ensure_entity_default_groups('school', r.id, r.owner_id, coalesce(r.name, 'School'));
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 15. Realtime publication for the new tables
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['groups', 'group_members', 'message_reactions', 'book_reads', 'community_books'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table %I', t);
    end if;
  end loop;
end $$;
