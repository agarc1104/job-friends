-- ============================================================
-- Remove incorrect UNIQUE constraint on Aplicants.Phone
-- Date: 2026-08-17
-- ============================================================
-- Multiple applicants can legitimately share a phone number (family,
-- shared devices, retries). The constraint caused registration to fail
-- with a 23505 unique_violation whenever a phone was already in use by
-- a different account, since the upsert only resolves conflicts on Email.

begin;

do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'Aplicants_Phone_key'
      and conrelid = 'public."Aplicants"'::regclass
  ) then
    alter table public."Aplicants" drop constraint "Aplicants_Phone_key";
  end if;
end
$$;

commit;
