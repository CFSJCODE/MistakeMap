# Planos, cota coletiva e aluno ativo

Migration: `supabase/migrations/20261111071500_school_plans_quota.sql` (depende de `20261111050000_schools_and_roles`, ver [ESCOLAS.md](ESCOLAS.md)).
Testes: `scripts/verify-school-quota.sh` (Postgres local descartável, rodar como usuário que não seja root) e `deno test` em `supabase/functions` (roteador por plano).

## Planos

| Plano | Usuários | Turmas | Análises por aluno ativo | Treinos por aluno ativo | Análise além do pote | IA |
|---|---|---|---|---|---|---|
| `free` (Grátis) | até 5 | 1 | 20 | 4 | bloqueada | standard (Gemini) |
| `escola` (Escola) | sem limite | sem limite | 60 | 15 | liberada, R$ 0,15 cada | standard (Gemini) |
| `plus` (Escola Plus) | sem limite | sem limite | 100 | 25 | liberada, R$ 0,15 cada | premium (Claude liberado) |

Os números ficam na tabela `school_plan_limits` (o app só lê). Para mudar um preço ou limite, crie uma migration nova com `update`.

## Aluno ativo

- É o membro com papel `student`, ativo, de uma escola em `pilot` ou `active`, que usou o app no mês.
- "Usou" é gravado no servidor, na mesma transação da ação: tentativa nova (`attempts`), sessão do catálogo (`platform_sessions`), resposta no banco de questões (`question_responses`) ou pedido de IA. Abrir o app só para ler não conta.
- O mês segue o calendário de Brasília (`school_usage_month()`).
- `school_active_students` evita contar a mesma pessoa duas vezes. O número cobrado é `school_usage_months.active_students`, que não cai se a conta for apagada depois.
- Professor, coordenador, TI, dono e responsável não contam como ativos.

## Pote coletivo

- O pote do mês é `análises por ativo × alunos ativos` (e o mesmo para treinos). Cada aluno novo no mês aumenta o pote da escola inteira.
- `consume_school_ai(user, kind)` roda dentro da transação que reserva a análise (`ai_service.ts`). Respostas:
  - `ok`: saiu do pote;
  - `extra`: pote esgotado em plano pago, análise liberada e contada em `extra_analyses` para a fatura;
  - `exhausted`: plano Grátis sem pote (ou treino sem pote); a Edge Function responde 429 `school_quota`;
  - `no_school`: a pessoa não é aluna de escola ativa e segue só a cota individual.
- Se a IA falhar, `release_school_ai` devolve o pedido ao pote (ou desconta o extra).
- Exercícios do catálogo revisado e o banco de questões objetivas não gastam pote. Material de estudo (`study-material`) também não: só segue o nível de IA do plano, porque o plano ainda não define a cota de materiais do Grátis e do Plus.
- A cota diária individual (`ai_daily_usage`, `AI_ANALYSES_PER_DAY`) continua valendo como teto por pessoa, para um aluno sozinho não esvaziar o pote da turma.
- `school_quota(school)` resume o mês para o dono, o coordenador e a TI (painel do item F).

## Plano efetivo

- `user_school_plan(user)` devolve a escola de melhor plano em que a pessoa é membro ativo. O `study-platform` usa essa função e devolve em `entitlements`: `plan`, `plan_label`, `plan_source` (`school` ou `individual`), `school` e `ai_tier`.
- Sem escola, vale `platform_entitlements` (plano individual), como antes.

## Nível de IA

- `model_router.ts`: `aiTierForPlan(plan)` dá `premium` só para `plus`; `providerAllowed(provider, tier)` barra a Anthropic (Claude) fora do premium.
- `gemini.ts`: com `aiTier` standard (o padrão quando nada é informado), Claude não é usado nem como provedor configurado (`AI_PROVIDER`, `AI_<TAREFA>_PROVIDER`), nem pela evidência do roteador, nem pelo fallback `AI_CLAUDE_FALLBACK_ENABLED`. O pedido segue no Gemini, e o OpenRouter gratuito continua disponível.
- Professor, coordenação e dono de uma escola Plus também recebem o nível premium, mas usam a cota individual (não gastam o pote dos alunos).

## Limites do Grátis

- Trigger `school_members_plan_limit`: o 6º usuário de uma escola Grátis é recusado com `MM402`, e o convite não é gasto.
- Trigger `platform_classes_plan_limit`: a 2ª turma de uma escola Grátis é recusada com `MM402`.
- Trigger `schools_plan_change_guard`: a escola só volta para o Grátis se couber nos limites.

## O que fica para depois

- Fechar o mês no dia 1, aplicar o mínimo de R$ 99 e os descontos por volume e gerar a fatura: item D (`school_invoices`, Asaas).
- Custo de IA por escola (`school_usage_months.ai_cost_usd`) e aviso em 80% do pote: item F (painéis).
- Telas para trocar de plano: item D.
