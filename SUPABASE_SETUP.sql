-- ============================================================
-- SankatMitra — Supabase Database Setup
-- Run this entire file in: Supabase Dashboard → SQL Editor
-- ============================================================

-- 1. Create the main table
create table if not exists session_users (
  user_id     text not null,
  session_id  text not null,
  role        text not null default 'victim',
  lat         double precision not null default 0,
  lng         double precision not null default 0,
  timestamp   bigint not null default 0,
  is_sos      boolean not null default false,
  name        text not null default '',
  priority    text not null default '',
  updated_at  timestamptz not null default now(),
  primary key (session_id, user_id)
);

-- If table already existed before, add columns with migration:
alter table session_users add column if not exists name text not null default '';
alter table session_users add column if not exists priority text not null default '';

-- 2. Row Level Security (open for hackathon prototype)
alter table session_users enable row level security;

create policy "allow_all_read" on session_users
  for select using (true);

create policy "allow_all_write" on session_users
  for insert with check (true);

create policy "allow_all_update" on session_users
  for update using (true) with check (true);

create policy "allow_all_delete" on session_users
  for delete using (true);

-- 3. Enable Realtime (critical for live location streaming)
alter publication supabase_realtime add table session_users;

-- 4. Auto-cleanup: Remove stale users older than 30 minutes
-- (Optional but nice for demos — prevents ghost markers)
create or replace function cleanup_stale_users()
returns void language sql as $$
  delete from session_users
  where updated_at < now() - interval '30 minutes';
$$;

-- To run cleanup every hour, enable pg_cron in Supabase:
-- select cron.schedule('cleanup-stale', '0 * * * *', 'select cleanup_stale_users()');

-- 5. Index for fast session queries
create index if not exists idx_session_users_session_id
  on session_users (session_id);

create index if not exists idx_session_users_updated_at
  on session_users (updated_at);

-- ============================================================
-- Verify setup:
select * from session_users limit 5;
-- ============================================================
