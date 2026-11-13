-- ============================================================
-- RLS hardening (core user/system data)
-- Date: 2026-06-08
-- ============================================================

begin;

-- ------------------------------------------------------------
-- Helper: normalized authenticated email from Supabase Auth JWT
-- ------------------------------------------------------------
create or replace function public.current_user_email()
returns text
language sql
stable
as $$
  select lower(nullif(auth.email(), ''))
$$;

grant execute on function public.current_user_email() to anon, authenticated;

-- ------------------------------------------------------------
-- Aplicants (user profile/credentials metadata)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public."Aplicants"') is not null then
    alter table public."Aplicants" enable row level security;
    alter table public."Aplicants" force row level security;

    drop policy if exists aplicants_select_own on public."Aplicants";
    create policy aplicants_select_own
      on public."Aplicants"
      for select
      to authenticated
      using (lower(coalesce("Email", '')) = public.current_user_email());

    drop policy if exists aplicants_insert_own on public."Aplicants";
    create policy aplicants_insert_own
      on public."Aplicants"
      for insert
      to authenticated
      with check (lower(coalesce("Email", '')) = public.current_user_email());

    drop policy if exists aplicants_update_own on public."Aplicants";
    create policy aplicants_update_own
      on public."Aplicants"
      for update
      to authenticated
      using (lower(coalesce("Email", '')) = public.current_user_email())
      with check (lower(coalesce("Email", '')) = public.current_user_email());

    drop policy if exists aplicants_delete_own on public."Aplicants";
    create policy aplicants_delete_own
      on public."Aplicants"
      for delete
      to authenticated
      using (lower(coalesce("Email", '')) = public.current_user_email());

    revoke all on public."Aplicants" from anon;
    grant select, insert, update, delete on public."Aplicants" to authenticated;
  end if;
end
$$;

-- ------------------------------------------------------------
-- Applications (user-owned applications)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public."Applications"') is not null then
    alter table public."Applications" enable row level security;
    alter table public."Applications" force row level security;

    drop policy if exists applications_select_own on public."Applications";
    create policy applications_select_own
      on public."Applications"
      for select
      to authenticated
      using (lower(coalesce(applicant_email::text, '')) = public.current_user_email());

    drop policy if exists applications_insert_own on public."Applications";
    create policy applications_insert_own
      on public."Applications"
      for insert
      to authenticated
      with check (lower(coalesce(applicant_email::text, '')) = public.current_user_email());

    drop policy if exists applications_update_own on public."Applications";
    create policy applications_update_own
      on public."Applications"
      for update
      to authenticated
      using (lower(coalesce(applicant_email::text, '')) = public.current_user_email())
      with check (lower(coalesce(applicant_email::text, '')) = public.current_user_email());

    drop policy if exists applications_delete_own on public."Applications";
    create policy applications_delete_own
      on public."Applications"
      for delete
      to authenticated
      using (lower(coalesce(applicant_email::text, '')) = public.current_user_email());

    revoke all on public."Applications" from anon;
    grant select, insert, update, delete on public."Applications" to authenticated;
  end if;
end
$$;

-- ------------------------------------------------------------
-- ApplicantCVs (user-owned CV metadata)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public."ApplicantCVs"') is not null then
    alter table public."ApplicantCVs" enable row level security;
    alter table public."ApplicantCVs" force row level security;

    drop policy if exists applicant_cvs_select_own on public."ApplicantCVs";
    create policy applicant_cvs_select_own
      on public."ApplicantCVs"
      for select
      to authenticated
      using (lower(coalesce(applicant_email::text, '')) = public.current_user_email());

    drop policy if exists applicant_cvs_insert_own on public."ApplicantCVs";
    create policy applicant_cvs_insert_own
      on public."ApplicantCVs"
      for insert
      to authenticated
      with check (lower(coalesce(applicant_email::text, '')) = public.current_user_email());

    drop policy if exists applicant_cvs_update_own on public."ApplicantCVs";
    create policy applicant_cvs_update_own
      on public."ApplicantCVs"
      for update
      to authenticated
      using (lower(coalesce(applicant_email::text, '')) = public.current_user_email())
      with check (lower(coalesce(applicant_email::text, '')) = public.current_user_email());

    drop policy if exists applicant_cvs_delete_own on public."ApplicantCVs";
    create policy applicant_cvs_delete_own
      on public."ApplicantCVs"
      for delete
      to authenticated
      using (lower(coalesce(applicant_email::text, '')) = public.current_user_email());

    revoke all on public."ApplicantCVs" from anon;
    grant select, insert, update, delete on public."ApplicantCVs" to authenticated;
  end if;
