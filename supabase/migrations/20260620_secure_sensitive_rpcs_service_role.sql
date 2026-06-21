-- ============================================================
-- Restrict sensitive RPCs to service_role and keep app behavior
-- Date: 2026-06-20
-- ============================================================

begin;

create or replace function public.soft_delete_account_for_user(
  _user_id uuid,
  _user_email text,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := _user_id;
  v_email text := lower(trim(coalesce(_user_email, '')));
  v_now timestamptz := timezone('utc', now());
  v_reason text := trim(coalesce(p_reason, ''));
  v_anonymized_email text;
  v_existing public.account_deletions%rowtype;
  v_original_email_hash text;
begin
  if v_user_id is null then
    raise exception 'User id is required.'
      using errcode = '22023';
  end if;

  if v_email = '' then
    raise exception 'User email is required.'
      using errcode = '22023';
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
      'version', 2
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

create or replace function public.update_applicant_contact_for_user(
  _auth_email text,
  _current_email text,
  _new_email text,
  _phone text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_email text := lower(trim(coalesce(_auth_email, '')));
  v_current_email text := lower(trim(coalesce(_current_email, '')));
  v_new_email text := lower(trim(coalesce(_new_email, '')));
  v_phone text := trim(coalesce(_phone, ''));
begin
  if v_auth_email = '' then
    raise exception 'Authenticated email required.'
      using errcode = '42501';
  end if;

  if v_new_email = '' then
    raise exception 'New email is required.'
      using errcode = '22023';
  end if;

  if v_auth_email <> v_current_email and v_auth_email <> v_new_email then
    raise exception 'Not allowed to update another applicant profile.'
      using errcode = '42501';
  end if;

  if to_regclass('public."Aplicants"') is not null then
    update public."Aplicants"
      set "Email" = v_new_email,
          "Phone" = v_phone
    where lower(coalesce("Email", '')) in (v_auth_email, v_current_email, v_new_email);

    if not found then
      insert into public."Aplicants" ("Email", "First_Name", "Last_Name", "Phone")
      values (v_new_email, '', '', v_phone)
      on conflict ("Email")
      do update set "Phone" = excluded."Phone";
    end if;
  end if;

  if v_current_email <> v_new_email then
    if to_regclass('public."Applications"') is not null then
      update public."Applications"
        set applicant_email = v_new_email
      where lower(coalesce(applicant_email::text, '')) = v_current_email;
    end if;

    if to_regclass('public."ApplicantCVs"') is not null then
      update public."ApplicantCVs"
        set applicant_email = v_new_email
      where lower(coalesce(applicant_email::text, '')) = v_current_email;
    end if;

    if to_regclass('public.interview_sessions') is not null then
      update public.interview_sessions
        set applicant_email = v_new_email
      where lower(coalesce(applicant_email, '')) = v_current_email;
    end if;

    if to_regclass('public.interview_messages') is not null then
      update public.interview_messages
        set applicant_email = v_new_email
      where lower(coalesce(applicant_email, '')) = v_current_email;
    end if;

    if to_regclass('public.user_seen_jobs') is not null then
      update public.user_seen_jobs
        set user_email = v_new_email
      where lower(coalesce(user_email, '')) = v_current_email;
    end if;
  end if;
end;
$$;

do $$
begin
  if to_regprocedure('public.soft_delete_current_account(text)') is not null then
    revoke execute on function public.soft_delete_current_account(text) from public, anon, authenticated;
    grant execute on function public.soft_delete_current_account(text) to service_role;
  end if;

  if to_regprocedure('public.update_current_applicant_contact(text, text, text)') is not null then
    revoke execute on function public.update_current_applicant_contact(text, text, text) from public, anon, authenticated;
    grant execute on function public.update_current_applicant_contact(text, text, text) to service_role;
  end if;

  revoke execute on function public.soft_delete_account_for_user(uuid, text, text)
    from public, anon, authenticated;
  grant execute on function public.soft_delete_account_for_user(uuid, text, text)
    to service_role;

  revoke execute on function public.update_applicant_contact_for_user(text, text, text, text)
    from public, anon, authenticated;
  grant execute on function public.update_applicant_contact_for_user(text, text, text, text)
    to service_role;
end
$$;

commit;
