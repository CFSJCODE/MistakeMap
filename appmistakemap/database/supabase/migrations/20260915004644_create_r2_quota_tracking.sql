-- SQL recuperado do histórico remoto; versão real aplicada em 2026-09-15.
CREATE TABLE IF NOT EXISTS r2_quota_usage (
    id                      SERIAL PRIMARY KEY,
    period                  CHAR(7)      NOT NULL,
    class_a_ops             BIGINT       NOT NULL DEFAULT 0,
    class_b_ops             BIGINT       NOT NULL DEFAULT 0,
    storage_bytes_estimate  BIGINT       NOT NULL DEFAULT 0,
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT r2_quota_usage_period_unique UNIQUE (period),
    CONSTRAINT r2_quota_usage_class_a_non_negative CHECK (class_a_ops >= 0),
    CONSTRAINT r2_quota_usage_class_b_non_negative CHECK (class_b_ops >= 0),
    CONSTRAINT r2_quota_usage_storage_non_negative CHECK (storage_bytes_estimate >= 0)
);

CREATE INDEX IF NOT EXISTS r2_quota_usage_period_idx ON r2_quota_usage (period);

ALTER TABLE r2_quota_usage ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role full access on r2_quota_usage"
    ON r2_quota_usage
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "authenticated read r2_quota_usage"
    ON r2_quota_usage
    FOR SELECT
    TO authenticated
    USING (true);

COMMENT ON TABLE r2_quota_usage IS
    'Rastreamento mensal de operações e storage no Cloudflare R2. '
    'O worker bloqueia novos uploads quando class_a_ops >= 950.000 ou '
    'class_b_ops >= 9.500.000 ou storage_bytes_estimate >= 10.200.547.328.';