end
$$;

-- ------------------------------------------------------------
-- interview_sessions (tighten previously permissive RLS)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.interview_sessions') is not null then
    alter table public.interview_sessions enable row level security;
    alter table public.interview_sessions force row level security;

    drop policy if exists interview_sessions_select_anon_auth on public.interview_sessions;
    drop policy if exists interview_sessions_insert_anon_auth on public.interview_sessions;
    drop policy if exists interview_sessions_update_anon_auth on public.interview_sessions;

    drop policy if exists interview_sessions_select_own on public.interview_sessions;
    create policy interview_sessions_select_own
      on public.interview_sessions
      for select
      to authenticated
      using (
        lower(coalesce(applicant_email, '')) = public.current_user_email()
        and public.is_eligible_interview_application(applicant_email, application_id)
      );

    drop policy if exists interview_sessions_insert_own on public.interview_sessions;
    create policy interview_sessions_insert_own
      on public.interview_sessions
      for insert
      to authenticated
      with check (
        lower(coalesce(applicant_email, '')) = public.current_user_email()
        and public.is_eligible_interview_application(applicant_email, application_id)
      );

    drop policy if exists interview_sessions_update_own on public.interview_sessions;
    create policy interview_sessions_update_own
      on public.interview_sessions
      for update
      to authenticated
      using (
        lower(coalesce(applicant_email, '')) = public.current_user_email()
        and public.is_eligible_interview_application(applicant_email, application_id)
      )
      with check (
        lower(coalesce(applicant_email, '')) = public.current_user_email()
        and public.is_eligible_interview_application(applicant_email, application_id)
      );

    drop policy if exists interview_sessions_delete_own on public.interview_sessions;
    create policy interview_sessions_delete_own
      on public.interview_sessions
      for delete
      to authenticated
      using (lower(coalesce(applicant_email, '')) = public.current_user_email());

    revoke all on public.interview_sessions from anon;
    grant select, insert, update, delete on public.interview_sessions to authenticated;
  end if;
end
$$;

-- ------------------------------------------------------------
-- interview_messages (tighten previously permissive RLS)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.interview_messages') is not null then
    alter table public.interview_messages enable row level security;
    alter table public.interview_messages force row level security;

    drop policy if exists interview_messages_select_anon_auth on public.interview_messages;
    drop policy if exists interview_messages_insert_anon_auth on public.interview_messages;

    drop policy if exists interview_messages_select_own on public.interview_messages;
    create policy interview_messages_select_own
      on public.interview_messages
      for select
      to authenticated
      using (
        exists (
          select 1
          from public.interview_sessions s
          where s.id = interview_messages.session_id
            and lower(coalesce(s.applicant_email, '')) = public.current_user_email()
            and s.application_id = interview_messages.application_id
            and public.is_eligible_interview_application(s.applicant_email, s.application_id)
        )
      );

    drop policy if exists interview_messages_insert_own on public.interview_messages;
    create policy interview_messages_insert_own
      on public.interview_messages
      for insert
      to authenticated
      with check (
        lower(coalesce(applicant_email, '')) = public.current_user_email()
        and exists (
          select 1
          from public.interview_sessions s
          where s.id = interview_messages.session_id
            and lower(coalesce(s.applicant_email, '')) = public.current_user_email()
            and s.application_id = interview_messages.application_id
            and s.mode = interview_messages.mode
            and public.is_eligible_interview_application(s.applicant_email, s.application_id)
        )
      );

    drop policy if exists interview_messages_delete_own on public.interview_messages;
    create policy interview_messages_delete_own
      on public.interview_messages
      for delete
      to authenticated
      using (
        exists (
          select 1
          from public.interview_sessions s
          where s.id = interview_messages.session_id
            and lower(coalesce(s.applicant_email, '')) = public.current_user_email()
        )
      );

    revoke all on public.interview_messages from anon;
    grant select, insert, delete on public.interview_messages to authenticated;
    grant usage, select on sequence public.interview_messages_id_seq to authenticated;
  end if;
end
$$;

