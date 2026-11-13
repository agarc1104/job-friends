import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";

function jsonResponse(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function randomReferralCode(length = 8): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  let out = "";
  for (let i = 0; i < length; i += 1) {
    out += alphabet[bytes[i] % alphabet.length];
  }
  return out;
}

function sanitizeCode(rawCode: string): string {
  return rawCode.trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
}

async function getOrCreateCode(adminClient: ReturnType<typeof createClient>, userEmail: string): Promise<string> {
  const { data: existingRow } = await adminClient
    .from("referral_codes")
    .select("referral_code")
    .eq("user_email", userEmail)
    .maybeSingle();

  const existingCode = String(existingRow?.referral_code ?? "").trim().toUpperCase();
  if (existingCode) {
    return existingCode;
  }

  for (let attempt = 0; attempt < 15; attempt += 1) {
    const candidate = randomReferralCode(8);
    const { error } = await adminClient
      .from("referral_codes")
      .insert({ user_email: userEmail, referral_code: candidate });

    if (!error) {
      return candidate;
    }

    // 23505 = unique_violation (retry with a new code)
    if (error.code !== "23505") {
      throw new Error(`Failed to create referral code: ${error.message}`);
    }
  }

  throw new Error("Could not allocate a unique referral code.");
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    return jsonResponse(500, {
      error: "Supabase environment variables are not fully configured.",
    });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse(401, { error: "Missing bearer token." });
  }

  const token = authHeader.replace("Bearer ", "").trim();
  const body = await req.json().catch(() => ({}));
  const action = String((body as Record<string, unknown>).action ?? "").trim().toLowerCase();

  if (!action) {
    return jsonResponse(400, {
      error: "action is required.",
      reason: "invalid_payload",
      retryable: false,
    });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  });

  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) {
    return jsonResponse(401, {
      error: "Invalid user session.",
      reason: "invalid_session",
      retryable: false,
    });
  }

  const userEmail = String(authData.user.email ?? "").trim().toLowerCase();
  if (!userEmail) {
    return jsonResponse(400, {
      error: "Authenticated user has no email.",
      reason: "missing_email",
      retryable: false,
    });
  }

  try {
    if (action === "get_code") {
      const referralCode = await getOrCreateCode(adminClient, userEmail);
      return jsonResponse(200, {
        success: true,
        referral_code: referralCode,
      });
    }

    if (action === "apply_code") {
      const rawCode = String((body as Record<string, unknown>).code ?? "");
      const code = sanitizeCode(rawCode);
      if (!code || !/^[A-Z0-9]{6,12}$/.test(code)) {
        return jsonResponse(400, {
          error: "Invalid referral code format.",
          reason: "invalid_code_format",
          retryable: false,
        });
      }

      const { data: ownReferral } = await adminClient
        .from("referrals")
        .select("id, status, applied_at, referrer_email, referral_code")
        .eq("referred_email", userEmail)
        .maybeSingle();

      if (ownReferral) {
        return jsonResponse(200, {
          success: true,
          applied: false,
          already_applied: true,
          referral: ownReferral,
        });
      }

      const { data: referrerCodeRow } = await adminClient
        .from("referral_codes")
        .select("user_email, referral_code")
        .eq("referral_code", code)
        .maybeSingle();

      const referrerEmail = String(referrerCodeRow?.user_email ?? "").trim().toLowerCase();
      if (!referrerEmail) {
        return jsonResponse(404, {
          error: "Referral code not found.",
          reason: "invalid_code",
          retryable: false,
        });
      }

      if (referrerEmail === userEmail) {
        return jsonResponse(400, {
          error: "You cannot apply your own referral code.",
          reason: "self_referral",
          retryable: false,
        });
      }

      const [applicationsCheck, seenJobsCheck, interviewCheck] = await Promise.all([
        adminClient
          .from("Applications")
          .select("id")
          .eq("applicant_email", userEmail)
          .limit(1),
        adminClient
          .from("user_seen_jobs")
          .select("job_fingerprint")
          .eq("user_email", userEmail)
          .limit(1),
        adminClient
          .from("interview_sessions")
          .select("id")
          .eq("applicant_email", userEmail)
          .limit(1),
      ]);

      const hasApplications = (applicationsCheck.data ?? []).length > 0;
      const hasSeenJobs = (seenJobsCheck.data ?? []).length > 0;
      const hasInterviewSessions = (interviewCheck.data ?? []).length > 0;

      if (hasApplications || hasSeenJobs || hasInterviewSessions) {
        return jsonResponse(400, {
          error: "Referral code can only be applied by new users.",
          reason: "not_new_user",
          retryable: false,
        });
      }

      const { data: createdReferral, error: insertError } = await adminClient
        .from("referrals")
        .insert({
          referrer_email: referrerEmail,
          referred_email: userEmail,
          referral_code: code,
          status: "pending",
          reward_days: 7,
        })
        .select("id, status, applied_at, referrer_email, referral_code")
        .single();

      if (insertError) {
        if (insertError.code === "23505") {
          const { data: duplicated } = await adminClient
            .from("referrals")
            .select("id, status, applied_at, referrer_email, referral_code")
            .eq("referred_email", userEmail)
            .maybeSingle();

          return jsonResponse(200, {
            success: true,
            applied: false,
            already_applied: true,
            referral: duplicated,
          });
        }

        throw new Error(`Failed to apply referral code: ${insertError.message}`);
      }

      return jsonResponse(200, {
        success: true,
        applied: true,
        referral: createdReferral,
      });
    }

    if (action === "status") {
      const now = Date.now();
      const referralCode = await getOrCreateCode(adminClient, userEmail);

      const { data: activeEntitlement } = await adminClient
        .from("ad_free_entitlements")
        .select("ends_at, starts_at")
        .eq("user_email", userEmail)
        .order("ends_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      const endsAtRaw = String(activeEntitlement?.ends_at ?? "").trim();
      const endsAtMs = endsAtRaw ? Date.parse(endsAtRaw) : Number.NaN;
      const isActive = Number.isFinite(endsAtMs) && endsAtMs > now;
      const daysRemaining = isActive ? Math.ceil((endsAtMs - now) / (1000 * 60 * 60 * 24)) : 0;

      const { data: referralStatsRows } = await adminClient
        .from("referrals")
        .select("status")
        .eq("referrer_email", userEmail);

      const stats = {
        pending: 0,
        qualified: 0,
        rewarded: 0,
        canceled: 0,
      };

      for (const row of referralStatsRows ?? []) {
        const status = String(row.status ?? "").trim().toLowerCase();
        if (status in stats) {
          stats[status as keyof typeof stats] += 1;
        }
      }

      const { data: incomingReferral } = await adminClient
        .from("referrals")
        .select("id, status, applied_at, first_search_completed_at, rewarded_at, referrer_email")
        .eq("referred_email", userEmail)
        .maybeSingle();

      return jsonResponse(200, {
        success: true,
        referral_code: referralCode,
        ad_free_active: isActive,
        ad_free_until: endsAtRaw || null,
        ad_free_days_remaining: daysRemaining,
        referrals_sent: stats,
        my_referral: incomingReferral,
      });
    }

    return jsonResponse(400, {
      error: "Unsupported action.",
      reason: "invalid_action",
      retryable: false,
    });
  } catch (error) {
    return jsonResponse(500, {
      error: `Referrals operation failed: ${error instanceof Error ? error.message : String(error)}`,
      reason: "referrals_failed",
      retryable: false,
    });
  }
});
