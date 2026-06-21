import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";

function jsonResponse(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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
  const requestBody = await req.json().catch(() => ({}));
  const currentEmail = String((requestBody as Record<string, unknown>).current_email ?? "").trim().toLowerCase();
  const newEmail = String((requestBody as Record<string, unknown>).new_email ?? "").trim().toLowerCase();
  const phone = String((requestBody as Record<string, unknown>).phone ?? "").trim();

  if (!currentEmail || !newEmail) {
    return jsonResponse(400, {
      error: "current_email and new_email are required.",
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

  const authEmail = (authData.user.email ?? "").trim().toLowerCase();
  if (!authEmail) {
    return jsonResponse(400, {
      error: "Authenticated user has no email.",
      reason: "missing_email",
      retryable: false,
    });
  }

  const { error: rpcError } = await adminClient.rpc(
    "update_applicant_contact_for_user",
    {
      _auth_email: authEmail,
      _current_email: currentEmail,
      _new_email: newEmail,
      _phone: phone,
    },
  );

  if (rpcError) {
    return jsonResponse(500, {
      error: `Failed to update applicant contact: ${rpcError.message}`,
      reason: "contact_update_failed",
      retryable: false,
    });
  }

  return jsonResponse(200, {
    success: true,
    email: newEmail,
    phone,
  });
});
