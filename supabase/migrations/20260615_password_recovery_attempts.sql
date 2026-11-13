-- ============================================================
-- Password recovery identity verification audit
-- Date: 2026-06-15
-- ============================================================

begin;

create table if not exists public.password_recovery_attempts (
  id bigint generated always as identity primary key,
  email_hash text not null,
  ip_hash text,
  success boolean not null default false,
  reason text not null default 'unknown',
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_password_recovery_attempts_email_created
  on public.password_recovery_attempts (email_hash, created_at desc);

create index if not exists idx_password_recovery_attempts_ip_created
  on public.password_recovery_attempts (ip_hash, created_at desc);

alter table public.password_recovery_attempts enable row level security;
alter table public.password_recovery_attempts force row level security;

drop policy if exists password_recovery_attempts_no_access on public.password_recovery_attempts;
create policy password_recovery_attempts_no_access
  on public.password_recovery_attempts
  using (false)
  with check (false);

revoke all on public.password_recovery_attempts from anon;
revoke all on public.password_recovery_attempts from authenticated;

commit;
