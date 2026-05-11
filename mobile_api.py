from __future__ import annotations

from datetime import datetime, timezone
import io
import json
from pathlib import Path
import threading
import traceback
from typing import Any
from urllib.parse import urlparse

import httpx
import requests
from bs4 import BeautifulSoup
from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, Field
from supabase import create_client

from backend_config import settings
from services.job_search_service import search_google_jobs


app = FastAPI(title="JobFriends Mobile API", version="0.1.0")

# ---------------------------------------------------------------------------
# In-memory metrics counters (reset on process restart)
# ---------------------------------------------------------------------------
_metrics_lock = threading.Lock()
_metrics: dict[str, int] = {
    "requests_total": 0,
    "requests_error": 0,
    "cv_generate_ok": 0,
    "cv_generate_error": 0,
    "cv_upload_ok": 0,
    "cv_upload_error": 0,
    "interview_reply_ok": 0,
    "interview_reply_error": 0,
    "jobs_search_ok": 0,
    "jobs_search_error": 0,
    "manual_application_ok": 0,
    "manual_application_error": 0,
}


def _inc(key: str, amount: int = 1) -> None:
    with _metrics_lock:
        _metrics[key] = _metrics.get(key, 0) + amount


@app.middleware("http")
async def _count_requests(request: Request, call_next):
    _inc("requests_total")
    response = await call_next(request)
    if response.status_code >= 500:
        _inc("requests_error")
    return response


class JobSearchRequest(BaseModel):
    keywords: str = Field(default="")
    location: str = Field(default="")
    city: str = Field(default="")
    region: str = Field(default="")
    country_name: str = Field(default="")
    hl: str = Field(default="")
    gl: str = Field(default="")
    google_domain: str = Field(default="")


class JobSearchResponse(BaseModel):
    jobs: list[dict[str, Any]]


class CvAssistRequest(BaseModel):
    full_name: str = Field(default="")
    email: str = Field(default="")
    target_roles: str = Field(default="")
    experience: str = Field(default="")
    education: str = Field(default="")
    skills: str = Field(default="")
    summary: str = Field(default="")


class CvAssistResponse(BaseModel):
    suggestion: str


class CvGenerateStoreRequest(BaseModel):
    full_name: str = Field(default="")
    email: str
    output_format: str = Field(default="docx")
    profile_data: dict[str, str] = Field(default_factory=dict)


class CvGenerateStoreResponse(BaseModel):
    file_name: str
    output_format: str
    public_url: str
    storage_path: str
    source: str


class MonetizationEventRequest(BaseModel):
    event_name: str
    user_email: str = Field(default="")
    value_usd: float = Field(default=0.0)
    metadata: dict[str, Any] = Field(default_factory=dict)


class MonetizationEventResponse(BaseModel):
    logged: bool
    detail: str = Field(default="")


class InterviewMessage(BaseModel):
    role: str
    content: str


class InterviewRequest(BaseModel):
    job_title: str = Field(default="")
    job_description: str = Field(default="")
    application_link: str = Field(default="")
    history: list[InterviewMessage] = Field(default_factory=list)
    user_message: str


class InterviewResponse(BaseModel):
    reply: str


class ManualApplicationRequest(BaseModel):
    applicant_email: str
    application_url: str


class ManualApplicationResponse(BaseModel):
    website: str
    vacancy: str
    status: str
    application_link: str
    description: str


