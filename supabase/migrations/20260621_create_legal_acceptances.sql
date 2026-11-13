-- ============================================================
-- Legal acceptances registry (terms and privacy)
-- Date: 2026-06-21
-- ============================================================

begin;

create table if not exists public.legal_acceptances (
  id bigint generated always as identity primary key,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  document_key text not null check (document_key in ('terms_and_conditions', 'privacy_policy')),
  document_version text not null,
  locale_code text not null default 'en',
  source text not null default 'mobile_app',
  accepted_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists uq_legal_acceptances_user_doc_version
  on public.legal_acceptances (auth_user_id, document_key, document_version);

create index if not exists idx_legal_acceptances_user_doc
  on public.legal_acceptances (auth_user_id, document_key, accepted_at desc);

create or replace function public.set_legal_acceptances_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_legal_acceptances_updated_at on public.legal_acceptances;
create trigger trg_legal_acceptances_updated_at
before update on public.legal_acceptances
for each row
execute function public.set_legal_acceptances_updated_at();

alter table public.legal_acceptances enable row level security;
alter table public.legal_acceptances force row level security;

drop policy if exists legal_acceptances_select_own on public.legal_acceptances;
create policy legal_acceptances_select_own
  on public.legal_acceptances
  for select
  to authenticated
  using (auth.uid() = auth_user_id);

drop policy if exists legal_acceptances_insert_own on public.legal_acceptances;
create policy legal_acceptances_insert_own
  on public.legal_acceptances
  for insert
  to authenticated
  with check (auth.uid() = auth_user_id);

drop policy if exists legal_acceptances_update_own on public.legal_acceptances;
create policy legal_acceptances_update_own
  on public.legal_acceptances
  for update
  to authenticated
  using (auth.uid() = auth_user_id)
  with check (auth.uid() = auth_user_id);

revoke all on public.legal_acceptances from anon;
grant select, insert, update on public.legal_acceptances to authenticated;

commit;
