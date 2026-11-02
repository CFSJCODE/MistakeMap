# Migrações PostgreSQL e Supabase — Design Técnico

## Interface

| Objeto | Entrada / contrato | Retorno / efeito | Observação |
|---|---|---|---|
| `subjects` | linha com `user_id` | matéria do estudante | RLS compara proprietário com `auth.uid()`. 🟢 |
| `concepts` / `concept_edges` | matéria, conceito e relação direcionada | grafo conceitual | FK limita relações a conceitos existentes. 🟢 |
| `exercises` / `exercise_concepts` | matéria, enunciado, dificuldade e conceitos | exercício e vínculo N:N | Enunciado protegido após análise/gabarito. 🟢 |
| `attempts` / `attempt_analyses` | usuário, exercício, resposta e estado | tentativa e análise única | Estado/versão validados por trigger/backend. 🟢 |
| `error_events` / `mastery_events` | tentativa, conceito, categoria/evidência/outcome | histórico de fragilidade/evolução | Cliente lê próprios dados, não escreve eventos de IA. 🟢 |
| `practice_sets` / `practice_answer_keys` | usuário, matéria, conjunto e exercício | prática e gabarito privado | Gabarito sem acesso direto do cliente. 🟢 |
| `processing_runs`, `attempt_assets`, `ocr_artifacts`, `audit_log` | execução e artefatos internos | trilha do pipeline | Sem policy de leitura do app. 🟢 |

## Fluxo Principal

1. Migrations iniciais criam tabelas e relações acadêmicas; migrations posteriores acrescentam perfil, rate limit, ingestão, IA, papéis, reparos de RLS e Realtime. 🟢
2. Auth trigger cria perfil padrão `user`; funções `is_admin()` e políticas específicas evitam recursão de RLS. 🟢
3. RLS filtra `subjects`/`attempts` por `auth.uid()` e deriva ownership de filhos pelas FKs. 🟢
4. Cliente cria tentativa em estado permitido; trigger impede adulterar proprietário, versão ou estado de processamento. 🟢
5. Backend grava análise/correção/eventos/gabaritos em tabelas privilegiadas. 🟢
6. Jobs com `pg_cron` + `pg_net` chamam funções assíncronas para lote e monitoramento. 🟢

## Fluxos Alternativos

- **Acesso de outro usuário:** RLS/FKs/policies recusam leitura ou escrita. 🟢
- **Alteração de exercício analisado:** trigger preserva o enunciado que fundamenta a análise. 🟢
- **Excesso de requisições:** trigger/rate limit bloqueia a operação. 🟢
- **Acesso a gabarito/tabela interna:** grants e ausência de policy negam acesso direto. 🟢
- **Revisão por estudante:** schema prevê estados para eventos, mas política e operação cliente ainda não estão implementadas. 🔴

## Dependências

- `auth.users` e claims Supabase: identidade e proprietário. 🟢
- Edge Functions: gravação privilegiada de análise, eventos, cotas e prática. 🟢
- `pg_cron` + `pg_net`: execução assíncrona de jobs. 🟢
- Realtime publication: sincronização de tabelas selecionadas no cliente. 🟢

## Decisões de Design Identificadas

| Decisão | Evidência no código | Confiança |
|---|---|---|
| Cliente não escreve resultados de IA diretamente | Migrations de análise e grants/RLS | 🟢 |
| Gabaritos e telemetria interna permanecem privados | Migrations de prática/IA | 🟢 |
| `guard_attempt_ai_state` valida estado e versão de tentativa | Migrations do pipeline | 🟢 |
| Exercício analisado não pode ser editado para preservar evidência | Migrations de integridade | 🟢 |
| Cron/HTTP não é executado sincronamente dentro de trigger | Migrations operacionais e arquitetura do projeto | 🟢 |
| Migration aplicada não é reescrita | `appmistakemap/database/README.md` | 🟢 |

## Estado Interno

O schema mantém estado de tentativa e pipeline, lease/retry em `processing_runs`, artefatos de upload/OCR, eventos temporais de erro/domínio e cotas. Migrations são a fonte versionada local; a imagem de produção pode divergir. 🟢/🔴

## Observabilidade

`audit_log`, `processing_runs`, contadores de uso, rate limits e estados de alertas dão suporte operacional. Jobs verificam saúde e cotas via funções assíncronas. 🟢

## Riscos e Lacunas

- 🔴 Não foi consultado o schema Supabase remoto nesta análise.
- 🔴 O app não tem política/endpoint para validar eventos `pending`.
- 🟡 `practice_sets.source_attempt_ids` é array UUID sem FK, portanto rastreabilidade não é garantida pelo banco.
- 🟢 Mudanças futuras devem ser migrations aditivas, com revisão das políticas RLS.
