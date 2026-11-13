# Contas e escolas de demonstração

Recria do zero o ambiente de demonstração comercial e acadêmica em produção.
Tudo é fictício e toda escola daqui é `demo = true` (nunca gera cobrança no Asaas).

| Ordem | Arquivo | Onde roda | O que faz |
|---|---|---|---|
| 1 | `apagar_demo_antiga.sql` | banco | Apaga todas as contas, menos as do dono e do coautor, e as escolas demo antigas |
| 2 | `criar_contas.ps1` | PC do dono | Cria as contas de `contas.json` e grava as senhas só em `appmistakemap/.env.contas-demo.local` |
| 3 | `seed_escolas.sql` | banco | Oficina Volt (pequena), Rede Nexo (Vale do Ferro + Centro), papéis por convite, turmas, tarefas, equipes, responsáveis, uso mensal e faturas demo |
| 4 | `seed_alunos.sql` | banco | Histórico de estudo (Mapa, Caderno, Estudar, revisão, Praticar) de cada aluno, variando por conta |

`seed_alunos.sql` é gerado: `python3 gerar_compacto.py <e-mails dos alunos>` (dados em `gerar_seed.py`, SQL em `seed_compacto_template.sql`).
Os scripts SQL são idempotentes. Senha nenhuma entra no Git.
