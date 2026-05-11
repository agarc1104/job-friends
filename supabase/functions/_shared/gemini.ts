export interface GeminiCallOptions {
  prompt: string;
  temperature: number;
  maxOutputTokens: number;
  minOutputLength?: number;
  requiredSubstrings?: string[];
}

function logGeminiTrace(stage: string, detail: Record<string, unknown> = {}): void {
  const payload = {
    ts: new Date().toISOString(),
    stage,
    ...detail,
  };
  console.log(`[GEMINI_TRACE] ${JSON.stringify(payload)}`);
}

function parseModelList(value: string | undefined): string[] {
  if (!value) return [];
  return value
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function parseGeminiText(data: unknown): string {
  const json = data as Record<string, unknown>;
  const candidates = json["candidates"] as Array<Record<string, unknown>> | undefined;
  if (!candidates || candidates.length === 0) {
    return "";
  }

  // Gemini can split output across multiple parts and return multiple candidates.
  // Choose the longest non-empty candidate to reduce partial/truncated outputs.
  let bestText = "";
  for (const candidate of candidates) {
    const content = candidate["content"] as Record<string, unknown> | undefined;
    const parts = content?.["parts"] as Array<Record<string, unknown>> | undefined;
    if (!parts || parts.length === 0) {
      continue;
    }

    const text = parts
      .map((part) => (part?.["text"] as string | undefined) ?? "")
      .join("")
      .trim();

    if (text.length > bestText.length) {
      bestText = text;
    }
  }

  return bestText;
}

function buildCompletionPrompt(originalPrompt: string, partialText: string): string {
  return (
    `${originalPrompt}\n\n` +
    "Tu respuesta anterior fue incompleta o truncada. Debes regenerar el documento COMPLETO.\n" +
    "Responde unicamente con LaTeX completo desde \\documentclass hasta \\end{document}.\n" +
    "No omitas \\begin{document} ni \\end{document}.\n\n" +
    "Respuesta parcial previa (referencia, no continuar desde aqui literalmente):\n" +
    partialText.slice(0, 1500)
  );
}

export async function callGeminiWithFallback(options: GeminiCallOptions): Promise<string> {
  const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
  const primaryModel = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
  const fallbackModels = parseModelList(
    Deno.env.get("GEMINI_FALLBACK_MODELS") ?? "gemini-2.5-flash-lite,gemini-2.0-flash,gemini-flash-latest",
  );

  if (!geminiApiKey) {
    throw new Error("GEMINI_API_KEY no configurada en Supabase Secrets.");
  }

  const models = [primaryModel, ...fallbackModels.filter((m) => m !== primaryModel)];
  const maxRounds = 2;

  logGeminiTrace("call.start", {
    modelPrimary: primaryModel,
    models,
    temperature: options.temperature,
    maxOutputTokens: options.maxOutputTokens,
    minOutputLength: options.minOutputLength ?? 0,
    requiredSubstrings: options.requiredSubstrings ?? [],
    maxRounds,
    promptLength: options.prompt.length,
    prompt: options.prompt,
  });

  let lastError = "";
  for (let round = 1; round <= maxRounds; round++) {
    logGeminiTrace("call.round.start", { round, maxRounds });

    for (const model of models) {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiApiKey}`;
      logGeminiTrace("call.attempt.request", {
        model,
        round,
        urlWithoutKey: `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        requestBody: {
          contents: [{ parts: [{ text: options.prompt }] }],
          generationConfig: {
            temperature: options.temperature,
            maxOutputTokens: options.maxOutputTokens,
          },
        },
      });

      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: options.prompt }] }],
          generationConfig: {
            temperature: options.temperature,
            maxOutputTokens: options.maxOutputTokens,
          },
        }),
      });

      if (response.ok) {
        const data = await response.json();
        const text = parseGeminiText(data);
        logGeminiTrace("call.attempt.response_ok", {
          model,
          round,
          textLength: text.length,
          textPreview: text.slice(0, 1200),
        });
        if (text.trim().length > 0) {
          const minOutputLength = options.minOutputLength ?? 0;
          const requiredSubstrings = options.requiredSubstrings ?? [];
          const missingSubstrings = requiredSubstrings.filter((item) => !text.includes(item));
          const meetsLength = text.length >= minOutputLength;
          const meetsSubstrings = missingSubstrings.length === 0;

          if (!meetsLength || !meetsSubstrings) {
            lastError =
              `Modelo ${model} devolvio salida insuficiente (length=${text.length}, min=${minOutputLength}, ` +
              `missing=${missingSubstrings.join("|") || "none"}).`;
            logGeminiTrace("call.attempt.output_rejected", {
              model,
              round,
              textLength: text.length,
              minOutputLength,
              requiredSubstrings,
              missingSubstrings,
              textPreview: text.slice(0, 1200),
            });

            // If output looks like partial LaTeX, ask the same model once for a full regeneration.
            if (text.includes("\\documentclass") && missingSubstrings.length > 0) {
              const completionPrompt = buildCompletionPrompt(options.prompt, text);
              logGeminiTrace("call.attempt.completion_retry.request", {
                model,
                round,
                missingSubstrings,
                completionPromptLength: completionPrompt.length,
              });

              const completionResponse = await fetch(url, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                  contents: [{ parts: [{ text: completionPrompt }] }],
                  generationConfig: {
                    temperature: 0.0,
                    maxOutputTokens: options.maxOutputTokens,
                  },
                }),
              });

              if (completionResponse.ok) {
                const completionData = await completionResponse.json();
                const completionText = parseGeminiText(completionData);
                const completionMissing = requiredSubstrings.filter((item) => !completionText.includes(item));
                const completionMeetsLength = completionText.length >= minOutputLength;
                const completionMeetsSubstrings = completionMissing.length === 0;

                logGeminiTrace("call.attempt.completion_retry.response_ok", {
                  model,
                  round,
                  textLength: completionText.length,
                  missingSubstrings: completionMissing,
                  textPreview: completionText.slice(0, 1200),
                });

                if (completionText.trim().length > 0 && completionMeetsLength && completionMeetsSubstrings) {
                  logGeminiTrace("call.success", {
                    model,
                    round,
                    strategy: "completion_retry",
                    textLength: completionText.length,
                  });
                  return completionText;
                }
              } else {
                const completionDetail = await completionResponse.text();
                logGeminiTrace("call.attempt.completion_retry.response_error", {
                  model,
                  round,
                  status: completionResponse.status,
                  detail: completionDetail.slice(0, 1200),
                });
              }
            }
            continue;
          }

          logGeminiTrace("call.success", {
            model,
            round,
            textLength: text.length,
          });
          return text;
        }
        lastError = `Modelo ${model} respondio sin texto util.`;
        logGeminiTrace("call.attempt.empty_text", {
          model,
          round,
        });
        continue;
      }

      const detail = await response.text();
      lastError = `Modelo ${model} fallo con HTTP ${response.status}: ${detail}`;
      logGeminiTrace("call.attempt.response_error", {
        model,
        round,
        status: response.status,
        detail: detail.slice(0, 1200),
      });

      // Continue to next fallback for transient and availability issues.
      if (response.status === 429 || response.status === 500 || response.status === 502 || response.status === 503 || response.status === 504) {
        logGeminiTrace("call.attempt.retryable_error", {
          model,
          round,
          status: response.status,
        });
        continue;
      }

      // For hard failures (e.g., auth/permissions), fail fast.
      throw new Error(lastError);
    }

    logGeminiTrace("call.round.end", {
      round,
      maxRounds,
      lastError,
    });

    if (round < maxRounds) {
      // Small backoff before retrying the full model sequence.
      await new Promise((resolve) => setTimeout(resolve, 350));
    }
  }

  logGeminiTrace("call.failed_all_models", {
    lastError,
  });

  throw new Error(lastError || "No fue posible obtener respuesta de Gemini.");
}
