# Migrações PostgreSQL e Supabase

## Visão Geral

As migrations definem o modelo canônico de usuários, matérias, conceitos, exercícios, tentativas, análises, eventos, práticas, cotas e execução. RLS, triggers e funções limitam acesso e protegem a integridade do pipeline. A reconciliação com o banco atualmente implantado não foi confirmada. 🟢/🔴

## Responsabilidades

- Persistir domínio acadêmico e relações do grafo. 🟢
- Isolar linhas de propriedade por usuário e reservar escrita privilegiada do pipeline. 🟢
- Proteger estados de análise, integridade de exercícios e uploads. 🟢
- Manter rate limits, cotas, auditoria, jobs e alertas. 🟢
- Permitir revisão auditável de erro pelo estudante. 🔴

## Regras de Negócio

- Matérias e tentativas pertencem a `auth.uid()`; recursos relacionados derivam propriedade por FK. 🟢
- Cliente não pode forjar estado/versão de análise nem editar exercício já analisado. 🟢
- `practice_answer_keys`, execuções e artefatos internos são privados ao servidor. 🟢
- Eventos de erro são sugeridos como `pending`; a escrita do cliente é restrita. 🟢
- Migrations aplicadas são imutáveis; correções devem ser aditivas. 🟢
- A configuração versionada não prova que o schema remoto corresponde ao histórico local. 🔴

## Requisitos Funcionais

| ID | Requisito | Prioridade | Critério de Aceite |
|---|---|---|---|
| RF-01 | Relacionar usuário, matéria, conceito, exercício, tentativa e análise com integridade referencial. 🟢 | Must | FKs impedem referências inválidas e escopo incompatível. |
| RF-02 | Aplicar RLS por proprietário nas tabelas do domínio. 🟢 | Must | Usuário não lê/altera linhas de outro usuário. |
| RF-03 | Reservar escrita de análise, eventos, gabarito e pipeline a backend autorizado. 🟢 | Must | Operações diretas do cliente não forjam resultados. |
| RF-04 | Restringir transições de estado e edição de enunciado após análise. 🟢 | Must | Trigger rejeita mudanças não permitidas. |
| RF-05 | Aplicar rate limits, cotas, leases, auditoria e rotinas operacionais. 🟢 | Should | Chamadas excedentes são recusadas e estados são observáveis. |
| RF-06 | Permitir confirmação/correção/rejeição auditável pelo estudante. 🔴 | Must | Não existe policy/API funcional no schema atual; necessário para validação do mapa. |
| RF-07 | Confirmar paridade do schema remoto com migrations locais. 🔴 | Should | Requer consulta e validação no projeto Supabase implantado antes de alterações de banco. |

## Requisitos Não Funcionais

| Tipo | Requisito inferido | Evidência no código | Confiança |
|---|---|---|---|
| Segurança | RLS está habilitada e funções internas restringem privilégios/search path. | `appmistakemap/database/supabase/migrations/` | 🟢 |
| Integridade | Triggers protegem estados e imutabilidade do exercício analisado. | Migrations de pipeline | 🟢 |
| Disponibilidade | Jobs assíncronos usam `pg_cron` + `pg_net`, sem HTTP síncrono em trigger. | Migrations operacionais | 🟢 |
| Controle de abuso | Rate limit usa janela fixa e limites configurados. | Migration de rate limit | 🟢 |

## Critérios de Aceitação

```gherkin
Dado um usuário autenticado e duas contas com dados distintos
Quando cada conta consulta matérias e tentativas
Então cada uma acessa somente seus próprios dados

Dado um cliente que tenta marcar análise como completed
Quando grava alteração direta incompatível
Então trigger ou privilégio rejeita a mudança

Dado um exercício com tentativa ou gabarito associado
Quando o cliente tenta alterar enunciado ou matéria
Então a alteração é recusada

Dado uma operação de cliente para ler gabarito ou tabela interna
Quando a consulta é executada
Então grants/RLS impedem o acesso

Dado um histórico de migrations já aplicado
Quando uma correção de schema é necessária
Então uma migration nova e aditiva é criada sem reescrever histórico

Dado o schema remoto implantado
Quando comparado com as migrations versionadas
Então diferenças são documentadas
Mas essa reconciliação ainda não foi confirmada
```

## Prioridade (MoSCoW)

| Requisito | MoSCoW | Justificativa |
|---|---|---|
| RLS, propriedade e integridade | Must | Protege dados pessoais e coerência do domínio. |
| Escrita privilegiada do pipeline | Must | Impede falsificação pelo cliente. |
| Rate limits, cotas e jobs | Should | Controles operacionais relevantes. |
| Revisão humana de eventos | Must | Requisito explícito do produto, sujeito a desenho e migration futura. |
| Paridade remota | Should | Pré-condição operacional para qualquer nova migration. |

## Rastreabilidade de Código

| Arquivo | Função / Classe | Cobertura |
|---|---|---|
| `appmistakemap/database/supabase/migrations/20260901163259_create_initial_schema.sql` | Modelo inicial | 🟢 |
| `appmistakemap/database/supabase/migrations/20260901173121_create_profiles.sql` | Perfis e políticas | 🟢 |
| `appmistakemap/database/supabase/migrations/20260901174740_add_rate_limiting.sql` | Rate limit | 🟢 |
| `appmistakemap/database/supabase/migrations/20260910023647_create_ingestion_pipeline_tables.sql` | Pipeline de ingestão | 🟢 |
| `appmistakemap/database/supabase/migrations/20261027013000_enable_realtime_sync.sql` | Realtime | 🟢 |
| `appmistakemap/database/README.md` | Regras de aplicação do histórico | 🟢 |
