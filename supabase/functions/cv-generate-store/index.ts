import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { callGeminiWithFallback } from "../_shared/gemini.ts";
import { Document, HeadingLevel, Packer, Paragraph, Table, TableCell, TableRow, TextRun, WidthType } from "https://esm.sh/docx@8.5.0";

const CV_BUCKET = "applicant-cvs";
const CV_METADATA_TABLE = "ApplicantCVs";

type ProfileData = Record<string, string>;

function logCvTrace(stage: string, detail: Record<string, unknown> = {}): void {
  const payload = {
    ts: new Date().toISOString(),
    stage,
    ...detail,
  };
  console.log(`[CV_TRACE] ${JSON.stringify(payload)}`);
}

function classifyUnhandledError(error: unknown): {
  status: number;
  body: Record<string, unknown>;
} {
  const raw = String(error);
  const lower = raw.toLowerCase();

  const retrySecondsMatch = raw.match(/retry in\s+([0-9]+(?:\.[0-9]+)?)s/i);
  const parsedRetry = retrySecondsMatch ? Math.ceil(Number(retrySecondsMatch[1])) : NaN;
  const suggestedRetrySeconds = Number.isFinite(parsedRetry)
    ? Math.max(3, Math.min(90, parsedRetry))
    : 20;

  const isCapacityError =
    lower.includes("http 503") ||
    lower.includes("unavailable") ||
    lower.includes("resource_exhausted") ||
    lower.includes("quota exceeded") ||
    lower.includes("high demand") ||
    lower.includes("salida insuficiente");

  if (isCapacityError) {
    return {
      status: 503,
      body: {
        error: "Alta demanda temporal del proveedor de IA. Intenta nuevamente en unos segundos.",
        retryable: true,
        reason: "capacity",
        suggested_retry_seconds: suggestedRetrySeconds,
        detail: raw,
      },
    };
  }

  return {
    status: 500,
    body: {
      error: raw,
      retryable: false,
      reason: "internal",
    },
  };
}

function normalizeText(value: unknown): string {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

function sanitizeStorageName(value: string): string {
  return normalizeText(value)
    .toLowerCase()
    .replace(/[^a-z0-9@._-]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 120);
}

function stripCodeFences(value: string): string {
  return value
    .replace(/^```(?:latex|tex)?\s*/i, "")
    .replace(/\s*```$/, "")
    .trim();
}

function extractLatexDocument(value: string): string {
  const cleaned = stripCodeFences(value);
  const start = cleaned.indexOf("\\documentclass");
  const end = cleaned.lastIndexOf("\\end{document}");
  if (start >= 0 && end > start) {
    return cleaned.slice(start, end + "\\end{document}".length).trim();
  }
  return cleaned;
}

function looksLikeLatexDocument(value: string): boolean {
  const text = normalizeText(value);
  return text.includes("\\documentclass") && text.includes("\\begin{document}") && text.includes("\\end{document}");
}

function ensureLatexDocumentClosed(value: string): string {
  const cleaned = value.trim();
  if (!cleaned.includes("\\documentclass") || !cleaned.includes("\\begin{document}")) {
    return cleaned;
  }
  if (cleaned.includes("\\end{document}")) {
    return cleaned;
  }
  return `${cleaned}\n\\end{document}`;
}

function hasPlaceholderSignals(value: string): boolean {
  const text = value.toLowerCase();
  return /tu nombre|your name|john doe|nombre apellido|año\s*-\s*presente|empresa líder|ciudad, país/.test(text);
}

function looksPersonalizedForUser(value: string, fullName: string, email: string): boolean {
  const normalizedLatex = normalizeText(value).toLowerCase();
  const normalizedEmail = normalizeText(email).toLowerCase();
  const normalizedName = normalizeText(fullName).toLowerCase();
  const nameTokens = normalizedName.split(" ").filter((token) => token.length >= 3);
  const hasEmail = normalizedEmail.length > 0 && normalizedLatex.includes(normalizedEmail);
  const hasNameToken = nameTokens.length === 0 || nameTokens.some((token) => normalizedLatex.includes(token));
  return hasEmail && hasNameToken && !hasPlaceholderSignals(normalizedLatex);
}

function sanitizeLatexForCompilation(latex: string): string {
  // moderncv \phone can break with malformed AI output. Preserve digits but render as plain extrainfo.
  return latex
    .replace(/^\s*\\usepackage(?:\[[^\]]*\])?\{noto(?:-sans)?\}\s*\n?/gim, "")
    .replace(/^\s*\\usepackage\[[^\]]*\]\{noto\}\s*\n?/gim, "")
    .replace(/^\s*\\usepackage\{fontspec\}\s*\n?/gim, "")
    .replace(/^\s*\\setmainfont\{[^}]*\}\s*\n?/gim, "")
    .replace(/\\phone(?:\[[^\]]*\])?\{([^}]*)\}/gim, (_match: string, value: string) => {
      const normalizedPhone = (value.match(/\d/g) ?? []).join("");
      if (!normalizedPhone) {
        return "";
      }
      return `\\extrainfo{Tel: ${normalizedPhone}}`;
    })
    .replace(/^.*\\phone[^\n]*\n?/gim, (line: string) => {
      const normalizedPhone = (line.match(/\d/g) ?? []).join("");
      if (!normalizedPhone) {
        return "";
      }
      return `\\extrainfo{Tel: ${normalizedPhone}}\n`;
    })
    .replace(/^\s*\\extrainfo\{\s*Tel:\s*\}\s*\n?/gim, "")
    .replace(/^\s*\\homepage\{\s*\}\s*\n?/gim, "")
    .replace(/^\s*\\social\[[^\]]*\]\{\s*\}\s*\n?/gim, "")
    .replace(/^\s*\\address\{\s*\}\{\s*\}(?:\{\s*\})?\s*\n?/gim, "")
    // \photo is fragile in server-side compilation because moderncv expects a resolvable local file path.
    .replace(/^\s*\\photo(?:\[[^\]]*\])?(?:\[[^\]]*\])?\{[^}]*\}\s*\n?/gim, "")
    // \cvsection is not a valid moderncv command; the correct command is \section.
    .replace(/\\cvsection\{/g, "\\section{");
}

