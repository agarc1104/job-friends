import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import {
  fingerprintJob as _fp,
  normalizeSerpJob,
  type NormalizedJob,
} from "../_shared/job_normalizer.ts";
import { normalizeQuery } from "../_shared/query_normalizer.ts";

// ============================================================
// Configuración
// ============================================================
const MAX_JOBS_PER_PROVIDER = 20;
const CACHE_TTL_HOURS = Number(Deno.env.get("CACHE_TTL_HOURS") ?? "6");

// ============================================================
// Supabase admin client (service_role para caché y seen_jobs)
// ============================================================
function getSupabaseAdmin() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return null;
  return createClient(url, key);
}

// ============================================================
// Caché helpers
// ============================================================
async function getCachedJobs(cacheKey: string): Promise<NormalizedJob[] | null> {
  const sb = getSupabaseAdmin();
  if (!sb) return null;
  try {
    const { data } = await sb
      .from("job_search_cache")
      .select("jobs_json, provider_used")
      .eq("cache_key", cacheKey)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (!data) return null;
    const providerUsed = String(data.provider_used ?? "").toLowerCase().trim();
    // Seguridad operativa: usar solo caché explícitamente generado por SerpAPI.
    if (providerUsed !== "serpapi") {
      console.log("[search-jobs] cache ignored (non-serpapi provider)", providerUsed);
      return null;
    }
    return Array.isArray(data.jobs_json) ? (data.jobs_json as NormalizedJob[]) : null;
  } catch { return null; }
}

async function writeCachedJobs(cacheKey: string, jobs: NormalizedJob[], providerUsed: string): Promise<void> {
  const sb = getSupabaseAdmin();
  if (!sb) return;
  const expiresAt = new Date(Date.now() + CACHE_TTL_HOURS * 60 * 60 * 1000).toISOString();
  try {
    await sb.from("job_search_cache").upsert(
      { cache_key: cacheKey, jobs_json: jobs, provider_used: providerUsed, expires_at: expiresAt },
      { onConflict: "cache_key" },
    );
  } catch { /* Non-fatal */ }
}

// ============================================================
// user_seen_jobs helpers
// ============================================================
async function getSeenFingerprints(userEmail: string): Promise<Set<string>> {
  const sb = getSupabaseAdmin();
  if (!sb) return new Set();
  try {
    const { data } = await sb
      .from("user_seen_jobs")
      .select("job_fingerprint")
      .eq("user_email", userEmail.toLowerCase().trim());
    if (!data) return new Set();
    return new Set(data.map((r: { job_fingerprint: string }) => r.job_fingerprint));
  } catch { return new Set(); }
}

async function markJobsSeen(userEmail: string, fingerprints: string[]): Promise<void> {
  if (!fingerprints.length) return;
  const sb = getSupabaseAdmin();
  if (!sb) return;
  const email = userEmail.toLowerCase().trim();
  try {
    await sb.from("user_seen_jobs").upsert(
      fingerprints.map((fp) => ({ user_email: email, job_fingerprint: fp })),
      { onConflict: "user_email,job_fingerprint", ignoreDuplicates: true },
    );
  } catch { /* Non-fatal */ }
}

// ============================================================
// Deduplicar por job_id (fingerprint)
// ============================================================
function deduplicateJobs(jobs: NormalizedJob[]): NormalizedJob[] {
  const seen = new Set<string>();
  return jobs.filter((j) => { if (seen.has(j.job_id)) return false; seen.add(j.job_id); return true; });
}

async function maybeRewardReferralForFirstSearch(userEmail: string): Promise<void> {
  const email = userEmail.trim().toLowerCase();
  if (!email || email === "__anon__") {
    return;
  }

  const sb = getSupabaseAdmin();
  if (!sb) {
    return;
  }

  try {
    const { error } = await sb.rpc("mark_referral_first_search_completed", {
      p_referred_email: email,
    });

    if (error) {
      console.warn("[search-jobs] referral reward rpc failed", error.message);
    }
  } catch (error) {
    console.warn("[search-jobs] referral reward unexpected error", String(error));
  }
}

