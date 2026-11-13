-- ============================================================
-- RLS hardening for monetization events
-- Date: 2026-06-15
-- ============================================================

begin;

do $$
begin
  if to_regclass('public."MonetizationEvents"') is not null then
    alter table public."MonetizationEvents" enable row level security;
    alter table public."MonetizationEvents" force row level security;

    drop policy if exists monetization_events_no_access on public."MonetizationEvents";
    create policy monetization_events_no_access
      on public."MonetizationEvents"
      using (false)
      with check (false);

    revoke all on public."MonetizationEvents" from anon;
    revoke all on public."MonetizationEvents" from authenticated;
  elsif to_regclass('public.monetization_events') is not null then
    alter table public.monetization_events enable row level security;
    alter table public.monetization_events force row level security;

    drop policy if exists monetization_events_no_access on public.monetization_events;
    create policy monetization_events_no_access
      on public.monetization_events
      using (false)
      with check (false);

    revoke all on public.monetization_events from anon;
    revoke all on public.monetization_events from authenticated;
  end if;
end
$$;

commit;
