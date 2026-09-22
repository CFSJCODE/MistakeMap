# CLAUDE.md — MistakeMap
<!-- Arquivo de entrada para o Claude Code neste projeto. -->

## Identidade do Projeto

**MistakeMap** — Mapa dos Padrões de Erro do Estudante  
Stack: Flutter + Dart (cliente) · Supabase (banco/auth) · Cloudflare R2 (arquivos) · Worker Rust (IA assíncrona)  
Plataformas: Android, Windows, Web

---

## Regras Fundamentais (não negociáveis)

1. **Nada de lógica de negócio no Flutter.** OCR, LLM e processamento de IA ficam no worker Rust.
2. **Nunca envie `service_role` ou segredos para o cliente.**
3. **Migrações do Supabase são imutáveis.** Correções viram novas migrations, nunca reescrita do histórico.
4. **HTTP síncrono dentro de trigger de banco é proibido.** Use pg_cron + pg_net para notificações assíncronas.
5. **Todo arquivo Dart deve passar em `flutter analyze` sem avisos.**

---

## Harness

Todos os loops e agentes autônomos devem carregar `harness.yaml` da raiz do projeto.

**Invocação:**
```bash
CLAUDE_CONFIG=harness.yaml claude /<comando> "<objetivo>"
```

**Limites ativos:**
| Recurso | Limite |
|---|---|
| Tokens por execução | 50.000 |
| Custo por execução | US$ 0,50 |
| Ciclos máximos | 10 |
| Stall (sem progresso) | aborta em 3 ciclos |
| Escrita permitida | `appmistakemap/`, `worker/src/`, `_reversa_*/`, `.reversa/` |
| Execução desacompanhada | habilitada, máx. 120 min |

---

## Critérios de Aceitação Padrão

**Flutter/Dart:**
| AC | Comando | Sucesso |
|---|---|---|
| AC1 | `flutter test --reporter compact` | `All tests passed` |
| AC2 | `flutter analyze` | `No issues found` |
| AC3 | `dart format --set-exit-if-changed lib/` | Exit code 0 |

**Worker Rust:**
| AC | Comando | Sucesso |
|---|---|---|
| AC1 | `cargo test` | todos os testes passam |
| AC2 | `cargo clippy -- -D warnings` | zero warnings |
| AC3 | `cargo check` | Exit code 0 |

---

## Loops de Engenharia (Harness)

Ative com `/` seguido do nome no Claude Code.

| Comando | Tipo | Quando usar |
|---|---|---|
| `/goal` | Loop de Objetivo | Bug aberto, meta de performance, problema sem caminho claro |
| `/loop` | Loop de Turno | Tarefa repetitiva em lote (refatorar N arquivos, migrar imports) |
| `/schedule` | Loop de Tempo | Rotina recorrente sem supervisão (auditoria, CVEs, relatórios) |

**Exemplos prontos:**

```bash
# Corrigir falhas de teste
CLAUDE_CONFIG=harness.yaml claude /goal "Corrigir falhas em appmistakemap/test/ \
  --AC1: flutter test 100% --AC2: flutter analyze sem avisos --AC3: sem regressão"

# Migrar imports em lote
CLAUDE_CONFIG=harness.yaml claude /loop "Migrar imports diretos de supabase_flutter \
  para package:appmistakemap/data/repositories/ em appmistakemap/lib/features/ \
  --AC1: dart analyze ok --AC2: flutter test ok"

# Auditoria semanal (segunda, 8h Brasília = 11h UTC)
CLAUDE_CONFIG=harness.yaml claude /schedule "0 11 * * 1" \
  "Auditoria de dependências Flutter e Rust \
  --AC1: dart pub outdated = 0 críticos --AC2: cargo audit = 0 CVEs --AC3: abrir PR"
```

---

## Reversa — Agentes Instalados

O Reversa está instalado completo neste projeto (63 agentes). Todos os artefatos ficam em pastas próprias e **nunca modificam o código-fonte sem permissão explícita em `.reversa/reversa-config.json`**.

### Pasta de artefatos
```
_reversa_sdd/        ← especificações extraídas (Discovery)
_reversa_forward/    ← features em evolução (Forward)
_reversa_bugs/       ← registro de defeitos (Debugger)
_reversa_docs/       ← mini-site de documentação
_reversa_refactor/   ← oportunidades de melhoria de código
.reversa/            ← estado, configuração e hooks
```

---

### Fluxo 1 — Discovery (extrair specs do código existente)

```
/reversa
```
Orquestra Scout → Archaeologist → Detective → Architect → Writer → Reviewer.  
Ao final gera o SDD completo em `_reversa_sdd/`.

**Modo autônomo (sem pausas entre agentes):**
```
/reversa-autonomous
```