function verifyVisualCompliance(
  latex: string,
  visual: { fontSizePt: string; moderncvColor: string; useTwoColumns: boolean },
): { ok: boolean; missing: string[] } {
  const missing: string[] = [];

  const fontSizePattern = new RegExp(`\\\\documentclass\\[${visual.fontSizePt.replace("pt", "")}pt[,\\]]`, "i");
  if (!fontSizePattern.test(latex)) {
    missing.push(`documentclass[${visual.fontSizePt}]`);
  }

  const colorPattern = new RegExp(`\\\\moderncvcolor\\{${visual.moderncvColor}\\}`, "i");
  if (!colorPattern.test(latex)) {
    missing.push(`moderncvcolor{${visual.moderncvColor}}`);
  }

  if (visual.useTwoColumns) {
    if (!/\\usepackage\{paracol\}/i.test(latex)) {
      missing.push("usepackage{paracol}");
    }
    if (!/\\begin\{paracol\}\{2\}/i.test(latex)) {
      missing.push("begin{paracol}{2}");
    }
    if (!/\\switchcolumn/i.test(latex)) {
      missing.push("switchcolumn");
    }
    if (!/\\end\{paracol\}/i.test(latex)) {
      missing.push("end{paracol}");
    }
  }

  return { ok: missing.length === 0, missing };
}

