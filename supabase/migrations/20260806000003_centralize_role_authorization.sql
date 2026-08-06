-- BookNest step 3: centralize Owner/Moderator/Teacher/Member authorization.
-- Client code must call these functions; role columns are never client-editable.

create or replace function public.has_club_role(target_club uuid, allowed public.member_role[])
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.club_members where club_id=target_club and user_id=auth.uid() and role=any(allowed));
$$;
create or replace function public.has_community_role(target_community uuid, allowed public.member_role[])
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.community_members where community_id=target_community and user_id=auth.uid() and role=any(allowed));
$$;
create or replace function public.has_organization_role(target_organization uuid, allowed public.member_role[])
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.organization_members where organization_id=target_organization and user_id=auth.uid() and role=any(allowed));
$$;
create or replace function public.has_school_role(target_school uuid, allowed public.member_role[])
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.school_members where school_id=target_school and user_id=auth.uid() and role=any(allowed));
$$;

create or replace function public.can_manage_club(target_club uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.clubs where id=target_club and owner_id=auth.uid()) or public.has_club_role(target_club,array['owner','vice_moderator','moderator']::public.member_role[]);
$$;
create or replace function public.can_manage_community(target_community uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.communities where id=target_community and owner_id=auth.uid()) or public.has_community_role(target_community,array['owner','vice_moderator','moderator']::public.member_role[]);
$$;
create or replace function public.can_manage_organization(target_organization uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.organizations where id=target_organization and owner_id=auth.uid()) or public.has_organization_role(target_organization,array['owner','vice_moderator','moderator']::public.member_role[]);
$$;
create or replace function public.can_manage_school(target_school uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.schools where id=target_school and owner_id=auth.uid()) or public.has_school_role(target_school,array['owner','vice_moderator','moderator','teacher']::public.member_role[]);
$$;

-- Safe read-state mutation. It does not expose role/can_post updates to clients.
create or replace function public.mark_chat_read(target_chat uuid, target_message uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.chat_participants
  set last_read_message_id=target_message, last_read_at=now()
  where chat_id=target_chat and user_id=auth.uid();
  if not found then raise exception 'You are not a member of this chat'; end if;
end;
$$;
grant execute on function public.mark_chat_read(uuid,uuid) to authenticated;

-- Membership role assignment is a management action, not a self-service action.
drop policy if exists membership_self_join on public.club_members;
drop policy if exists community_members_join on public.community_members;
drop policy if exists org_members_join on public.organization_members;
drop policy if exists school_members_join on public.school_members;
create policy membership_self_join on public.club_members for insert with check(user_id=auth.uid() and role='member');
create policy community_members_join on public.community_members for insert with check(user_id=auth.uid() and role='member');
create policy org_members_join on public.organization_members for insert with check(user_id=auth.uid() and role='member');
create policy school_members_join on public.school_members for insert with check(user_id=auth.uid() and role='member');
create policy club_members_manage on public.club_members for update using(public.can_manage_club(club_id)) with check(public.can_manage_club(club_id));
create policy community_members_manage on public.community_members for update using(public.can_manage_community(community_id)) with check(public.can_manage_community(community_id));
create policy organization_members_manage on public.organization_members for update using(public.can_manage_organization(organization_id)) with check(public.can_manage_organization(organization_id));
create policy school_members_manage on public.school_members for update using(public.can_manage_school(school_id)) with check(public.can_manage_school(school_id));
create policy club_members_remove on public.club_members for delete using(user_id=auth.uid() or public.can_manage_club(club_id));
create policy community_members_remove on public.community_members for delete using(user_id=auth.uid() or public.can_manage_community(community_id));
create policy organization_members_remove on public.organization_members for delete using(user_id=auth.uid() or public.can_manage_organization(organization_id));
create policy school_members_remove on public.school_members for delete using(user_id=auth.uid() or public.can_manage_school(school_id));

-- Parent-entity edits are restricted to Owners and Moderators.
create policy clubs_manage on public.clubs for update using(public.can_manage_club(id)) with check(public.can_manage_club(id));
create policy communities_manage on public.communities for update using(public.can_manage_community(id)) with check(public.can_manage_community(id));
create policy organizations_manage on public.organizations for update using(public.can_manage_organization(id)) with check(public.can_manage_organization(id));
create policy schools_manage on public.schools for update using(public.can_manage_school(id)) with check(public.can_manage_school(id));

-- Chat roles and posting rights can only be changed by the owning entity role.
drop policy if exists participants_read_update on public.chat_participants;
drop policy if exists participants_update_self on public.chat_participants;
create policy participants_update_read_state on public.chat_participants for update using(user_id=auth.uid()) with check(user_id=auth.uid());
-- The policy above is retained for compatibility, but direct role changes are
-- prevented by the trigger below. The app uses mark_chat_read for read state.
create or replace function public.prevent_client_chat_role_change()
returns trigger language plpgsql as $$
begin
  if (new.role, new.can_post) is distinct from (old.role, old.can_post)
     and current_user <> 'postgres' then
    raise exception 'Chat role and posting rights are managed by BookNest authorization';
  end if;
  return new;
end;
$$;
drop trigger if exists protect_chat_role on public.chat_participants;
create trigger protect_chat_role before update on public.chat_participants
for each row execute function public.prevent_client_chat_role_change();

-- Resource/channel creation is controlled by the parent role.
create policy school_channels_read on public.school_channels for select using(public.has_school_role(school_id,array['owner','vice_moderator','moderator','teacher','member']::public.member_role[]));
create policy school_channels_manage on public.school_channels for insert with check(public.can_manage_school(school_id) and created_by=auth.uid());
create policy school_channels_update on public.school_channels for update using(public.can_manage_school(school_id)) with check(public.can_manage_school(school_id));
create policy school_channels_delete on public.school_channels for delete using(public.can_manage_school(school_id));

-- Only moderators can change a book's moderation state.
create or replace function public.moderate_book(target_book uuid, next_status public.moderation_status)
returns void language plpgsql security definer set search_path=public as $$
declare target_club uuid;
begin
 select club_id into target_club from public.club_books where id=target_book;
 if target_club is null or not public.can_manage_club(target_club) then raise exception 'Only Club Owners or Moderators can moderate books'; end if;
 update public.club_books set moderation_status=next_status, updated_at=now() where id=target_book;
end;
$$;
grant execute on function public.moderate_book(uuid,public.moderation_status) to authenticated;
