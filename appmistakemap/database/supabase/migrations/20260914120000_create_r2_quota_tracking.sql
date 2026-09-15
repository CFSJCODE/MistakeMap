-- Rastreia o consumo mensal do Cloudflare R2 (plano gratuito).
-- O worker incrementa os contadores a cada operação e verifica o teto de 95%
-- antes de permitir novos uploads ou downloads.
--
-- Limites gratuitos R2:
--   Class A (PUT/POST/LIST/COPY): 1.000.000 ops/mês → teto 95% = 950.000
--   Class B (GET):               10.000.000 ops/mês → teto 95% = 9.500.000
--   Storage:                     10 GB/mês           → teto 95% ≈ 9,5 GB

CREATE TABLE IF NOT EXISTS r2_quota_usage (
    id                      SERIAL PRIMARY KEY,
    period                  CHAR(7)      NOT NULL,  -- 'YYYY-MM'
    class_a_ops             BIGINT       NOT NULL DEFAULT 0,
    class_b_ops             BIGINT       NOT NULL DEFAULT 0,
    storage_bytes_estimate  BIGINT       NOT NULL DEFAULT 0,
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT r2_quota_usage_period_unique UNIQUE (period),
    CONSTRAINT r2_quota_usage_class_a_non_negative CHECK (class_a_ops >= 0),
    CONSTRAINT r2_quota_usage_class_b_non_negative CHECK (class_b_ops >= 0),
    CONSTRAINT r2_quota_usage_storage_non_negative CHECK (storage_bytes_estimate >= 0)
);

-- Índice para lookup por período (o worker sempre consulta o mês corrente).
CREATE INDEX IF NOT EXISTS r2_quota_usage_period_idx ON r2_quota_usage (period);

-- O worker usa uma role de serviço — garante que só ela escreve nesta tabela.
-- Leitura é permitida para administradores acompanharem o consumo.
ALTER TABLE r2_quota_usage ENABLE ROW LEVEL SECURITY;

-- Administradores e service_role podem ler e escrever.
CREATE POLICY "service_role full access on r2_quota_usage"
    ON r2_quota_usage
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Authenticated users podem apenas ler (para dashboards futuros).
CREATE POLICY "authenticated read r2_quota_usage"
    ON r2_quota_usage
    FOR SELECT
    TO authenticated
    USING (true);

COMMENT ON TABLE r2_quota_usage IS
    'Rastreamento mensal de operações e storage no Cloudflare R2. '
    'O worker bloqueia novos uploads quando class_a_ops >= 950.000 ou '
    'class_b_ops >= 9.500.000 ou storage_bytes_estimate >= 10.200.547.328.';
