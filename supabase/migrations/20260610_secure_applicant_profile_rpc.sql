-- ============================================================
-- Secure profile helpers for authenticated users
-- Date: 2026-06-10
-- ============================================================

begin;

create or replace function public.current_applicant_profile()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'Email', a."Email",
        'First_Name', coalesce(a."First_Name", ''),
        'Last_Name', coalesce(a."Last_Name", ''),
        'Phone', coalesce(a."Phone", '')
      )
      from public."Aplicants" a
      where lower(coalesce(a."Email", '')) = public.current_user_email()
      order by a."Email" asc
      limit 1
    ),
    jsonb_build_object(
      'Email', public.current_user_email(),
      'First_Name', '',
      'Last_Name', '',
      'Phone', ''
    )
  );
$$;

grant execute on function public.current_applicant_profile() to authenticated;

create or replace function public.save_current_applicant_profile(
  _first_name text,
  _last_name text,
  _phone text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_email text := public.current_user_email();
begin
  if coalesce(normalized_email, '') = '' then
    raise exception 'Authenticated email required.'
      using errcode = '42501';
  end if;

  delete from public."Aplicants"
  where lower(coalesce("Email", '')) = normalized_email;

  insert into public."Aplicants" ("Email", "First_Name", "Last_Name", "Phone")
  values (
    normalized_email,
    trim(coalesce(_first_name, '')),
    trim(coalesce(_last_name, '')),
    trim(coalesce(_phone, ''))
  );
end;
$$;

grant execute on function public.save_current_applicant_profile(text, text, text) to authenticated;

commit;