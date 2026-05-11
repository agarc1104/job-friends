import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { callGeminiWithFallback } from "../_shared/gemini.ts";

interface HistoryMessage {
  role: string;
  content: string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { job_title, job_description, application_link, history, user_message } =
      await req.json();

    // Build conversation history (last 12 messages)
    const recentHistory: HistoryMessage[] = Array.isArray(history)
      ? (history as HistoryMessage[]).slice(-12)
      : [];

    const historyLines = recentHistory
      .filter((m) => m.content?.trim())
      .map((m) => {
        const speaker = m.role?.toLowerCase() === "user" ? "Usuario" : "Asistente";
        return `${speaker}: ${m.content.trim()}`;
      });

    historyLines.push(`Usuario: ${(user_message ?? "").trim()}`);

    const prompt =
      "Actua como coach experto en entrevistas laborales y responde en espanol.\n" +
      "Da respuestas practicas, concretas y aplicables al rol.\n\n" +
      `Vacante: ${job_title ?? "No disponible"}\n` +
      `Enlace: ${application_link ?? "No disponible"}\n` +
      `Descripcion de la vacante:\n${job_description ?? "No disponible"}\n\n` +
      "Historial:\n" +
      historyLines.join("\n") +
      "\n\nResponde como Asistente:";

    const reply = await callGeminiWithFallback({
      prompt,
      temperature: 0.6,
      maxOutputTokens: 1024,
    });

    return new Response(
      JSON.stringify({ reply }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
