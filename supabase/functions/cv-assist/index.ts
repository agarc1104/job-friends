import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { callGeminiWithFallback } from "../_shared/gemini.ts";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { full_name, email, target_roles, experience, education, skills, summary } =
      await req.json();

    const prompt =
      "Actua como asesor senior de CV en espanol.\n" +
      "Devuelve una propuesta concreta para mejorar el perfil, con 1 resumen profesional,\n" +
      "5 bullets de experiencia, 8 habilidades ATS y recomendaciones de enfoque.\n\n" +
      `Nombre: ${full_name}\n` +
      `Email: ${email}\n` +
      `Vacantes objetivo: ${target_roles}\n` +
      `Resumen actual: ${summary}\n` +
      `Experiencia: ${experience}\n` +
      `Educacion: ${education}\n` +
      `Habilidades: ${skills}\n`;

    const suggestion = await callGeminiWithFallback({
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