**Agentes do Discovery:**
| Agente | O que faz |
|---|---|
| `reversa-scout` | Mapeia estrutura, frameworks, dependências e pontos de entrada |
| `reversa-archaeologist` | Analisa módulo a módulo (lib/domain, lib/features, worker Rust) |
| `reversa-detective` | Extrai regras de negócio implícitas (RLS, fórmula de prioridade P = F×R×I×(1−M)) |
| `reversa-architect` | Gera diagramas C4, ERD e mapa de integração Flutter↔Supabase↔R2↔Worker |
| `reversa-writer` | Produz especificações operacionais em `_reversa_sdd/` |
| `reversa-reviewer` | Valida gaps com o usuário antes de fechar o ciclo |
| `reversa-spec-sdd` | Geração direta de SDD a partir de código sem o pipeline completo |
| `reversa-explorer` | Exploração dirigida de módulo específico |
| `reversa-inspector` | Inspeção profunda de um arquivo ou função |
| `reversa-depth-inspection` | Análise de dependências cruzadas e acoplamento |

---

### Fluxo 2 — Forward (specs → código)

```
/reversa-forward
```
Detecta o estágio da feature ativa em `_reversa_forward/` e roteia para o próximo agente.

**Pipeline forward:**
```
requirements → clarify → plan → to-do → audit → quality → coding → add → sync
```

| Agente | O que faz |
|---|---|
| `reversa-requirements` | Elicita e estrutura requisitos da feature |
| `reversa-clarify` | Resolve ambiguidades antes de planejar |
| `reversa-plan` | Gera plano de implementação com tarefas e ordem |
| `reversa-to-do` | Transforma o plano em checklist executável |
| `reversa-audit` | Audita cobertura de testes e conformidade com specs |
| `reversa-quality` | Avalia qualidade do código gerado |
| `reversa-coding` | Gera o código com hooks `flutter analyze` + `flutter test` |
| `reversa-code-express` | Codificação rápida sem o pipeline completo |
| `reversa-add` | Adiciona uma sub-feature a uma feature existente |
| `reversa-sync` | Sincroniza artefatos de `_reversa_forward/` com `_reversa_sdd/` |

**Hooks automáticos configurados em `.reversa/hooks.yml`:**
- Após `coding`: `flutter analyze` + `flutter test`
- Após `code-express`: `flutter analyze`
- Após `add`: `dart format lib/`
- Após `sync`: `flutter test`
- Antes de `quality`: `flutter analyze`
- Após `audit`: `flutter test`

---

### Fluxo 3 — Bugs

```
/reversa-debugger        ← registra o bug
/reversa-debugger-fix    ← corrige com dois gates de aprovação
```

| Agente | O que faz |
|---|---|
| `reversa-debugger` | Intake, triagem, dedupe, classificação e rastreabilidade SPEC↔CODE↔TEST↔BUG |
| `reversa-debugger-fix` | Propõe correção, aguarda aprovação, aplica e valida |
| `reversa-debugger-debate` | Debate adversarial: valida se a causa-raiz diagnosticada é a real |
| `reversa-debugger-graph` | Gera grafo de causalidade do bug |

---

### Fluxo 4 — Novo Projeto (Greenfield)

```
/reversa-new             ← da ideia ao PRD + specs
/reversa-new expresso    ← entrevista única, sem pausas
```

**Sub-agentes ativados automaticamente:**
| Agente | O que faz |
|---|---|
| `reversa-brainstorm` | Clarifica ideia bruta antes de qualquer artefato |
| `reversa-ideator` | Gera variações e alternativas de solução |
| `reversa-challenger` | Questiona premissas e faz premortem |
| `reversa-drafter` | Produz o rascunho inicial do PRD |
| `reversa-pre-spec` | Extrai specs preliminares do PRD |

---

### Fluxo 5 — Documentação Visual

```
/reversa-docs
```
Gera mini-site HTML autocontido em `_reversa_docs/` com arquitetura 3D, dashboards, glossário e deck de apresentação.

| Agente | O que faz |
|---|---|
| `reversa-docs` | Orquestra o time de documentação |
| `reversa-docs-analyst` | Analisa o SDD e extrai pontos-chave para documentar |
| `reversa-docs-mapper` | Cria o mapa de navegação do mini-site |
| `reversa-docs-publisher` | Publica o mini-site final |
| `reversa-docs-storyteller` | Escreve narrativa para o deck de apresentação |
| `reversa-visor` | Visualizador interativo do grafo de specs |
| `reversa-arquitetura-3d` | Gera visualização 3D da arquitetura do sistema |

---

### Fluxo 6 — Refatoração e Qualidade

```
/reversa-refactor
```
Inventaria oportunidades de melhoria por ROI real (hotpath, não estética).

| Agente | O que faz |
|---|---|
| `reversa-refactor` | Orquestra o time Code Quality |
| `reversa-optimize` | Identifica gargalos de performance |
| `reversa-decouple` | Mapeia acoplamento excessivo entre módulos |
| `reversa-modularize` | Propõe extração de módulos coesos |
| `reversa-simplify` | Detecta complexidade desnecessária |
| `reversa-prune` | Identifica código morto e dependências órfãs |
| `reversa-standardize` | Padronização de nomenclatura e convenções |
| `reversa-restructure` | Reorganização de estrutura de pastas |
| `reversa-principles` | Valida aderência a SOLID, Clean Architecture |

---

### Fluxo 7 — Migração

