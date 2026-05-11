# Rollback Runbook — JobFriends Mobile

## Scope
This runbook covers rollback procedures for the JobFriends Flutter app and the FastAPI backend (`mobile_api.py` / `main.py`).

---

## 1. Decision Criteria — When to Roll Back

Roll back immediately if ANY of the following are true within 30 min of a release:
- Crash rate > 2 % (Android Vitals)
- Login success rate < 95 %
- `/health` returns non-200 for more than 60 s
- `/readiness` returns `ready: false` in production
- CV generation endpoint error rate > 10 %
- User reports of data loss or stored CVs inaccessible

---

## 2. Flutter App Rollback

### 2.1 Rollback via Play Store (preferred, no code needed)
1. Open [Play Console](https://play.google.com/console) → App → Release → Production.
2. Click **"Create new release"** → upload **previous AAB** (keep all previous AABs in `mobile_app/docs/play-store/releases/`).
3. Set rollout percentage to 100 % and submit for review (usually <1 h for rollbacks).

### 2.2 Emergency: halt rollout
1. Play Console → Production → Edit release → set rollout to **0 %**.
2. This stops new installs from getting the broken version; existing installs are unaffected.

### 2.3 Local verification after rollback
```powershell
Set-Location C:\Users\HP\Documents\my-app\mobile_app
flutter test test\smoke_shell_test.dart
```
Expected: `All tests passed`

---

## 3. Backend Rollback

### 3.1 Git-based rollback
```bash
# Identify last known good commit
git log --oneline -10

# Revert to previous commit (replace <SHA> with actual hash)
git checkout <SHA> -- mobile_api.py main.py backend_config.py
git commit -m "rollback: revert to <SHA>"
```

### 3.2 Restart backend
```powershell
# Kill existing uvicorn if running
Stop-Process -Name "uvicorn" -ErrorAction SilentlyContinue

# Start from venv
C:\Users\HP\Documents\my-app\venv\Scripts\Activate.ps1
uvicorn mobile_api:app --host 0.0.0.0 --port 8000
```

### 3.3 Verify rollback
```powershell
Invoke-RestMethod http://127.0.0.1:8000/health        # { status: "ok" }
Invoke-RestMethod http://127.0.0.1:8000/readiness     # { ready: true } or missing creds list
```

### 3.4 Rollback Supabase schema (if migration was applied)
1. Open [Supabase Dashboard](https://supabase.com) → SQL Editor.
2. Run the inverse of the migration SQL (kept in `docs/migrations/`).
3. Do NOT drop tables — use `ALTER TABLE` to revert column additions.

---

## 4. Environment Variable Rollback

If a broken environment variable was deployed:
1. Update the `.env` file or hosting platform env vars.
2. Restart the backend (step 3.2 above).
3. Confirm `/readiness` returns `{ ready: true }`.

Required production env vars (validated by `/readiness`):
```
SUPABASE_URL
SUPABASE_KEY
GEMINI_API_KEY
SERPAPI_API_KEY
ADMOB_ANDROID_BANNER_ID
ADMOB_ANDROID_INTERSTITIAL_ID
```

---

## 5. Rollback Checklist

| # | Action | Responsible | Done? |
|---|--------|-------------|-------|
| 1 | Halt Play Store rollout (set to 0 %) | Release manager | ☐ |
| 2 | Notify team in Slack/channel | On-call | ☐ |
| 3 | Identify root cause (crash log / Vitals) | Engineer | ☐ |
| 4 | Revert backend code if needed | Engineer | ☐ |
| 5 | Restart backend and verify `/health` | Engineer | ☐ |
| 6 | Verify `/readiness` returns ready | Engineer | ☐ |
| 7 | Run smoke tests locally | QA | ☐ |
| 8 | Upload previous AAB to Play Console | Release manager | ☐ |
| 9 | Verify `/metrics` counters stabilise | Engineer | ☐ |
| 10 | Post post-mortem (within 48 h) | Team | ☐ |

---

## 6. Contacts and Resources

| Resource | URL / Command |
|----------|---------------|
| Play Console | https://play.google.com/console |
| Supabase Dashboard | https://supabase.com/dashboard |
| Backend metrics | `GET /metrics` |
| Backend readiness | `GET /readiness` |
| Parity matrix | `mobile_app/docs/migration/flet_flutter_parity_matrix.md` |
| Preprod gate | `mobile_app/scripts/preprod_gate.ps1` |
