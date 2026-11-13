// Operações da Edge Function school-admin: cadastro por perfil, convites,
// escola, equipe e consentimento do responsável.
//
// Toda operação em nome do usuário roda com `role authenticated` e o `sub`
// do JWT na transação, como uma chamada do app pelo PostgREST: as políticas
// RLS e as funções security definer da migration valem aqui do mesmo jeito,
// e o trigger school_members_guard confere o convite em qualquer caminho.
import type postgres from "postgresjs";
import { PublicError } from "./ai_contract.ts";
import type { Database } from "./ai_service.ts";
import { GUARDIAN_CONSENT_VERSION } from "./guardian_consent.ts";
import { id, type Input, text } from "./platform_contract.ts";
import { platformOperation } from "./platform_service.ts";
import {
  birthDate,
  boundedInteger,
  classOrInviteCode,
  cnpj,
  competition,
  databaseError,
  expectedRoles,
  INVITE_ROLES_BY_PERSONA,
  optionalEmail,
  persona,
  type SchoolAdminAction,
  schoolAdminAction,
  type SchoolRole,
  schoolRole,
  shortCode,
  teamRole,
} from "./school_admin_contract.ts";
import { isSchoolItAction, schoolItOperation } from "./school_it_service.ts";

type Tx = postgres.TransactionSql;

/** Executa `run` como o usuário autenticado (RLS e auth.uid() valem). */
export async function asUser<T>(
  sql: Database,
  user: string,
  run: (tx: Tx) => Promise<T>,
): Promise<T> {
  try {
    return await sql.begin(async (tx) => {
      const claims = JSON.stringify({ sub: user, role: "authenticated" });
      await tx`SELECT set_config('request.jwt.claims', ${claims}, true),
        set_config('request.jwt.claim.sub', ${user}, true)`;
      await tx`SET LOCAL ROLE authenticated`;
      return await run(tx);
    }) as T;
  } catch (error) {
    throw databaseError(error);
  }
}

const wrongRole = (role: string) =>
  new PublicError(
    409,
    "invite_role_mismatch",
    `Este convite é para ${
      ROLE_LABELS[role] ?? role
    }. Volte e escolha esse perfil, ou peça outro convite.`,
  );
const ROLE_LABELS: Record<string, string> = {
  owner: "dono da escola",
  coordinator: "coordenação",
  it_admin: "TI da escola",
  finance: "Financeiro/Compras",
  teacher: "professor",
  student: "estudante",
  guardian: "responsável",
};

/** Papel do convite, lido com privilégio só para conferir antes de resgatar. */
async function inviteRole(sql: Database, code: string): Promise<string> {
  const [row] = await sql`SELECT role FROM public.school_invites
    WHERE code_hash=public.code_digest(${code})`;
  if (!row) {
    throw new PublicError(
      404,
      "code_invalid",
      "Convite inválido, vencido, já usado ou de outro e-mail.",
    );
  }
  return String(row.role);
}

async function redeem(
  sql: Database,
  user: string,
  code: string,
  expected: readonly SchoolRole[] | null,
) {
  if (expected) {
    const role = await inviteRole(sql, code);
    if (!expected.includes(role as SchoolRole)) throw wrongRole(role);
  }
  const [row] = await asUser(
    sql,
    user,
    (tx) => tx`SELECT * FROM public.redeem_school_invite(${code})`,
  );
  return { school_id: row.school_id, role: row.role };
}

