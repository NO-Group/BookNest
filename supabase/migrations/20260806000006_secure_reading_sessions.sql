-- Secure reading time: the server owns session timestamps and minute totals.
alter table public.reading_sessions add column if not exists last_heartbeat timestamptz;
alter table public.reading_sessions add column if not exists closed_at timestamptz;

drop policy if exists reading_owner_insert on public.reading_sessions;
revoke insert, update, delete on public.reading_sessions from anon, authenticated;

create or replace function public.start_reading_session(target_book uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare session_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from public.club_books where id=target_book and moderation_status='approved') then raise exception 'Book is not available for reading'; end if;
 -- One active session per user prevents parallel clients multiplying time.
 update public.reading_sessions set closed_at=now(), ended_at=now(), minutes=least(720,greatest(0,floor(extract(epoch from (now()-started_at))/60)::integer))
 where user_id=auth.uid() and closed_at is null;
 insert into public.reading_sessions(user_id,book_id,started_at,last_heartbeat)
 values(auth.uid(),target_book,now(),now()) returning id into session_id;
 return session_id;
end;
$$;

grant execute on function public.start_reading_session(uuid) to authenticated;

create or replace function public.heartbeat_reading_session(target_session uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 update public.reading_sessions set last_heartbeat=now()
 where id=target_session and user_id=auth.uid() and closed_at is null;
 if not found then raise exception 'Reading session is not active'; end if;
end;
$$;
grant execute on function public.heartbeat_reading_session(uuid) to authenticated;

create or replace function public.finish_reading_session(target_session uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare total integer;
begin
 update public.reading_sessions
 set ended_at=coalesce(ended_at,now()), closed_at=coalesce(closed_at,now()),
     minutes=least(720,greatest(0,floor(extract(epoch from (coalesce(closed_at,now())-started_at))/60)::integer))
 where id=target_session and user_id=auth.uid() and closed_at is null
 returning minutes into total;
 return coalesce(total,0);
end;
$$;
grant execute on function public.finish_reading_session(uuid) to authenticated;

create or replace function public.get_my_reading_stats()
returns table(total_minutes bigint, current_month_minutes bigint, books_read bigint)
language sql stable security definer set search_path=public as $$
 select
   coalesce((select sum(minutes)::bigint from public.reading_sessions where user_id=auth.uid()),0),
   coalesce((select sum(minutes)::bigint from public.reading_sessions where user_id=auth.uid() and started_at >= date_trunc('month',now())),0),
   coalesce((select count(distinct book_id)::bigint from public.reading_sessions where user_id=auth.uid() and minutes > 0),0);
$$;
grant execute on function public.get_my_reading_stats() to authenticated;

drop policy if exists reading_owner_read on public.reading_sessions;
create policy reading_owner_read on public.reading_sessions for select using(user_id=auth.uid());
