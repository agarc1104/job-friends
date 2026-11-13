-- ============================================================
-- Fix account deletion 500 error: digest() not found
-- Date: 2026-08-17
-- ============================================================
-- pgcrypto (and its digest() function) is installed in the "extensions"
-- schema on Supabase, not "public". Both soft-delete functions set
-- search_path = public only, so digest() could not be resolved and every
-- account deletion failed with: "function digest(text, unknown) does not exist".

begin;

do $$
begin
  if to_regprocedure('public.soft_delete_current_account(text)') is not null then
    alter function public.soft_delete_current_account(text) set search_path = public, extensions;
  end if;

  if to_regprocedure('public.soft_delete_account_for_user(uuid, text, text)') is not null then
    alter function public.soft_delete_account_for_user(uuid, text, text) set search_path = public, extensions;
  end if;
end
$$;

commit;
