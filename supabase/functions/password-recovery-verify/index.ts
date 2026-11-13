import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";

const WINDOW_MINUTES = 15;
const MAX_ATTEMPTS_PER_WINDOW = 5;

function jsonResponse(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizeEmail(value: unknown): string {
  return String(value ?? "").trim().toLowerCase();
}

function normalizePhone(value: unknown): string {
  return String(value ?? "").replace(/\D/g, "");
}

function stripDiacritics(value: string): string {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

function normalizeName(value: unknown): string {
  return stripDiacritics(String(value ?? ""))
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

async function sha256(value: string): Promise<string> {
  const encoded = new TextEncoder().encode(value);
  const hashBuffer = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(hashBuffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
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

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(500, {
      error: "Supabase environment variables are not fully configured.",
    });
  }

  const payload = await req.json().catch(() => ({}));
  const email = normalizeEmail((payload as Record<string, unknown>).email);
  const phone = normalizePhone((payload as Record<string, unknown>).phone);
  const fullName = normalizeName((payload as Record<string, unknown>).full_name);

  if (!email || !phone || !fullName) {
    return jsonResponse(200, {
      verified: false,
      message: "No se pudo verificar tu identidad con los datos enviados.",
    });
  }

  const forwardedFor = req.headers.get("x-forwarded-for") ?? "";
  const realIp = req.headers.get("x-real-ip") ?? "";
  const ipSource = forwardedFor.split(",")[0]?.trim() || realIp.trim() || "unknown";

  const emailHash = await sha256(`email:${email}`);
  const ipHash = await sha256(`ip:${ipSource}`);

  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const { count: recentAttemptCount } = await adminClient
    .from("password_recovery_attempts")
    .select("id", { count: "exact", head: true })
    .eq("email_hash", emailHash)
    .gte("created_at", new Date(Date.now() - WINDOW_MINUTES * 60 * 1000).toISOString());

  const isRateLimited = (recentAttemptCount ?? 0) >= MAX_ATTEMPTS_PER_WINDOW;
  if (isRateLimited) {
    await adminClient.from("password_recovery_attempts").insert({
      email_hash: emailHash,
      ip_hash: ipHash,
      success: false,
      reason: "rate_limited",
    });

    return jsonResponse(200, {
      verified: false,
      message: "No se pudo verificar tu identidad con los datos enviados.",
    });
  }

  const { data: applicant } = await adminClient
    .from("Aplicants")
    .select("Email, First_Name, Last_Name, Phone")
    .eq("Email", email)
    .maybeSingle();

  let isVerified = false;
  let reason = "not_found_or_mismatch";

  if (applicant) {
    const expectedFullName = normalizeName(
      `${String(applicant.First_Name ?? "")} ${String(applicant.Last_Name ?? "")}`,
    );
    const expectedPhone = normalizePhone(applicant.Phone);

    if (expectedFullName == fullName && expectedPhone == phone) {
      isVerified = true;
      reason = "verified";
    }
  }

  await adminClient.from("password_recovery_attempts").insert({
    email_hash: emailHash,
    ip_hash: ipHash,
    success: isVerified,
    reason,
  });

  return jsonResponse(200, {
    verified: isVerified,
    message: isVerified
      ? "Identidad verificada. Revisa tu correo para continuar."
      : "No se pudo verificar tu identidad con los datos enviados.",
  });
});
