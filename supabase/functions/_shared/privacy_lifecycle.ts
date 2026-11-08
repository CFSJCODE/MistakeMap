import type postgres from "postgresjs";
import type { Database } from "./ai_service.ts";
import { PublicError, uuid } from "./ai_contract.ts";

type Job = {
  id: string;
  request_id: string;
  user_id: string;
  lease_token: string;
  attempts: number;
};
export type DeletionServices = {
  listObjects: (user: string, limit: number) => Promise<string[]>;
  deleteObject: (path: string) => Promise<void>;
  deleteAuthUser: (user: string) => Promise<void>;
  now?: () => number;
};
export function ownedObjectPath(user: string, path: unknown): string {
  uuid(user);
  if (
    typeof path !== "string" || !path.startsWith(`uploads/${user}/`) ||
    !/^uploads\/[0-9a-f-]{36}\/[A-Za-z0-9._-]+\.(jpg|jpeg|png|webp)$/i.test(
      path,
    )
  ) {
    throw new PublicError(
      409,
      "invalid_asset_path",
      "Um arquivo precisa de verificação antes de concluir a exclusão.",
    );
  }
  return path;
}
export function deletionError(error: unknown): string {
  const code = error instanceof PublicError ? error.code : "internal_error";
  return [
      "storage_unavailable",
      "auth_unavailable",
      "invalid_asset_path",
      "lease_lost",
    ].includes(code)
    ? code
    : "internal_error";
}
async function renew(sql: Database, job: Job) {
  const rows =
    await sql`UPDATE public.account_deletion_jobs SET lease_until=now()+interval '120 seconds'
    WHERE id=${job.id} AND lease_token=${job.lease_token} AND status='processing' RETURNING id`;
  if (!rows.length) {
    throw new PublicError(
      409,
      "lease_lost",
      "O processamento foi retomado por outro trabalhador.",
    );
  }
}
async function claim(sql: Database) {
  return await sql.begin(async (tx) => {
    // SKIP LOCKED e lease tornam concorrência e retomada explícitas.
    const [job] = await tx<
      Job[]
    >`SELECT id,request_id,user_id,attempts FROM public.account_deletion_jobs
      WHERE status<>'completed' AND not_before<=now() AND next_attempt_at<=now()
      AND (lease_until IS NULL OR lease_until<now())
      ORDER BY next_attempt_at,created_at FOR UPDATE SKIP LOCKED LIMIT 1`;
    if (job) {
      const token = crypto.randomUUID();
      await tx`UPDATE public.account_deletion_jobs SET status='processing',lease_token=${token},lease_until=now()+interval '120 seconds',
        attempts=attempts+1,last_error=NULL WHERE id=${job.id}`;
      return {
        job: { ...job, lease_token: token, attempts: Number(job.attempts) + 1 },
      };
    }
    const [request] =
      await tx`SELECT id,user_id FROM public.platform_privacy_requests
      WHERE kind='account_deletion' AND status='pending'
      ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1`;
    if (!request) return { job: null };
    await tx`INSERT INTO public.account_deletion_jobs(request_id,user_id) VALUES(${request.id},${request.user_id})
      ON CONFLICT(request_id) DO NOTHING`;
    await tx`UPDATE public.platform_privacy_requests SET status='processing' WHERE id=${request.id} AND status='pending'`;
    return { job: null, waiting: true };
  });
}

