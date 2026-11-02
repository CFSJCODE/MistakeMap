# Inventário do MistakeMap

> **Escopo:** arquivos-fonte e configuração em `appmistakemap/lib/`,
> `appmistakemap/test/`, `appmistakemap/database/supabase/`,
> `supabase/functions/`, `worker/src/`, `scripts/` e `.github/workflows/`.
> Diretórios de build, caches e a cópia `MistakeMap_release/` não foram tratados
> como código-fonte canônico. O worker Rust está arquivado.
>
> **Confiança:** 🟢 CONFIRMADO = evidência no código/configuração;
> 🟡 INFERIDO = interpretação da estrutura; 🔴 LACUNA = exige validação.

## Visão geral

🟢 O MistakeMap é uma aplicação Flutter multiplataforma com autenticação,
cadastro de exercícios e tentativas, envio de imagens, análise de erros por IA,
mapa/insights e prática direcionada. O backend ativo usa Supabase (Auth,
PostgreSQL e Edge Functions), Gemini e Cloudflare R2. Há SQLite local para o
caderno de erros e cache/fila de sincronização.

🟢 O núcleo arquitetural está separado em cliente Flutter, funções Deno,
schema/migrations Supabase e integrações externas. O diretório `worker/`
contém a implementação histórica Rust e não deve ser evoluído como backend
ativo.

🟡 A documentação do estado atual é inconsistente: o README principal descreve
análise e prática como funcionais, enquanto `BACKEND.md` ainda afirma que o
Flutter não exibe análises nem chama a geração de prática. A verificação
funcional deve prevalecer sobre esses textos; a divergência fica como ponto de
validação na análise detalhada.

## Tecnologias e contagem de arquivos

Contagem feita nos diretórios-fonte delimitados acima (120 arquivos):

| Linguagem / formato | Arquivos |
|---|---:|
| Dart | 61 |
| TypeScript | 15 |
| Rust | 11 |
| SQL | 22 |
| JSON | 6 |
| PowerShell | 1 |
| TOML | 1 |
| Lockfile | 1 |
| Outros (`.gitignore`, `.gitkeep`) | 2 |

🟢 Linguagem principal: Dart. 🟢 Linguagens secundárias: TypeScript para
Supabase Edge Functions, Rust para o worker arquivado e SQL para migrations.

## Módulos e responsabilidades

### Cliente Flutter — `appmistakemap/`

- 🟢 **Bootstrap, autenticação e navegação:** `lib/main.dart` inicializa
  Supabase e concentra grande parte das telas Fluent e do fluxo autenticado.
  Login/cadastro oferece e-mail/senha e Google; a navegação é adaptativa.
- 🟢 **Exercícios, tentativas e mapa/IA:** `lib/ai/` contém modelos,
  repositório, formulário de envio, análise e insights/mapa. A captura aceita
  imagem e registro textual.
- 🟢 **Caderno local:** `lib/local/` e `lib/caderno_erros.dart` implementam
  disciplinas e registros de erro com CRUD em SQLite.
- 🟢 **Offline/sincronização:** `lib/sync/` implementa cache, fila local,
  retomada de envios e sincronização com Supabase.
- 🟢 **Administração:** `lib/admin/` reúne métricas e políticas/cotas de uso.
- 🟢 **Layout, tema e sobre:** `lib/layout/`, `lib/theme/`, `lib/about/` e
  `lib/assets/` dão suporte à responsividade, identidade visual e tela Sobre.
- 🟢 Interface principal baseada em Fluent UI; o fluxo de IA fica em uma rota
  Material isolada.
- 🟢 Plataformas configuradas: Android, Windows e Web.

### Backend ativo — `supabase/`

- 🟢 `functions/analyze-attempt/`: solicita/anexa uma análise de tentativa.
- 🟢 `functions/generate-practice/`: gera exercícios de prática para uma
  disciplina/categoria.
- 🟢 `functions/process-batch/`: processa tentativas pendentes em lote.
- 🟢 `functions/upload-url/`: emite URL pré-assinada para upload no R2.
- 🟢 `functions/health/`: verifica conectividade de PostgreSQL e R2.
- 🟢 `functions/_shared/`: contrato/validação da IA, HTTP/autenticação,
  serviço de domínio e cliente Gemini.
