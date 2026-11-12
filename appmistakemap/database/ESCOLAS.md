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

Contrato, cobrança e auditoria ficam nas próximas etapas (itens D, E e F da onda 1). Planos, cota coletiva e aluno ativo estão em [PLANOS_E_COTA.md](PLANOS_E_COTA.md).

## Cadastro por perfil (item B)

Migration: `supabase/migrations/20261111223000_signup_profiles.sql`.
Testes: `scripts/verify-signup-profiles.sh` (Postgres local, usuário não root).
Edge Function: `school-admin` (toda escrita do cadastro e da escola).
Telas: `lib/school/` (`quem_e_voce.dart`, `porta_perfil.dart`, `painel_escola.dart`).

| Tabela | O que guarda |
|---|---|
| `user_signups` | perfil escolhido em "Quem é você?" e data de nascimento do estudante. É só um pedido: não dá papel |
| `guardian_consent_requests` | código (hash) que o menor mostra ao responsável; uso único, 7 dias |
| `guardian_links` | responsável → estudante, versão do termo, data, revogação |
| `school_teams`, `school_team_members` | equipe de robótica com código (hash) e função (programação, mecânica, eletrônica, estratégia) |

Regras:

- Professor da escola, coordenação e TI só ganham o papel com convite. A `school-admin` confere se o papel do convite bate com o perfil escolhido; o trigger `school_members_guard` confere o resto.
- Professor sem convite começa no plano Grátis: `start_free_teacher` cria uma escola Grátis com ele como dono e professor (pelo mesmo caminho de convite). Turma nova de quem dá aula em uma escola só fica ligada a ela.
- `guardian_consent_pending(user)`: estudante menor de 18 anos, sem papel de estudante numa escola, sem turma de escola e sem aceite ativo do responsável. As funções de IA (analyze-attempt, generate-practice, study-material, dissertativa do question-bank e process-batch) recusam enquanto for verdadeiro. Conta antiga sem data de nascimento não é bloqueada.
- Conta sem perfil e sem papel vê "Quem é você?". Quem já tem papel (convite, planilha) pula a tela. Mais de um papel → seletor de perfil no topo.

## Relatórios da escola (migration 20261112210000)

`public.school_reports(p_school, p_months)` devolve, num jsonb, o relatório
pedagógico (dono e coordenação) e o financeiro (dono e Financeiro/Compras).
TI, professor, aluno e quem é de fora recebem 42501.

- Pedagógico: uso por mês (alunos ativos, análises, práticas), turmas
  (alunos, ativos em 28 dias, tarefas) e mapa de erros dos últimos 90 dias
  (tipo de erro e conceito × tipo). O mapa só aparece com 5+ alunos com erro
  e cada conceito com 3+ alunos. Nunca há id, nome ou e-mail de aluno.
- Financeiro: custo de cada mês pelo uso (mesma fórmula da fatura), faturas
  por mês (pago e em aberto), forma de pagamento, situação e as últimas
  faturas (o app exporta em CSV).
- `school_demo_report`: amostra fictícia só lida para escola com
  `school_billing_settings.demo`, sempre marcada `sample = true` no app.

Testes: `scripts/school_billing/reports_tests.sql` (roda em
`scripts/verify-school-billing.sh`).
