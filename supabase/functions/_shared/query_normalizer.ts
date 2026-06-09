// ============================================================
// query_normalizer.ts
// Normalización nativa de keywords, filtros y location.
// Sin dependencias externas ni llamadas a IA.
// ============================================================

// ------------------------------------------------------------
// Output de normalización
// ------------------------------------------------------------
export interface NormalizedQuery {
  normalized_query: string;   // keywords canónicas + filtros mapeados
  location_canonical: string; // location limpia para cache_key
  remote: boolean;            // true si algún filtro o keyword indica remoto
  employment_type: string;    // "full-time" | "part-time" | "contract" | ""
  seniority: string;          // "junior" | "senior" | "mid" | ""
  cache_key: string;          // sha256 hex truncado a 32 chars
}

// ------------------------------------------------------------
// Mapa de filtros quick del cliente → términos canónicos
// Cubre los valores actuales de _quickFilterOptions en Flutter:
//   'Remoto', 'Tiempo completo', 'Junior', 'IA'
// y variantes en inglés/español.
// ------------------------------------------------------------
const FILTER_TERM_MAP: Record<string, string> = {
  // Modalidad
  "remoto": "remote",
  "remote": "remote",
  "home office": "remote",
  "teletrabajo": "remote",
  "trabajo desde casa": "remote",
  // Tipo de empleo
  "tiempo completo": "full-time",
  "full-time": "full-time",
  "full time": "full-time",
  "medio tiempo": "part-time",
  "part-time": "part-time",
  "part time": "part-time",
  "contrato": "contract",
  "contract": "contract",
  "temporal": "contract",
  // Seniority
  "junior": "junior",
  "jr": "junior",
  "senior": "senior",
  "sr": "senior",
  "mid": "mid",
  "semi senior": "mid",
  "semi-senior": "mid",
  // Tecnología / especializaciones
  "ia": "AI",
  "ai": "AI",
  "inteligencia artificial": "AI",
  "machine learning": "machine learning",
  "data science": "data science",
};

// Filtros que implican remote=true
const REMOTE_TERMS = new Set(["remote", "home office", "teletrabajo", "trabajo desde casa"]);

// Filtros que implican employment_type
const EMPLOYMENT_TERMS: Record<string, string> = {
  "full-time": "full-time",
  "part-time": "part-time",
  "contract": "contract",
};

// Filtros que implican seniority
const SENIORITY_TERMS: Record<string, string> = {
  "junior": "junior",
  "senior": "senior",
  "mid": "mid",
};

// ------------------------------------------------------------
// Helpers
// ------------------------------------------------------------
function stripDiacritics(value: string): string {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

function normalizeToken(value: string): string {
  return stripDiacritics(value)
    .toLowerCase()
    .replace(/[^a-z0-9\s\-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function canonicalizeLocation(
  exactLocation: string,
  city: string,
  region: string,
  countryName: string,
): string {
  if (exactLocation.trim()) {
    return normalizeToken(exactLocation.trim());
  }
  const parts = [city, region, countryName]
    .map((p) => normalizeToken(p.trim()))
    .filter((p) => p.length > 0);
  // Dedup case-insensitive
  const seen = new Set<string>();
  const deduped: string[] = [];
  for (const p of parts) {
    if (!seen.has(p)) {
      seen.add(p);
      deduped.push(p);
    }
  }
  return deduped.join(", ");
}

async function sha256Hex(value: string): Promise<string> {
  const encoded = new TextEncoder().encode(value);
  const hashBuffer = await crypto.subtle.digest("SHA-256", encoded);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ------------------------------------------------------------
// Función principal
// ------------------------------------------------------------
export async function normalizeQuery(
  keywords: string,
  filters: string[],           // lista de quick filters del cliente
  exactLocation: string,
  city: string,
  region: string,
  countryName: string,
): Promise<NormalizedQuery> {
  // 1. Normalizar keywords base
  const normalizedKeywords = normalizeToken(keywords.trim());

  // 2. Mapear filtros a términos canónicos
  const mappedFilters: string[] = [];
  let remote = false;
  let employment_type = "";
  let seniority = "";

  for (const filter of filters) {
    const key = normalizeToken(filter);
    const mapped = FILTER_TERM_MAP[key] ?? normalizeToken(filter);
    if (mapped) {
      mappedFilters.push(mapped);
    }
    const lowerMapped = mapped.toLowerCase();
    if (REMOTE_TERMS.has(lowerMapped)) {
      remote = true;
    }
    if (EMPLOYMENT_TERMS[lowerMapped]) {
      employment_type = EMPLOYMENT_TERMS[lowerMapped];
    }
    if (SENIORITY_TERMS[lowerMapped]) {
      seniority = SENIORITY_TERMS[lowerMapped];
    }
  }

  // También detectar remote/seniority desde keywords libres
  const kwLower = normalizedKeywords.toLowerCase();
  if (!remote && (kwLower.includes("remot") || kwLower.includes("home office"))) {
    remote = true;
  }
  if (!seniority && kwLower.includes("junior")) seniority = "junior";
  if (!seniority && kwLower.includes("senior")) seniority = "senior";

  // 3. Construir query canónica (keywords + filtros mapeados sin duplicar)
  const allTerms = [normalizedKeywords, ...mappedFilters].filter((t) => t.length > 0);
  const normalized_query = [...new Set(allTerms)].join(" ");

  // 4. Canonicalizar location
  const location_canonical = canonicalizeLocation(exactLocation, city, region, countryName);

  // 5. Generar cache_key
  const hashInput = `${normalized_query}|${location_canonical}`;
  const fullHash = await sha256Hex(hashInput);
  const cache_key = fullHash.slice(0, 32);

  return {
    normalized_query,
    location_canonical,
    remote,
    employment_type,
    seniority,
    cache_key,
  };
}