async function context(sql: Database, user: string) {
  return await asUser(sql, user, async (tx) => {
    const [signup] = await tx`SELECT persona, birth_date::text AS birth_date
      FROM public.user_signups WHERE user_id=${user}`;
    const roles = await tx`SELECT m.school_id, s.name AS school_name, s.plan,
        s.status AS school_status, m.role, m.status
      FROM public.school_members m
      LEFT JOIN public.schools s ON s.id = m.school_id
      WHERE m.user_id=${user} ORDER BY m.joined_at`;
    const teams = await tx`SELECT t.id, t.name, t.competition, t.school_id,
        tm.team_role
      FROM public.school_team_members tm
      JOIN public.school_teams t ON t.id = tm.team_id
      WHERE tm.user_id=${user} AND t.archived_at IS NULL ORDER BY tm.joined_at`;
    const [pending] =
      await tx`SELECT public.my_guardian_consent_pending() AS pending`;
    const children = await tx`SELECT * FROM public.my_guardian_children()`;
    return {
      signup: signup ?? null,
      roles,
      teams,
      guardian_consent_pending: pending?.pending === true,
      children,
      consent_version: GUARDIAN_CONSENT_VERSION,
    };
  });
}

async function schoolOverview(sql: Database, user: string, school: string) {
  return await asUser(sql, user, async (tx) => {
    const [row] =
      await tx`SELECT id, name, plan, status, billing_cycle FROM public.schools
      WHERE id=${school}`;
    if (!row) {
      throw new PublicError(
        404,
        "not_found",
        "Escola não encontrada na sua conta.",
      );
    }
    const [mine] = await tx`SELECT array_agg(role) AS roles
      FROM public.school_members WHERE school_id=${school} AND user_id=${user}
        AND status='active'`;
    // Contagem por papel: a RLS só mostra todos para dono, coordenação e TI.
    const members = await tx`SELECT role, count(*)::int AS total
      FROM public.school_members WHERE school_id=${school} AND status='active'
      GROUP BY role`;
    const invites = await tx`SELECT id, role, email, max_uses, uses,
        created_at, expires_at, revoked_at
      FROM public.school_invites WHERE school_id=${school}
        AND revoked_at IS NULL AND expires_at > now() AND uses < max_uses
      ORDER BY created_at DESC LIMIT 50`;
    const teams = await tx`SELECT id, name, competition, created_at
      FROM public.school_teams WHERE school_id=${school} AND archived_at IS NULL
      ORDER BY created_at DESC LIMIT 50`;
    return {
      school: row,
      my_roles: mine?.roles ?? [],
      members,
      invites,
      teams,
    };
  });
}