async function buildLatex(fullName: string, email: string, profileData: ProfileData): Promise<string> {
  const phone = normalizeText(profileData.phone);
  const linkedin = normalizeText(profileData.linkedin);
  const targetRoles = normalizeText(profileData.target_roles) || "Profesional";
  const experience = normalizeText(profileData.experience) || "No especificada";
  const education = normalizeText(profileData.education) || "No especificada";
  const skills = normalizeText(profileData.skills) || "No especificadas";
  const jobDescription = normalizeText(profileData.job_description);
  const contact = [email, phone, linkedin].filter(Boolean).join(", ");

  // --- Visual design preferences ---
  const rawFontSize = normalizeText(profileData.cv_font_size).toLowerCase();
  const fontSizePt = rawFontSize === "compacta" ? "10pt" : rawFontSize === "amplia" ? "12pt" : "11pt";

  const rawPalette = normalizeText(profileData.cv_color_palette).toLowerCase();
  const moderncvColor =
    rawPalette === "verde_moderno" ? "green" : rawPalette === "gris_ejecutivo" ? "grey" : "blue";

  const rawColumns = normalizeText(profileData.cv_columns).toLowerCase();
  const useTwoColumns = rawColumns === "dos_columnas";

  const twoColumnsSection = useTwoColumns
    ? "DISEÑO DE DOS COLUMNAS (OBLIGATORIO):\n" +
      "- Usa el paquete paracol para dividir el documento en dos columnas.\n" +
      "- Columna izquierda (ancha, ~65%): Objetivo profesional, Experiencia, Educación.\n" +
      "- Columna derecha (angosta, ~35%): Habilidades, Idiomas, Certificaciones y Proyectos.\n" +
      "- Agrega \\usepackage{paracol} en el preámbulo.\n" +
      "- Usa \\begin{paracol}{2} antes del contenido y \\switchcolumn para cambiar de columna.\n" +
      "- Cierra con \\end{paracol} al final del cuerpo.\n" +
      "- Mantén la compatibilidad con moderncv: las secciones siguen usando \\section, \\cventry y \\cvitem.\n\n"
    : "";

  const jobDescriptionSection = jobDescription
    ? `CONTEXTO DE VACANTE (solo para adaptar redacción y prioridades, NO para agregar experiencia):\n\n${jobDescription}\n\nAdapta el lenguaje del CV a esta vacante, pero sin inventar experiencia ni mezclar datos de la vacante como si fueran historial real del candidato.\n\n`
    : "";

  const prompt =
    `Actúa como un experto en reclutamiento y experto en LaTeX. Necesito que generes un archivo de currículum profesional utilizando la clase moderncv (estilo 'classic', color '${moderncvColor}').\n\n` +
    "IMPORTANTE: responde SOLO con código LaTeX compilable, sin markdown, sin comentarios fuera de LaTeX, sin explicaciones y sin texto conversacional.\n\n" +
    "El contenido debe comenzar con \\documentclass y terminar con \\end{document}.\n\n" +
    "Compatibilidad de compilación obligatoria:\n" +
    "- NO usar \\usepackage{fontspec}.\n" +
    "- NO usar \\setmainfont.\n" +
    "- NO usar \\firstname ni \\familyname.\n" +
    "- Usar \\name{Nombre}{Apellido}.\n" +
    "- Para teléfono usar únicamente \\phone[mobile]{...}; si falta dato, omitir la línea completa (no dejarla vacía).\n" +
    "- Mantener preámbulo mínimo y estable para moderncv.\n" +
    "- NO usar \\cvsection; para títulos de sección usar únicamente \\section{...}.\n\n" +
    "Usa este bloque de preámbulo base como obligatorio (puedes agregar paracol solo si se solicita 2 columnas):\n" +
    `\\documentclass[${fontSizePt},a4paper,sans]{moderncv}\n` +
    "\\moderncvstyle{classic}\n" +
    `\\moderncvcolor{${moderncvColor}}\n` +
    "\\usepackage[utf8]{inputenc}\n" +
    "\\usepackage[T1]{fontenc}\n" +
    "\\usepackage[spanish]{babel}\n" +
    "\\usepackage[sfdefault]{noto}\n\n" +
    "Reglas obligatorias de formato:\n\n" +
    "Usa el bloque universal de preámbulo para LaTeX con babel en español y fuentes Noto Sans.\n\n" +
    "Todos los comandos \\cventry deben tener exactamente SEIS argumentos {...}{...}{...}{...}{...}{...}. Si un dato falta, usa corchetes vacíos {}.\n\n" +
    "Estructura el documento con secciones de: Resumen, Experiencia, Educación, Habilidades y Proyectos.\n\n" +
    "No uses placeholders ni datos ficticios como 'Tu Nombre', 'John Doe', 'Ciudad, País', 'Empresa líder' o similares.\n\n" +
    twoColumnsSection +
    "Reglas críticas de veracidad (OBLIGATORIAS):\n" +
    "- El CV debe basarse EXCLUSIVAMENTE en los datos del candidato entregados abajo.\n" +
    "- La vacante se usa solo para adaptar tono, enfoque y palabras clave; NO es fuente de experiencia del candidato.\n" +
    "- NO agregar empresas, cargos, fechas, logros, responsabilidades, herramientas o proyectos que no estén explícitamente en los datos del candidato.\n" +
    "- NO copiar frases literales de la vacante dentro de Experiencia como si fueran funciones realizadas por el candidato.\n" +
    "- Si falta evidencia para una afirmación, omitirla en lugar de inventarla.\n" +
    "- El CARGO OBJETIVO es el tipo de posición a la que aspira el candidato. Úsalo SOLO para redactar el resumen/objetivo profesional y como guía de enfoque del CV. NO lo incluyas como entrada de experiencia laboral ni como cargo actual.\n\n" +
    "Debes usar exactamente estos datos del candidato para identidad y contacto:\n\n" +
    `Nombre completo exacto: ${fullName}\n` +
    `Email exacto: ${email}\n\n` +
    "DATOS DEL CANDIDATO (fuente única de verdad):\n\n" +
    `Nombre: ${fullName}\n\n` +
    `Cargo objetivo (posición a la que aspira, usar solo para el resumen/objetivo del CV): ${targetRoles}\n\n` +
    `Contacto: ${contact}\n\n` +
    `Experiencia: ${experience}\n\n` +
    `Educación: ${education}\n\n` +
    `Habilidades: ${skills}\n\n` +
    jobDescriptionSection +
    "Por favor, optimiza el lenguaje para que suene profesional, orientado a logros y utiliza verbos de acción. Genera el código completo en un solo bloque listo para previsualizar.";

  logCvTrace("buildLatex.prompt_prepared", {
    fullName,
    email,
    profileKeys: Object.keys(profileData),
    promptLength: prompt.length,
    designChoices: { fontSizePt, moderncvColor, useTwoColumns },
    prompt,
  });

  const raw = await callGeminiWithFallback({
    prompt,
    temperature: 0.1,
    maxOutputTokens: 2800,
    minOutputLength: 500,
    requiredSubstrings: ["\\documentclass", "\\begin{document}"],
  });

  logCvTrace("buildLatex.gemini_raw_response", {
    rawLength: raw.length,
    rawPreview: raw.slice(0, 1200),
  });

  const cleaned = ensureLatexDocumentClosed(extractLatexDocument(raw));
  logCvTrace("buildLatex.cleaned_latex", {
    cleanedLength: cleaned.length,
    cleanedPreview: cleaned.slice(0, 1200),
    hasDocumentClass: cleaned.includes("\\documentclass"),
    hasBeginDocument: cleaned.includes("\\begin{document}"),
    hasEndDocument: cleaned.includes("\\end{document}"),
  });

  const visualCompliance = verifyVisualCompliance(cleaned, { fontSizePt, moderncvColor, useTwoColumns });

  if (looksLikeLatexDocument(cleaned) && looksPersonalizedForUser(cleaned, fullName, email) && visualCompliance.ok) {
    logCvTrace("buildLatex.validation_success", {
      isLatex: true,
      personalized: true,
      visualCompliance: visualCompliance.ok,
    });
    return cleaned;
  }

  const visualRequiredSubstrings = [
    "\\documentclass",
    "\\begin{document}",
    `\\moderncvcolor{${moderncvColor}}`,
  ];
  if (useTwoColumns) {
    visualRequiredSubstrings.push("\\usepackage{paracol}", "\\begin{paracol}{2}", "\\switchcolumn", "\\end{paracol}");
  }

  const strictRepairPrompt =
    `${prompt}\n\n` +
    "CORRECCION OBLIGATORIA: tu salida anterior no cumplio requisitos visuales. Regenera TODO el documento completo y asegúrate de cumplir exactamente estos puntos:\n" +
    `- Debe usar \\documentclass[${fontSizePt},a4paper,sans]{moderncv}.\n` +
    `- Debe usar \\moderncvcolor{${moderncvColor}}.\n` +
    (useTwoColumns
      ? "- Debe incluir \\usepackage{paracol}, \\begin{paracol}{2}, \\switchcolumn y \\end{paracol}.\n"
      : "") +
    "- Responde SOLO con LaTeX completo compilable, sin texto adicional.\n";

  logCvTrace("buildLatex.repair_attempt.start", {
    visualMissing: visualCompliance.missing,
    visualRequiredSubstrings,
  });

  const repairRaw = await callGeminiWithFallback({
    prompt: strictRepairPrompt,
    temperature: 0.0,
    maxOutputTokens: 3200,
    minOutputLength: 500,
    requiredSubstrings: visualRequiredSubstrings,
  });

  const repairCleaned = ensureLatexDocumentClosed(extractLatexDocument(repairRaw));
  const repairVisualCompliance = verifyVisualCompliance(repairCleaned, { fontSizePt, moderncvColor, useTwoColumns });

  logCvTrace("buildLatex.repair_attempt.result", {
    rawLength: repairRaw.length,
    cleanedLength: repairCleaned.length,
    visualCompliance: repairVisualCompliance.ok,
    visualMissing: repairVisualCompliance.missing,
  });

  if (
    looksLikeLatexDocument(repairCleaned) &&
    looksPersonalizedForUser(repairCleaned, fullName, email) &&
    repairVisualCompliance.ok
  ) {
    logCvTrace("buildLatex.validation_success", {
      isLatex: true,
      personalized: true,
      visualCompliance: true,
      strategy: "repair_attempt",
    });
    return repairCleaned;
  }

  logCvTrace("buildLatex.validation_failed", {
    isLatex: looksLikeLatexDocument(cleaned),
    personalized: looksPersonalizedForUser(cleaned, fullName, email),
    visualCompliance: visualCompliance.ok,
    visualMissing: visualCompliance.missing,
  });

  throw new Error(
    `Gemini no devolvio un archivo LaTeX valido/personalizado y con estilo solicitado. ` +
    `Faltantes visuales: ${visualCompliance.missing.join(", ") || "ninguno"}.`,
  );
}

