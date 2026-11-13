// Operações do perfil TI da escola (Edge Function school-admin).
//
// A TI administra contas e acessos sem ver dado pedagógico nem financeiro.
// Toda conferência de papel fica nas funções do banco (migration
// 20261113180000_school_it_admin.sql), chamadas como o usuário autenticado.
// Aqui só fica o que o banco não faz: pedir ao Auth o e-mail de redefinição.
import { PublicError } from "./ai_contract.ts";
import { env, type Environment, required } from "./ai_http.ts";
import type { Database } from "./ai_service.ts";
import { id, type Input } from "./platform_contract.ts";
import {
  boundedInteger,
  importRows,
  memberStatus,
  type SchoolAdminAction,
  schoolRole,
} from "./school_admin_contract.ts";
import { asUser } from "./school_admin_service.ts";

export type SchoolItAction = Extract<SchoolAdminAction, `it_${string}`>;

export const isSchoolItAction = (
  action: SchoolAdminAction,
): action is SchoolItAction => action.startsWith("it_");

/** Pede ao Auth o mesmo e-mail do "Esqueci minha senha". */
export type SendRecovery = (email: string) => Promise<void>;

export function authRecovery(
  get: Environment = env,
  fetcher: typeof fetch = fetch,
): SendRecovery {
  return async (email) => {
    let response: Response;
    try {
      response = await fetcher(
        `${required("SUPABASE_URL", get).replace(/\/$/, "")}/auth/v1/recover`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            apikey: required("SUPABASE_ANON_KEY", get),
          },
          body: JSON.stringify({ email }),
          signal: AbortSignal.timeout(10000),
        },
      );
    } catch {
      throw new PublicError(
        503,
        "auth_unavailable",
        "Não foi possível pedir o e-mail agora. Tente de novo em instantes.",
      );
    }
    await response.body?.cancel();
    if (response.status === 429) {
      throw new PublicError(
        429,
        "limit_reached",
        "O servidor de e-mail pediu uma pausa. Tente de novo em alguns minutos.",
      );
    }
    if (!response.ok) {
      throw new PublicError(
        502,
        "auth_failed",
        "Não foi possível pedir o e-mail agora. Tente de novo em instantes.",
      );
    }
  };
}

const one = async (rows: Promise<Record<string, unknown>[]>) =>
  (await rows)[0] ?? {};

type Tx = Parameters<Parameters<typeof asUser>[2]>[0];
type Step = (tx: Tx, school: string, input: Input) => Promise<unknown>;

/** Lê a coluna `r` (jsonb) da única linha devolvida. */
const read = (
  query: (tx: Tx, school: string, input: Input) => Promise<
    Record<string, unknown>[]
  >,
): Step =>
async (tx, school, input) => (await one(query(tx, school, input))).r;

const optionalBefore = (input: Input) =>
  input.before == null
    ? null
    : boundedInteger(input, "before", 1, Number.MAX_SAFE_INTEGER, 1);

/** Ações que só chamam uma função do banco como o usuário. */
const STEPS: Record<Exclude<SchoolItAction, "it_reset_password">, Step> = {
  it_directory: read((tx, school) =>
    tx`SELECT public.school_it_directory(${school}::uuid) AS r`
  ),
  it_licenses: read((tx, school) =>
    tx`SELECT public.school_it_licenses(${school}::uuid) AS r`
  ),
  it_audit: read((tx, school, input) =>
    tx`SELECT public.school_audit(${school}::uuid, ${
      boundedInteger(input, "limit", 1, 500, 100)
    }, ${optionalBefore(input)}::bigint) AS r`
  ),
  it_member_sessions: read((tx, school, input) =>
    tx`SELECT public.school_member_sessions(${school}::uuid, ${
      id(input, "user_id")
    }::uuid) AS r`
  ),
  it_revoke_sessions: async (tx, school, input) => {
    const row = await one(
      tx`SELECT public.revoke_school_member_sessions(${school}::uuid, ${
        id(input, "user_id")
      }::uuid) AS total`,
    );
    return { revoked: Number(row.total ?? 0) };
  },
  it_set_status: async (tx, school, input) => {
    const status = memberStatus(input);
    await tx`SELECT public.set_school_member_status(${school}::uuid, ${
      id(input, "user_id")
    }::uuid, ${schoolRole(input)}, ${status})`;
    return { status };
  },
  it_remove_member: async (tx, school, input) => {
    await tx`SELECT public.remove_school_member(${school}::uuid, ${
      id(input, "user_id")
    }::uuid, ${schoolRole(input)})`;
    return { removed: true };
  },
  it_import_invites: read((tx, school, input) =>
    tx`SELECT public.create_school_invites_batch(${school}::uuid, ${
      tx.json(importRows(input))
    }::jsonb, ${boundedInteger(input, "valid_days", 1, 90, 30)}) AS r`
  ),
  it_renew_invite: async (tx, _school, input) => {
    const row = await one(
      tx`SELECT * FROM public.renew_school_invite(${
        id(input, "invite_id")
      }::uuid)`,
    );
    return {
      invite_id: row.invite_id,
      code: row.code,
      expires_at: row.expires_at,
    };
  },
};

export async function schoolItOperation(
  sql: Database,
  user: string,
  action: SchoolItAction,
  input: Input,
  sendRecovery: SendRecovery = authRecovery(),
): Promise<unknown> {
  const school = id(input, "school_id");
  if (action === "it_reset_password") {
    const member = id(input, "user_id");
    // Confere a permissão e registra na auditoria; o e-mail não volta ao app.
    const row = await asUser(sql, user, (tx) =>
      one(
        tx`SELECT public.school_member_password_reset(${school}::uuid, ${member}::uuid) AS email`,
      ));
    await sendRecovery(String(row.email));
    return { sent: true };
  }
  return await asUser(sql, user, (tx) => STEPS[action](tx, school, input));
}