export async function processAccountDeletion(
  sql: Database,
  services: DeletionServices,
) {
  // Somente tombstones concluídos, nunca pedidos pendentes, são expurgados.
  await sql`DELETE FROM public.account_deletion_jobs WHERE status='completed' AND completed_at<now()-interval '30 days'`;
  const claimed = await claim(sql);
  if (!claimed.job) {
    return { status: claimed.waiting ? "waiting" : "idle", completed: false };
  }
  const job = claimed.job;
  const started = (services.now ?? Date.now)();
  let removed = 0;
  const timeLeft = () => (services.now ?? Date.now)() - started < 50000;
  const pause = async () => {
    await sql`UPDATE public.account_deletion_jobs SET status='retry',lease_token=NULL,lease_until=NULL,
      next_attempt_at=now()+interval '15 seconds',removed_objects=removed_objects+${removed}
      WHERE id=${job.id} AND lease_token=${job.lease_token}`;
    return { status: "continuing", completed: false, removed_objects: removed };
  };
  try {
    // Metadados com dono comprovado primeiro. DELETE R2 é idempotente; só após
    // sucesso removemos o metadado para avançar lotes sem repetir os mesmos 25.
    const assets = await sql<
      postgres.Row[]
    >`SELECT DISTINCT aa.object_path FROM public.attempt_assets aa
      JOIN public.attempts a ON a.id=aa.attempt_id WHERE a.user_id=${job.user_id} ORDER BY aa.object_path LIMIT 25`;
    for (const asset of assets) {
      if (!timeLeft() || removed >= 25) return await pause();
      await renew(sql, job);
      const path = ownedObjectPath(job.user_id, asset.object_path);
      await services.deleteObject(path);
      await sql`DELETE FROM public.attempt_assets aa USING public.attempts a
        WHERE aa.attempt_id=a.id AND a.user_id=${job.user_id} AND aa.object_path=${path}`;
      removed++;
    }
    const [remaining] =
      await sql`SELECT EXISTS(SELECT 1 FROM public.attempt_assets aa JOIN public.attempts a ON a.id=aa.attempt_id
      WHERE a.user_id=${job.user_id}) AS pending`;
    if (remaining.pending || !timeLeft() || removed >= 25) return await pause();
    // Prefixo também inclui uploads abandonados, sem linha em attempt_assets.
    const orphaned = await services.listObjects(job.user_id, 25 - removed);
    for (const rawPath of orphaned) {
      if (!timeLeft() || removed >= 25) return await pause();
      await renew(sql, job);
      await services.deleteObject(ownedObjectPath(job.user_id, rawPath));
      removed++;
    }
    if (!timeLeft() || (await services.listObjects(job.user_id, 1)).length) {
      return await pause();
    }
    await renew(sql, job);
    // knowledge_posts.author_id é uma FK restritiva no schema existente.
    // O pedido apaga também publicações criadas pela conta, sem tocar as alheias.
    await sql`DELETE FROM public.knowledge_posts WHERE author_id=${job.user_id}`;
    await services.deleteAuthUser(job.user_id);
    // Auth excluído mas confirmação perdida: na retomada, 404 é sucesso e o
    // ledger independente permite uma última varredura do prefixo R2.
    if ((await services.listObjects(job.user_id, 1)).length) {
      return await pause();
    }
    const done =
      await sql`UPDATE public.account_deletion_jobs SET status='completed',completed_at=now(),
      lease_token=NULL,lease_until=NULL,last_error=NULL,removed_objects=removed_objects+${removed}
      WHERE id=${job.id} AND lease_token=${job.lease_token} RETURNING id`;
    if (!done.length) {
      throw new PublicError(
        409,
        "lease_lost",
        "O processamento mudou de trabalhador.",
      );
    }
    return { status: "completed", completed: true, removed_objects: removed };
  } catch (error) {
    const code = deletionError(error);
    await sql`UPDATE public.account_deletion_jobs SET status='retry',lease_token=NULL,lease_until=NULL,last_error=${code},
      next_attempt_at=now()+${
      Math.min(3600, 60 * Math.pow(2, Math.min(job.attempts, 6)))
    }*interval '1 second',
      removed_objects=removed_objects+${removed} WHERE id=${job.id} AND lease_token=${job.lease_token}`;
    return {
      status: "retry",
      completed: false,
      error: code,
      removed_objects: removed,
    };
  }
}
