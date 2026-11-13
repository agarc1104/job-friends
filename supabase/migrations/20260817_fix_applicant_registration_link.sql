-- ============================================================
-- Fix new user registration not persisting to Aplicants
-- Date: 2026-08-17
-- ============================================================
-- Root cause: the legacy "Password" column on "Aplicants" is NOT NULL
-- with no default. Since auth is fully handled by Supabase Auth, the
-- app never sends a value for it, so every insert/RPC call for a new
-- registration was rejected (23502) and silently swallowed client-side.

begin;

do $$
begin
  if to_regclass('public."Aplicants"') is not null then
    alter table public."Aplicants" alter column "Password" drop not null;
    alter table public."Aplicants" alter column "Password" set default '';
  end if;
end
$$;

commit;
