-- ============================================================================
-- BookNest 2.38 · Profile cover photos
-- ============================================================================
-- Readers can set a wide cover photo above their profile, next to the
-- profile photo. Like avatar_url it holds a Cloudinary URL only (the image
-- itself lives on Cloudinary). Readers write it through the existing
-- "update own row" policy; it is not privileged.
--
-- Idempotent: safe to run on every deploy.
-- ============================================================================

alter table if exists public.profiles
  add column if not exists cover_url text;

-- Refuse anything that is not an https URL (or empty), and keep it short.
do $$
begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'profiles')
     and not exists (select 1 from pg_constraint
                     where conname = 'profiles_cover_url_https') then
    alter table public.profiles
      add constraint profiles_cover_url_https
      check (cover_url is null or cover_url = ''
             or (cover_url like 'https://%' and length(cover_url) <= 600));
  end if;
end $$;

-- PostgREST picks the new column up immediately.
notify pgrst, 'reload schema';
