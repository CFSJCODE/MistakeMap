import postgres from "postgresjs";
import { readLimited } from './ai_http.ts';

type Environment = (name: string) => string | undefined;
type Observation = {
  model: string;
  elapsed_ms: number;
  status_code: number;
  input_tokens: number | null;
  output_tokens: number | null;
  total_tokens: number | null;
  error_code: string | null;
};
export interface ProviderRecorder {
  start(model: string): Promise<string>;
  finish(id: string, result: Observation): Promise<void>;
  close(): Promise<void>;
}
export function canonicalModel(model: string): string {
  return /gemini-3\.[68]-flash/.exec(model)?.[0] ?? model;
}
function token(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
}
function recorder(url: string): ProviderRecorder {
  const sql = postgres(url, { prepare: false, max: 1, connect_timeout: 5, idle_timeout: 5 });
  return {
    async start(model) {
      const [row] = await sql`insert into public.ai_api_events(requested_model,model) values(${model},${canonicalModel(model)}) returning id`;
      return row.id as string;
    },
    async finish(id, result) {
      await sql`update public.ai_api_events set finished_at=now(), model=${result.model},
        elapsed_ms=${result.elapsed_ms}, status_code=${result.status_code},
        input_tokens=${result.input_tokens}, output_tokens=${result.output_tokens},
        total_tokens=${result.total_tokens},error_code=${result.error_code} where id=${id}`;
    },
    async close() { await sql.end({ timeout: 2 }).catch(() => {}); },
  };
}

/** Observe provider requests without storing body, key, student identity or error text. */
export function monitoredFetch(
  fetcher: typeof fetch,
  get: Environment,
  makeRecorder: (url: string) => ProviderRecorder = recorder,
): typeof fetch {
  return async (input, init) => {
    const url = String(input);
    const model = decodeURIComponent(/\/models\/([^:]+):generateContent/.exec(url)?.[1] ?? "unknown");
    const dbUrl = get("SUPABASE_DB_URL");
    // Unit tests without a database retain their injected transport.
    if (!dbUrl) return fetcher(input, init);
    const store = makeRecorder(dbUrl);
    let id: string | undefined;
    try { id = await store.start(model); }
    catch { console.warn(JSON.stringify({event:"ai_telemetry_unavailable"})); }
    const started = performance.now();
    try {
      const response = await fetcher(input, init);
      let metadata: Record<string, unknown> = {};
      let actualModel = model;
      try {
        const parsed = JSON.parse(new TextDecoder().decode(await readLimited(response.clone().body, 256000)));
        metadata = parsed?.usageMetadata ?? {};
        if (typeof parsed?.modelVersion === "string") actualModel = parsed.modelVersion;
      } catch { /* Missing metadata remains unknown, never zero tokens. */ }
      if (id) {
        await store.finish(id, {
          model: canonicalModel(actualModel),
          elapsed_ms: Math.round(performance.now()-started), status_code: response.status,
          input_tokens: token(metadata.promptTokenCount), output_tokens: token(metadata.candidatesTokenCount),
          total_tokens: token(metadata.totalTokenCount),
          error_code: response.ok ? null : `http_${response.status}`,
        }).catch(() => console.warn(JSON.stringify({event:"ai_telemetry_unavailable"})));
      }
      return response;
    } catch (error) {
      if (id) await store.finish(id, {model:canonicalModel(model),elapsed_ms:Math.round(performance.now()-started),status_code:0,
        input_tokens:null,output_tokens:null,total_tokens:null,error_code:"network_or_timeout"}).catch(() => {});
      throw error;
    } finally { await store.close(); }
  };
}
