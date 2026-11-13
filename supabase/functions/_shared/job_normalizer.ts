// ============================================================
// job_normalizer.ts
// Contrato unificado NormalizedJob + mappers para cada proveedor.
// Compatible con JobSearchResult.fromMap() de Flutter sin cambios.
// ============================================================

// ------------------------------------------------------------
// Contrato unificado
// ------------------------------------------------------------
export interface NormalizedJob {
  // Campos que lee JobSearchResult.fromMap directamente
  job_id: string;
  title: string;
  company_name: string;
  location: string;
  description: string;
  apply_options: Array<{ title: string; link: string }>;
  share_link: string;
  via: string;
  source_link: string;
  extensions: string[];
  thumbnail: string;
  job_highlights: Array<{ title: string; items: string[] }>;
  detected_extensions: Record<string, string>;

  // Campos semánticos adicionales (no rompen fromMap, se ignoran si no se usan)
  source: "serpapi";
  employment_type: string;
  remote: boolean;
  salary: string;
  posted_at: string;
}

// ------------------------------------------------------------
// Fingerprint determinístico
// sha256-like simplificado usando Web Crypto (Deno compatible)
// ------------------------------------------------------------
export async function fingerprintJob(
  title: string,
  company: string,
  location: string,
): Promise<string> {
  const raw = `${title.toLowerCase().trim()}|${company.toLowerCase().trim()}|${location.toLowerCase().trim()}`;
  const encoded = new TextEncoder().encode(raw);
  const hashBuffer = await crypto.subtle.digest("SHA-256", encoded);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 16);
}

// ------------------------------------------------------------
// Helpers internos
// ------------------------------------------------------------
function safeStr(value: unknown, fallback = ""): string {
  if (typeof value === "string") return value.trim();
  if (value == null) return fallback;
  return String(value).trim();
}

function detectRemote(fields: string[]): boolean {
  const combined = fields.join(" ").toLowerCase();
  return (
    combined.includes("remot") ||
    combined.includes("remote") ||
    combined.includes("home office") ||
    combined.includes("trabajo desde casa") ||
    combined.includes("teletrabajo")
  );
}

// ------------------------------------------------------------
// Mapper: SerpAPI Google Jobs → NormalizedJob
// SerpAPI jobs_results fields:
//   title, company_name, location, description, via,
//   share_link, source_link, apply_options[], job_highlights[],
//   detected_extensions{schedule_type, salary, posted_at, ...},
//   thumbnail, job_id
// ------------------------------------------------------------
export async function normalizeSerpJob(
  raw: Record<string, unknown>,
): Promise<NormalizedJob> {
  const title = safeStr(raw["title"], "Vacante sin titulo");
  const company = safeStr(
    raw["company_name"] ??
      (raw["detected_extensions"] as Record<string, unknown> | undefined)?.[
        "posted_by"
      ],
    "Empresa no disponible",
  );
  const location = safeStr(raw["location"], "Ubicacion no disponible");
  const description = safeStr(raw["description"]);
  const shareLink = safeStr(raw["share_link"]);
  const sourceLink = safeStr(raw["source_link"]);
  const via = safeStr(raw["via"]);
  const thumbnail = safeStr(raw["thumbnail"]);

  const rawApplyOptions = raw["apply_options"];
  const applyOptions: Array<{ title: string; link: string }> = Array.isArray(
    rawApplyOptions,
  )
    ? rawApplyOptions
        .filter((o): o is Record<string, unknown> => typeof o === "object" && o !== null)
        .map((o) => ({
          title: safeStr(o["title"], "Aplicar"),
          link: safeStr(o["link"]),
        }))
        .filter((o) => o.link.length > 0)
    : [];

  const rawHighlights = raw["job_highlights"];
  const jobHighlights: Array<{ title: string; items: string[] }> = Array.isArray(
    rawHighlights,
  )
    ? rawHighlights
        .filter((h): h is Record<string, unknown> => typeof h === "object" && h !== null)
        .map((h) => ({
          title: safeStr(h["title"]),
          items: Array.isArray(h["items"])
            ? h["items"].filter((i) => typeof i === "string") as string[]
            : [],
        }))
    : [];

  const detectedExtRaw = raw["detected_extensions"];
  const detectedExt: Record<string, string> =
    typeof detectedExtRaw === "object" && detectedExtRaw !== null
      ? Object.fromEntries(
          Object.entries(detectedExtRaw as Record<string, unknown>).map(([k, v]) => [
            k,
            String(v ?? ""),
          ]),
        )
      : {};

  const employmentType = safeStr(detectedExt["schedule_type"] ?? "");
  const remote = detectRemote([
    detectedExt["schedule_type"] ?? "",
    location,
    description,
    via,
  ]);
  const salary = detectedExt["salary"] ?? "";
  const postedAt = detectedExt["posted_at"] ?? "";

  const applyLink = applyOptions[0]?.link ?? shareLink;
  const fp = await fingerprintJob(title, company, location);

  return {
    job_id: fp,
    title,
    company_name: company,
    location,
    description,
    apply_options: applyOptions.length > 0 ? applyOptions : (applyLink ? [{ title: "Aplicar", link: applyLink }] : []),
    share_link: shareLink,
    via,
    source_link: sourceLink,
    extensions: Array.isArray(raw["extensions"])
      ? (raw["extensions"] as unknown[]).map(String)
      : [],
    thumbnail,
    job_highlights: jobHighlights,
    detected_extensions: detectedExt,
    source: "serpapi",
    employment_type: employmentType,
    remote,
    salary,
    posted_at: postedAt,
  };
}