// ============================================================
// SerpAPI helpers (preservados del flujo original)
// ============================================================
const COUNTRY_ALIASES: Record<string, string> = {
  argentina: "ar",
  bolivia: "bo",
  "bosnia and herzegovina": "ba",
  brasil: "br",
  brazil: "br",
  bulgaria: "bg",
  canada: "ca",
  chile: "cl",
  china: "cn",
  colombia: "co",
  "corea del sur": "kr",
  "costa rica": "cr",
  croatia: "hr",
  czechia: "cz",
  "czech republic": "cz",
  denmark: "dk",
  ecuador: "ec",
  egypt: "eg",
  "el salvador": "sv",
  espana: "es",
  estonia: "ee",
  finland: "fi",
  france: "fr",
  francia: "fr",
  germany: "de",
  greece: "gr",
  guatemala: "gt",
  honduras: "hn",
  hongkong: "hk",
  "hong kong": "hk",
  hungary: "hu",
  india: "in",
  indonesia: "id",
  ireland: "ie",
  israel: "il",
  italia: "it",
  italy: "it",
  japan: "jp",
  japon: "jp",
  kazakhstan: "kz",
  latvia: "lv",
  lithuania: "lt",
  luxembourg: "lu",
  malaysia: "my",
  mexico: "mx",
  "new zealand": "nz",
  nicaragua: "ni",
  norway: "no",
  panama: "pa",
  paraguay: "py",
  peru: "pe",
  philippines: "ph",
  poland: "pl",
  portugal: "pt",
  "puerto rico": "pr",
  romania: "ro",
  russia: "ru",
  "reino unido": "uk",
  singapore: "sg",
  slovakia: "sk",
  slovenia: "si",
  "south africa": "za",
  "south korea": "kr",
  spain: "es",
  sweden: "se",
  switzerland: "ch",
  taiwan: "tw",
  thailand: "th",
  turkey: "tr",
  "united kingdom": "uk",
  "united states": "us",
  "estados unidos": "us",
  usa: "us",
  ukraine: "ua",
  uruguay: "uy",
  venezuela: "ve",
  vietnam: "vn",
  australia: "au",
  austria: "at",
  belgium: "be",
  netherlands: "nl",
};

const LANGUAGE_BY_GL: Record<string, string> = {
  ar: "es",
  bo: "es",
  br: "pt",
  cl: "es",
  co: "es",
  cr: "es",
  ec: "es",
  es: "es",
  gt: "es",
  hn: "es",
  mx: "es",
  ni: "es",
  pa: "es",
  pe: "es",
  py: "es",
  sv: "es",
  uy: "es",
  ve: "es",
  us: "en",
  uk: "en",
};

const GOOGLE_DOMAIN_BY_GL: Record<string, string> = {
  ae: "google.ae",
  ar: "google.com.ar",
  at: "google.at",
  au: "google.com.au",
  ba: "google.ba",
  be: "google.be",
  bg: "google.bg",
  bo: "google.com.bo",
  br: "google.com.br",
  ca: "google.ca",
  ch: "google.ch",
  cl: "google.cl",
  cn: "google.com.hk",
  co: "google.com.co",
  cr: "google.co.cr",
  cz: "google.cz",
  de: "google.de",
  dk: "google.dk",
  ec: "google.com.ec",
  ee: "google.ee",
  eg: "google.com.eg",
  es: "google.es",
  fi: "google.fi",
  fr: "google.fr",
  gr: "google.gr",
  gt: "google.com.gt",
  hk: "google.com.hk",
  hn: "google.hn",
  hr: "google.hr",
  hu: "google.hu",
  id: "google.co.id",
  ie: "google.ie",
  il: "google.co.il",
  in: "google.co.in",
  it: "google.it",
  jp: "google.co.jp",
  kr: "google.co.kr",
  kz: "google.kz",
  lt: "google.lt",
  lu: "google.lu",
  mx: "google.com.mx",
  my: "google.com.my",
  nl: "google.nl",
  ni: "google.com.ni",
  no: "google.no",
  nz: "google.co.nz",
  pa: "google.com.pa",
  pe: "google.com.pe",
  ph: "google.com.ph",
  pl: "google.pl",
  pt: "google.pt",
  py: "google.com.py",
  ro: "google.ro",
  ru: "google.ru",
  se: "google.se",
  sg: "google.com.sg",
  si: "google.si",
  sk: "google.sk",
  sv: "google.com.sv",
  th: "google.co.th",
  tr: "google.com.tr",
  tw: "google.com.tw",
  ua: "google.com.ua",
  uk: "google.co.uk",
  us: "google.com",
  uy: "google.com.uy",
  ve: "google.co.ve",
  vn: "google.com.vn",
  za: "google.co.za",
};

