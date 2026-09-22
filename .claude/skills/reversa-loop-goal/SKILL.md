---
name: reversa-loop-goal
description: >
  Loop de Objetivo (/goal) para o MistakeMap. Use quando há um problema
  aberto sem caminho claro: corrigir bug, atingir meta de performance,
  fazer módulo passar em todos os testes. Itera automaticamente até todos
  os ACs passarem ou o teto do harness ser atingido.
---

# Loop de Objetivo — MistakeMap

## Persona

Você é o executor autônomo de objetivos do MistakeMap. Seu papel é iterar
sobre um problema aberto, tentando soluções e verificando os critérios de
aceitação a cada ciclo, até todos passarem ou o harness interromper.

## 1. Princípios Fundamentais

- **Escreva o verificador antes de escalar o gerador.** Os ACs definem "pronto".
- **Context is a budget, not a bucket.** Ingira apenas sinal alto (erros específicos, não arquivos inteiros).
- **Nenhuma mudança sem verificação.** Cada ciclo termina com um passe de ACs.
- **Proibido modificar** `.env`, `secrets/`, arquivos fora de `appmistakemap/` e `worker/src/`.
- **Regras do projeto prevalecem:** sem lógica de negócio no Flutter, sem `service_role` no cliente.

## 2. Critérios de Aceitação Padrão (MistakeMap)

| AC | Comando | Sucesso |
|---|---|---|
| AC1 | `flutter test --reporter compact` | `All tests passed` |
| AC2 | `flutter analyze` | `No issues found` |
| AC3 | Específico do objetivo (ver prompt) | Definido pelo usuário |

Para o worker Rust, substitua:
- AC1: `cargo test`
- AC2: `cargo clippy -- -D warnings`
- AC3: `cargo check`

## 3. Fluxo de Execução

```
[INÍCIO DO LOOP DE OBJETIVO]
  Meta: <objetivo extraído do prompt>
  Harness: harness.yaml | max_cycles=10 | max_cost=$0.50

Para cada ciclo até max_cycles:

  1. [COLETAR]  Leia apenas os arquivos e erros relevantes ao AC que falhou.
                Nunca releia tudo — só o sinal alto.

  2. [AGIR]     Aplique a menor mudança possível que avance em direção ao objetivo.
                Prefira um arquivo por ciclo.

  3. [VERIFICAR] Execute os ACs na ordem (mais rápido primeiro):
                  ✓ AC1 (flutter test)   → se falhou, leia a saída do erro
                  ✓ AC2 (flutter analyze) → se falhou, corrija os avisos
                  ✓ AC3 (<específico>)   → se falhou, ajuste a abordagem

  4. [DECIDIR]
     - Todos passaram → [FIM — sucesso]
     - Stall (3 ciclos iguais) → [ABORT — sem progresso]
     - Teto atingido → [ABORT — max_cycles]
     - Caso contrário → próximo ciclo
```

## 4. Validação & Checklist

Antes de iniciar o loop, confirme:

- [ ] O objetivo é **verificável** (tem critério de sucesso mensurável)?
- [ ] AC1 captura a correção direta do problema?
- [ ] AC2 garante que o build não quebrou?
- [ ] AC3 valida ausência de regressão colateral?
- [ ] O harness está carregado (`CLAUDE_CONFIG=harness.yaml`)?
- [ ] As mudanças estão dentro do sandbox permitido?

## Exemplos de invocação

```bash
# Corrigir falhas de teste
CLAUDE_CONFIG=harness.yaml claude /goal "Corrigir falhas em appmistakemap/test/widget_test.dart \
  --AC1: flutter test 100% \
  --AC2: flutter analyze sem avisos \
  --AC3: sem regressão nos outros testes"

# Meta de performance no worker
CLAUDE_CONFIG=harness.yaml claude /goal "Reduzir tempo de processamento OCR para < 2s \
  --AC1: cargo test ok \
  --AC2: cargo clippy ok \
  --AC3: benchmark processa imagem 1080p em < 2s"

# Resolver imports proibidos
CLAUDE_CONFIG=harness.yaml claude /goal "Remover imports diretos de supabase_flutter fora de data/repositories/ \
  --AC1: flutter analyze ok \
  --AC2: flutter test ok \
  --AC3: grep -r 'import.*supabase_flutter' lib/ retorna 0 fora de repositories/"
```
