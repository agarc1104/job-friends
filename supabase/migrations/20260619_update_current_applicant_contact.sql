-- ============================================================
-- Update current applicant contact info (email + phone)
-- Date: 2026-06-19
-- ============================================================

begin;

create or replace function public.update_current_applicant_contact(
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
  v_auth_email text := public.current_user_email();
  v_current_email text := lower(trim(coalesce(_current_email, '')));
  v_new_email text := lower(trim(coalesce(_new_email, '')));
  v_phone text := trim(coalesce(_phone, ''));
begin
  if coalesce(v_auth_email, '') = '' then
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

revoke execute on function public.update_current_applicant_contact(text, text, text)
  from public, anon;
grant execute on function public.update_current_applicant_contact(text, text, text)
  to authenticated;

commit;
