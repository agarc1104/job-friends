-- ============================================================
-- Reduce SECURITY DEFINER exposure on profile RPCs
-- Date: 2026-06-18
-- ============================================================

begin;

do $$
begin
  if to_regprocedure('public.current_applicant_profile()') is not null then
    alter function public.current_applicant_profile() security invoker;
  end if;

  if to_regprocedure('public.save_current_applicant_profile(text, text, text)') is not null then
    alter function public.save_current_applicant_profile(text, text, text) security invoker;
  end if;
end
$$;

commit;
