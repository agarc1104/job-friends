-- ============================================================
-- Harden remaining Supabase security warnings without regressions
-- Date: 2026-06-17
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1) Fix mutable search_path warnings
-- ------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.current_user_email()') is not null then
    alter function public.current_user_email() set search_path = public;
  end if;

  if to_regprocedure('public.purge_expired_job_cache()') is not null then
    alter function public.purge_expired_job_cache() set search_path = public;
  end if;
end
$$;

-- ------------------------------------------------------------
-- 2) Restrict execute on SECURITY DEFINER/internal functions
-- ------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.cleanup_interview_data_on_application_delete()') is not null then
    revoke execute on function public.cleanup_interview_data_on_application_delete() from public, anon, authenticated;
    grant execute on function public.cleanup_interview_data_on_application_delete() to service_role;
  end if;

  if to_regprocedure('public.restrict_interview_message_insert()') is not null then
    revoke execute on function public.restrict_interview_message_insert() from public, anon, authenticated;
    grant execute on function public.restrict_interview_message_insert() to service_role;
  end if;

  if to_regprocedure('public.restrict_interview_session_insert()') is not null then
    revoke execute on function public.restrict_interview_session_insert() from public, anon, authenticated;
    grant execute on function public.restrict_interview_session_insert() to service_role;
  end if;

  if to_regprocedure('public.restrict_interview_session_update()') is not null then
    revoke execute on function public.restrict_interview_session_update() from public, anon, authenticated;
    grant execute on function public.restrict_interview_session_update() to service_role;
  end if;

  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
    grant execute on function public.rls_auto_enable() to service_role;
  end if;

  if to_regprocedure('public.purge_expired_job_cache()') is not null then
    revoke execute on function public.purge_expired_job_cache() from public, anon, authenticated;
    grant execute on function public.purge_expired_job_cache() to service_role;
  end if;

  if to_regprocedure('public.current_applicant_profile()') is not null then
    revoke execute on function public.current_applicant_profile() from public, anon;
    grant execute on function public.current_applicant_profile() to authenticated;
  end if;

  if to_regprocedure('public.save_current_applicant_profile(text, text, text)') is not null then
    revoke execute on function public.save_current_applicant_profile(text, text, text) from public, anon;
    grant execute on function public.save_current_applicant_profile(text, text, text) to authenticated;
  end if;

  if to_regprocedure('public.soft_delete_current_account(text)') is not null then
    revoke execute on function public.soft_delete_current_account(text) from public, anon;
    grant execute on function public.soft_delete_current_account(text) to authenticated;
  end if;
end
$$;

-- ------------------------------------------------------------
-- 3) Remove broad public listing policy for applicant-cvs bucket
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "anon read cvs 1flkx05_0" on storage.objects;
  end if;
end
$$;

-- ------------------------------------------------------------
-- 4) Remove RPC access to helper function while preserving behavior
--    by inlining eligibility checks directly into interview policies.
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.interview_sessions') is not null then
    drop policy if exists interview_sessions_select_own on public.interview_sessions;
    create policy interview_sessions_select_own
      on public.interview_sessions
      for select
      to authenticated
      using (
        lower(coalesce(applicant_email, '')) = public.current_user_email()
        and exists (
          select 1
          from public."Applications" a
          where a.id::text = interview_sessions.application_id
            and lower(coalesce(a.applicant_email::text, '')) = lower(coalesce(interview_sessions.applicant_email, ''))
            and a.added_at is not null
            and a.added_at >= timezone('utc', now()) - interval '90 days'
        )
      );

    drop policy if exists interview_sessions_insert_own on public.interview_sessions;
    create policy interview_sessions_insert_own
      on public.interview_sessions
      for insert
      to authenticated
      with check (
        lower(coalesce(applicant_email, '')) = public.current_user_email()
        and exists (
          select 1
          from public."Applications" a
          where a.id::text = interview_sessions.application_id
            and lower(coalesce(a.applicant_email::text, '')) = lower(coalesce(interview_sessions.applicant_email, ''))
            and a.added_at is not null
            and a.added_at >= timezone('utc', now()) - interval '90 days'
        )
      );

    drop policy if exists interview_sessions_update_own on public.interview_sessions;
    create policy interview_sessions_update_own
      on public.interview_sessions
      for update
      to authenticated
      using (
        lower(coalesce(applicant_email, '')) = public.current_user_email()
        and exists (
          select 1
          from public."Applications" a
          where a.id::text = interview_sessions.application_id
            and lower(coalesce(a.applicant_email::text, '')) = lower(coalesce(interview_sessions.applicant_email, ''))
            and a.added_at is not null
            and a.added_at >= timezone('utc', now()) - interval '90 days'
        )
      )
      with check (
        lower(coalesce(applicant_email, '')) = public.current_user_email()
        and exists (
          select 1
          from public."Applications" a
          where a.id::text = interview_sessions.application_id
            and lower(coalesce(a.applicant_email::text, '')) = lower(coalesce(interview_sessions.applicant_email, ''))
            and a.added_at is not null
            and a.added_at >= timezone('utc', now()) - interval '90 days'
        )
      );
  end if;

  if to_regclass('public.interview_messages') is not null then
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
            and exists (
              select 1
              from public."Applications" a
              where a.id::text = s.application_id
                and lower(coalesce(a.applicant_email::text, '')) = lower(coalesce(s.applicant_email, ''))
                and a.added_at is not null
                and a.added_at >= timezone('utc', now()) - interval '90 days'
            )
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
            and exists (
              select 1
              from public."Applications" a
              where a.id::text = s.application_id
                and lower(coalesce(a.applicant_email::text, '')) = lower(coalesce(s.applicant_email, ''))
                and a.added_at is not null
                and a.added_at >= timezone('utc', now()) - interval '90 days'
            )
        )
      );
  end if;
end
$$;

-- Now helper can stay SECURITY DEFINER but not be directly callable via RPC.
do $$
begin
  if to_regprocedure('public.is_eligible_interview_application(text, text)') is not null then
    revoke execute on function public.is_eligible_interview_application(text, text) from public, anon, authenticated;
    grant execute on function public.is_eligible_interview_application(text, text) to service_role;
  end if;
end
$$;

commit;
