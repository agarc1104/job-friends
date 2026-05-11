-- Creates table to store companies interested in collaborating with Job-Friends.
-- Run this script in Supabase SQL Editor.

create table if not exists public.company_interest_leads (
  id bigint generated always as identity primary key,
  company_name text not null,
  email text not null,
  phone text not null,
  source text not null default 'mobile_flutter_registration',
  created_at timestamptz not null default timezone('utc', now())
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'company_interest_leads_company_name_not_empty'
  ) then
    alter table public.company_interest_leads
      add constraint company_interest_leads_company_name_not_empty
      check (length(trim(company_name)) > 1);
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'company_interest_leads_email_format'
  ) then
    alter table public.company_interest_leads
      add constraint company_interest_leads_email_format
      check (email ~* '^[^\s@]+@[^\s@]+\.[^\s@]+$');
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'company_interest_leads_phone_len'
  ) then
    alter table public.company_interest_leads
      add constraint company_interest_leads_phone_len
      check (length(regexp_replace(phone, '\\D', '', 'g')) >= 8);
  end if;
end
$$;

create index if not exists idx_company_interest_leads_created_at
  on public.company_interest_leads (created_at desc);

create index if not exists idx_company_interest_leads_email
  on public.company_interest_leads (lower(email));

-- Keep only the most recent row per email before enforcing uniqueness.
delete from public.company_interest_leads older
using public.company_interest_leads newer
where older.email = newer.email
  and older.id < newer.id;

create unique index if not exists ux_company_interest_leads_email
  on public.company_interest_leads (email);

alter table public.company_interest_leads enable row level security;

drop policy if exists company_interest_leads_insert_anon_auth
  on public.company_interest_leads;

create policy company_interest_leads_insert_anon_auth
  on public.company_interest_leads
  for insert
  to anon, authenticated
  with check (true);

grant usage on schema public to anon, authenticated;
grant insert on public.company_interest_leads to anon, authenticated;
grant select on public.company_interest_leads to authenticated;
