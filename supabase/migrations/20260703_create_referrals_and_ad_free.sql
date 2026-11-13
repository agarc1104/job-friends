-- ============================================================
-- Referrals + ad-free entitlements (7 days reward)
-- Date: 2026-07-03
-- ============================================================

begin;

create table if not exists public.referral_codes (
  user_email text primary key,
  referral_code text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint referral_codes_email_lower check (user_email = lower(user_email)),
  constraint referral_codes_code_format check (referral_code ~ '^[A-Z0-9]{6,12}$')
);

create index if not exists idx_referral_codes_code
  on public.referral_codes (referral_code);

create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_email text not null,
  referred_email text not null,
  referral_code text not null,
  status text not null default 'pending',
  reward_days integer not null default 7,
  applied_at timestamptz not null default now(),
  first_search_completed_at timestamptz,
  rewarded_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  constraint referrals_referrer_lower check (referrer_email = lower(referrer_email)),
  constraint referrals_referred_lower check (referred_email = lower(referred_email)),
  constraint referrals_no_self check (referrer_email <> referred_email),
  constraint referrals_status check (status in ('pending', 'qualified', 'rewarded', 'canceled')),
  constraint referrals_reward_days_positive check (reward_days > 0),
  constraint referrals_referred_unique unique (referred_email),
  constraint referrals_code_fk
    foreign key (referrer_email)
    references public.referral_codes (user_email)
    on delete cascade
);

create index if not exists idx_referrals_referrer_status
  on public.referrals (referrer_email, status, applied_at desc);

create index if not exists idx_referrals_referred
  on public.referrals (referred_email, applied_at desc);

create table if not exists public.ad_free_entitlements (
  id uuid primary key default gen_random_uuid(),
  user_email text not null,
  source text not null default 'referral',
  referral_id uuid not null,
  granted_days integer not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint ad_free_entitlements_email_lower check (user_email = lower(user_email)),
  constraint ad_free_entitlements_granted_days_positive check (granted_days > 0),
  constraint ad_free_entitlements_order check (ends_at > starts_at),
  constraint ad_free_entitlements_referral_fk
    foreign key (referral_id)
    references public.referrals (id)
    on delete set null
);

create unique index if not exists uq_ad_free_entitlements_referral_user
  on public.ad_free_entitlements (source, referral_id, user_email);

create index if not exists idx_ad_free_entitlements_user_ends
  on public.ad_free_entitlements (user_email, ends_at desc);

create index if not exists idx_ad_free_entitlements_source_created
  on public.ad_free_entitlements (source, created_at desc);

alter table public.referral_codes enable row level security;
alter table public.referral_codes force row level security;

alter table public.referrals enable row level security;
alter table public.referrals force row level security;

alter table public.ad_free_entitlements enable row level security;
alter table public.ad_free_entitlements force row level security;

drop policy if exists referral_codes_select_own on public.referral_codes;
create policy referral_codes_select_own
  on public.referral_codes
  for select
  to authenticated
  using (user_email = public.current_user_email());

drop policy if exists referrals_select_own on public.referrals;
create policy referrals_select_own
  on public.referrals
  for select
  to authenticated
  using (
    referrer_email = public.current_user_email()
    or referred_email = public.current_user_email()
  );

drop policy if exists ad_free_entitlements_select_own on public.ad_free_entitlements;
create policy ad_free_entitlements_select_own
  on public.ad_free_entitlements
  for select
  to authenticated
  using (user_email = public.current_user_email());

revoke all on public.referral_codes from anon;
revoke all on public.referral_codes from authenticated;
grant select on public.referral_codes to authenticated;

revoke all on public.referrals from anon;
revoke all on public.referrals from authenticated;
grant select on public.referrals to authenticated;

revoke all on public.ad_free_entitlements from anon;
revoke all on public.ad_free_entitlements from authenticated;
grant select on public.ad_free_entitlements to authenticated;

