# ai/ — Portal Central de Inteligência Artificial

> Ponto de entrada para entender, configurar e operar todos os recursos de IA instalados no MistakeMap.

---

## O que está instalado

| Recurso | Localização real | Para que serve |
|---|---|---|
| **Claude Code** — entry file | [`/CLAUDE.md`](../CLAUDE.md) | Guia completo de agentes, loops e regras do projeto |
| **Codex / OpenAI** — entry file | [`/AGENTS.md`](../AGENTS.md) | Entrada alternativa para agentes OpenAI |
| **Gemini CLI** — entry file | [`/GEMINI.md`](../GEMINI.md) | Entrada para Gemini CLI |
| **Harness** — configuração | [`ai/harness.yaml`](harness.yaml) | Limites de tokens, custo, ciclos e sandbox |
| **Reversa** — estado | [`/.reversa/`](../.reversa/) | Estado, config e hooks do framework Reversa |
| **Reversa** — skills Claude | [`/.claude/skills/`](../.claude/skills/) | 63 agentes para Claude Code |
| **Reversa** — skills outros | [`/.agents/skills/`](../.agents/skills/) | 63 agentes para Codex e outros engines |
| **Artefatos Discovery** | `/_reversa_sdd/` | Especificações extraídas do código |
| **Artefatos Forward** | `/_reversa_forward/` | Features em desenvolvimento |
| **Artefatos Bugs** | `/_reversa_bugs/` | Registro de defeitos |
| **Artefatos Docs** | `/_reversa_docs/` | Mini-site de documentação visual |
| **Artefatos Refactor** | `/_reversa_refactor/` | Oportunidades de melhoria |

> **Por que os arquivos funcionais não estão aqui?**  
> Claude Code, Codex, Gemini CLI e o framework Reversa lêem seus arquivos em caminhos fixos e obrigatórios (raiz do projeto). Mover quebraria todas as ferramentas. Esta pasta é o portal de documentação e configuração — não substitui os caminhos de convenção.

---

## Engines suportadas

| Engine | Arquivo de entrada | Como ativar |
|---|---|---|
| Claude Code (CLI) | `CLAUDE.md` | `claude` na raiz do projeto |
| Codex | `AGENTS.md` | `codex` na raiz |
| Gemini CLI | `GEMINI.md` | `gemini` na raiz |
| Hermes | `CLAUDE.md` / `AGENTS.md` | configurado em `.reversa/state.json` |

---

## Guia Rápido — Qual comando usar?

```
Entender o código existente?         →  /reversa
Implementar uma nova feature?        →  /reversa-forward
Registrar ou corrigir um bug?        →  /reversa-debugger  /reversa-debugger-fix
Começar um módulo do zero?           →  /reversa-new
Gerar documentação visual?           →  /reversa-docs
Melhorar qualidade do código?        →  /reversa-refactor
Planejar migração?                   →  /reversa-migrate
Repetir transformação em N arquivos? →  /loop
Resolver problema aberto?            →  /goal
Rotina automática recorrente?        →  /schedule
Ver catálogo de todos os agentes?    →  /reversa-agents-help
```

---

## Harness — Limites Ativos

Arquivo: [`ai/harness.yaml`](harness.yaml)

| Recurso | Limite |
|---|---|
| Tokens por execução | 50.000 |
| Custo por execução | US$ 0,50 |
| Ciclos máximos | 10 |
| Stall sem progresso | aborta em 3 ciclos |
| Execução autônoma | habilitada, máx. 120 min |
| Escrita permitida | `appmistakemap/`, `worker/src/`, `_reversa_*/`, `.reversa/` |

---

## Reversa — 63 Agentes por Fluxo

### Discovery (extrair specs do código)
`/reversa` · `/reversa-autonomous`  
Agentes: scout → archaeologist → detective → architect → writer → reviewer  
+ explorer, inspector, depth-inspection, spec-sdd

### Forward (specs → código)
`/reversa-forward`  
Pipeline: requirements → clarify → plan → to-do → audit → quality → coding → add → sync  
+ code-express

### Bugs
`/reversa-debugger` · `/reversa-debugger-fix`  
+ debugger-debate, debugger-graph

### Greenfield (projeto novo)
`/reversa-new` · `/reversa-new expresso`  
+ brainstorm, ideator, challenger, drafter, pre-spec

### Documentação visual
`/reversa-docs`  
+ docs-analyst, docs-mapper, docs-publisher, docs-storyteller, visor, arquitetura-3d

### Qualidade e refatoração
`/reversa-refactor`  
+ optimize, decouple, modularize, simplify, prune, standardize, restructure, principles

### Migração
`/reversa-migrate`  
+ paradigm-advisor, curator, strategist, designer, screen-translator, reconstructor

### Apoio e estimativas
reversa-agents-help · reversa-resume · reversa-arbiter · reversa-researcher  
reversa-pricing-estimate · reversa-pricing-profile · reversa-pricing-size  
reversa-data-master · reversa-framer · reversa-extract-soul · reversa-n8n

### Visuais e dados
reversa-especialista-d3 · reversa-highcharts-visualizer · reversa-image-prompt-json  
reversa-selo-generativo · reversa-design-system

---

## Critérios de Aceitação Padrão

**Flutter/Dart**
```bash
flutter test --reporter compact   # AC1 — All tests passed
flutter analyze                   # AC2 — No issues found
dart format --set-exit-if-changed lib/  # AC3 — exit 0
```

**Worker Rust**
```bash
cargo test          # AC1
cargo clippy -- -D warnings  # AC2
cargo check         # AC3
```

---

## Regras de Segurança dos Agentes

1. Agentes **nunca modificam** arquivos fora de `_reversa_*/` e `.reversa/` por padrão.
2. Para liberar edições no código-fonte, o usuário deve editar `.reversa/reversa-config.json` manualmente.
3. O harness bloqueia escrita em `.env`, `secrets/` e qualquer caminho fora do projeto.
4. Loops autônomos abortam após 3 ciclos sem progresso nos ACs.