def _invoke_supabase_edge_function(function_name: str, payload: dict[str, Any]) -> dict[str, Any]:
    if not settings.supabase_url:
        raise ValueError("SUPABASE_URL no configurada en el servidor.")

    api_key = settings.supabase_service_role_key or settings.supabase_key
    if not api_key:
        raise ValueError("SUPABASE_SERVICE_ROLE_KEY o SUPABASE_KEY no configurada en el servidor.")

    base_url = settings.supabase_url.rstrip("/")
    edge_url = f"{base_url}/functions/v1/{function_name}"

    try:
        response = httpx.post(
            edge_url,
            json=payload,
            headers={
                "apikey": api_key,
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            timeout=90.0,
        )
    except httpx.HTTPError as ex:
        raise ValueError(f"No fue posible conectar con Edge Function '{function_name}': {ex}") from None

    if response.status_code >= 400:
        detail = ""
        try:
            payload_error = response.json()
            if isinstance(payload_error, dict):
                detail = str(payload_error.get("error") or payload_error.get("message") or "").strip()
        except ValueError:
            detail = response.text.strip()
        if detail:
            raise ValueError(f"Edge Function '{function_name}' devolvio HTTP {response.status_code}: {detail}")
        raise ValueError(f"Edge Function '{function_name}' devolvio HTTP {response.status_code}.")

    try:
        result = response.json()
    except ValueError:
        raise ValueError(f"Edge Function '{function_name}' no devolvio JSON valido.") from None

    if not isinstance(result, dict):
        raise ValueError(f"Edge Function '{function_name}' devolvio una respuesta inesperada.")

    return result


def _extract_gemini_text(response_data: dict[str, Any]) -> str:
    candidates = response_data.get("candidates")
    if not candidates:
        return ""

    parts = candidates[0].get("content", {}).get("parts", [])
    return "\n".join(part.get("text", "") for part in parts if part.get("text")).strip()


def _call_gemini(prompt: str, temperature: float = 0.6, max_output_tokens: int = 1024) -> str:
    if not settings.gemini_api_key:
        raise ValueError("GEMINI_API_KEY no configurada en el servidor.")

    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": temperature,
            "topP": 0.9,
            "maxOutputTokens": max_output_tokens,
        },
    }

    models_to_try = [settings.gemini_model] + [
        m for m in settings.gemini_fallback_models if m != settings.gemini_model
    ]

    for model_name in models_to_try:
        url = (
            f"https://generativelanguage.googleapis.com/"
            f"{settings.gemini_api_version}/models/{model_name}:generateContent"
        )
        try:
            response = httpx.post(
                url,
                json=payload,
                headers={"x-goog-api-key": settings.gemini_api_key},
                timeout=45.0,
            )
            response.raise_for_status()
            text = _extract_gemini_text(response.json())
            if text:
                return text
        except httpx.HTTPStatusError as ex:
            if ex.response.status_code == 404:
                continue
            raise ValueError(f"Gemini devolvio HTTP {ex.response.status_code}.") from None
        except httpx.HTTPError as ex:
            raise ValueError(f"No fue posible conectar con Gemini: {ex}") from None

    raise ValueError("No fue posible obtener respuesta de Gemini.")


def _save_monetization_event(payload: MonetizationEventRequest) -> tuple[bool, str]:
    event_payload = {
        "event_name": payload.event_name,
        "user_email": payload.user_email,
        "value_usd": payload.value_usd,
        "metadata": payload.metadata,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    effective_key = settings.supabase_service_role_key or settings.supabase_key

    if not settings.supabase_url or not effective_key:
        fallback_file = Path("monetization_events_fallback.jsonl")
        fallback_file.write_text(
            (fallback_file.read_text(encoding="utf-8") if fallback_file.exists() else "")
            + json.dumps(event_payload, ensure_ascii=False)
            + "\n",
            encoding="utf-8",
        )
        return True, "registrado en fallback local (sin Supabase)."

    try:
        supabase = create_client(settings.supabase_url, effective_key)
        supabase.table(settings.monetization_events_table).insert(event_payload).execute()
        return True, ""
    except Exception as ex:
        fallback_file = Path("monetization_events_fallback.jsonl")
        fallback_file.write_text(
            (fallback_file.read_text(encoding="utf-8") if fallback_file.exists() else "")
            + json.dumps(event_payload, ensure_ascii=False)
            + "\n",
            encoding="utf-8",
        )
        return True, f"registrado en fallback local: {ex}"


def _extract_manual_application_fields(url: str) -> tuple[str, str, str]:
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/124.0.0.0 Safari/537.36"
        )
    }

    response = requests.get(url, timeout=7, headers=headers)
    response.raise_for_status()

    soup = BeautifulSoup(response.text, "html.parser")

    title_tag = soup.find("title")
    title = (title_tag.get_text(" ", strip=True) if title_tag else "") or "Empleo sin titulo"

    meta = soup.find("meta", attrs={"name": "description"}) or soup.find(
        "meta", attrs={"property": "og:description"}
    )
    description = (meta.get("content", "") if meta else "").strip() or "Sin descripcion"

    parsed = urlparse(url)
    website = parsed.netloc or ""
    if website.startswith("www."):
        website = website[4:]

    return website, title, description


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/jobs/search", response_model=JobSearchResponse)
def jobs_search(payload: JobSearchRequest) -> JobSearchResponse:
    try:
        jobs = search_google_jobs(
            payload.keywords,
            payload.city,
            payload.region,
            payload.country_name,
            location=payload.location,
            hl=payload.hl,
            gl=payload.gl,
            google_domain=payload.google_domain,
        )
        _inc("jobs_search_ok")
        return JobSearchResponse(jobs=jobs)
    except Exception:
        _inc("jobs_search_error")
        raise


