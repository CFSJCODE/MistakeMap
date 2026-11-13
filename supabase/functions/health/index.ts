// Edge Function: health
//
// Verifica se o banco de dados e o bucket R2 estão acessíveis.
// Sem autenticação — endpoint público de monitoramento.
//
// Equivalente ao GET /health do worker Rust (routes/health.rs).
//
// Usado pelo job pg_cron 'worker-health-monitor' a cada 5 minutos
// para detectar degradação de serviço antes dos usuários perceberem.

import { AwsClient } from "aws4fetch"
import postgres from "postgresjs"
import { cors } from "../_shared/ai_http.ts"

// CORS das mesmas origens das outras funções: a Central da Equipe na web
// chama a health pelo navegador.
function headers(req: Request): HeadersInit {
  return { ...cors(req), "Access-Control-Allow-Methods": "GET, OPTIONS" }
}

function json(req: Request, body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...headers(req),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  })
}

// Pinga o PostgreSQL com SELECT 1.
async function pingDb(dbUrl: string): Promise<boolean> {
  const sql = postgres(dbUrl, {
    prepare: false,
    max: 1,
    idle_timeout: 5,
    connect_timeout: 5,
  })
  try {
    await sql`SELECT 1`
    return true
  } catch {
    return false
  } finally {
    await sql.end({ timeout: 3 }).catch(() => {})
  }
}

// Pinga o bucket R2 com HEAD — verifica credenciais e existência do bucket.
// Equivalente ao storage::ping do Rust (head_bucket via aws-sdk-s3).
async function pingR2(
  endpoint: string,
  bucket: string,
  accessKeyId: string,
  secretAccessKey: string,
): Promise<boolean> {
  const r2 = new AwsClient({
    accessKeyId,
    secretAccessKey,
    region: "auto",
    service: "s3",
  })

  try {
    // HEAD /{bucket}/ — retorna 200 se bucket existe e credenciais são válidas.
    const resp = await r2.fetch(`${endpoint}/${bucket}/`, {
      method: "HEAD",
    })
    // 200 = ok; 403 = sem permissão de listagem mas bucket existe.
    // Qualquer outro status (404, 5xx) indica problema.
    return resp.status === 200 || resp.status === 403
  } catch {
    return false
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: headers(req) })
  }
  const dbUrl = Deno.env.get("SUPABASE_DB_URL") ?? ""
  const endpoint = Deno.env.get("CLOUDFLARE_R2_S3_ENDPOINT") ?? ""
  const bucket = Deno.env.get("CLOUDFLARE_R2_BUCKET") ?? ""
  const accessKeyId = Deno.env.get("CLOUDFLARE_R2_ACCESS_KEY_ID") ?? ""
  const secretAccessKey = Deno.env.get("CLOUDFLARE_R2_SECRET_ACCESS_KEY") ?? ""

  // Executa as verificações em paralelo para reduzir latência total.
  const [dbOk, r2Ok] = await Promise.all([
    pingDb(dbUrl),
    pingR2(endpoint, bucket, accessKeyId, secretAccessKey),
  ])

  const status = dbOk && r2Ok ? 200 : 503

  console.log(`health: db=${dbOk ? "ok" : "error"} r2=${r2Ok ? "ok" : "error"}`)

  return json(
    req,
    {
      database: dbOk ? "ok" : "error",
      r2: r2Ok ? "ok" : "error",
      bucket,
    },
    status,
  )
})
