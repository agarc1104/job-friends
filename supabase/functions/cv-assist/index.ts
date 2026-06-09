import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { callDeepSeekWithFallback } from "../_shared/gemini.ts";

type SupportedLanguage = "es" | "en" | "pt" | "fr" | "de" | "it";

function resolveSupportedLanguage(languageCode: unknown, locale: unknown): SupportedLanguage {
  const fromCode = String(languageCode ?? "").trim().toLowerCase();
  const fromLocale = String(locale ?? "").trim().toLowerCase();
  const candidate = fromCode || fromLocale;
  const normalized = candidate.replace("_", "-").split("-")[0];
  if (["es", "en", "pt", "fr", "de", "it"].includes(normalized)) {
    return normalized as SupportedLanguage;
  }
  return "es";
}

function languageDisplayName(language: SupportedLanguage): string {
  switch (language) {
    case "en":
      return "English";
    case "pt":
      return "Portuguese";
    case "fr":
      return "French";
    case "de":
      return "German";
    case "it":
      return "Italian";
    case "es":
    default:
      return "Spanish";
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { full_name, email, target_roles, experience, education, skills, summary, language_code, locale } =
      await req.json();

    const language = resolveSupportedLanguage(language_code, locale);
    const languageName = languageDisplayName(language);

    const prompt =
      `Act as a senior resume advisor and respond strictly in ${languageName}.\n` +
      `Write all generated content in ${languageName}.\n` +
      "Return a concrete proposal to improve the profile with: 1 professional summary,\n" +
      "5 experience bullets, 8 ATS skills, and practical recommendations.\n\n" +
      `Nombre: ${full_name}\n` +
      `Email: ${email}\n` +
      `Vacantes objetivo: ${target_roles}\n` +
      `Resumen actual: ${summary}\n` +
      `Experiencia: ${experience}\n` +
      `Educacion: ${education}\n` +
      `Habilidades: ${skills}\n`;

    const suggestion = await callDeepSeekWithFallback({
      prompt,
      temperature: 0.5,
      maxOutputTokens: 1400,
    });

    return new Response(
      JSON.stringify({ suggestion }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
