import { AwsClient } from "aws4fetch"
import postgres from "postgresjs"

// Mesmos valores do quota.rs
const BATCH_SIZE = 5
const CLASS_B_CEILING = 9_500_000 // 95% de 10 M ops/mês

// Comparação sem saída antecipada: evita timing attacks no segredo do cron.
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  }
  return diff === 0
}

function currentPeriod(): string {
  const now = new Date()
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 })
  }

  // Autenticação por segredo compartilhado (mesmo esquema do Rust).
  // pg_net não assina com IAM, então usamos X-Cron-Secret.
  const cronSecret = Deno.env.get("WORKER_CRON_SECRET") ?? ""
  const received = req.headers.get("x-cron-secret") ?? ""
  if (!timingSafeEqual(received, cronSecret)) {
    return json({ error: "unauthorized" }, 401)
  }

  const dbUrl = Deno.env.get("SUPABASE_DB_URL")!
  const sql = postgres(dbUrl, {
    prepare: false,   // obrigatório com pgBouncer/Supavisor
    max: 1,
    idle_timeout: 10,
    connect_timeout: 10,
  })

  const r2 = new AwsClient({
    accessKeyId: Deno.env.get("CLOUDFLARE_R2_ACCESS_KEY_ID")!,
    secretAccessKey: Deno.env.get("CLOUDFLARE_R2_SECRET_ACCESS_KEY")!,
    region: "auto",
    service: "s3",
  })

  const endpoint = Deno.env.get("CLOUDFLARE_R2_S3_ENDPOINT")!
  const bucket = Deno.env.get("CLOUDFLARE_R2_BUCKET")!
  const period = currentPeriod()

  try {
    // Garantir que a linha do mês atual existe na tabela de cotas.
    await sql`
      INSERT INTO r2_quota_usage (period)
      VALUES (${period})
      ON CONFLICT (period) DO NOTHING
    `

    // Buscar e travar tentativas pendentes atomicamente.
    // FOR UPDATE SKIP LOCKED garante que invocações concorrentes nunca
    // processam a mesma tentativa (mesmo contrato do worker Rust).
    const attempts = await sql`
      UPDATE public.attempts
      SET status = 'queued', version = version + 1
      WHERE id IN (
        SELECT id FROM public.attempts
        WHERE status = 'pending'
        ORDER BY attempted_at
        LIMIT ${BATCH_SIZE}
        FOR UPDATE SKIP LOCKED
      )
      RETURNING id, version
    `

    const summary = { encontradas: attempts.length, concluidas: 0, falhas: 0 }

    for (const attempt of attempts) {
      const ok = await processAttempt(sql, r2, endpoint, bucket, period, attempt)
      if (ok) summary.concluidas++
      else summary.falhas++
    }

    console.log("lote processado", summary)
    return json(summary, 200)
  } catch (err) {
    console.error("erro no lote:", err)
    return json({ error: String(err) }, 500)
  } finally {
    await sql.end({ timeout: 5 })
  }
})

async function processAttempt(
  sql: ReturnType<typeof postgres>,
  r2: AwsClient,
  endpoint: string,
  bucket: string,
  period: string,
  attempt: { id: string; version: number },
): Promise<boolean> {
  const { id, version } = attempt
  console.log(`attempt_id=${id} iniciando processamento`)

  try {
    // Verificar cota Class B antes de qualquer download.
    const [quota] = await sql`
      SELECT class_b_ops FROM r2_quota_usage WHERE period = ${period}
    `
    if (Number(quota.class_b_ops) >= CLASS_B_CEILING) {
      console.warn(`attempt_id=${id} download bloqueado por cota Class B`)
      await markFailed(sql, id, version)
      return false
    }

    // Buscar assets da tentativa.
    const assets = await sql`
      SELECT id, object_path FROM public.attempt_assets
      WHERE attempt_id = ${id}
      ORDER BY created_at
    `

    if (assets.length === 0) {
      console.warn(`attempt_id=${id} sem assets — marcando como falha`)
      await markFailed(sql, id, version)
      return false
    }

    // Baixar cada asset do R2 e atualizar contadores de cota.
    for (const asset of assets) {
      console.log(`attempt_id=${id} asset_id=${asset.id} baixando ${asset.object_path}`)

      const resp = await r2.fetch(`${endpoint}/${bucket}/${asset.object_path}`)
      if (!resp.ok) {
        console.error(
          `attempt_id=${id} falha ao baixar ${asset.object_path}: HTTP ${resp.status}`,
        )
        await markFailed(sql, id, version)
        return false
      }

      const bytes = await resp.arrayBuffer()
      const byteCount = bytes.byteLength
      console.log(`attempt_id=${id} asset_id=${asset.id} bytes=${byteCount}`)

      await sql`
        UPDATE r2_quota_usage
        SET
          class_b_ops = class_b_ops + 1,
          storage_bytes_estimate = storage_bytes_estimate + ${byteCount},
          updated_at = NOW()
        WHERE period = ${period}
      `

      // TODO (Fase P1): encaminhar bytes para OCR → LLM → gravar error_events.
      void bytes
    }

    await markCompleted(sql, id, version)
    return true
  } catch (err) {
    console.error(`attempt_id=${id} erro inesperado: ${err}`)
    await markFailed(sql, id, version)
    return false
  }
}

async function markCompleted(
  sql: ReturnType<typeof postgres>,
  id: string,
  version: number,
) {
  const result = await sql`
    UPDATE public.attempts
    SET status = 'completed', version = version + 1
    WHERE id = ${id} AND version = ${version}
  `
  if (result.count === 0) {
    console.warn(`attempt_id=${id} versão divergiu ao marcar completed`)
  } else {
    console.log(`attempt_id=${id} marcado como completed`)
  }
}

async function markFailed(
  sql: ReturnType<typeof postgres>,
  id: string,
  version: number,
) {
  const result = await sql`
    UPDATE public.attempts
    SET status = 'retryable_failed', version = version + 1
    WHERE id = ${id} AND version = ${version}
  `
  if (result.count === 0) {
    console.warn(`attempt_id=${id} versão divergiu ao marcar failed`)
  } else {
    console.warn(`attempt_id=${id} marcado como retryable_failed`)
  }
}
