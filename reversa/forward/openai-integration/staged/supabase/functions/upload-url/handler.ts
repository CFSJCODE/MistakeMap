export const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export type UploadInput = {
  extension: string;
  contentType: string;
  sizeBytes: number;
};
export interface UploadServices {
  authenticate(authorization: string): Promise<string | null>;
  reserve(sizeBytes: number): Promise<boolean>;
  sign(path: string, contentType: string, sizeBytes: number): Promise<string>;
  uuid(): string;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

export function validateUpload(body: unknown): UploadInput | null {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const value = body as Record<string, unknown>;
  if (typeof value.filename !== "string" || value.filename.length > 200) {
    return null;
  }
  if (/[\\/\x00-\x1f]/.test(value.filename)) return null;
  const extension = value.filename.split(".").at(-1)?.toLowerCase() ?? "";
  const types: Record<string, string> = {
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    png: "image/png",
    webp: "image/webp",
  };
  if (!types[extension] || value.content_type !== types[extension]) return null;
  if (
    !Number.isSafeInteger(value.size_bytes) ||
    (value.size_bytes as number) <= 0 ||
    (value.size_bytes as number) > MAX_UPLOAD_BYTES
  ) return null;
  return {
    extension,
    contentType: types[extension],
    sizeBytes: value.size_bytes as number,
  };
}

async function boundedJson(req: Request): Promise<unknown> {
  if (!req.body) throw new Error("missing_body");
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      length += part.value.byteLength;
      if (length > 4096) {
        await reader.cancel();
        throw new Error("large_body");
      }
      chunks.push(part.value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}

export function createUploadHandler(services: UploadServices) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (req.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    const authorization = req.headers.get("Authorization") ?? "";
    if (!/^Bearer\s+\S+$/i.test(authorization)) {
      return json({ error: "unauthorized" }, 401);
    }
    try {
      const userId = await services.authenticate(authorization);
      if (!userId) return json({ error: "unauthorized" }, 401);
      let input: UploadInput | null;
      try {
        input = validateUpload(await boundedJson(req));
      } catch {
        return json({
          error: "invalid_upload",
          message: "Envie uma foto JPG, PNG ou WebP de até 8 MB.",
        }, 400);
      }
      if (!input) {
        return json({
          error: "invalid_upload",
          message: "Envie uma foto JPG, PNG ou WebP de até 8 MB.",
        }, 400);
      }
      const objectPath =
        `uploads/${userId}/${services.uuid()}.${input.extension}`;
      // Sign before reserving quota: configuration failures must not consume a reservation.
      const uploadUrl = await services.sign(
        objectPath,
        input.contentType,
        input.sizeBytes,
      );
      if (!await services.reserve(input.sizeBytes)) {
        return json({ error: "storage_quota_exceeded" }, 429);
      }
      return json({
        upload_url: uploadUrl,
        object_path: objectPath,
        content_type: input.contentType,
        expires_in: 900,
      }, 200);
    } catch {
      // Never return SDK errors: they may include URLs, credentials or database details.
      return json({
        error: "upload_unavailable",
        message: "O envio de fotos está temporariamente indisponível.",
      }, 503);
    }
  };
}
