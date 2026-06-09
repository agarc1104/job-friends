import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { callDeepSeekWithFallback } from "../_shared/gemini.ts";

interface HistoryMessage {
  role: string;
  content: string;
}

interface CoachReply {
  reply: string;
  coach_feedback: string;
  improved_answer: string;
  next_question: string;
  score: number | null;
  tags: string[];
  session_summary: string;
}

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

function modeInstruction(rawMode: string): string {
  switch ((rawMode || "").trim().toLowerCase()) {
    case "star":
      return "STAR mode: require Situation, Task, Action, and measurable Result.";
    case "technical":
      return [
        "Technical mode: stay tied to the vacancy and the candidate answer.",
        "Ask about stack, APIs, debugging, testing, data flow, performance, or reliability only when relevant.",
        "Do not drift into generic system design, architecture theory, or unrelated coding trivia.",
        "If the vacancy is not deeply technical, keep the question practical and role-specific.",
      ].join(" ");
    case "salary":
      return "Salary negotiation mode: focus on candidate value, range, and professional framing.";
    case "hard_questions":
      return "Hard questions mode: train confident and honest answers under pressure.";
    case "simulation":
    default:
      return "Real simulation mode: alternate as interviewer and coaching mentor.";
  }
}

function extractJsonBlock(rawText: string): CoachReply | null {
  const trimmed = (rawText || "").trim();
  if (!trimmed) {
    return null;
  }

  const fencedMatch = trimmed.match(/```json\s*([\s\S]*?)```/i);
  const candidate = fencedMatch?.[1]?.trim() ?? trimmed;

  try {
    const parsed = JSON.parse(candidate) as Record<string, unknown>;
    const rawTags = parsed.tags;
    const tags = Array.isArray(rawTags)
      ? rawTags
          .map((tag) => String(tag).trim())
          .filter((tag) => tag.length > 0)
      : [];

    const parsedScore = (() => {
      const value = parsed.score;
      if (value === null || value === undefined) {
        return null;
      }
      if (typeof value === "number") {
        return Math.max(0, Math.min(10, value));
      }
      const asNumber = Number(value);
      if (Number.isNaN(asNumber)) {
        return null;
      }
      return Math.max(0, Math.min(10, asNumber));
    })();

    return {
      reply: String(parsed.reply ?? "").trim(),
      coach_feedback: String(parsed.coach_feedback ?? "").trim(),
      improved_answer: String(parsed.improved_answer ?? "").trim(),
      next_question: String(parsed.next_question ?? "").trim(),
      score: parsedScore,
      tags,
      session_summary: String(parsed.session_summary ?? "").trim(),
    };
  } catch (_) {
    return null;
  }
}