export async function schoolAdminOperation(
  sql: Database,
  user: string,
  input: Input,
): Promise<unknown> {
  const action: SchoolAdminAction = schoolAdminAction(input.action);
  if (isSchoolItAction(action)) {
    return await schoolItOperation(sql, user, action, input);
  }
  switch (action) {
    case "context":
      return await context(sql, user);
    case "save_profile": {
      const chosen = persona(input);
      const born = birthDate(input);
      if ((chosen === "student" || chosen === "student_team") && !born) {
        throw new PublicError(
          400,
          "birth_date_required",
          "Informe a data de nascimento.",
        );
      }
      await asUser(
        sql,
        user,
        (tx) => tx`SELECT public.save_signup_profile(${chosen}, ${born}::date)`,
      );
      return await context(sql, user);
    }
    case "redeem_invite": {
      const expected = expectedRoles(input) ??
        (input.persona == null
          ? null
          : INVITE_ROLES_BY_PERSONA[persona(input)]);
      return await redeem(sql, user, shortCode(input), expected);
    }
    case "join_class": {
      const code = classOrInviteCode(input);
      if (code.kind === "class") {
        return await platformOperation(sql, user, {
          action: "join_class",
          code: code.code,
        });
      }
      return await redeem(sql, user, code.code, ["student"]);
    }
    case "start_free_teacher": {
      // Plano Grátis: o professor cria o próprio espaço (escola Grátis) e se
      // convida como professor. Passa pelos mesmos convites e triggers.
      const name = text(input, "name", 160);
      return await asUser(sql, user, async (tx) => {
        const [school] = await tx`SELECT public.create_school(${name}) AS id`;
        const [invite] = await tx`SELECT code FROM public.create_school_invite(
          ${school.id}::uuid, 'teacher', null, 1, 1)`;
        await tx`SELECT * FROM public.redeem_school_invite(${invite.code})`;
        return { school_id: school.id, role: "teacher" };
      });
    }
    case "create_school": {
      const name = text(input, "name", 160);
      const document = cnpj(input);
      return await asUser(sql, user, async (tx) => {
        const [school] =
          await tx`SELECT public.create_school(${name}, ${document}) AS id`;
        return { school_id: school.id, role: "owner" };
      });
    }
    case "school_overview":
      return await schoolOverview(sql, user, id(input, "school_id"));
    case "create_invite": {
      const school = id(input, "school_id");
      const role = schoolRole(input);
      const email = optionalEmail(input);
      const management = ["owner", "coordinator", "it_admin", "finance"]
        .includes(role);
      const uses = management
        ? 1
        : boundedInteger(input, "max_uses", 1, 1000, 1);
      const days = boundedInteger(input, "valid_days", 1, 90, 7);
      const [row] = await asUser(
        sql,
        user,
        (tx) =>
          tx`SELECT * FROM public.create_school_invite(${school}::uuid, ${role},
            ${email}, ${uses}, ${days})`,
      );
      return {
        invite_id: row.invite_id,
        code: row.code,
        expires_at: row.expires_at,
        role,
      };
    }
    case "revoke_invite": {
      const invite = id(input, "invite_id");
      await asUser(
        sql,
        user,
        (tx) => tx`SELECT public.revoke_school_invite(${invite}::uuid)`,
      );
      return { revoked: true };
    }
    case "request_guardian_consent": {
      const [row] = await asUser(
        sql,
        user,
        (tx) => tx`SELECT * FROM public.request_guardian_consent()`,
      );
      return { code: row.code, expires_at: row.expires_at };
    }
    case "guardian_code": {
      // O responsável digita um código só: do filho (consentimento) ou da
      // escola (convite de responsável).
      const code = shortCode(input);
      const [consent] = await sql`SELECT 1 FROM public.guardian_consent_requests
        WHERE code_hash=public.code_digest(${code})`;
      if (consent) {
        if (input.accepted !== true) {
          throw new PublicError(
            400,
            "consent_required",
            "Leia e aceite o termo de consentimento para continuar.",
          );
        }
        const [row] = await asUser(
          sql,
          user,
          (tx) =>
            tx`SELECT public.grant_guardian_consent(${code}, ${GUARDIAN_CONSENT_VERSION}) AS student_id`,
        );
        return {
          kind: "consent",
          student_id: row.student_id,
          consent_version: GUARDIAN_CONSENT_VERSION,
        };
      }
      return { kind: "invite", ...await redeem(sql, user, code, ["guardian"]) };
    }
    case "revoke_guardian_consent": {
      const student = id(input, "student_id");
      await asUser(
        sql,
        user,
        (tx) => tx`SELECT public.revoke_guardian_consent(${student}::uuid)`,
      );
      return { revoked: true };
    }
    case "create_team": {
      const school = id(input, "school_id");
      const name = text(input, "name", 120);
      const kind = competition(input);
      const [row] = await asUser(
        sql,
        user,
        (tx) =>
          tx`SELECT * FROM public.create_school_team(${school}::uuid, ${name}, ${kind})`,
      );
      return { team_id: row.team_id, code: row.code };
    }
    case "join_team": {
      const code = shortCode(input);
      const role = teamRole(input);
      const [row] = await asUser(
        sql,
        user,
        (tx) => tx`SELECT * FROM public.join_school_team(${code}, ${role})`,
      );
      return {
        team_id: row.team_id,
        team_name: row.team_name,
        team_role: role,
      };
    }
    case "leave_team": {
      const team = id(input, "team_id");
      await asUser(
        sql,
        user,
        (tx) => tx`SELECT public.leave_school_team(${team}::uuid)`,
      );
      return { left: true };
    }
  }
}
