import type postgres from "postgresjs";
import { PublicError } from "./ai_contract.ts";

type Query = postgres.Sql | postgres.TransactionSql;

/** Versão do termo de consentimento do responsável aceita no app. */
export const GUARDIAN_CONSENT_VERSION = "responsavel-2026-11-11";

export const guardianConsentRequired = () =>
  new PublicError(
    403,
    "guardian_consent_required",
    "Para usar a IA, falta o consentimento do seu responsável. " +
      "Gere o código em Perfil e peça para ele confirmar na conta dele.",
  );

/**
 * Menor de 18 anos sem escola só usa a IA depois do aceite do responsável
 * (LGPD, art. 14). A regra fica no banco: guardian_consent_pending().
 */
export async function assertAiAllowed(sql: Query, user: string) {
  const [row] =
    await sql`SELECT public.guardian_consent_pending(${user}::uuid) AS pending`;
  if (row?.pending === true) throw guardianConsentRequired();
}
