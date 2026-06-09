-- Prevent storing interview chats for deleted or stale applications.
-- This migration adds a backend guard so clients cannot bypass the mobile app checks.

create or replace function public.is_eligible_interview_application(
  _applicant_email text,
  _application_id text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public."Applications" a
    where a.id::text = _application_id
      and lower(coalesce(a.applicant_email::text, '')) = lower(coalesce(_applicant_email, ''))
      and a.added_at is not null
      and a.added_at >= timezone('utc', now()) - interval '90 days'
  );
$$;

create or replace function public.restrict_interview_session_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_eligible_interview_application(new.applicant_email, new.application_id) then
    raise exception
      'Interview sessions can only be stored for existing applications created in the last 90 days.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function public.restrict_interview_session_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_eligible_interview_application(new.applicant_email, new.application_id) then
    raise exception
      'Interview sessions can only be updated for existing applications created in the last 90 days.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function public.restrict_interview_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  session_applicant_email text;
  session_application_id text;
begin
  select s.applicant_email, s.application_id
    into session_applicant_email, session_application_id
  from public.interview_sessions s
  where s.id = new.session_id;

  if not found then
    raise exception
      'Interview messages require a valid interview session.'
      using errcode = '23503';
  end if;

  if lower(coalesce(session_applicant_email, '')) <> lower(coalesce(new.applicant_email, ''))
     or session_application_id <> new.application_id then
    raise exception
      'Interview messages must match the session scope.'
      using errcode = '23514';
  end if;

  if not public.is_eligible_interview_application(session_applicant_email, session_application_id) then
    raise exception
      'Interview messages can only be stored for existing applications created in the last 90 days.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function public.cleanup_interview_data_on_application_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.interview_sessions
  where applicant_email = old.applicant_email
    and application_id = old.id::text;

  return old;
end;
$$;

drop trigger if exists trg_interview_sessions_restrict_insert on public.interview_sessions;
create trigger trg_interview_sessions_restrict_insert
before insert on public.interview_sessions
for each row
execute function public.restrict_interview_session_insert();

drop trigger if exists trg_interview_sessions_restrict_update on public.interview_sessions;
create trigger trg_interview_sessions_restrict_update
before update on public.interview_sessions
for each row
execute function public.restrict_interview_session_update();

drop trigger if exists trg_interview_messages_restrict_insert on public.interview_messages;
create trigger trg_interview_messages_restrict_insert
before insert on public.interview_messages
for each row
execute function public.restrict_interview_message_insert();

drop trigger if exists trg_applications_cleanup_interviews on public."Applications";
create trigger trg_applications_cleanup_interviews
after delete on public."Applications"
for each row
execute function public.cleanup_interview_data_on_application_delete();

drop policy if exists interview_sessions_insert_anon_auth
  on public.interview_sessions;
create policy interview_sessions_insert_anon_auth
  on public.interview_sessions
  for insert
  to anon, authenticated
  with check (public.is_eligible_interview_application(applicant_email, application_id));

drop policy if exists interview_sessions_update_anon_auth
  on public.interview_sessions;
create policy interview_sessions_update_anon_auth
  on public.interview_sessions
  for update
  to anon, authenticated
  using (public.is_eligible_interview_application(applicant_email, application_id))
  with check (public.is_eligible_interview_application(applicant_email, application_id));

drop policy if exists interview_messages_insert_anon_auth
  on public.interview_messages;
create policy interview_messages_insert_anon_auth
  on public.interview_messages
  for insert
  to anon, authenticated
  with check (
    exists (
      select 1
      from public.interview_sessions s
      where s.id = session_id
        and lower(coalesce(s.applicant_email, '')) = lower(coalesce(applicant_email, ''))
        and s.application_id = application_id
        and public.is_eligible_interview_application(applicant_email, application_id)
    )
  );

grant execute on function public.is_eligible_interview_application(text, text) to anon, authenticated;
grant execute on function public.restrict_interview_session_insert() to anon, authenticated;
grant execute on function public.restrict_interview_session_update() to anon, authenticated;
grant execute on function public.restrict_interview_message_insert() to anon, authenticated;
grant execute on function public.cleanup_interview_data_on_application_delete() to anon, authenticated;

create index if not exists idx_applications_applicant_created_at
  on public."Applications" (applicant_email, added_at desc);