```
/reversa-migrate
```
Planeja migração de sistema legado após o Discovery estar completo.

| Agente | O que faz |
|---|---|
| `reversa-migrate` | Orquestra o time de Migração |
| `reversa-paradigm-advisor` | Aconselha sobre paradigma-alvo (ex: de imperativo para reativo) |
| `reversa-curator` | Seleciona o que migrar primeiro por valor de negócio |
| `reversa-strategist` | Cria estratégia de migração incremental sem quebrar prod |
| `reversa-designer` | Projeta a nova arquitetura-alvo |
| `reversa-screen-translator` | Traduz telas legadas para novo framework |
| `reversa-reconstructor` | Reconstrói módulos do zero a partir das specs |

---

### Agentes de Apoio (invocáveis diretamente)

| Comando | O que faz |
|---|---|
| `/reversa-agents-help` | Catálogo interativo de todos os agentes com analogias |
| `/reversa-resume` | Retoma sessão interrompida do ponto exato onde parou |
| `/reversa-arbiter` | Resolve conflitos entre agentes com visões diferentes |
| `/reversa-researcher` | Pesquisa referências externas para embasar decisões técnicas |
| `/reversa-pricing-estimate` | Estima custo de desenvolvimento da feature |
| `/reversa-pricing-profile` | Perfila o projeto para estimativas mais precisas |
| `/reversa-pricing-size` | Dimensiona a complexidade da feature (P, M, G, GG) |
| `/reversa-n8n` | Gera workflows de automação n8n a partir das specs |
| `/reversa-data-master` | Projeta e documenta o modelo de dados |
| `/reversa-framer` | Cria wireframes textuais das telas |
| `/reversa-extract-soul` | Extrai a "essência" de negócio do sistema legado |

---

### Agentes Visuais e de Dados

| Comando | O que faz |
|---|---|
| `/reversa-especialista-d3` | Gera visualizações D3.js a partir dos dados do projeto |
| `/reversa-highcharts-visualizer` | Gera dashboards Highcharts |
| `/reversa-image-prompt-json` | Gera prompts JSON para geração de imagens de UI |
| `/reversa-selo-generativo` | Cria selos/badges generativos do projeto |
| `/reversa-design-system` | Documenta e/ou cria design system para o projeto |

---

## Estrutura do Projeto

```
MistakeMap/
├── appmistakemap/           # Cliente Flutter/Dart
│   ├── lib/
│   │   ├── core/
│   │   │   └── constants/   # about_content.dart, app_constants.dart
│   │   └── features/        # Telas por funcionalidade
│   └── test/
├── worker/                  # Worker Rust (OCR + LLM)
│   └── src/
├── harness.yaml             # Harness de loops autônomos
├── CLAUDE.md                # Este arquivo
├── AGENTS.md                # Entrada para Codex e outros agentes
├── GEMINI.md                # Entrada para Gemini CLI
├── BACKEND.md               # Decisões de arquitetura do backend
├── .reversa/                # Estado e configuração do Reversa
│   ├── state.json           # Estado atual (fase, checkpoints, agentes)
│   ├── config.toml          # Configuração do projeto
│   ├── reversa-config.json  # Política de edição de arquivos legados
│   └── hooks.yml            # Hooks de CI nos gates do ciclo forward
├── _reversa_sdd/            # Especificações geradas (Discovery)
├── _reversa_forward/        # Features em evolução (Forward)
├── _reversa_bugs/           # Registro de defeitos
├── _reversa_docs/           # Mini-site de documentação
└── _reversa_refactor/       # Oportunidades de refatoração
```

---

## Guia de Decisão — Qual Fluxo Usar?

```
Tenho código existente e quero entender o que ele faz?
  → /reversa (Discovery)

Quero implementar uma nova feature com qualidade?
  → /reversa-forward

Encontrei um bug?
  → /reversa-debugger (registra) → /reversa-debugger-fix (corrige)

Quero começar um módulo do zero?
  → /reversa-new

Quero melhorar a qualidade do código existente?
  → /reversa-refactor

Quero gerar documentação visual para apresentar?
  → /reversa-docs

Preciso repetir uma transformação em N arquivos?
  → /loop (Loop de Turno)

Tenho um problema aberto sem caminho claro?
  → /goal (Loop de Objetivo)

Quero uma rotina automática recorrente?
  → /schedule (Loop de Tempo)
```

---

## Comportamento ao ativar agentes Reversa

Quando o usuário digitar `/reversa` ou qualquer `/reversa-*`:

1. Ative o skill correspondente em `.claude/skills/<nome>/SKILL.md`
2. Se não encontrar em `.claude/skills/`, tente `.agents/skills/<nome>/SKILL.md`
3. Leia o `SKILL.md` na íntegra e siga exatamente as instruções

**Regra de escrita:**  
Antes de modificar qualquer arquivo fora das pastas `_reversa_*/` e `.reversa/`, leia `.reversa/reversa-config.json`. Com `allowLegacyEdits: false` (padrão atual), recuse qualquer escrita fora dessas pastas e informe o usuário como liberar.
