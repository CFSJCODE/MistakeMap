-- Tabelas do pipeline de ingestão (Roadmap de Backend, seção 5.1), reconciliadas
-- com o schema já aplicado (Proposta original) em vez de duplicadas:
--
-- - attempts ganha "status" (cache leve do estado atual) e "version" (controle
--   de concorrência otimista), sem alterar exercise_id/solution_text/answer.
-- - error_types ganha severity/ontology_version/concept_id (extensão, em vez
--   de criar error_taxonomy como tabela concorrente).
-- - attempt_assets, processing_runs, ocr_artifacts e audit_log são novas.
--
-- O estado detalhado/repetitivo do pipeline (uma linha por execução, retry,
-- lease) fica em processing_runs — não em attempts — justamente para isolar
-- a escrita de alta frequência longe de attempts.solution_text (texto
-- potencialmente grande, que seria reescrito por inteiro a cada UPDATE de
-- status caso o status vivesse na mesma linha).

-- ---------------------------------------------------------------------------
-- attempts: cache leve de estado + versão otimista
-- ---------------------------------------------------------------------------
alter table public.attempts
  add column if not exists status text not null default 'uploading',
  add column if not exists version integer not null default 1;

alter table public.attempts
  add constraint attempts_status_check
    check (status in (
      'uploading', 'pending', 'queued', 'processing',
      'awaiting_review', 'completed', 'retryable_failed',
      'dead_letter', 'cancelled'
    ));

create index if not exists attempts_status_idx on public.attempts (status);

-- ---------------------------------------------------------------------------
-- error_types: extensão para taxonomia canônica (em vez de error_taxonomy)
-- ---------------------------------------------------------------------------
alter table public.error_types
  add column if not exists severity text,
  add column if not exists ontology_version text,
  add column if not exists concept_id uuid references public.concepts (id) on delete set null;

-- ---------------------------------------------------------------------------
-- attempt_assets: metadados do objeto no Storage/R2 e criptografia
-- ---------------------------------------------------------------------------
create table if not exists public.attempt_assets (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.attempts (id) on delete cascade,
  object_path text not null,
  sha256 text not null,
  nonce text,
  wrapped_dek text,
  key_version text,
  created_at timestamptz not null default now()
);

create index if not exists attempt_assets_attempt_id_idx on public.attempt_assets (attempt_id);

alter table public.attempt_assets enable row level security;

create policy "attempt_assets_owner_select" on public.attempt_assets
  for select
  using (
    exists (
      select 1 from public.attempts a
      where a.id = attempt_assets.attempt_id and a.user_id = auth.uid()
    )
  );

create policy "attempt_assets_owner_insert" on public.attempt_assets
  for insert
  with check (
    exists (
      select 1 from public.attempts a
      where a.id = attempt_assets.attempt_id and a.user_id = auth.uid()
    )
  );

create trigger enforce_rate_limit
  before insert on public.attempt_assets
  for each row execute function public.enforce_rate_limit();

-- ---------------------------------------------------------------------------
-- processing_runs: execuções do pipeline, leases e idempotência
-- Sem acesso de cliente (nenhuma policy) — só a role do worker/service_role.
-- ---------------------------------------------------------------------------
create table if not exists public.processing_runs (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.attempts (id) on delete cascade,
  pipeline_version text not null,
  status text not null default 'queued',
  retry_count integer not null default 0,
  trace_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint processing_runs_unique_attempt_version unique (attempt_id, pipeline_version)
);

create index if not exists processing_runs_attempt_id_idx on public.processing_runs (attempt_id);
create index if not exists processing_runs_status_idx on public.processing_runs (status);

alter table public.processing_runs enable row level security;

-- ---------------------------------------------------------------------------
-- ocr_artifacts: saída OCR normalizada e auditável
-- Sem acesso de cliente — o aluno vê o resultado via error_events, não aqui.
-- ---------------------------------------------------------------------------
create table if not exists public.ocr_artifacts (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.attempts (id) on delete cascade,
  engine text not null,
  version text,
  latex text,
  confidence numeric,
  created_at timestamptz not null default now()
);

create index if not exists ocr_artifacts_attempt_id_idx on public.ocr_artifacts (attempt_id);

alter table public.ocr_artifacts enable row level security;

-- ---------------------------------------------------------------------------
-- audit_log: trilha append-only de mutações sensíveis
-- Sem acesso de cliente — gravado só por componentes confiáveis (worker).
-- ---------------------------------------------------------------------------
create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor text,
  action text not null,
  entity text not null,
  trace_id text,
  payload_hash text,
  created_at timestamptz not null default now()
);

create index if not exists audit_log_entity_created_at_idx on public.audit_log (entity, created_at desc);
create index if not exists audit_log_trace_id_idx on public.audit_log (trace_id);

alter table public.audit_log enable row level security;