@app.post("/cv/assist", response_model=CvAssistResponse)
def cv_assist(payload: CvAssistRequest) -> CvAssistResponse:
    prompt = (
        "Actua como asesor senior de CV en espanol.\n"
        "Devuelve una propuesta concreta para mejorar el perfil, con 1 resumen profesional,\n"
        "5 bullets de experiencia, 8 habilidades ATS y recomendaciones de enfoque.\n\n"
        f"Nombre: {payload.full_name}\n"
        f"Email: {payload.email}\n"
        f"Vacantes objetivo: {payload.target_roles}\n"
        f"Resumen actual: {payload.summary}\n"
        f"Experiencia: {payload.experience}\n"
        f"Educacion: {payload.education}\n"
        f"Habilidades: {payload.skills}\n"
    )

    try:
        suggestion = _call_gemini(prompt, temperature=0.5, max_output_tokens=1400)
    except ValueError as ex:
        raise HTTPException(status_code=400, detail=str(ex)) from None

    return CvAssistResponse(suggestion=suggestion)


@app.post("/cv/generate-store", response_model=CvGenerateStoreResponse)
def cv_generate_store(payload: CvGenerateStoreRequest) -> CvGenerateStoreResponse:
    if not payload.email.strip():
        raise HTTPException(status_code=400, detail="El email es obligatorio para generar/guardar el CV.")

    if payload.output_format.lower() not in {"docx", "pdf"}:
        raise HTTPException(status_code=400, detail="output_format debe ser docx o pdf.")

    normalized_profile = {
        str(key): str(value)
        for key, value in payload.profile_data.items()
        if str(key).strip()
    }

    full_name = payload.full_name.strip() or payload.email.strip()

    normalized_email = payload.email.strip().lower()
    normalized_output = payload.output_format.lower()

    try:
        # Source of truth: same Edge Function used in production, preserving Gemini output path.
        metadata = _invoke_supabase_edge_function(
            "cv-generate-store",
            {
                "full_name": full_name,
                "email": normalized_email,
                "output_format": normalized_output,
                "profile_data": normalized_profile,
            },
        )
    except ValueError as ex:
        _inc("cv_generate_error")
        raise HTTPException(
            status_code=502,
            detail=(
                "No se pudo generar CV desde la Edge Function cv-generate-store. "
                f"Detalle: {ex}"
            ),
        ) from None
    except Exception as ex:
        _inc("cv_generate_error")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"No se pudo generar/guardar CV: {ex}") from None

    _inc("cv_generate_ok")
    return CvGenerateStoreResponse(
        file_name=str(metadata.get("file_name", "")),
        output_format=str(metadata.get("output_format", payload.output_format.lower())),
        public_url=str(metadata.get("public_url", "")),
        storage_path=str(metadata.get("storage_path", "")),
        source=str(metadata.get("source", "ai_generated")),
    )


