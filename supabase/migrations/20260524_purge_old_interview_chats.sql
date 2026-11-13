-- Remove existing interview chats that violate the eligibility rules.
-- This deletes only historical data; new inserts remain protected by the guard migration.

delete from public.interview_sessions
where id in (
  select s.id
  from public.interview_sessions s
  left join public."Applications" a
    on a.id::text = s.application_id
   and lower(coalesce(a.applicant_email::text, '')) = lower(coalesce(s.applicant_email, ''))
  where a.id is null
     or a.added_at < timezone('utc', now()) - interval '90 days'
);