create or replace function public.grant_referral_ad_free(
  p_user_email text,
  p_referral_id uuid,
  p_days integer,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(coalesce(p_user_email, '')));
  v_days integer := greatest(coalesce(p_days, 0), 0);
  v_now timestamptz := now();
  v_last_end timestamptz;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_inserted boolean := false;
  v_rows integer := 0;
begin
  if v_email = '' then
    return jsonb_build_object('inserted', false, 'reason', 'missing_email');
  end if;

  if v_days <= 0 then
    return jsonb_build_object('inserted', false, 'reason', 'invalid_days');
  end if;

  select max(e.ends_at)
    into v_last_end
  from public.ad_free_entitlements e
  where e.user_email = v_email;

  if v_last_end is null or v_last_end <= v_now then
    v_starts_at := v_now;
  else
    v_starts_at := v_last_end;
  end if;

  v_ends_at := v_starts_at + make_interval(days => v_days);

  insert into public.ad_free_entitlements (
    user_email,
    source,
    referral_id,
    granted_days,
    starts_at,
    ends_at,
    metadata
  )
  values (
    v_email,
    'referral',
    p_referral_id,
    v_days,
    v_starts_at,
    v_ends_at,
    jsonb_build_object('role', coalesce(p_role, 'unknown'))
  )
  on conflict (source, referral_id, user_email)
  do nothing;

  get diagnostics v_rows = row_count;
  v_inserted := v_rows > 0;

  return jsonb_build_object(
    'inserted', v_inserted,
    'starts_at', v_starts_at,
    'ends_at', v_ends_at,
    'days', v_days
  );
end;
$$;

create or replace function public.mark_referral_first_search_completed(
  p_referred_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(coalesce(p_referred_email, '')));
  v_referral public.referrals%rowtype;
  v_now timestamptz := now();
  v_referrer_result jsonb;
  v_referred_result jsonb;
begin
  if v_email = '' then
    return jsonb_build_object('awarded', false, 'reason', 'missing_email');
  end if;

  select r.*
    into v_referral
  from public.referrals r
  where r.referred_email = v_email
    and r.status in ('pending', 'qualified', 'rewarded')
  order by r.applied_at desc
  limit 1
  for update;

  if v_referral.id is null then
    return jsonb_build_object('awarded', false, 'reason', 'no_referral');
  end if;

  if v_referral.rewarded_at is not null then
    return jsonb_build_object('awarded', false, 'reason', 'already_rewarded', 'referral_id', v_referral.id);
  end if;

  update public.referrals
  set
    first_search_completed_at = coalesce(first_search_completed_at, v_now),
    status = 'qualified'
  where id = v_referral.id;

  select public.grant_referral_ad_free(v_referral.referrer_email, v_referral.id, v_referral.reward_days, 'referrer')
    into v_referrer_result;

  select public.grant_referral_ad_free(v_referral.referred_email, v_referral.id, v_referral.reward_days, 'referred')
    into v_referred_result;

  update public.referrals
  set
    status = 'rewarded',
    rewarded_at = v_now,
    first_search_completed_at = coalesce(first_search_completed_at, v_now)
  where id = v_referral.id
    and rewarded_at is null;

  return jsonb_build_object(
    'awarded', true,
    'referral_id', v_referral.id,
    'referrer_email', v_referral.referrer_email,
    'referred_email', v_referral.referred_email,
    'reward_days', v_referral.reward_days,
    'referrer_entitlement', v_referrer_result,
    'referred_entitlement', v_referred_result
  );
end;
$$;

revoke execute on function public.grant_referral_ad_free(text, uuid, integer, text) from public, anon, authenticated;
grant execute on function public.grant_referral_ad_free(text, uuid, integer, text) to service_role;

revoke execute on function public.mark_referral_first_search_completed(text) from public, anon, authenticated;
grant execute on function public.mark_referral_first_search_completed(text) to service_role;

commit;