// ---------------------------------------------------------------------------
// PDF: compile LaTeX via latexonline.cc
// ---------------------------------------------------------------------------
async function compileLatexToPdf(latex: string): Promise<Uint8Array> {
  const compilerCandidates = ["xelatex", "pdflatex"];
  const errors: string[] = [];
  const pdfMagic = [0x25, 0x50, 0x44, 0x46, 0x2d]; // %PDF-

  for (const compiler of compilerCandidates) {
    const compileUrl = `https://latexonline.cc/compile?command=${compiler}&force=true&text=${encodeURIComponent(latex)}`;
    logCvTrace("compileLatexToPdf.request", {
      compiler,
      latexLength: latex.length,
      latexPreview: latex.slice(0, 1000),
      compileUrlLength: compileUrl.length,
    });

    const response = await fetch(compileUrl, {
      method: "GET",
    });

    logCvTrace("compileLatexToPdf.response", {
      compiler,
      status: response.status,
      ok: response.ok,
      contentType: response.headers.get("content-type") ?? "",
    });

    if (!response.ok) {
      const compilerLog = normalizeText(await response.text()).slice(0, 600);
      logCvTrace("compileLatexToPdf.compiler_error", {
        compiler,
        compilerLog,
      });
      errors.push(`${compiler}: ${response.status} ${response.statusText} | ${compilerLog || "sin detalle"}`);
      continue;
    }

    const bytes = new Uint8Array(await response.arrayBuffer());
    const isPdf = bytes.length > 5 && pdfMagic.every((value, index) => bytes[index] === value);
    if (!isPdf) {
      logCvTrace("compileLatexToPdf.invalid_pdf_magic", {
        compiler,
        firstBytes: Array.from(bytes.slice(0, 8)),
        totalBytes: bytes.length,
      });
      errors.push(`${compiler}: salida no es PDF valido (bytes=${bytes.length})`);
      continue;
    }

    logCvTrace("compileLatexToPdf.success", {
      compiler,
      totalBytes: bytes.length,
    });
    return bytes;
  }

  throw new Error(
    `Error compilando LaTeX a PDF con todos los compiladores disponibles. Detalles: ${errors.join(" || ")}`,
  );
}

