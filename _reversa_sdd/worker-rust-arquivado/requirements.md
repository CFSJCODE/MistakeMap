# Worker Rust arquivado

## Visão Geral

Esta unit documenta o worker histórico Axum/SQLx que foi substituído por Supabase Edge Functions. Ele contém rotas de health, URL de upload e processamento em lote, mas o pipeline ainda não realiza OCR/LLM e não deve ser tratado como backend ativo. 🟢

## Responsabilidades

- Registrar o desenho e os contratos históricos para consulta. 🟢
- Explicitar diferenças entre worker legado e backend ativo. 🟢
- Impedir que a referência arquivada seja reativada sem reconstrução e revisão. 🟢
- Processar exercícios como implementação de produção. 🔴

## Regras de Negócio

- Edge Functions Supabase são o backend ativo; worker Rust é somente referência histórica. 🟢
- `run_batch` busca até cinco tentativas `pending`, usa lock skip-locked e versionamento otimista. 🟢
- O pipeline baixa assets, mas OCR e LLM ainda são TODOs; em seguida marca tentativa concluída. 🟢
- Retry grava `retryable_failed`, porém a busca do worker escolhe somente `pending`. 🟢
- Upload legado aceita PDF, incompatível com o contrato de imagem atual. 🟢

## Requisitos Funcionais

| ID | Requisito | Prioridade | Critério de Aceite |
|---|---|---|---|
| RF-01 | Documentar endpoints, autenticação, dependências e limites do worker. 🟢 | Should | Especificação identifica o caráter legado e divergências. |
| RF-02 | Manter health/upload/batch para consulta histórica, sem considerá-los rotas de produção atuais. 🟢 | Won't | Deploy não é acionado pelo app atual. |
| RF-03 | Reativar processamento de análise sem implementar OCR/LLM e validar fim a fim. 🔴 | Won't | Reativação não é permitida com pipeline incompleto. |
| RF-04 | Substituir Edge Functions pelo worker arquivado. 🔴 | Won't | Exige aprovação e reconstrução integral, fora do estado atual. |

## Requisitos Não Funcionais

| Tipo | Requisito inferido | Evidência no código | Confiança |
|---|---|---|---|
| Segurança | JWT e segredo de cron protegem rotas do worker histórico. | `worker/src/routes/`, `worker/src/main.rs` | 🟢 |
| Integridade | Concorrência usa lock e controle de versão. | `worker/src/attempts.rs`, `worker/src/pipeline.rs` | 🟢 |
| Confiabilidade | Retry legado não cobre estados reprocessáveis, apesar de gravar falha. | `worker/src/attempts.rs` | 🟢 |

## Critérios de Aceitação

```gherkin
Dado um leitor da arquitetura atual
Quando consulta a documentação do worker
Então distingue o worker arquivado das Edge Functions ativas

Dado um lote worker com assets baixados
Quando não há implementação de OCR/LLM
Então não se considera a tentativa corretamente analisada

Dado uma falha marcada retryable_failed pelo worker
Quando a consulta seguinte busca apenas pending
Então a lacuna de retry é explicitada e não é descrita como recuperação funcional

Dado um pedido para reativar o worker
Quando OCR, LLM, contrato e retry não foram reconstruídos
Então a reativação é bloqueada
```

## Prioridade (MoSCoW)

| Requisito | MoSCoW | Justificativa |
|---|---|---|
| Registrar estado e riscos de legado | Should | Evita reuso incorreto e preserva contexto técnico. |
| Worker como backend ativo | Won't | Migração substituiu esse caminho e implementação é incompleta. |
| Reescrever pipeline somente após novo projeto aprovado | Won't | Não é escopo do módulo arquivado. |

## Rastreabilidade de Código

| Arquivo | Função / Classe | Cobertura |
|---|---|---|
| `worker/src/main.rs` | Inicialização, configuração e JWKS | 🟢 |
| `worker/src/pipeline.rs` | Processamento incompleto | 🟢 |
| `worker/src/attempts.rs` | Lock, busca e status | 🟢 |
| `worker/src/routes/upload_url.rs` | Endpoint legado de upload | 🟢 |
| `worker/src/routes/process_batch.rs` | Endpoint protegido de lote | 🟢 |
| `BACKEND.md` | Histórico da migração | 🟢 |
