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
  const reason = String((requestBody as Record<string, unknown>).reason ?? "").trim();

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

  const userId = authData.user.id;
  const userEmail = (authData.user.email ?? "").trim().toLowerCase();
  if (!userEmail) {
    return jsonResponse(400, {
      error: "Authenticated user has no email.",
      reason: "missing_email",
      retryable: false,
    });
  }

  const { data: cvRows } = await adminClient
    .from("ApplicantCVs")
    .select("storage_path")
    .eq("applicant_email", userEmail);

  const storagePaths = Array.isArray(cvRows)
    ? cvRows
        .map((row) => String(row.storage_path ?? "").trim())
        .filter((path) => path.length > 0)
    : [];

  const { data: rpcResult, error: rpcError } = await adminClient.rpc(
    "soft_delete_account_for_user",
    {
      _user_id: userId,
      _user_email: userEmail,
      p_reason: reason,
    },
  );

  if (rpcError) {
    return jsonResponse(500, {
      error: `Failed to anonymize account data: ${rpcError.message}`,
      reason: "anonymization_failed",
      retryable: false,
    });
  }

  const storageCleanupErrors: string[] = [];
  if (storagePaths.length > 0) {
    const { error: removeError } = await adminClient
      .storage
      .from("applicant-cvs")
      .remove(storagePaths);

    if (removeError) {
      storageCleanupErrors.push(removeError.message);
    }
  }

  const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(userId);
  if (deleteUserError) {
    return jsonResponse(500, {
      error: `Account was anonymized, but auth deletion failed: ${deleteUserError.message}`,
      reason: "auth_delete_failed",
      retryable: true,
      storage_cleanup_errors: storageCleanupErrors,
      anonymization_result: rpcResult,
    });
  }

  return jsonResponse(200, {
    success: true,
    deleted_at: (rpcResult as Record<string, unknown> | null)?.deleted_at ?? null,
    anonymized_email: (rpcResult as Record<string, unknown> | null)?.anonymized_email ?? null,
    already_deleted: (rpcResult as Record<string, unknown> | null)?.already_deleted ?? false,
    storage_cleanup_errors: storageCleanupErrors,
  });
});