@app.post("/interview/reply", response_model=InterviewResponse)
def interview_reply(payload: InterviewRequest) -> InterviewResponse:
    history_lines: list[str] = []
    for message in payload.history[-12:]:
        role = (message.role or "").strip().lower()
        content = (message.content or "").strip()
        if not content:
            continue
        speaker = "Usuario" if role == "user" else "Asistente"
        history_lines.append(f"{speaker}: {content}")
    history_lines.append(f"Usuario: {payload.user_message.strip()}")

    prompt = (
        "Actua como coach experto en entrevistas laborales y responde en espanol.\n"
        "Da respuestas practicas, concretas y aplicables al rol.\n\n"
        f"Vacante: {payload.job_title or 'No disponible'}\n"
        f"Enlace: {payload.application_link or 'No disponible'}\n"
        f"Descripcion de la vacante:\n{payload.job_description or 'No disponible'}\n\n"
        "Historial:\n"
        + "\n".join(history_lines)
        + "\n\nResponde como Asistente:"
    )

    try:
        reply = _call_gemini(prompt, temperature=0.6, max_output_tokens=1024)
    except ValueError as ex:
        _inc("interview_reply_error")
        raise HTTPException(status_code=400, detail=str(ex)) from None

    _inc("interview_reply_ok")
    return InterviewResponse(reply=reply)


@app.post("/applications/add-manual", response_model=ManualApplicationResponse)
def add_manual_application(payload: ManualApplicationRequest) -> ManualApplicationResponse:
    applicant_email = payload.applicant_email.strip().lower()
    application_url = payload.application_url.strip()

    if not applicant_email:
        raise HTTPException(status_code=400, detail="applicant_email es obligatorio.")
    if not application_url.startswith("http://") and not application_url.startswith("https://"):
        raise HTTPException(status_code=400, detail="application_url debe iniciar con http:// o https://")

    effective_key = settings.supabase_service_role_key or settings.supabase_key
    if not settings.supabase_url or not effective_key:
        raise HTTPException(status_code=500, detail="Supabase no esta configurado en el servidor.")

    try:
        website, vacancy, description = _extract_manual_application_fields(application_url)
    except requests.RequestException as ex:
        raise HTTPException(status_code=400, detail=f"No fue posible leer la URL indicada: {ex}") from None
    except Exception as ex:
        raise HTTPException(status_code=400, detail=f"No se pudo procesar la URL: {ex}") from None

    row = {
        "applicant_email": applicant_email,
        "website": website,
        "vaccancy": vacancy,
        "status": "Aplicado",
        "application_link": application_url,
        "Description": description,
    }

    try:
        supabase = create_client(settings.supabase_url, effective_key)
        existing = (
            supabase.table("Applications")
            .select("id")
            .eq("applicant_email", applicant_email)
            .eq("application_link", application_url)
            .execute()
        )

        existing_rows = existing.data or []
        if existing_rows:
            row_id = existing_rows[0].get("id")
            supabase.table("Applications").update(row).eq("id", row_id).execute()
        else:
            supabase.table("Applications").insert(row).execute()
    except Exception as ex:
        _inc("manual_application_error")
        raise HTTPException(status_code=500, detail=f"No se pudo guardar la aplicacion manual: {ex}") from None

    _inc("manual_application_ok")
    return ManualApplicationResponse(
        website=website,
        vacancy=vacancy,
        status="Aplicado",
        application_link=application_url,
        description=description,
    )


@app.post("/monetization/event", response_model=MonetizationEventResponse)
def monetization_event(payload: MonetizationEventRequest) -> MonetizationEventResponse:
    if not payload.event_name.strip():
        raise HTTPException(status_code=400, detail="event_name es obligatorio.")

    logged, detail = _save_monetization_event(payload)
    return MonetizationEventResponse(logged=logged, detail=detail)


# ---------------------------------------------------------------------------
# Metrics endpoint
# ---------------------------------------------------------------------------

@app.get("/metrics")
def metrics() -> dict[str, Any]:
    """Return in-process counters. Resets on restart; use for live dashboards."""
    with _metrics_lock:
        snapshot = dict(_metrics)
    snapshot["reported_at"] = datetime.now(timezone.utc).isoformat()
    return snapshot


