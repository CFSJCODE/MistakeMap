import { PIPELINE_VERSION, PublicError } from "../_shared/ai_contract.ts";
import { cronAuthorized, env, failure, json } from "../_shared/ai_http.ts";
import { analyzeAttempt, dailyLimit, database } from "../_shared/ai_service.ts";
import { aiConfig } from "../_shared/gemini.ts";
export async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return json(req, { error: "method_not_allowed" }, 405);
  }
  if (
    !cronAuthorized(req.headers.get("x-cron-secret"), env("WORKER_CRON_SECRET"))
  ) return json(req, { error: "unauthorized" }, 401);
  let sql: ReturnType<typeof database> | undefined;
  try {
    aiConfig();
    sql = database();
    // Inspect a small candidate window, but make at most one model call. Skip
    // exhausted owners so a single user's quota cannot starve the entire queue.
    const rows = await sql`SELECT a.id,a.user_id FROM public.attempts a
      LEFT JOIN public.processing_runs r ON r.attempt_id=a.id AND r.pipeline_version=${PIPELINE_VERSION}
      WHERE (a.status IN ('pending','retryable_failed') OR (a.status IN ('queued','processing') AND (r.lease_until IS NULL OR r.lease_until<now())))
      AND (r.retry_count IS NULL OR r.retry_count<3 OR (a.status IN ('queued','processing') AND r.lease_until<now()))
      AND (r.updated_at IS NULL OR r.status='completed' OR r.updated_at<now()-interval '1 minute')
      AND (r.retry_count>=3 OR NOT EXISTS(SELECT 1 FROM public.ai_daily_usage u WHERE u.user_id=a.user_id AND u.kind='analysis' AND u.usage_day=CURRENT_DATE AND u.requests>=${
      dailyLimit("analysis")
    }))
      ORDER BY a.attempted_at LIMIT 20`;
    const summary = {
      encontradas: rows.length,
      concluidas: 0,
      aguardando_revisao: 0,
      em_processamento: 0,
      falhas: 0,
    };
    for (const row of rows) {
      try {
        const result = await analyzeAttempt(sql, row.id, row.user_id);
        if (result.status === "completed") summary.concluidas++;
        else if (result.status === "awaiting_review") {
          summary.aguardando_revisao++;
        } else {
          summary.em_processamento++;
          continue;
        }
        break;
      } catch (error) {
        summary.falhas++;
        console.warn(
          JSON.stringify({
            event: "batch_attempt_failed",
            code: error instanceof PublicError ? error.code : "internal_error",
          }),
        );
        if (error instanceof PublicError && [400, 404].includes(error.status)) {
          await sql`UPDATE public.attempts SET status='dead_letter',version=version+1 WHERE id=${row.id} AND status IN ('pending','retryable_failed')`;
          continue;
        }
        if (
          error instanceof PublicError &&
          ["daily_limit", "attempt_changed", "attempt_not_ready", "retry_limit"]
            .includes(error.code)
        ) continue;
        break;
      }
    }
    return json(req, summary);
  } catch (error) {
    return failure(req, error);
  } finally {
    await sql?.end({ timeout: 5 }).catch(() => {});
  }
}
