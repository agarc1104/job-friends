export interface DeepSeekCallOptions {
  prompt: string;
  temperature: number;
  maxOutputTokens: number;
  minOutputLength?: number;
  requiredSubstrings?: string[];
}

function logDeepSeekTrace(stage: string, detail: Record<string, unknown> = {}): void {
  const payload = {
    ts: new Date().toISOString(),
    stage,
    ...detail,
  };
  console.log(`[DEEPSEEK_TRACE] ${JSON.stringify(payload)}`);
}

function parseModelList(value: string | undefined): string[] {
  if (!value) return [];
  return value
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function parseDeepSeekText(data: unknown): string {
  const json = data as Record<string, unknown>;
  const choices = json["choices"] as Array<Record<string, unknown>> | undefined;
  if (!choices || choices.length === 0) {
    return "";
  }

  // Choose the longest non-empty answer across choices to reduce partial outputs.
  let bestText = "";
  for (const choice of choices) {
    const message = choice["message"] as Record<string, unknown> | undefined;
    if (!message) {
      continue;
    }

    const content = message["content"];
    const text = (() => {
      if (typeof content === "string") {
        return content.trim();
      }

      if (Array.isArray(content)) {
        return content
          .map((part) => {
            if (!part || typeof part !== "object") {
              return "";
            }
            const record = part as Record<string, unknown>;
            const partText = record["text"];
            return typeof partText === "string" ? partText : "";
          })
          .join("")
          .trim();
      }

      return "";
    })();

    if (text.length > bestText.length) {
      bestText = text;
    }
  }

  return bestText;
}

function extractDeepSeekErrorDetail(data: unknown): string {
  if (!data || typeof data !== "object") {
    return "";
  }
  const json = data as Record<string, unknown>;
  const error = json["error"] as Record<string, unknown> | undefined;
  if (!error) {
    return "";
  }
  const message = error["message"];
  return typeof message === "string" ? message.trim() : "";
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

export async function callDeepSeekWithFallback(options: DeepSeekCallOptions): Promise<string> {
  const deepSeekApiKey = Deno.env.get("DEEPSEEK_API_KEY");
  const primaryModel = Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-chat";
  const fallbackModels = parseModelList(
    Deno.env.get("DEEPSEEK_FALLBACK_MODELS") ?? "",
  );
  const baseUrl = (Deno.env.get("DEEPSEEK_API_BASE_URL") ?? "https://api.deepseek.com").replace(/\/+$/, "");
  const url = `${baseUrl}/chat/completions`;

  if (!deepSeekApiKey) {
    throw new Error("DEEPSEEK_API_KEY no configurada en Supabase Secrets.");
  }

  const models = [primaryModel, ...fallbackModels.filter((m) => m !== primaryModel)];
  const maxRounds = 2;

  logDeepSeekTrace("call.start", {
    modelPrimary: primaryModel,
    models,
    url,
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
    logDeepSeekTrace("call.round.start", { round, maxRounds });

    for (const model of models) {
      const requestBody = {
        model,
        messages: [{ role: "user", content: options.prompt }],
        temperature: options.temperature,
        max_tokens: options.maxOutputTokens,
      };

      logDeepSeekTrace("call.attempt.request", {
        model,
        round,
        url,
        requestBody,
      });

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${deepSeekApiKey}`,
        },
        body: JSON.stringify(requestBody),
      });

      if (response.ok) {
        const data = await response.json();
        const text = parseDeepSeekText(data);
        logDeepSeekTrace("call.attempt.response_ok", {
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
            logDeepSeekTrace("call.attempt.output_rejected", {
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
              logDeepSeekTrace("call.attempt.completion_retry.request", {
                model,
                round,
                missingSubstrings,
                completionPromptLength: completionPrompt.length,
              });

              const completionBody = {
                model,
                messages: [{ role: "user", content: completionPrompt }],
                temperature: 0.0,
                max_tokens: options.maxOutputTokens,
              };

              const completionResponse = await fetch(url, {
                method: "POST",
                headers: {
                  "Content-Type": "application/json",
                  "Authorization": `Bearer ${deepSeekApiKey}`,
                },
                body: JSON.stringify(completionBody),
              });

              if (completionResponse.ok) {
                const completionData = await completionResponse.json();
                const completionText = parseDeepSeekText(completionData);
                const completionMissing = requiredSubstrings.filter((item) => !completionText.includes(item));
                const completionMeetsLength = completionText.length >= minOutputLength;
                const completionMeetsSubstrings = completionMissing.length === 0;

                logDeepSeekTrace("call.attempt.completion_retry.response_ok", {
                  model,
                  round,
                  textLength: completionText.length,
                  missingSubstrings: completionMissing,
                  textPreview: completionText.slice(0, 1200),
                });

                if (completionText.trim().length > 0 && completionMeetsLength && completionMeetsSubstrings) {
                  logDeepSeekTrace("call.success", {
                    model,
                    round,
                    strategy: "completion_retry",
                    textLength: completionText.length,
                  });
                  return completionText;
                }
              } else {
                const completionDetail = await completionResponse.text();
                logDeepSeekTrace("call.attempt.completion_retry.response_error", {
                  model,
                  round,
                  status: completionResponse.status,
                  detail: completionDetail.slice(0, 1200),
                });
              }
            }
            continue;
          }

          logDeepSeekTrace("call.success", {
            model,
            round,
            textLength: text.length,
          });
          return text;
        }
        lastError = `Modelo ${model} respondio sin texto util.`;
        logDeepSeekTrace("call.attempt.empty_text", {
          model,
          round,
        });
        continue;
      }

      const responseData = await response.json().catch(() => ({}));
      const detail = extractDeepSeekErrorDetail(responseData) || JSON.stringify(responseData);
      lastError = `Modelo ${model} fallo con HTTP ${response.status}: ${detail}`;
      logDeepSeekTrace("call.attempt.response_error", {
        model,
        round,
        status: response.status,
        detail: detail.slice(0, 1200),
      });

      // Continue to next fallback for transient and availability issues.
      if (response.status === 429 || response.status === 500 || response.status === 502 || response.status === 503 || response.status === 504) {
        logDeepSeekTrace("call.attempt.retryable_error", {
          model,
          round,
          status: response.status,
        });
        continue;
      }

      // For hard failures (e.g., auth/permissions), fail fast.
      throw new Error(lastError);
    }

    logDeepSeekTrace("call.round.end", {
      round,
      maxRounds,
      lastError,
    });

    if (round < maxRounds) {
      // Small backoff before retrying the full model sequence.
      await new Promise((resolve) => setTimeout(resolve, 350));
    }
  }

  logDeepSeekTrace("call.failed_all_models", {
    lastError,
  });

  throw new Error(lastError || "No fue posible obtener respuesta de DeepSeek.");
}

// Temporary alias to reduce churn while callers are migrated.
export const callGeminiWithFallback = callDeepSeekWithFallback;
