-- ============================================================
-- search-jobs: caché de resultados + historial de vistos
-- ============================================================

-- ------------------------------------------------------------
-- 1. Caché de búsquedas
--    Clave: hash(normalized_query + "|" + location_canonical)
--    TTL:   expires_at (6 h por defecto)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_search_cache (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  cache_key    text        NOT NULL,
  jobs_json    jsonb       NOT NULL DEFAULT '[]',
  provider_used text       NOT NULL DEFAULT '',
  created_at   timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL DEFAULT (now() + INTERVAL '6 hours'),
  CONSTRAINT job_search_cache_key_unique UNIQUE (cache_key)
);

CREATE INDEX IF NOT EXISTS idx_job_search_cache_key
  ON public.job_search_cache (cache_key);

CREATE INDEX IF NOT EXISTS idx_job_search_cache_expires
  ON public.job_search_cache (expires_at);

-- Solo service_role puede leer/escribir; los usuarios nunca acceden directamente.
ALTER TABLE public.job_search_cache ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role_only_cache"
  ON public.job_search_cache
  USING (false);               -- ningún usuario anónimo/autenticado puede acceder

-- ------------------------------------------------------------
  job_fingerprint text        NOT NULL,
  first_seen_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_seen_jobs_unique UNIQUE (user_email, job_fingerprint)
);

CREATE INDEX IF NOT EXISTS idx_user_seen_jobs_lookup
  ON public.user_seen_jobs (user_email, job_fingerprint);

ALTER TABLE public.user_seen_jobs ENABLE ROW LEVEL SECURITY;

-- Cada usuario autenticado solo puede leer sus propias filas.
CREATE POLICY "user_read_own_seen_jobs"
  ON public.user_seen_jobs
  FOR SELECT
  USING (auth.email() = user_email);

-- Las inserciones las hace únicamente la Edge Function (service_role).
CREATE POLICY "service_role_insert_seen_jobs"
  ON public.user_seen_jobs
  FOR INSERT
  WITH CHECK (false);          -- anon/authenticated nunca insertan directamente

-- ------------------------------------------------------------
-- 3. Limpieza automática de entradas de caché expiradas
--    (ejecutar vía pg_cron o manualmente)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_expired_job_cache()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
  DELETE FROM public.job_search_cache WHERE expires_at < now();
$$;