// ---------------------------------------------------------------------------
// DOCX: parse moderncv LaTeX into sections, render with docx library
// ---------------------------------------------------------------------------
function parseLatexSections(latex: string): { name: string; sections: { title: string; items: string[] }[] } {
  const normalizeLatexText = (value: string): string => {
    const cleaned = value
      .replace(/\\textbf\{([^}]*)\}/g, "$1")
      .replace(/\\emph\{([^}]*)\}/g, "$1")
      .replace(/\\underline\{([^}]*)\}/g, "$1")
      .replace(/\\item\s+/g, "")
      .replace(/\\begin\{[^}]*\}/g, "")
      .replace(/\\end\{[^}]*\}/g, "")
      .replace(/\\[a-zA-Z]+\*?(?:\[[^\]]*\])?/g, "")
      .replace(/[{}]/g, "")
      .replace(/~+/g, " ")
      .replace(/\\%/g, "%")
      .replace(/\\&/g, "&")
      .replace(/\\_/g, "_")
      .replace(/\\#/g, "#")
      .replace(/\\\$/g, "$")
      .replace(/\\,/g, ",")
      .replace(/\\:/g, ":");
    return normalizeText(cleaned);
  };

  const extractCommandArguments = (source: string, command: string, expectedArgs: number): string[][] => {
    const outputs: string[][] = [];
    const matcher = new RegExp(`\\\\${command}\\s*`, "g");
    let match: RegExpExecArray | null;

    while ((match = matcher.exec(source)) !== null) {
      let cursor = matcher.lastIndex;
      const args: string[] = [];

      for (let argIndex = 0; argIndex < expectedArgs; argIndex += 1) {
        while (cursor < source.length && /\s/.test(source[cursor])) cursor += 1;
        if (source[cursor] !== "{") {
          args.length = 0;
          break;
        }

        cursor += 1;
        let depth = 1;
        let buffer = "";
        while (cursor < source.length && depth > 0) {
          const ch = source[cursor];
          if (ch === "{") {
            depth += 1;
            buffer += ch;
          } else if (ch === "}") {
            depth -= 1;
            if (depth > 0) {
              buffer += ch;
            }
          } else {
            buffer += ch;
          }
          cursor += 1;
        }

        if (depth !== 0) {
          args.length = 0;
          break;
        }

        args.push(buffer);
      }

      if (args.length === expectedArgs) {
        outputs.push(args);
      }
      matcher.lastIndex = cursor;
    }

    return outputs;
  };

  const nameMatch = latex.match(/\\name\{([^}]*)\}\{([^}]*)\}/);
  const name = nameMatch ? normalizeLatexText(`${nameMatch[1]} ${nameMatch[2]}`) : "Curriculum Vitae";

  const sections: { title: string; items: string[] }[] = [];
  const sectionRegex = /\\section\{([^}]+)\}([\s\S]*?)(?=\\section\{|\\end\{document\})/g;
  let sectionMatch: RegExpExecArray | null;

  while ((sectionMatch = sectionRegex.exec(latex)) !== null) {
    const title = normalizeLatexText(sectionMatch[1]);
    const body = sectionMatch[2];
    const items: string[] = [];

    const cventries = extractCommandArguments(body, "cventry", 6);
    for (const entry of cventries) {
      const parts = [entry[0], entry[1], entry[2], entry[3], entry[5]]
        .map((p) => normalizeLatexText(p))
        .filter((p) => p.length > 0);
      if (parts.length > 0) {
        items.push(parts.join(" — "));
      }
    }

    const cvitemRegex = /\\cvitem\{([^}]*)\}\{([^}]*)\}/g;
    let m: RegExpExecArray | null;
    while ((m = cvitemRegex.exec(body)) !== null) {
      const label = normalizeLatexText(m[1]);
      const value = normalizeLatexText(m[2]);
      if (value) items.push(label ? `${label}: ${value}` : value);
    }

    const cvlistRegex = /\\cvlistitem\{([^}]*)\}/g;
    while ((m = cvlistRegex.exec(body)) !== null) {
      const value = normalizeLatexText(m[1]);
      if (value) items.push(value);
    }

    if (items.length > 0) sections.push({ title, items });
  }

  return { name, sections };
}