- 🟢 `functions/tests/`: testes de contrato da IA e upload.
- 🟢 Migrations canônicas em `appmistakemap/database/supabase/migrations/`;
  a configuração de deploy das Edge Functions fica na raiz `supabase/`.

### Persistência

- 🟢 PostgreSQL/Supabase: autenticação, perfil, disciplinas, exercícios,
  tentativas, imagens, análises, eventos de erro, prática, cotas e sincronização
  em tempo real; migrations configuram tabelas, funções, políticas e rotinas.
- 🟢 SQLite local: caderno e suporte offline; Web usa implementação SQLite
  baseada em armazenamento do navegador.
- 🟢 R2: imagens submetidas, via URL pré-assinada.
- 🔴 A reconciliação do schema efetivamente implantado com todas as migrations
  versionadas requer consulta ao projeto Supabase; este inventário é local.

### Worker histórico — `worker/`

- 🟢 Serviço Rust/Axum com rotas health, upload-url e process-batch, integração
  PostgreSQL/SQLx, R2 e validação JWT.
- 🟢 Arquivado após a migração de processamento para Supabase Edge Functions;
  manter apenas como referência histórica.

## Integrações externas

| Integração | Uso observado |
|---|---|
| Supabase Auth | Login, sessão e identidade do usuário |
| Supabase PostgreSQL / RLS / RPC | Dados do aluno e isolamento por usuário |
| Supabase Realtime | Atualização/sincronização de dados |
| Supabase Edge Functions / Deno | Processamento e APIs do backend |
| Google Gemini | Análise multimodal e geração de prática |
| Cloudflare R2 | Armazenamento de fotos por URL pré-assinada |
| Google Sign-In | Autenticação Google no cliente |
| GitHub Actions | CI, deploy de funções/banco e deploy web |
| Vercel | Publicação web, conforme README |

## Entradas, configuração e deploy

- Cliente: `appmistakemap/lib/main.dart`.
- Funções: `supabase/functions/{analyze-attempt,generate-practice,process-batch,upload-url}/index.ts`;
  `health/index.ts` expõe monitoramento.
- Worker arquivado: `worker/src/main.rs`.
- Configuração Flutter: `appmistakemap/pubspec.yaml`.
- Configuração Deno: `supabase/functions/deno.json` e `deno.lock`.
- Configuração Rust: `worker/Cargo.toml` e `Cargo.lock`.
- Migrações e configuração local Supabase:
  `appmistakemap/database/supabase/`.
- Configuração das funções/deploy: `supabase/config.toml`.
- CI: `.github/workflows/ci.yml` executa verificações Flutter, Deno e Rust;
  workflows separados fazem deploy Supabase e Web.

## Testes

- 🟢 Flutter: 23 arquivos de teste em `appmistakemap/test/`, cobrindo UI,
  autenticação, análise, CRUD local, sincronização, layout e contratos.
- 🟢 Deno: 2 arquivos em `supabase/functions/tests/`.
- 🟡 O worker Rust tem CI para `cargo check`, `clippy` e `cargo test`; a
  quantidade de testes não foi inferida pelo número de módulos.
- 🟢 O pipeline de CI define Flutter 3.47.2, Deno 2.9.x e Rust 1.98.1.

## Requisitos de entrega acadêmica informados

Os itens relatados para as sprints incluem:

1. Documento PDF de proposta com nome do projeto, componentes/funções do time,
   link do GitHub, objetivo, público-alvo, funcionalidades e rascunhos das telas.
2. Projeto de telas em Figma/Marvel ou ferramenta equivalente e documento PDF;
   pelo menos Início, funcionalidade principal, Cadastro e Sobre.
3. Navegação funcional entre telas em Flutter.
4. Documento PDF do projeto do banco e CRUD integrado ao aplicativo, com
   demonstração em aula.
5. Documentação completa do sistema em PDF e demonstração funcional das
   principais funcionalidades.

O código e README evidenciam funcionalidades e telas implementadas, mas a
existência dos documentos PDF, projeto-fonte de mockup e demonstração de aula
não pode ser confirmada apenas pelo inventário do repositório.
