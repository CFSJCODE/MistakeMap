import { AwsClient } from "aws4fetch";
import postgres from "postgresjs";
import { createUploadHandler } from "./handler.ts";

function required(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error("configuration_missing");
  return value;
}

const handler = createUploadHandler({
  uuid: () => crypto.randomUUID(),
  async authenticate(authorization) {
    const response = await fetch(`${required("SUPABASE_URL")}/auth/v1/user`, {
      headers: {
        Authorization: authorization,
        apikey: required("SUPABASE_ANON_KEY"),
      },
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) return null;
    const user = await response.json();
    return typeof user.id === "string" && /^[0-9a-f-]{36}$/i.test(user.id)
      ? user.id
      : null;
  },
  async sign(path, contentType, sizeBytes) {
    const r2 = new AwsClient({
      accessKeyId: required("CLOUDFLARE_R2_ACCESS_KEY_ID"),
      secretAccessKey: required("CLOUDFLARE_R2_SECRET_ACCESS_KEY"),
      region: "auto",
      service: "s3",
    });
    const url = new URL(
      `${required("CLOUDFLARE_R2_S3_ENDPOINT")}/${
        required("CLOUDFLARE_R2_BUCKET")
      }/${path}`,
    );
    url.searchParams.set("X-Amz-Expires", "900");
    const signed = await r2.sign(url.toString(), {
      method: "PUT",
      headers: {
        "Content-Type": contentType,
        "Content-Length": String(sizeBytes),
      },
      aws: { signQuery: true, allHeaders: true },
    });
    return signed.url;
  },
  async reserve(sizeBytes) {
    const sql = postgres(required("SUPABASE_DB_URL"), {
      prepare: false,
      max: 1,
      idle_timeout: 10,
      connect_timeout: 10,
    });
    try {
      const period = new Date().toISOString().slice(0, 7);
      return await sql.begin(async (tx) => {
        // Storage survives calendar months. Serialize reservations across periods.
        await tx`SELECT pg_advisory_xact_lock(1818985001)`;
        await tx`INSERT INTO public.r2_quota_usage(period) VALUES (${period}) ON CONFLICT (period) DO NOTHING`;
        // Conservative ledger, not a billing cap: abandoned uploads stay reserved;
        // preexisting objects require reconciliation against the actual R2 inventory.
        const result = await tx`
          UPDATE public.r2_quota_usage
          SET class_a_ops = class_a_ops + 1,
              storage_bytes_estimate = storage_bytes_estimate + ${sizeBytes}, updated_at = now()
          WHERE period = ${period} AND class_a_ops < 950000
            AND (SELECT coalesce(sum(storage_bytes_estimate), 0) FROM public.r2_quota_usage)
              + ${sizeBytes} <= 10200547328
          RETURNING id`;
        return result.length === 1;
      });
    } finally {
      await sql.end({ timeout: 5 });
    }
  },
});

Deno.serve(handler);