-- ------------------------------------------------------------
-- company_interest_leads (public write-only intake)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.company_interest_leads') is not null then
    alter table public.company_interest_leads enable row level security;
    alter table public.company_interest_leads force row level security;

    drop policy if exists company_interest_leads_insert_anon_auth on public.company_interest_leads;
    create policy company_interest_leads_insert_anon_auth
      on public.company_interest_leads
      for insert
      to anon, authenticated
      with check (
        position('@' in lower(coalesce(email, ''))) > 1
        and length(coalesce(company_name, '')) between 2 and 120
        and length(coalesce(phone, '')) between 6 and 40
      );

    drop policy if exists company_interest_leads_select_authenticated on public.company_interest_leads;
    create policy company_interest_leads_select_authenticated
      on public.company_interest_leads
      for select
      to authenticated
      using (false);

    revoke all on public.company_interest_leads from anon, authenticated;
    grant insert on public.company_interest_leads to anon, authenticated;
  end if;
end
$$;

-- ------------------------------------------------------------
-- job_search_cache (service-only)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.job_search_cache') is not null then
    alter table public.job_search_cache enable row level security;
    alter table public.job_search_cache force row level security;

    drop policy if exists "service_role_only_cache" on public.job_search_cache;
    drop policy if exists job_search_cache_no_client_access on public.job_search_cache;

    create policy job_search_cache_no_client_access
      on public.job_search_cache
      as restrictive
      for all
      to anon, authenticated
      using (false)
      with check (false);

    revoke all on public.job_search_cache from anon, authenticated;
  end if;
end
$$;

-- ------------------------------------------------------------
-- user_seen_jobs (authenticated user reads own rows only)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.user_seen_jobs') is not null then
    alter table public.user_seen_jobs enable row level security;
    alter table public.user_seen_jobs force row level security;

    drop policy if exists "user_read_own_seen_jobs" on public.user_seen_jobs;
    drop policy if exists "service_role_insert_seen_jobs" on public.user_seen_jobs;

    create policy user_read_own_seen_jobs
      on public.user_seen_jobs
      for select
      to authenticated
      using (lower(coalesce(user_email, '')) = public.current_user_email());

    create policy user_seen_jobs_block_direct_client_writes
      on public.user_seen_jobs
      as restrictive
      for insert
      to anon, authenticated
      with check (false);

    create policy user_seen_jobs_block_direct_client_updates
      on public.user_seen_jobs
      as restrictive
      for update
      to anon, authenticated
      using (false)
      with check (false);

    create policy user_seen_jobs_block_direct_client_deletes
      on public.user_seen_jobs
      as restrictive
      for delete
      to anon, authenticated
      using (false);

    revoke all on public.user_seen_jobs from anon;
    grant select on public.user_seen_jobs to authenticated;
  end if;
end
$$;

-- ------------------------------------------------------------
-- Storage bucket: applicant-cvs
-- Owner folder convention: <lower(email)>/... 
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists applicant_cvs_objects_select_own on storage.objects;
    create policy applicant_cvs_objects_select_own
      on storage.objects
      for select
      to authenticated
      using (
        bucket_id = 'applicant-cvs'
        and lower(split_part(name, '/', 1)) = public.current_user_email()
      );

    drop policy if exists applicant_cvs_objects_insert_own on storage.objects;
    create policy applicant_cvs_objects_insert_own
      on storage.objects
      for insert
      to authenticated
      with check (
        bucket_id = 'applicant-cvs'
        and lower(split_part(name, '/', 1)) = public.current_user_email()
      );

    drop policy if exists applicant_cvs_objects_update_own on storage.objects;
    create policy applicant_cvs_objects_update_own
      on storage.objects
      for update
      to authenticated
      using (
        bucket_id = 'applicant-cvs'
        and lower(split_part(name, '/', 1)) = public.current_user_email()
      )
      with check (
        bucket_id = 'applicant-cvs'
        and lower(split_part(name, '/', 1)) = public.current_user_email()
      );

    drop policy if exists applicant_cvs_objects_delete_own on storage.objects;
    create policy applicant_cvs_objects_delete_own
      on storage.objects
      for delete
      to authenticated
      using (
        bucket_id = 'applicant-cvs'
        and lower(split_part(name, '/', 1)) = public.current_user_email()
      );
  end if;
end
$$;

commit;
