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

Contrato e cobrança: itens D, E e F da onda 1. Auditoria: seção "Painel de TI" abaixo. Planos, cota coletiva e aluno ativo estão em [PLANOS_E_COTA.md](PLANOS_E_COTA.md).

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

## Cobrança de teste (migration 20261112230000)

- Ação `test_charge` da Edge Function `school-billing`: quem paga numa escola
  **real** (sem `demo`) gera um Pix ou boleto de R$ 5 (`kind = 'test'`). Serve
  para provar Asaas + webhook de ponta a ponta. Paga, não muda o plano, não
  emite NFS-e e não vira crédito no fechamento do mês.
- No app: botão "Cobrança de teste (R$ 5)" no cartão "Plano e cobrança".
- A mesma migration cria "Escola Teste de Cobrança (real)" para
  `dono.demo@mistakemap.dev`, com o CNPJ informado pelo Cláudio, sem a marca
  demo. Para apagar depois, remova a escola (as faturas vão junto).

## Painel de TI (migration 20261113180000)

Migration: `supabase/migrations/20261113180000_school_it_admin.sql`.
Testes: `scripts/verify-school-it.sh` (Postgres local + Edge Function).
Demonstração: `scripts/school_it/seed_demo_ti.sql` (Unidade Centro da Rede Nexo; idempotente; não manda e-mail nem mexe em sessão).
Telas: `lib/school/painel_ti.dart` e `lib/school/ti_modelos.dart`.

A TI cuida de contas e acessos. Nunca vê respostas, mapa, caderno nem valores em reais.

| Função (ação da `school-admin`) | Quem | O que faz |
|---|---|---|
| `school_it_licenses` (`it_licenses`) | dono, coordenação, TI, Financeiro | usuários ativos × limite do plano, suspensos, turmas, convites em aberto, alunos ativos e pote de IA do mês (sem R$) |
| `school_it_directory` (`it_directory`) | dono, TI | pessoas da escola: e-mail, nome, papéis e situação, entrada, último acesso, nº de aparelhos |
| `school_member_sessions` (`it_member_sessions`) | dono, TI | aparelhos conectados (tipo de aparelho e metade do IP) |
| `revoke_school_member_sessions` (`it_revoke_sessions`) | dono, TI | encerra as sessões da conta em todos os aparelhos |
| `school_member_password_reset` (`it_reset_password`) | dono, TI | a Edge Function pede ao Auth o e-mail do "Esqueci minha senha"; 1 por pessoa a cada 10 min; a TI nunca vê nem define senha |
| `set_school_member_status` (`it_set_status`) | dono, TI | suspende ou reativa um papel (reativar respeita o limite do plano) |
| `remove_school_member` (`it_remove_member`) | dono, TI | tira o papel da escola (a conta continua) |
| `create_school_invites_batch` (`it_import_invites`) | dono, TI | até 500 convites pessoais (professor, estudante, responsável) de uma planilha colada; devolve o código ou o motivo por linha |
| `renew_school_invite` (`it_renew_invite`) | quem pode revogar o convite | revoga e gera um código novo igual |
| `school_audit` (`it_audit`) | dono, TI | registro de auditoria paginado |

Regras de permissão:

- TI administra professor, estudante e responsável. Coordenação, TI e Financeiro só o dono administra; o papel de dono não é suspenso nem removido por aqui; ninguém age sobre si mesmo.
- Sessões e senha (ações na conta inteira) só quando todos os papéis da pessoa na escola são administráveis por quem pede, ela não tem papel de gestão em outra escola e não é da equipe MistakeMap (`profiles.role` admin/developer).

`school_audit_log` é gravada por triggers em `school_members` (entrou, suspenso, reativado, removido) e `school_invites` (criado, revogado) e pelas funções acima (lote, renovação, sessões, senha). O app só lê (RLS: dono e TI da escola).

## Cargo e área (organograma)

Migration `20261113200000_school_member_titles.sql`. `school_members.job_title` e `department` são só rótulos do organograma (ex.: "Diretora Regional", "Sede — Diretoria Regional"); o acesso continua vindo do papel.

| Função | O que faz |
|---|---|
| `set_school_member_title(school, user, cargo, area)` | dono, coordenação e TI definem cargo e área de quem é da escola (todas as linhas da pessoa) |
| `school_staff(school)` | quem trabalha na escola (sem alunos e responsáveis), com nome, e-mail, papéis, cargo e área; só devolve linhas para dono, coordenação, TI e financeiro |

O app mostra o cargo no seletor de perfil (só nos papéis de gestão) e no cartão "Equipe e cargos" do painel, agrupado por área (`school-admin` → `school_overview.staff`).