@app.get("/metrics/dashboard", response_class=HTMLResponse)
def metrics_dashboard() -> str:
        """Lightweight dashboard for minimum production metrics."""
        return """
<!doctype html>
<html lang=\"es\">
    <head>
        <meta charset=\"utf-8\" />
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
        <title>JobFriends Metrics Dashboard</title>
        <style>
            :root {
                --bg: #f5f7fb;
                --card: #ffffff;
                --text: #0f172a;
                --muted: #64748b;
                --border: #dbe1ec;
                --ok: #16a34a;
                --warn: #d97706;
                --bad: #dc2626;
            }
            body {
                margin: 0;
                font-family: Segoe UI, Arial, sans-serif;
                background: radial-gradient(circle at top left, #eef3ff, var(--bg));
                color: var(--text);
            }
            .wrap {
                max-width: 1080px;
                margin: 24px auto;
                padding: 0 16px;
            }
            .title {
                font-size: 28px;
                font-weight: 700;
                margin-bottom: 4px;
            }
            .sub {
                color: var(--muted);
                margin-bottom: 16px;
            }
            .grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
                gap: 12px;
            }
            .card {
                background: var(--card);
                border: 1px solid var(--border);
                border-radius: 14px;
                padding: 14px;
            }
            .label {
                color: var(--muted);
                font-size: 12px;
            }
            .value {
                font-size: 28px;
                font-weight: 700;
                margin-top: 4px;
            }
            .ok { color: var(--ok); }
            .warn { color: var(--warn); }
            .bad { color: var(--bad); }
            .foot { margin-top: 16px; color: var(--muted); font-size: 12px; }
            button {
                margin-top: 10px;
                border: 1px solid var(--border);
                background: var(--card);
                border-radius: 10px;
                padding: 8px 12px;
                cursor: pointer;
            }
        </style>
    </head>
    <body>
        <div class=\"wrap\">
            <div class=\"title\">JobFriends Metrics Dashboard</div>
            <div class=\"sub\">Monitoreo minimo para login/busqueda/cv/interview y salud API.</div>
            <div class=\"grid\">
                <div class=\"card\"><div class=\"label\">Requests totales</div><div class=\"value\" id=\"requests_total\">-</div></div>
                <div class=\"card\"><div class=\"label\">Errores request</div><div class=\"value bad\" id=\"requests_error\">-</div></div>
                <div class=\"card\"><div class=\"label\">CV OK</div><div class=\"value ok\" id=\"cv_generate_ok\">-</div></div>
                <div class=\"card\"><div class=\"label\">CV Error</div><div class=\"value bad\" id=\"cv_generate_error\">-</div></div>
                <div class=\"card\"><div class=\"label\">CV Upload OK</div><div class=\"value ok\" id=\"cv_upload_ok\">-</div></div>
                <div class=\"card\"><div class=\"label\">CV Upload Error</div><div class=\"value bad\" id=\"cv_upload_error\">-</div></div>
                <div class=\"card\"><div class=\"label\">Interview OK</div><div class=\"value ok\" id=\"interview_reply_ok\">-</div></div>
                <div class=\"card\"><div class=\"label\">Interview Error</div><div class=\"value bad\" id=\"interview_reply_error\">-</div></div>
                <div class=\"card\"><div class=\"label\">Jobs OK</div><div class=\"value ok\" id=\"jobs_search_ok\">-</div></div>
                <div class=\"card\"><div class=\"label\">Jobs Error</div><div class=\"value bad\" id=\"jobs_search_error\">-</div></div>
            </div>
            <button onclick=\"refresh()\">Actualizar</button>
            <div class=\"foot\" id=\"updated_at\">Actualizando...</div>
        </div>
        <script>
            async function refresh() {
                const r = await fetch('/metrics');
                const data = await r.json();
                const keys = [
                    'requests_total','requests_error','cv_generate_ok','cv_generate_error',
                    'cv_upload_ok','cv_upload_error','interview_reply_ok','interview_reply_error',
                    'jobs_search_ok','jobs_search_error'
                ];
                for (const k of keys) {
                    const el = document.getElementById(k);
                    if (el) el.textContent = data[k] ?? 0;
                }
                const ts = data.reported_at || new Date().toISOString();
                document.getElementById('updated_at').textContent = `Actualizado: ${ts}`;
            }
            refresh();
            setInterval(refresh, 15000);
        </script>
    </body>
</html>
        """