const stripDiacritics = (value: string): string =>
  value.normalize("NFD").replace(/[\u0300-\u036f]/g, "");

const normalizeForLookup = (value: string): string =>
  stripDiacritics(value)
    .toLowerCase()
    .replace(/\.+/g, " ")
    .replace(/[^a-z\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

const asTwoLetterCode = (value: string): string | null => {
  const normalized = value.trim().toLowerCase();
  return /^[a-z]{2}$/.test(normalized) ? normalized : null;
};

const resolveCountryCode = (countryCode: string, countryName: string): string | null => {
  const explicitCode = asTwoLetterCode(countryCode);
  if (explicitCode) {
    return explicitCode;
  }

  const lookupKey = normalizeForLookup(countryName);
  if (!lookupKey) {
    return null;
  }

  if (COUNTRY_ALIASES[lookupKey]) {
    return COUNTRY_ALIASES[lookupKey];
  }

  return asTwoLetterCode(lookupKey);
};

const ADMIN_SEGMENTS_TO_DROP = new Set(["dc", "d c"]);

const normalizeLocationToken = (value: string): string =>
  stripDiacritics(value)
    .replace(/\./g, " ")
    .replace(/\s+/g, " ")
    .trim();

const extractNormalizedLocationParts = (value: string): string[] => {
  const rawParts = value
    .split(",")
    .map((part) => normalizeLocationToken(part))
    .filter((part) => part.length > 0);

  return rawParts.filter((part) => !ADMIN_SEGMENTS_TO_DROP.has(part.toLowerCase()));
};

const dedupeCaseInsensitive = (items: string[]): string[] => {
  const seen = new Set<string>();
  const result: string[] = [];

  for (const item of items) {
    const key = item.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.push(item);
  }

  return result;
};

const buildLocation = (
  exactLocation: string,
  city: string,
  region: string,
  countryName: string,
): string | null => {
  const exactParts = dedupeCaseInsensitive(extractNormalizedLocationParts(exactLocation));
  if (exactParts.length > 0) {
    return exactParts.join(", ");
  }

  const parts = [
    ...extractNormalizedLocationParts(city),
    ...extractNormalizedLocationParts(region),
    ...extractNormalizedLocationParts(countryName),
  ];

  const normalizedParts = dedupeCaseInsensitive(parts);
  return normalizedParts.length > 0 ? normalizedParts.join(", ") : null;
};

const buildLocationCandidates = (
  exactLocation: string,
  city: string,
  region: string,
  countryName: string,
): string[] => {
  const candidates: string[] = [];
  const pushCandidate = (value: string | null) => {
    if (!value || !value.trim()) return;
    candidates.push(value.trim());
  };

  const exact = buildLocation(exactLocation, "", "", "");
  pushCandidate(exact);

  const full = buildLocation("", city, region, countryName);
  pushCandidate(full);

  const cityCountry = buildLocation("", city, "", countryName);
  pushCandidate(cityCountry);

  const regionCountry = buildLocation("", "", region, countryName);
  pushCandidate(regionCountry);

  const countryOnly = buildLocation("", "", "", countryName);
  pushCandidate(countryOnly);

  return dedupeCaseInsensitive(candidates);
};

const resolveLanguageCode = (hl: string, gl: string | null): string | null => {
  const explicitHl = asTwoLetterCode(hl);
  if (explicitHl) return explicitHl;
  if (!gl) return null;
  return LANGUAGE_BY_GL[gl] ?? null;
};

// ============================================================
// Fetch SerpAPI (fallback)
// ============================================================
async function fetchSerpApi(
  keywords: string,
  exactLocation: string,
  city: string,
  region: string,
  countryName: string,
  countryCode: string,
  hl: string,
  gl: string,
  googleDomain: string,
  nextPageToken: string,
): Promise<{ jobs: NormalizedJob[]; nextToken: string | null }> {
  const serpapiKey = Deno.env.get("SERPAPI_API_KEY");
  if (!serpapiKey) { console.warn("[search-jobs] SERPAPI_API_KEY no configurada."); return { jobs: [], nextToken: null }; }

  const resolvedGl = asTwoLetterCode(gl) ?? resolveCountryCode(countryCode, countryName);
  const resolvedHl = resolveLanguageCode(hl, resolvedGl);
  const locationCandidates = buildLocationCandidates(exactLocation, city, region, countryName);

  const baseParams = new URLSearchParams({ engine: "google_jobs", q: keywords, api_key: serpapiKey });
  if (resolvedHl) baseParams.set("hl", resolvedHl);
  if (resolvedGl) baseParams.set("gl", resolvedGl);
  if (googleDomain) baseParams.set("google_domain", googleDomain);
  else if (resolvedGl && GOOGLE_DOMAIN_BY_GL[resolvedGl]) baseParams.set("google_domain", GOOGLE_DOMAIN_BY_GL[resolvedGl]);
  if (nextPageToken) baseParams.set("next_page_token", nextPageToken);

  const doRequest = async (p: URLSearchParams) => {
    const requestUrl = new URL("https://serpapi.com/search");
    requestUrl.search = p.toString();
    const redactedUrl = new URL(requestUrl.toString());
    if (redactedUrl.searchParams.has("api_key")) {
      redactedUrl.searchParams.set("api_key", "[REDACTED]");
    }
    console.log(`[search-jobs] serpapi final request ${redactedUrl.toString()}`);
    const r = await fetch(requestUrl.toString());
    const t = await r.text();
    console.log(`[search-jobs] serpapi status=${r.status} preview=${t.slice(0, 300)}`);
    return { response: r, text: t };
  };

  const attempts: Array<string | null> = [...locationCandidates, null];
  for (const candidateLocation of attempts) {
    const params = new URLSearchParams(baseParams);
    if (candidateLocation) {
      params.set("location", candidateLocation);
    }

    console.log("[search-jobs] serpapi location attempt", JSON.stringify({
      location: candidateLocation,
      gl: resolvedGl,
      hl: resolvedHl,
      google_domain: params.get("google_domain"),
    }));

    const { response: serpResp, text: respText } = await doRequest(params);
    if (serpResp.ok) {
      const data = JSON.parse(respText);
      const rawJobs: Array<Record<string, unknown>> = data.jobs_results ?? [];
      const nextToken = data?.serpapi_pagination?.next_page_token ?? null;
      const normalized = await Promise.all(
        rawJobs.slice(0, MAX_JOBS_PER_PROVIDER).map((j) => normalizeSerpJob(j)),
      );
      console.log("[search-jobs] serpapi normalized", normalized.length, "effective_location", candidateLocation ?? "none");
      return { jobs: normalized, nextToken: typeof nextToken === "string" ? nextToken : null };
    }

    const unsupportedLocation = serpResp.status === 400 && !!candidateLocation &&
      respText.includes("Unsupported") && respText.includes("location");
    if (unsupportedLocation) {
      console.warn("[search-jobs] serpapi unsupported location", candidateLocation);
      continue;
    }

    console.warn("[search-jobs] serpapi failed", serpResp.status, "location", candidateLocation ?? "none");
    return { jobs: [], nextToken: null };
  }

  return { jobs: [], nextToken: null };
}

// ============================================================
// Servidor principal — orquestador SerpApi-only
// ============================================================
serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ----------------------------------------------------------
    // PASO 1: PARSE
    // ----------------------------------------------------------
    const body = await req.json();
    const keywords = String(body.keywords ?? "").trim();
    const exactLocation = String(body.location ?? "").trim();
    const city = String(body.city ?? "").trim();
    const region = String(body.region ?? "").trim();
    const countryName = String(body.country_name ?? "").trim();
    const countryCode = String(body.country_code ?? "").trim();
    const hl = String(body.hl ?? "").trim().toLowerCase();
    const gl = String(body.gl ?? "").trim().toLowerCase();
    const googleDomain = String(body.google_domain ?? "").trim().toLowerCase();
    const nextPageToken = String(body.next_page_token ?? "").trim();
    const userEmail = String(body.user_email ?? "").trim().toLowerCase();
    const filters: string[] = Array.isArray(body.filters)
      ? body.filters.map((f: unknown) => String(f ?? "").trim()).filter((f: string) => f.length > 0)
      : [];

    console.log("[search-jobs] incoming", JSON.stringify({
      keywords, location: exactLocation, city, region, country_name: countryName,
      country_code: countryCode, hl, gl, google_domain: googleDomain,
      next_page_token_present: nextPageToken.length > 0,
      user_email_present: userEmail.length > 0, filters,
    }));

    if (!keywords) {
      return new Response(
        JSON.stringify({ error: "keywords es obligatorio." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ----------------------------------------------------------
    // PASO 2: NORMALIZE (nativo, sin IA)
    // ----------------------------------------------------------
    const normalized = await normalizeQuery(keywords, filters, exactLocation, city, region, countryName);
    console.log("[search-jobs] normalized", JSON.stringify(normalized));

    // ----------------------------------------------------------
    // PASO 3: CACHE CHECK (solo primera página)
    // ----------------------------------------------------------
    if (!nextPageToken) {
      const cached = await getCachedJobs(normalized.cache_key);
      if (cached && cached.length > 0) {
        console.log("[search-jobs] cache hit", cached.length, "jobs");
        let jobsToReturn = cached;
        if (userEmail) {
          const seen = await getSeenFingerprints(userEmail);
          const newJobs = cached.filter((j) => !seen.has(j.job_id));
          if (newJobs.length > 0) jobsToReturn = newJobs;
          // Si todos fueron vistos → devolver caché completo para no dejar pantalla vacía
        }
        await maybeRewardReferralForFirstSearch(userEmail);
        await markJobsSeen(userEmail || "__anon__", jobsToReturn.map((j) => j.job_id));
        return new Response(
          JSON.stringify({ jobs: jobsToReturn, next_page_token: null, source_used: "cache" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    // ----------------------------------------------------------
    // PASO 4: FILTER SEEN (si hay user_email)
    // ----------------------------------------------------------
    let seenFingerprints = new Set<string>();
    if (userEmail) {
      seenFingerprints = await getSeenFingerprints(userEmail);
    }
    // ----------------------------------------------------------
    // PASO 5: FETCH SerpAPI (única fuente)
    // ----------------------------------------------------------
    const serpResult = await fetchSerpApi(
      normalized.normalized_query,
      exactLocation,
      city,
      region,
      countryName,
      countryCode,
      hl,
      gl,
      googleDomain,
      nextPageToken,
    );
    const primaryJobs = serpResult.jobs;
    const serpOutNextToken = serpResult.nextToken;
    const unseenJobs = primaryJobs.filter((j) => !seenFingerprints.has(j.job_id));
    const jobsToReturn = unseenJobs.length > 0 ? unseenJobs : primaryJobs;
    const providerUsed = "serpapi";

    // ----------------------------------------------------------
    // PASO 6: CACHE WRITE (solo página 1)
    // ----------------------------------------------------------
    if (!nextPageToken && primaryJobs.length > 0) {
      await writeCachedJobs(normalized.cache_key, primaryJobs, providerUsed);
    }

    // ----------------------------------------------------------
    // PASO 7: MARK SEEN + next_page_token + RETURN
    // ----------------------------------------------------------
    if (!nextPageToken) {
      await maybeRewardReferralForFirstSearch(userEmail);
    }
    await markJobsSeen(userEmail || "__anon__", jobsToReturn.map((j) => j.job_id));

    const outNextPageToken: string | null = serpOutNextToken;

    console.log("[search-jobs] response", JSON.stringify({
      jobs_count: jobsToReturn.length,
      provider_used: providerUsed,
      next_page_token_present: !!outNextPageToken,
    }));

    return new Response(
      JSON.stringify({ jobs: jobsToReturn, next_page_token: outNextPageToken, source_used: providerUsed }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("[search-jobs] unhandled error", error);
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
