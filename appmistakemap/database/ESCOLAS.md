# Escola e papéis

Migration: `supabase/migrations/20261111050000_schools_and_roles.sql`.
Testes de RLS: `scripts/verify-schools-rls.sh` (Postgres local descartável, nunca o banco publicado).

## Tabelas

| Tabela | O que guarda | Quem lê pelo app |
|---|---|---|
| `schools` | nome, CNPJ (14 dígitos), plano (`free`, `escola`, `plus`), ciclo, status | qualquer membro ativo da escola |
| `school_members` | `(school_id, user_id, role)`, status `active`/`suspended`, convite usado | o próprio papel; dono, coordenador e TI veem todos da escola |
| `school_invites` | papel, e-mail opcional, usos, validade, revogação; só o hash SHA-256 do código | dono, coordenador e TI (sem a coluna `code_hash`) |
| `platform_classes.school_id` | turma passa a poder ser de uma escola | gestão da escola lê título e professor |

Papéis: `owner`, `coordinator`, `it_admin`, `teacher`, `student`, `guardian`.
O app nunca escreve nessas tabelas direto: só pelas funções abaixo ou pela Edge Function `school-admin` (service_role).

## Funções

| Função | Para quê |
|---|---|
| `is_school_member(school, roles[] default null)` | conferência de papel usada nas políticas; `security definer` com `search_path = ''` para não repetir a recursão de RLS de 20260929112200 e 20261109221500 |
| `create_school(name, cnpj default null)` | cria a escola no plano Grátis; quem chamou vira dono |
| `create_school_invite(school, role, email, max_uses, valid_days)` | devolve o código uma única vez. Gestão (dono, coordenador, TI) só o dono convida e o convite é de uso único; professor, estudante e responsável podem ser convidados por dono, coordenador ou TI |
| `redeem_school_invite(code)` | quem chamou ganha o papel; repetir não gasta o convite |
| `revoke_school_invite(invite)` | revoga um convite |

## Regra do convite

O trigger `school_members_guard` vale para qualquer caminho de escrita, inclusive service_role:

- sem convite, só entra o dono fundador (quem criou a escola, enquanto ela não tem dono);
- com convite, confere escola, papel, validade, revogação, usos e e-mail (se o convite tiver) e consome um uso;
- papel, escola, usuário e convite de um membro não mudam por UPDATE: troca de papel é convite novo.

Erros: `MM401` sem login, `MM403` sem permissão ou sem convite, `MM404` convite inválido, `MM429` limite de 5 escolas criadas por usuário.

## O que ainda não tem

Telas, Edge Function `school-admin`, cobrança, contrato e auditoria ficam nas próximas etapas (itens B, D, E e F da onda 1). Planos, cota coletiva e aluno ativo estão em [PLANOS_E_COTA.md](PLANOS_E_COTA.md).
