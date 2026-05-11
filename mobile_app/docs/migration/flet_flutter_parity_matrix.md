# Flet to Flutter parity matrix

Purpose
- Track migration progress from Python Flet app to Flutter app.
- Confirm full functional parity while preserving current Flutter UX.
- Provide auditable go/no-go evidence for production release.

Status legend
- Done: implemented and verified in Flutter.
- Partial: implemented with gaps or missing validation.
- Missing: not implemented in Flutter.
- Blocked: dependency not ready (API, infra, keys).

## Domain checklist

### 1) Authentication
- [ ] Login with email/password (status: Done)
- [ ] Register user with required profile fields (status: Done)
- [ ] Logout and session reset (status: Done)
- [ ] Remember me credential persistence (status: Done)
- [ ] Auto login from saved credentials (status: Done)
- Evidence files:
  - ../../lib/features/auth/login_screen.dart
  - ../../../main.py

### 2) Job search
- [ ] Search jobs by keywords and city (status: Done)
- [ ] Country handling and defaults (status: Partial)
- [ ] Enriched description flow (status: Partial)
- [ ] Mobile and desktop-like rendering parity rules (status: Partial)
- [ ] Open apply link from result (status: Done)
- Evidence files:
  - ../../lib/features/jobs/jobs_screen.dart
  - ../../../main.py
  - ../../../services/job_search_service.py

### 3) Applications
- [ ] Save application from search result (status: Done)
- [ ] Avoid duplicate application entries (status: Done)
- [ ] Update application status (status: Done)
- [ ] Delete application (status: Done)
- [ ] Manual add by URL scrape (status: Done)
- [ ] Status distribution dashboard/chips (status: Partial)
- Evidence files:
  - ../../lib/features/applications/applications_screen.dart
  - ../../../main.py

### 4) CV prep and generation
- [ ] CV assist suggestions (status: Done)
- [ ] CV generate and store DOCX/PDF (status: Done)
- [ ] Format selection DOCX/PDF (status: Done)
- [ ] CV upload existing file path flow (status: Missing)
- [ ] Visual preferences (palette, font size, columns, photo) (status: Done)
- [ ] Conversational Gemini CV builder full flow (status: Partial)
- Evidence files:
  - ../../lib/features/cv/cv_prep_screen.dart
  - ../../../mobile_api.py
  - ../../../main.py

### 5) Interview prep
- [ ] Select application context (status: Done)
- [ ] Multi turn chat with API (status: Done)
- [ ] Per-application chat memory (status: Partial)
- [ ] Startup context and fallback behavior parity (status: Partial)
- Evidence files:
  - ../../lib/features/interview/interview_prep_screen.dart
  - ../../../main.py

### 6) Theme and responsiveness
- [ ] App theme toggle light/dark (status: Missing)
- [ ] Responsive breakpoints behavior (status: Partial)
- [ ] Adaptive layout parity for key screens (status: Partial)
- Evidence files:
  - ../../lib/theme/app_theme.dart
  - ../../../main.py

### 7) Integrations and data
- [ ] Supabase tables and fields parity (status: Partial)
- [ ] Supabase storage bucket cv uploads (status: Partial)
- [ ] Gemini model fallback behavior (status: Partial)
- [ ] Monetization event tracking (status: Done)
- Evidence files:
  - ../../lib/data/jobfriends_repository.dart
  - ../../../mobile_api.py
  - ../../../backend_config.py

### 8) Production readiness
- [ ] Flutter analyze passes (status: Done)
- [ ] Unit tests pass (status: Done)
- [ ] Integration smoke test pass (status: Done (fallback))
- [ ] API health and endpoint contract checks pass (status: Done)
- [ ] Android release build APK/AAB pass (status: Pending)
- [ ] Play Store checklist complete (status: Pending)
- Evidence files:
  - ../../scripts/qa_android.ps1
  - ../../scripts/build_android_release.ps1
  - ../play-store/checklist_publicacion.md

## Gap backlog template

| ID | Domain | Gap | Severity | Owner | ETA | Status | Notes |
|---|---|---|---|---|---|---|---|
| G-001 | Auth | Remember me + auto login parity | P1 | TBD | TBD | Done | Implementado en login y shell; falta evidencia QA E2E. |
| G-002 | CV | Visual preference parity for CV generation | P1 | TBD | TBD | Done | Implementado en CV Prep: paleta, tamano, columnas, foto base64 y claves backend. |
| G-003 | Jobs | Manual add by URL parity | P1 | TBD | TBD | Done | Implementado con endpoint /applications/add-manual y dialogo en Applications. |

## Acceptance gate
- No open P0/P1 gaps.
- All production readiness checks marked complete with attached evidence.
- Flutter behavior accepted against this matrix by product and QA.
