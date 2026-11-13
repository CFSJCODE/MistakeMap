# Contas e escolas de demonstração

Recria do zero o ambiente de demonstração comercial e acadêmica em produção.
Tudo é fictício e toda escola daqui é `demo = true` (nunca gera cobrança no Asaas).

| Ordem | Arquivo | Onde roda | O que faz |
|---|---|---|---|
| 1 | `apagar_demo_antiga.sql` | banco | Apaga todas as contas, menos as do dono e do coautor, e as escolas demo antigas |
| 2 | `criar_contas.ps1` | PC do dono | Cria as contas de `contas.json` e grava as senhas só em `appmistakemap/.env.contas-demo.local` |
| 3 | `seed_escolas.sql` | banco (depois da migration 20261113200000) | Oficina Volt (pequena), Rede Nexo (Vale do Ferro + Centro), papéis por convite, turmas, tarefas, equipes, responsáveis, uso mensal e faturas demo |
| 4 | `seed_alunos.sql` | banco | Histórico de estudo (Mapa, Caderno, Estudar, revisão, Praticar) de cada aluno, variando por conta |

`seed_alunos.sql` é gerado: `python3 gerar_compacto.py <e-mails dos alunos>` (dados em `gerar_seed.py`, SQL em `seed_compacto_template.sql`).
Os scripts SQL são idempotentes. Senha nenhuma entra no Git.

## Organograma

A Rede Nexo segue o organograma de uma rede tipo SESI/SENAI/FIEMG e os regimentos escolares de unidades SENAI (MT e CE) e de colégios maristas, com nomes fictícios. O cargo de cada pessoa está em `contas.json` (`cargo`, vai para `user_metadata.job_title`) e, por escola, em `school_members.job_title` e `department`, que o app mostra no seletor de perfil e no cartão "Equipe e cargos" do painel.

| Nível | Cargo | Papel no app | Onde |
|---|---|---|---|
| Sede | Diretora Regional | dono | as duas unidades |
| Sede | Superintendente de Educação | coordenação | as duas unidades |
| Sede | Gerente Geral de TI | TI | as duas unidades |
| Sede | Gerente de Finanças e Controle (paga) | financeiro | as duas unidades |
| Sede | Analista de Suprimentos, Compras e Contratos | financeiro | as duas unidades |
| Unidade Vale do Ferro | Diretor, Coordenadora Pedagógica, Orientadora Educacional, Coord. Administrativo-Financeiro, Secretário Escolar | dono, coordenação, coordenação, financeiro, TI | só a unidade |
| Unidade Centro | Gerente da Unidade, Coordenador de Educação, Coord. Administrativo-Financeiro, Secretária Acadêmica, 2 instrutores, 10 alunos, 1 responsável | dono, coordenação, financeiro, TI, professor, estudante, responsável | só a unidade |

Na Oficina Volt o dono acumula direção, coordenação e aula, e a secretária cuida de matrículas e convites (papel TI).

Para acrescentar contas novas sem trocar a senha das que já existem: `criar_contas.ps1 -SomenteNovas` e depois `seed_escolas.sql`.
