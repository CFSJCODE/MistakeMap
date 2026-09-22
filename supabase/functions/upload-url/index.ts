import { createClient } from "@supabase/supabase-js"
import { AwsClient } from "aws4fetch"
import postgres from "postgresjs"

// Mesmos tetos do quota.rs (95% dos limites gratuitos do R2).
const CLASS_A_CEILING = 950_000
const STORAGE_CEILING = Math.floor(10 * 1024 * 1024 * 1024 * 0.95) // ~9.5 GB

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

  // Autenticar via JWT do Supabase (token enviado pelo Flutter no header Authorization).
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  )

  const { data: { user }, error: authErr } = await supabase.auth.getUser()
  if (authErr || !user) {
    return json({ error: "não autorizado" }, 401)
  }

  // Ler e validar body.
  let filename: string
  let contentType: string
  try {
    const body = await req.json()
    filename = body.filename
    contentType = body.content_type
    if (!filename || !contentType) throw new Error("campos ausentes")
  } catch {
    return json({ error: "body inválido: filename e content_type são obrigatórios" }, 400)
  }

  const dbUrl = Deno.env.get("SUPABASE_DB_URL")!
  const sql = postgres(dbUrl, {
    prepare: false,
    max: 1,
    idle_timeout: 10,
    connect_timeout: 10,
  })

  try {
    const period = currentPeriod()
    const endpoint = Deno.env.get("CLOUDFLARE_R2_S3_ENDPOINT")!
    const bucket = Deno.env.get("CLOUDFLARE_R2_BUCKET")!

    // Garantir linha do mês atual.
    await sql`
      INSERT INTO r2_quota_usage (period)
      VALUES (${period})
      ON CONFLICT (period) DO NOTHING
    `

    // Verificar cotas Class A e Storage antes de gerar a URL.
    const [quota] = await sql`
      SELECT class_a_ops, storage_bytes_estimate
      FROM r2_quota_usage WHERE period = ${period}
    `

    if (Number(quota.class_a_ops) >= CLASS_A_CEILING) {
      return json(
        { error: `cota R2 Class A atingida: ${quota.class_a_ops}/${CLASS_A_CEILING} ops` },
        429,
      )
    }
    if (Number(quota.storage_bytes_estimate) >= STORAGE_CEILING) {
      return json(
        { error: `cota R2 storage atingida: ${quota.storage_bytes_estimate}/${STORAGE_CEILING} bytes` },
        429,
      )
    }

    // Construir caminho do objeto: uploads/<user_id>/<uuid>.<ext>
    const ext = filename.includes(".") ? filename.split(".").pop() : "bin"
    const objectPath = `uploads/${user.id}/${crypto.randomUUID()}.${ext}`

    // Gerar URL presigned de PUT com validade de 1 hora.
    // X-Amz-Expires deve constar na URL ANTES de assinar (requisito do S3/R2).
    const r2 = new AwsClient({
      accessKeyId: Deno.env.get("CLOUDFLARE_R2_ACCESS_KEY_ID")!,
      secretAccessKey: Deno.env.get("CLOUDFLARE_R2_SECRET_ACCESS_KEY")!,
      region: "auto",
      service: "s3",
    })

    const url = new URL(`${endpoint}/${bucket}/${objectPath}`)
    url.searchParams.set("X-Amz-Expires", "3600")

    const signed = await r2.sign(
      new Request(url.toString(), { method: "PUT" }),
      { aws: { signQuery: true } },
    )

    // Incrementar cota Class A: cada URL presigned representa um PUT futuro.
    await sql`
      UPDATE r2_quota_usage
      SET class_a_ops = class_a_ops + 1, updated_at = NOW()
      WHERE period = ${period}
    `

    console.log(`upload-url gerada user_id=${user.id} path=${objectPath}`)

    return json({ upload_url: signed.url, object_path: objectPath }, 200)
  } catch (err) {
    console.error("erro ao gerar upload-url:", err)
    return json({ error: String(err) }, 500)
  } finally {
    await sql.end({ timeout: 5 })
  }
})
