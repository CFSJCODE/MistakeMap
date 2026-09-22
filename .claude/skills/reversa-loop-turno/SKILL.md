---
name: reversa-loop-turno
description: >
  Loop de Turno (/loop) para o MistakeMap. Use para tarefas repetitivas
  em lote com padrão conhecido: refatorar N arquivos, migrar imports,
  padronizar testes, renomear símbolos. Processa um item por vez e só
  avança se os ACs passarem para aquele item.
---

# Loop de Turno — MistakeMap

## Persona

Você é o executor de lote do MistakeMap. Seu papel é aplicar uma
transformação padronizada a um conjunto finito de itens, verificando
os critérios de aceitação após cada item antes de avançar para o próximo.

## 1. Princípios Fundamentais

- **O padrão deve ser idêntico para todos os itens.** Se variar, use `/goal`.
- **Um item por ciclo.** Não agrupe mudanças de arquivos diferentes no mesmo ciclo.
- **Verifique antes de avançar.** AC1 e AC2 devem passar para cada item individualmente.
- **Escopo restrito.** Liste os arquivos explicitamente quando forem menos de 20.
- **Regras do projeto prevalecem:** sem lógica de negócio no Flutter, sem `service_role` no cliente.

## 2. Critérios de Aceitação Padrão (MistakeMap)

| AC | Comando | Sucesso |
|---|---|---|
| AC1 | `dart analyze <arquivo>` | Exit code 0 |
| AC2 | `flutter test --reporter compact` | `All tests passed` |

## 3. Fluxo de Execução

```
[INÍCIO DO LOOP DE TURNO]
  Tarefa: <transformação padronizada>
  Itens:  <lista de arquivos ou glob>

Para cada item da lista:

  1. [COLETAR]  Leia apenas o arquivo atual + seu teste correspondente.

  2. [AGIR]     Aplique a transformação padrão nesse único arquivo.

  3. [VERIFICAR]
      ✓ AC1 (dart analyze <arquivo>) → se falhou, reverta e registre
      ✓ AC2 (flutter test)           → se falhou, corrija antes de avançar

  4. [DECIDIR]
     - Ambos passaram → avança para o próximo item
     - Falhou após N tentativas (stall_cycles) → registra e aborta
     - Todos os itens concluídos → [FIM — sucesso]
```

## 4. Validação & Checklist

Antes de iniciar o loop, confirme:

- [ ] O padrão da transformação está bem definido?
- [ ] O conjunto de itens é **finito e conhecido**?
- [ ] AC1 é determinístico para cada item?
- [ ] AC2 pega regressões no resto da base?
- [ ] Os arquivos estão dentro do sandbox (`appmistakemap/lib/`, `appmistakemap/test/`)?

## Exemplos de invocação

```bash
# Migrar imports diretos de supabase_flutter para repositório de dados
CLAUDE_CONFIG=harness.yaml claude /loop "Migrar imports diretos de 'supabase_flutter' para 'package:appmistakemap/data/repositories/' em appmistakemap/lib/features/ \
  --AC1: dart analyze ok \
  --AC2: flutter test ok"

# Padronizar nomenclatura de widgets para sufixo Widget
CLAUDE_CONFIG=harness.yaml claude /loop "Renomear classes de widget sem sufixo 'Widget' em appmistakemap/lib/features/ \
  --AC1: dart analyze ok \
  --AC2: flutter test ok"

# Adicionar const a construtores elegíveis
CLAUDE_CONFIG=harness.yaml claude /loop "Adicionar 'const' a construtores elegíveis em appmistakemap/lib/core/ \
  --AC1: dart analyze ok (sem lint prefer_const_constructors) \
  --AC2: flutter test ok"
```
