import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";

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

const resolveLanguageCode = (hl: string, gl: string | null): string | null => {
  const explicitHl = asTwoLetterCode(hl);
  if (explicitHl) {
    return explicitHl;
  }
  if (!gl) {
    return null;
  }
  return LANGUAGE_BY_GL[gl] ?? null;
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
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

    console.log(
      "[search-jobs] incoming body",
      JSON.stringify({
        keywords,
        location: exactLocation,
        city,
        region,
        country_name: countryName,
        country_code: countryCode,
        hl,
        gl,
        google_domain: googleDomain,
        next_page_token_present: nextPageToken.length > 0,
      }),
    );

    if (!keywords) {
      return new Response(
        JSON.stringify({ error: "keywords es obligatorio." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const serpapiKey = Deno.env.get("SERPAPI_API_KEY");
    if (!serpapiKey) {
      return new Response(
        JSON.stringify({ error: "SERPAPI_API_KEY no configurada en Supabase Secrets." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const params = new URLSearchParams({
      engine: "google_jobs",
      q: keywords,
      api_key: serpapiKey,
    });

    const resolvedGl = asTwoLetterCode(gl) ?? resolveCountryCode(countryCode, countryName);
    const resolvedHl = resolveLanguageCode(hl, resolvedGl);

    const location = buildLocation(exactLocation, city, region, countryName);
    if (location) {
      params.set("location", location);
    }

    if (resolvedHl) {
      params.set("hl", resolvedHl);
    }
    if (resolvedGl) {
      params.set("gl", resolvedGl);
    }
    if (googleDomain) {
      params.set("google_domain", googleDomain);
    } else if (resolvedGl && GOOGLE_DOMAIN_BY_GL[resolvedGl]) {
      params.set("google_domain", GOOGLE_DOMAIN_BY_GL[resolvedGl]);
    }
    if (nextPageToken) {
      params.set("next_page_token", nextPageToken);
    }

    const sanitizedParams = new URLSearchParams(params);
    sanitizedParams.delete("api_key");
    console.log("[search-jobs] request params", sanitizedParams.toString());

    const requestSerpApi = async (queryParams: URLSearchParams) => {
      const response = await fetch(`https://serpapi.com/search?${queryParams.toString()}`);
      const text = await response.text();
      console.log(
        `[search-jobs] serpapi response status=${response.status} ok=${response.ok} body_preview=${text.slice(0, 500)}`,
      );
      return { response, text };
    };

    let { response: serpResponse, text: responseText } = await requestSerpApi(params);

    if (!serpResponse.ok) {
      const unsupportedLocationError =
        serpResponse.status === 400 &&
        params.has("location") &&
        responseText.includes("Unsupported") &&
        responseText.includes("location-location parameter");

      if (unsupportedLocationError) {
        console.log("[search-jobs] unsupported location detected, retrying without location");
        params.delete("location");
        const retrySanitizedParams = new URLSearchParams(params);
        retrySanitizedParams.delete("api_key");
        console.log("[search-jobs] retry params", retrySanitizedParams.toString());
        const retry = await requestSerpApi(params);
        serpResponse = retry.response;
        responseText = retry.text;
      }
    }

    if (!serpResponse.ok) {
      return new Response(
        JSON.stringify({ error: `SerpAPI error ${serpResponse.status}`, detail: responseText }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const data = JSON.parse(responseText);
    const rawJobs: Array<Record<string, unknown>> = data.jobs_results ?? [];
    const nextToken = data?.serpapi_pagination?.next_page_token;
    const searchParameters = data?.search_parameters ?? {};

    console.log(
      "[search-jobs] parsed response",
      JSON.stringify({
        jobs_count: rawJobs.length,
        next_page_token_present: typeof nextToken === "string" && nextToken.length > 0,
        search_parameters: {
          location_requested: searchParameters.location_requested,
          location_used: searchParameters.location_used,
          hl: searchParameters.hl,
          gl: searchParameters.gl,
          google_domain: searchParameters.google_domain,
        },
      }),
    );

    const jobs = rawJobs.map((job) => ({
      title: job.title ?? "",
      company_name: job.company_name ?? "",
      location: job.location ?? "",
      via: job.via ?? "",
      description: job.description ?? "",
      share_link: job.share_link ?? "",
      source_link: job.source_link ?? "",
      extensions: job.extensions ?? [],
      apply_options: job.apply_options ?? [],
      thumbnail: job.thumbnail ?? "",
      job_id: job.job_id ?? "",
      job_highlights: job.job_highlights ?? [],
      detected_extensions: job.detected_extensions ?? {},
    }));

    return new Response(
      JSON.stringify({
        jobs,
        next_page_token: typeof nextToken === "string" ? nextToken : null,
      }),
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
