-- Creates interview practice persistence tables.
-- Run this migration in Supabase SQL Editor before using Interview V2.

create extension if not exists pgcrypto;

create table if not exists public.interview_sessions (
  id uuid primary key default gen_random_uuid(),
  applicant_email text not null,
  application_id text not null,
  mode text not null default 'simulation',
  status text not null default 'active',
  last_summary text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'interview_sessions_mode_allowed'
  ) then
    alter table public.interview_sessions
      add constraint interview_sessions_mode_allowed
      check (mode in ('simulation', 'star', 'technical', 'salary', 'hard_questions'));
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'interview_sessions_status_allowed'
  ) then
    alter table public.interview_sessions
      add constraint interview_sessions_status_allowed
      check (status in ('active', 'completed', 'archived'));
  end if;
end
$$;

create unique index if not exists ux_interview_sessions_scope
  on public.interview_sessions (applicant_email, application_id, mode, status)
  where status = 'active';

create index if not exists idx_interview_sessions_lookup
  on public.interview_sessions (applicant_email, application_id, mode, updated_at desc);

create table if not exists public.interview_messages (
  id bigint generated always as identity primary key,
  session_id uuid not null references public.interview_sessions(id) on delete cascade,
  applicant_email text not null,
  application_id text not null,
  mode text not null,
  role text not null,
  content text not null,
  coach_feedback text not null default '',
  improved_answer text not null default '',
  next_question text not null default '',
  score numeric,
  tags jsonb not null default '[]'::jsonb,
  session_summary text not null default '',
  created_at timestamptz not null default timezone('utc', now())
);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'interview_messages_role_allowed'
  ) then
    alter table public.interview_messages
      add constraint interview_messages_role_allowed
      check (role in ('user', 'assistant'));
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'interview_messages_score_range'
  ) then
    alter table public.interview_messages
      add constraint interview_messages_score_range
      check (score is null or (score >= 0 and score <= 10));
  end if;
end
$$;

create index if not exists idx_interview_messages_session_created
  on public.interview_messages (session_id, created_at asc);

create index if not exists idx_interview_messages_lookup
  on public.interview_messages (applicant_email, application_id, mode, created_at desc);

alter table public.interview_sessions enable row level security;
alter table public.interview_messages enable row level security;

drop policy if exists interview_sessions_select_anon_auth
  on public.interview_sessions;
create policy interview_sessions_select_anon_auth
  on public.interview_sessions
  for select
  to anon, authenticated
  using (true);

drop policy if exists interview_sessions_insert_anon_auth
  on public.interview_sessions;
create policy interview_sessions_insert_anon_auth
  on public.interview_sessions
  for insert
  to anon, authenticated
  with check (true);

drop policy if exists interview_sessions_update_anon_auth
  on public.interview_sessions;
create policy interview_sessions_update_anon_auth
  on public.interview_sessions
  for update
  to anon, authenticated
  using (true)
  with check (true);

drop policy if exists interview_messages_select_anon_auth
  on public.interview_messages;
create policy interview_messages_select_anon_auth
  on public.interview_messages
  for select
  to anon, authenticated
  using (true);

drop policy if exists interview_messages_insert_anon_auth
  on public.interview_messages;
create policy interview_messages_insert_anon_auth
  on public.interview_messages
  for insert
  to anon, authenticated
  with check (true);

grant usage on schema public to anon, authenticated;
grant select, insert, update on public.interview_sessions to anon, authenticated;
grant select, insert on public.interview_messages to anon, authenticated;
grant usage, select on sequence public.interview_messages_id_seq to anon, authenticated;