// Palette key → 6-char hex (no #) for docx TextRun color
const DOCX_PALETTE_HEX: Record<string, string> = {
  blue: "2E74B5",
  green: "2E9D52",
  grey: "555555",
};

async function renderDocxFromLatex(latex: string): Promise<Uint8Array> {
  logCvTrace("renderDocxFromLatex.start", {
    latexLength: latex.length,
  });
  const { name, sections } = parseLatexSections(latex);

  // --- Parse design preferences from the LaTeX preamble ---
  const colorMatch = latex.match(/\\moderncvcolor\{(\w+)\}/);
  const headingHex = DOCX_PALETTE_HEX[colorMatch?.[1] ?? ""] ?? DOCX_PALETTE_HEX["blue"];

  const fontSizeMatch = latex.match(/\\documentclass\[(\d+)pt[,\]]/);
  const bodyPt = parseInt(fontSizeMatch?.[1] ?? "11", 10);
  const bodyHalfPts = bodyPt * 2;          // docx uses half-points
  const headingHalfPts = (bodyPt + 4) * 2; // section titles slightly larger
  const titleHalfPts = (bodyPt + 8) * 2;   // name/title larger still

  const useTwoColumns = latex.includes("\\begin{paracol}");

  logCvTrace("renderDocxFromLatex.parsed", {
    name,
    sectionsCount: sections.length,
    sectionTitles: sections.map((s) => s.title),
    headingHex,
    bodyPt,
    useTwoColumns,
  });

  // --- Paragraph builders ---
  const noBorder = { style: "none" as const, size: 0, color: "FFFFFF" };
  const noBorders = { top: noBorder, bottom: noBorder, left: noBorder, right: noBorder };

  const makeTitleParagraph = () =>
    new Paragraph({
      heading: HeadingLevel.TITLE,
      children: [new TextRun({ text: name, bold: true, color: headingHex, size: titleHalfPts })],
    });

  const makeSectionParagraphs = (section: { title: string; items: string[] }): Paragraph[] => [
    new Paragraph({ text: "" }),
    new Paragraph({
      heading: HeadingLevel.HEADING_1,
      children: [new TextRun({ text: section.title, bold: true, color: headingHex, size: headingHalfPts })],
    }),
    ...section.items.map(
      (item) =>
        new Paragraph({
          bullet: { level: 0 },
          children: [new TextRun({ text: item, size: bodyHalfPts })],
        }),
    ),
  ];

  // --- Build document body ---
  type DocChild = Paragraph | Table;
  let docChildren: DocChild[];

  if (useTwoColumns) {
    const LEFT_KEYWORDS = ["resumen", "objetivo", "experiencia", "educación", "educacion", "perfil"];
    const isLeft = (title: string) =>
      LEFT_KEYWORDS.some((kw) => title.toLowerCase().includes(kw));

    const leftParagraphs: Paragraph[] = sections
      .filter((s) => isLeft(s.title))
      .flatMap(makeSectionParagraphs);
    const rightParagraphs: Paragraph[] = sections
      .filter((s) => !isLeft(s.title))
      .flatMap(makeSectionParagraphs);

    const columnTable = new Table({
      width: { size: 5000, type: WidthType.PERCENTAGE },
      rows: [
        new TableRow({
          children: [
            new TableCell({
              width: { size: 3000, type: WidthType.PERCENTAGE },
              borders: noBorders,
              children: leftParagraphs.length > 0 ? leftParagraphs : [new Paragraph({ text: "" })],
            }),
            new TableCell({
              width: { size: 2000, type: WidthType.PERCENTAGE },
              borders: noBorders,
              children: rightParagraphs.length > 0 ? rightParagraphs : [new Paragraph({ text: "" })],
            }),
          ],
        }),
      ],
    });

    docChildren = [makeTitleParagraph(), columnTable];
  } else {
    docChildren = [makeTitleParagraph(), ...sections.flatMap(makeSectionParagraphs)];
  }

  const document = new Document({ sections: [{ children: docChildren }] });
  const packer = Packer as unknown as {
    toArrayBuffer?: (doc: Document) => Promise<ArrayBuffer>;
    toBuffer?: (doc: Document) => Promise<Uint8Array | ArrayBuffer>;
    toBase64String?: (doc: Document) => Promise<string>;
  };

  let bytes: Uint8Array;

  if (typeof packer.toArrayBuffer === "function") {
    bytes = new Uint8Array(await packer.toArrayBuffer(document));
  } else if (typeof packer.toBuffer === "function") {
    const buf = await packer.toBuffer(document);
    bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  } else if (typeof packer.toBase64String === "function") {
    const b64 = await packer.toBase64String(document);
    bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  } else {
    throw new Error("No fue posible serializar DOCX en este runtime.");
  }

  const zipMagic = [0x50, 0x4b, 0x03, 0x04]; // PK\x03\x04
  const isDocxZip = bytes.length > 4 && zipMagic.every((value, index) => bytes[index] === value);
  if (!isDocxZip) {
    logCvTrace("renderDocxFromLatex.invalid_zip_magic", {
      firstBytes: Array.from(bytes.slice(0, 8)),
      totalBytes: bytes.length,
    });
    throw new Error("La generacion no devolvio un DOCX valido.");
  }

  logCvTrace("renderDocxFromLatex.success", {
    totalBytes: bytes.length,
  });

  return bytes;
}

