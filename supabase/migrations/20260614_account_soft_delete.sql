-- ============================================================
-- Account deletion with irreversible soft delete + anonymization
-- Date: 2026-06-14
-- ============================================================

begin;

create extension if not exists pgcrypto;

create table if not exists public.account_deletions (
  id bigint generated always as identity primary key,
  auth_user_id uuid not null unique,
  original_email_hash text not null,
  anonymized_email text not null unique,
  reason text not null default '',
  deleted_at timestamptz not null default timezone('utc', now()),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_account_deletions_deleted_at
  on public.account_deletions (deleted_at desc);

alter table public.account_deletions enable row level security;
alter table public.account_deletions force row level security;

drop policy if exists account_deletions_select_own on public.account_deletions;
create policy account_deletions_select_own
  on public.account_deletions
  for select
  to authenticated
  using (auth.uid() = auth_user_id);

revoke all on public.account_deletions from anon;
grant select on public.account_deletions to authenticated;

create or replace function public.soft_delete_current_account(p_reason text default '')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text := public.current_user_email();
  v_now timestamptz := timezone('utc', now());
  v_reason text := trim(coalesce(p_reason, ''));
  v_anonymized_email text;
  v_existing public.account_deletions%rowtype;
  v_original_email_hash text;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.'
      using errcode = '42501';
  end if;

  if coalesce(v_email, '') = '' then
    raise exception 'Authenticated email required.'
      using errcode = '42501';
  end if;

  select *
    into v_existing
  from public.account_deletions
  where auth_user_id = v_user_id
  limit 1;

  if found then
    return jsonb_build_object(
      'success', true,
      'already_deleted', true,
      'anonymized_email', v_existing.anonymized_email,
      'deleted_at', v_existing.deleted_at
    );
  end if;

  v_original_email_hash := encode(digest(v_email, 'sha256'), 'hex');
  v_anonymized_email := format(
    'deleted_%s@deleted.local',
    replace(v_user_id::text, '-', '')
  );

  if to_regclass('public."Aplicants"') is not null then
    update public."Aplicants"
      set "Email" = v_anonymized_email,
          "First_Name" = 'Deleted',
          "Last_Name" = 'User',
          "Phone" = ''
    where lower(coalesce("Email", '')) = v_email;
  end if;

  if to_regclass('public."Applications"') is not null then
    update public."Applications"
      set applicant_email = v_anonymized_email
    where lower(coalesce(applicant_email::text, '')) = v_email;
  end if;

  if to_regclass('public."ApplicantCVs"') is not null then
    update public."ApplicantCVs"
      set applicant_email = v_anonymized_email,
          file_name = 'deleted_account_cv',
          storage_path = '',
          public_url = '',
          source = 'deleted_user',
          target_roles = '',
          profile_data = '{}'::jsonb,
          updated_at = v_now
    where lower(coalesce(applicant_email::text, '')) = v_email;
  end if;

  if to_regclass('public.interview_sessions') is not null then
    update public.interview_sessions
      set applicant_email = v_anonymized_email,
          updated_at = v_now,
          last_summary = ''
    where lower(coalesce(applicant_email, '')) = v_email;
  end if;

  if to_regclass('public.interview_messages') is not null then
    update public.interview_messages
      set applicant_email = v_anonymized_email,
          content = case when role = 'user' then '' else content end,
          improved_answer = '',
          session_summary = ''
    where lower(coalesce(applicant_email, '')) = v_email;
  end if;

  if to_regclass('public.user_seen_jobs') is not null then
    update public.user_seen_jobs
      set user_email = v_anonymized_email
    where lower(coalesce(user_email, '')) = v_email;
  end if;

  if to_regclass('public.company_interest_leads') is not null then
    update public.company_interest_leads
      set email = v_anonymized_email,
          company_name = 'Deleted company',
          phone = '00000000'
    where lower(coalesce(email, '')) = v_email;
  end if;

  insert into public.account_deletions (
    auth_user_id,
    original_email_hash,
    anonymized_email,
    reason,
    deleted_at,
    metadata
  )
  values (
    v_user_id,
    v_original_email_hash,
    v_anonymized_email,
    v_reason,
    v_now,
    jsonb_build_object(
      'source', 'mobile_app',
      'version', 1
    )
  );

  return jsonb_build_object(
    'success', true,
    'already_deleted', false,
    'anonymized_email', v_anonymized_email,
    'deleted_at', v_now
  );
end;
$$;

grant execute on function public.soft_delete_current_account(text) to authenticated;

commit;