function buildFallbackReply(rawText: string, language: SupportedLanguage): CoachReply {
  const content = rawText.trim();
  const fallbackByLanguage: Record<SupportedLanguage, Omit<CoachReply, "reply">> = {
    en: {
      coach_feedback: "Be more specific and show measurable impact.",
      improved_answer: "Include context, concrete action, and quantifiable outcome.",
      next_question: "What specific example best shows your impact in a similar project?",
      score: null,
      tags: ["clarity", "impact"],
      session_summary: "Good momentum. Add more precision and measurable outcomes.",
    },
    es: {
      coach_feedback: "Enfocate en ser mas especifico y mostrar impacto con datos.",
      improved_answer: "Incluye contexto, accion concreta y resultado cuantificable.",
      next_question: "Que ejemplo concreto demuestra mejor tu impacto en un proyecto similar?",
      score: null,
      tags: ["claridad", "impacto"],
      session_summary: "La sesion avanza bien. Falta mas precision y resultados medibles.",
    },
    pt: {
      coach_feedback: "Seja mais especifico e mostre impacto com dados.",
      improved_answer: "Inclua contexto, acao concreta e resultado quantificavel.",
      next_question: "Qual exemplo concreto demonstra melhor seu impacto em um projeto similar?",
      score: null,
      tags: ["clareza", "impacto"],
      session_summary: "Boa evolucao. Falta mais precisao e resultados mensuraveis.",
    },
    fr: {
      coach_feedback: "Sois plus precis et montre ton impact avec des resultats.",
      improved_answer: "Ajoute le contexte, une action concrete et un resultat mesurable.",
      next_question: "Quel exemple concret montre le mieux ton impact sur un projet similaire ?",
      score: null,
      tags: ["clarte", "impact"],
      session_summary: "Bonne progression. Il faut plus de precision et des resultats mesurables.",
    },
    de: {
      coach_feedback: "Sei konkreter und zeige messbare Wirkung mit Daten.",
      improved_answer: "Nenne Kontext, konkrete Aktion und messbares Ergebnis.",
      next_question: "Welches konkrete Beispiel zeigt deinen Einfluss in einem ahnlichen Projekt am besten?",
      score: null,
      tags: ["klarheit", "wirkung"],
      session_summary: "Guter Fortschritt. Es fehlen mehr Prazision und messbare Resultate.",
    },
    it: {
      coach_feedback: "Sii piu specifico e mostra impatto con risultati misurabili.",
      improved_answer: "Includi contesto, azione concreta e risultato quantificabile.",
      next_question: "Quale esempio concreto dimostra meglio il tuo impatto in un progetto simile?",
      score: null,
      tags: ["chiarezza", "impatto"],
      session_summary: "Buona progressione. Servono piu precisione e risultati misurabili.",
    },
  };
  const fallback = fallbackByLanguage[language];
  return {
    reply: content.length > 0
      ? content
      : language === "en"
      ? "Thanks for your answer. Let's practice one more iteration."
      : language === "pt"
      ? "Obrigado pela sua resposta. Vamos praticar mais uma iteracao."
      : language === "fr"
      ? "Merci pour ta reponse. Faisons une iteration de plus."
      : language === "de"
      ? "Danke fur deine Antwort. Lass uns eine weitere Runde uben."
      : language === "it"
      ? "Grazie per la tua risposta. Facciamo un'altra iterazione."
      : "Gracias por tu respuesta. Practiquemos una iteracion mas.",
    coach_feedback: fallback.coach_feedback,
    improved_answer: fallback.improved_answer,
    next_question: fallback.next_question,
    score: fallback.score,
    tags: fallback.tags,
    session_summary: fallback.session_summary,
  };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const {
      job_title,
      job_description,
      application_link,
      history,
      user_message,
      bootstrap_prompt,
      mode,
      session_summary,
      language_code,
      locale,
    } =
      await req.json();

    const language = resolveSupportedLanguage(language_code, locale);
    const languageName = languageDisplayName(language);

    // Build conversation history (last 12 messages)
    const recentHistory: HistoryMessage[] = Array.isArray(history)
      ? (history as HistoryMessage[]).slice(-12)
      : [];

    const historyLines = recentHistory
      .filter((m) => m.content?.trim())
      .map((m) => {
        const speaker = m.role?.toLowerCase() === "user" ? "User" : "Assistant";
        return `${speaker}: ${m.content.trim()}`;
      });

    const normalizedMessage = (user_message ?? "").trim();
    const normalizedBootstrapPrompt = (bootstrap_prompt ?? "").trim();
    const normalizedSummary = (session_summary ?? "").trim();
    const modeRule = modeInstruction(String(mode ?? "simulation"));
    const isBootstrapStart =
      normalizedMessage.length === 0 && normalizedBootstrapPrompt.length > 0;
    const effectiveUserMessage = isBootstrapStart
      ? normalizedBootstrapPrompt
      : normalizedMessage;
    const currentMessageLabel = isBootstrapStart
      ? "Mensaje interno de inicio"
      : "Mensaje actual del usuario";

    const prompt =
      `Act as an expert job interview coach and respond strictly in ${languageName}.\n` +
      "Return ALWAYS valid JSON without extra text.\n" +
      `All string fields in JSON must be written in ${languageName}.\n` +
      "Provide practical, concrete, role-focused guidance.\n" +
      "For technical mode, avoid generic system design unless the vacancy explicitly requires it. Keep the question grounded in the specific role, the stack mentioned in the vacancy, and the candidate's last answer.\n" +
      `${modeRule}\n\n` +
      `Vacante: ${job_title ?? "No disponible"}\n` +
      `Enlace: ${application_link ?? "No disponible"}\n` +
      `Descripcion de la vacante:\n${job_description ?? "No disponible"}\n\n` +
      `Resumen acumulado de sesion:\n${normalizedSummary || "Sin resumen previo"}\n\n` +
      "Historial:\n" +
      historyLines.join("\n") +
      "\n\n" +
      `${currentMessageLabel}:\n${effectiveUserMessage || "(vacio)"}\n\n` +
      "Responde con este objeto JSON exacto:\n" +
      "{\n" +
      "  \"reply\": \"respuesta principal para el usuario\",\n" +
      "  \"coach_feedback\": \"feedback breve y accionable\",\n" +
      "  \"improved_answer\": \"version mejorada o guion sugerido\",\n" +
      "  \"next_question\": \"siguiente pregunta para continuar la practica\",\n" +
      "  \"score\": 0-10 o null,\n" +
      "  \"tags\": [\"etiqueta_1\", \"etiqueta_2\"],\n" +
      "  \"session_summary\": \"resumen de progreso (1-2 lineas)\"\n" +
      "}";

    const rawReply = await callDeepSeekWithFallback({
      prompt,
      temperature: 0.4,
      maxOutputTokens: 1200,
    });

    const structuredReply = extractJsonBlock(rawReply) ?? buildFallbackReply(rawReply, language);

    return new Response(
      JSON.stringify(structuredReply),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
