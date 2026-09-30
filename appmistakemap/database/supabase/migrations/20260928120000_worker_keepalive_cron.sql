-- Migration: worker-health-monitor
-- Objetivo: verificar a saúde das Edge Functions a cada 5 minutos via pg_cron.
--
-- Contexto: o backend foi migrado do worker Rust (Fly.io) para Supabase Edge
-- Functions, que são serverless — não precisam de "keepalive" para se manter
-- ativas. Este job serve como monitor de saúde: detecta degradação antes dos
-- usuários perceberem e registra o histórico em net._http_response.
--
-- Pré-requisitos:
--   • pg_cron habilitado  (SELECT * FROM cron.job LIMIT 1 deve funcionar)
--   • pg_net habilitado   (extensão net disponível no Supabase Cloud)
--
-- Como verificar o estado atual:
--   SELECT * FROM cron.job WHERE jobname = 'worker-health-monitor';
--
-- Como ver o histórico de respostas:
--   SELECT created, status_code, error_msg
--   FROM net._http_response
--   ORDER BY created DESC
--   LIMIT 20;

-- Remove job anterior caso exista (idempotente)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'worker-health-monitor') THEN
    PERFORM cron.unschedule('worker-health-monitor');
  END IF;
  -- Remove alias antigo criado por versão anterior desta migration
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'worker-keepalive') THEN
    PERFORM cron.unschedule('worker-keepalive');
  END IF;
END;
$$;

-- Agenda monitor de saúde a cada 5 minutos.
-- URL da Edge Function health do projeto MistakeMap.
-- A função é pública (sem autenticação) — apenas verifica se DB e R2 respondem.
SELECT cron.schedule(
    'worker-health-monitor',
    '*/5 * * * *',
    $$
    SELECT net.http_get(
        url     := 'https://bmdjicshcjpknuaywaph.supabase.co/functions/v1/health',
        headers := jsonb_build_object(
            'User-Agent', 'supabase-health-monitor/1.0'
        ),
        timeout_milliseconds := 10000
    ) AS request_id;
    $$
);
