import { AwsClient } from "aws4fetch";
import { PublicError } from "./ai_contract.ts";
import { env, type Environment, readLimited, required } from "./ai_http.ts";
import { type DeletionServices, ownedObjectPath } from "./privacy_lifecycle.ts";

export function listedObjectPaths(xml: string, user: string): string[] {
  if (
    !/<ListBucketResult[\s>]/.test(xml) ||
    !/<IsTruncated>(true|false)<\/IsTruncated>/.test(xml)
  ) {
    throw new PublicError(
      502,
      "storage_unavailable",
      "Não foi possível verificar os arquivos.",
    );
  }
  const paths = [...xml.matchAll(/<Key>([^<]*)<\/Key>/g)].map((m) =>
    ownedObjectPath(user, m[1])
  );
  if (!paths.length && /<IsTruncated>true<\/IsTruncated>/.test(xml)) {
    throw new PublicError(
      502,
      "storage_unavailable",
      "A listagem de arquivos está incompleta.",
    );
  }
  return paths;
}
export function deletionServices(
  get: Environment = env,
  fetcher: typeof fetch = fetch,
): DeletionServices {
  const endpoint = required("CLOUDFLARE_R2_S3_ENDPOINT", get).replace(
    /\/$/,
    "",
  );
  const bucket = required("CLOUDFLARE_R2_BUCKET", get);
  const service = required("SUPABASE_SERVICE_ROLE_KEY", get);
  const authUrl = required("SUPABASE_URL", get).replace(/\/$/, "");
  const r2 = new AwsClient({
    retries: 0,
    accessKeyId: required("CLOUDFLARE_R2_ACCESS_KEY_ID", get),
    secretAccessKey: required("CLOUDFLARE_R2_SECRET_ACCESS_KEY", get),
    region: "auto",
    service: "s3",
  });
  const storageError = () =>
    new PublicError(
      502,
      "storage_unavailable",
      "Não foi possível remover ou verificar os arquivos.",
    );
  return {
    async listObjects(user, limit) {
      const url = new URL(`${endpoint}/${bucket}`);
      url.searchParams.set("list-type", "2");
      url.searchParams.set("prefix", `uploads/${user}/`);
      url.searchParams.set(
        "max-keys",
        String(Math.max(1, Math.min(25, limit))),
      );
      let response: Response;
      try {
        response = await r2.fetch(url, {
          method: "GET",
          signal: AbortSignal.timeout(15000),
        });
      } catch {
        throw storageError();
      }
      if (!response.ok) {
        await response.body?.cancel();
        throw storageError();
      }
      const xml = new TextDecoder().decode(
        await readLimited(response.body, 100000),
      );
      return listedObjectPaths(xml, user);
    },
    async deleteObject(path) {
      let response: Response;
      try {
        response = await r2.fetch(`${endpoint}/${bucket}/${path}`, {
          method: "DELETE",
          signal: AbortSignal.timeout(15000),
        });
      } catch {
        throw storageError();
      }
      const ok = response.ok || response.status === 404;
      await response.body?.cancel();
      if (!ok) throw storageError();
    },
    async deleteAuthUser(user) {
      let response: Response;
      try {
        response = await fetcher(`${authUrl}/auth/v1/admin/users/${user}`, {
          method: "DELETE",
          headers: { Authorization: `Bearer ${service}`, apikey: service },
          signal: AbortSignal.timeout(10000),
        });
      } catch {
        throw new PublicError(
          502,
          "auth_unavailable",
          "Não foi possível concluir a exclusão da conta.",
        );
      }
      const ok = response.ok || response.status === 404;
      await response.body?.cancel();
      if (!ok) {
        throw new PublicError(
          502,
          "auth_unavailable",
          "Não foi possível concluir a exclusão da conta.",
        );
      }
    },
  };
}