# ---------------------------------------------------------------------------
# Readiness / production-credentials validation endpoint
# ---------------------------------------------------------------------------

@app.get("/readiness")
def readiness() -> JSONResponse:
    """
    Validates that all required production credentials are present.
    Returns 200 {ready: true} when all pass, or 503 with a list of missing items.
    """
    missing: list[str] = []

    if not settings.supabase_url:
        missing.append("SUPABASE_URL")
    if not settings.supabase_key:
        missing.append("SUPABASE_KEY")
    if not settings.gemini_api_key:
        missing.append("GEMINI_API_KEY")
    if not settings.serpapi_api_key:
        missing.append("SERPAPI_API_KEY")
    if not settings.admob_android_banner_id:
        missing.append("ADMOB_ANDROID_BANNER_ID")
    if not settings.admob_android_interstitial_id:
        missing.append("ADMOB_ANDROID_INTERSTITIAL_ID")

    if missing:
        return JSONResponse(
            status_code=503,
            content={
                "ready": False,
                "missing_credentials": missing,
                "hint": "Set the listed environment variables before going live.",
            },
        )

    # Quick Supabase connectivity check (select 1 row max)
    try:
        supabase = create_client(settings.supabase_url, settings.supabase_key)
        supabase.table(settings.cv_metadata_table).select("applicant_email").limit(1).execute()
    except Exception as ex:
        return JSONResponse(
            status_code=503,
            content={"ready": False, "supabase_error": str(ex)},
        )

    return JSONResponse(
        status_code=200,
        content={"ready": True, "checked_at": datetime.now(timezone.utc).isoformat()},
    )


# ---------------------------------------------------------------------------
# CV file upload endpoint
# ---------------------------------------------------------------------------

ALLOWED_CV_MIME = {
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
}
ALLOWED_CV_SUFFIXES = {".pdf", ".doc", ".docx"}
MAX_CV_BYTES = 10 * 1024 * 1024  # 10 MB


class CvUploadResponse(BaseModel):
    file_name: str
    storage_path: str
    public_url: str
    source: str
    content_type: str


@app.post("/cv/upload", response_model=CvUploadResponse)
async def cv_upload(
    email: str,
    file: UploadFile = File(...),
) -> CvUploadResponse:
    """
    Upload an existing CV file (PDF / DOC / DOCX) to Supabase Storage.
    Pass `email` as a query parameter and the file as multipart form-data field `file`.
    """
    if not email.strip():
        raise HTTPException(status_code=400, detail="El parametro email es obligatorio.")

    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in ALLOWED_CV_SUFFIXES:
        raise HTTPException(
            status_code=400,
            detail=f"Extension no permitida: '{suffix}'. Usa PDF, DOC o DOCX.",
        )

    content = await file.read()
    if not content:
        _inc("cv_upload_error")
        raise HTTPException(status_code=400, detail="El archivo esta vacio.")

    if len(content) > MAX_CV_BYTES:
        _inc("cv_upload_error")
        raise HTTPException(
            status_code=413,
            detail=f"El archivo supera el limite de {MAX_CV_BYTES // (1024*1024)} MB.",
        )

    try:
        from main import upload_cv_bytes

        metadata = upload_cv_bytes(
            email=email.strip().lower(),
            file_name=file.filename or f"cv{suffix}",
            content=content,
            source="uploaded",
        )
    except Exception as ex:
        _inc("cv_upload_error")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"No se pudo subir el CV: {ex}") from None

    _inc("cv_upload_ok")
    return CvUploadResponse(
        file_name=str(metadata.get("file_name", "")),
        storage_path=str(metadata.get("storage_path", "")),
        public_url=str(metadata.get("public_url", "")),
        source=str(metadata.get("source", "uploaded")),
        content_type=str(metadata.get("content_type", "")),
    )