serve(async (req: Request) => {
  logCvTrace("request.received", {
    method: req.method,
    url: req.url,
  });

  if (req.method === "OPTIONS") {
    logCvTrace("request.options_preflight", {});
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { full_name, email, profile_data, output_format } = await req.json();
    const profileData = (profile_data ?? {}) as ProfileData;

    logCvTrace("request.payload_parsed", {
      full_name,
      email,
      output_format,
      profile_keys: Object.keys(profileData),
      profile_data: profileData,
    });

    if (!email?.trim()) {
      logCvTrace("request.validation_error", {
        reason: "missing_email",
      });
      return new Response(
        JSON.stringify({ error: "El email es obligatorio." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const normalizedOutputFormat = normalizeText(output_format).toLowerCase() || "pdf";
    if (!(["pdf", "docx", "latex"] as string[]).includes(normalizedOutputFormat)) {
      logCvTrace("request.validation_error", {
        reason: "invalid_output_format",
        normalizedOutputFormat,
      });
      return new Response(
        JSON.stringify({ error: "output_format debe ser pdf, docx o latex." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const normalizedEmail = normalizeText(email).toLowerCase();
    const fullName = normalizeText(full_name) || normalizedEmail;

    const { data: existingCvRecord, error: existingCvError } = await supabase
      .from(CV_METADATA_TABLE)
      .select("storage_path")
      .eq("applicant_email", normalizedEmail)
      .maybeSingle();

    if (existingCvError) {
      logCvTrace("metadata.fetch_existing_error", {
        applicant_email: normalizedEmail,
        message: existingCvError.message,
      });
    }

    const previousStoragePath = normalizeText(existingCvRecord?.storage_path);

    logCvTrace("request.normalized", {
      normalizedEmail,
      fullName,
      normalizedOutputFormat,
    });

    const latexContent = await buildLatex(fullName, normalizedEmail, profileData);
    const sanitizedLatexContent = sanitizeLatexForCompilation(latexContent);

    logCvTrace("latex.sanitized", {
      originalLength: latexContent.length,
      sanitizedLength: sanitizedLatexContent.length,
      changed: latexContent !== sanitizedLatexContent,
      sanitizedPreview: sanitizedLatexContent.slice(0, 1200),
    });

    let fileBytes: Uint8Array;
    let extension: string;
    let contentType: string;

    if (normalizedOutputFormat === "pdf") {
      fileBytes = await compileLatexToPdf(sanitizedLatexContent);
      extension = "pdf";
      contentType = "application/pdf";
    } else if (normalizedOutputFormat === "docx") {
      fileBytes = await renderDocxFromLatex(sanitizedLatexContent);
      extension = "docx";
      contentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    } else {
      fileBytes = new TextEncoder().encode(sanitizedLatexContent);
      extension = "tex";
      contentType = "text/x-tex";
    }

    logCvTrace("file.generated", {
      extension,
      contentType,
      bytes: fileBytes.length,
    });

    const sanitizedEmail = sanitizeStorageName(normalizedEmail);
    const sanitizedName = sanitizeStorageName(fullName || normalizedEmail).replace(/@/g, "_");
    const fileName = `cv_${sanitizedName || "perfil"}.${extension}`;
    const timestamp = new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
    const storagePath = `${sanitizedEmail}/${timestamp}_${fileName}`;

    logCvTrace("storage.pre_upload", {
      fileName,
      storagePath,
      bucket: CV_BUCKET,
    });

    const { error: uploadError } = await supabase.storage
      .from(CV_BUCKET)
      .upload(storagePath, fileBytes, {
        contentType,
        upsert: true,
      });

    if (uploadError) {
      logCvTrace("storage.upload_error", {
        message: uploadError.message,
      });
      return new Response(
        JSON.stringify({ error: `Error al subir CV: ${uploadError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    logCvTrace("storage.upload_success", {
      storagePath,
    });

    const { data: urlData } = supabase.storage.from(CV_BUCKET).getPublicUrl(storagePath);

    const metadataPayload = {
      applicant_email: normalizedEmail,
      file_name: fileName,
      storage_path: storagePath,
      public_url: urlData.publicUrl,
      source: "ai_generated",
      target_roles: normalizeText(profileData.target_roles),
      profile_data: profileData,
      updated_at: new Date().toISOString(),
    };

    const { error: metadataError } = await supabase
      .from(CV_METADATA_TABLE)
      .upsert(metadataPayload, { onConflict: "applicant_email" });

    if (metadataError) {
      logCvTrace("metadata.upsert_error", {
        message: metadataError.message,
      });
      return new Response(
        JSON.stringify({ error: `Error guardando metadata CV: ${metadataError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    logCvTrace("metadata.upsert_success", {
      applicant_email: normalizedEmail,
      output_format: normalizedOutputFormat,
    });

    if (previousStoragePath && previousStoragePath !== storagePath) {
      const { error: removePreviousError } = await supabase.storage
        .from(CV_BUCKET)
        .remove([previousStoragePath]);

      if (removePreviousError) {
        logCvTrace("storage.remove_previous_error", {
          previousStoragePath,
          message: removePreviousError.message,
        });
      } else {
        logCvTrace("storage.remove_previous_success", {
          previousStoragePath,
        });
      }
    }

    console.log(
      `[Telemetry] CV generado por Edge | email=${normalizedEmail} | format=${normalizedOutputFormat} | file=${fileName} | storage=${storagePath} | source=ai_generated`,
    );

    return new Response(
      JSON.stringify({
        file_name: fileName,
        output_format: normalizedOutputFormat,
        public_url: urlData.publicUrl,
        storage_path: storagePath,
        source: "ai_generated",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    logCvTrace("request.unhandled_error", {
      error: String(error),
      stack: error instanceof Error ? error.stack ?? "" : "",
    });

    const classified = classifyUnhandledError(error);
    logCvTrace("request.error_classified", {
      status: classified.status,
      body: classified.body,
    });

    return new Response(
      JSON.stringify(classified.body),
      { status: classified.status, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
