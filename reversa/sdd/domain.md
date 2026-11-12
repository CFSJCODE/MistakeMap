# Domínio do MistakeMap

> Nível: Essencial. Evidências do código são marcadas como confirmadas; regras
> do produto fornecidas no briefing são distinguidas das funcionalidades já
> implementadas.

## Propósito

O MistakeMap deve transformar exercícios corrigidos em um mapa temporal de
fragilidades conceituais, recorrência e evolução. A intenção é orientar estudo
e revisão, não resumir o estudante a uma nota. O estudante registra uma
resolução manual ou por foto, confere as sugestões de análise e usa o histórico
para escolher o próximo reforço.

O cliente já registra tentativas, solicita análise multimodal e apresenta mapa
de conceitos/erros. Revisão validada pelo estudante, flashcards, rodada de quiz
com métricas agregadas e geração estritamente fundamentada em enunciados
existentes permanecem lacunas.

## Glossário

| Termo | Significado |
|---|---|
| Estudante | Conta autenticada proprietária de matérias, exercícios e tentativas. |
| Matéria | Contexto de estudo do estudante; contém conceitos e exercícios. |
| Exercício | Enunciado imutável depois de receber uma tentativa ou gabarito de prática. |
| Tentativa | Resposta ou resolução do estudante para um exercício, com data e estado de processamento. |
| Conceito | Unidade de conhecimento associada à matéria e aos exercícios. |
| Tipo de erro | Taxonomia aplicada a uma evidência específica da tentativa. |
| Evento de erro | Sugestão de erro associada a uma tentativa, conceito, evidência, confiança e estado de revisão. |
| Evento de domínio | Evidência temporal de acerto usada para reduzir a prioridade de revisão; atualmente o evento é sugerido pela IA. |
| Mapa de erros | Agregação visual por matéria, conceito e tipo de erro. As conexões atuais representam coocorrência, não pré-requisito. |
| Conjunto de prática | Lote de 3 a 5 exercícios gerados para uma matéria, opcionalmente focados em categoria/conceito prioritário. |
| Gabarito de prática | Resposta e explicação privada ao servidor até a tentativa ser analisada. |
| Caderno local | CRUD offline de registros manuais; é separado dos eventos de análise que alimentam o mapa de IA. |
| Rodada de quiz | Sessão de resolução sequencial com resultado agregado; desejada no briefing, mas não representada como entidade hoje. |

## Taxonomia observada

Categorias no contrato e no banco:

1. `calculo`
2. `conceito`
3. `sinal`
4. `interpretacao`
5. `procedimento`
6. `unidade`
7. `outro`

O briefing cita negação lógica e condição de contorno como padrões relevantes.
Não há categorias próprias para esses casos; o contrato atual precisa mapeá-los
para categorias existentes ou receber uma mudança coordenada no backend e no
cliente.

## Regras de domínio observadas

### Tentativa e análise

- 🟢 A tentativa pertence ao usuário e a um exercício de uma matéria do mesmo
  usuário. A análise só processa texto ou imagem legível dentro dos limites
  definidos pelo backend.
- 🟢 A IA pode concluir `is_correct=true`, `false` ou `null`. `null` significa
  que não há evidência suficiente e não deve fabricar erros.
- 🟢 Erro sugerido precisa trazer categoria, conceito declarado, evidência e
  confiança. A confiança é estimativa, não probabilidade calibrada.
- 🟢 A resposta correta sugerida pela IA é referência sujeita a revisão. Os
  eventos de erro são gravados como `pending`; o código ainda não oferece ação
  persistente do estudante para confirmar, corrigir ou rejeitar cada evento.
- 🟡 O mapa atual agrupa por tentativas distintas, matéria, conceito e
  categoria. Arestas representam coocorrência na tentativa e não relações
  causais, sequência didática ou pré-requisitos.
- 🟢 `completed` significa que a análise terminou; não significa que a resposta
  está correta nem que o erro sugerido foi validado.

### Prioridade de revisão e evolução

- 🟢 O gerador consulta até 50 análises incorretas da matéria e ordena conceitos
  por erros ponderados pela recência. Um erro de 14 dias tem metade do peso de
  um erro atual.
- 🟢 Acertos posteriores ao erro mais recente reduzem a prioridade; três
  acertos removem o conceito da lista prioritária. Datas de tentativas, não de
  execução da análise, preservam a ordem histórica.
- 🟡 A função atual calcula `score = soma(peso de recência) × (1 − mastery)`.
  A fórmula `P = F × R × I × (1 − M)` aparece na documentação do projeto, mas
  o cálculo implementado não usa `importance` (`I`) como fator explícito.
- 🟡 Eventos de domínio são gravados automaticamente para acerto sugerido pela
  IA; portanto, o cálculo de recuperação não depende de confirmação humana.
  Isso diverge do objetivo de atualizar o mapa somente após validação do
  estudante.

### Prática e aprendizagem

- 🟢 O gerador retorna de 3 a 5 exercícios distintos, com enunciado, dificuldade
  (`facil`, `media`, `dificil`), conceito focal, resposta e explicação. A chave
  não é exposta no retorno ao cliente.
- 🔴 Com erros históricos, a geração recebe categoria, conceito e trechos de
  evidência, mas não os enunciados originais. Sem erro pendente, usa somente o
  nome da matéria. Assim, a regra solicitada de que todo exercício gerado se
  baseie em exercícios já existentes não está garantida.
- 🔴 O app não apresenta uma rodada de quiz com contagem/percentual de acertos e
  erros, assuntos mais errados e opção de iniciar outra rodada a partir do
  resultado.
- 🔴 Não foram localizados flashcards nem uma trilha de revisão teórica
  integrada aos conceitos prioritários.
- 🟢 Não há nota global do estudante no fluxo de domínio analisado. A prática
  atual analisa tentativas individuais; métricas de rodada ainda não existem.

### Persistência offline

- 🟢 O caderno manual local possui CRUD e sincronização, mas sua taxonomia é
  independente da análise de IA e não alimenta diretamente o mapa de erros.
- 🟢 Conflitos de sincronização obedecem ao servidor; edição offline de
  exercício já analisado é recusada para preservar o diagnóstico associado ao
  enunciado original.

## Decisões e lacunas prioritárias

| Prioridade | Lacuna | Evidência / consequência |
|---|---|---|
| P0 | Validação do estudante | `error_events` ficam `pending`, sem fluxo cliente para confirmar/corrigir/rejeitar; a recuperação também conta acertos sugeridos pela IA. |
| P0 | Exercícios de prática fundamentados | Os prompts não recebem os exercícios-fonte e o caminho sem erros usa apenas a matéria. |
| P1 | Rodada de quiz e métricas | Não há sessão de rodada nem resumo agregado com percentual e assuntos mais errados. |
| P1 | Revisão teórica e flashcards | Não há materiais ligados aos conceitos prioritários. |
| P1 | Taxonomia do briefing | Negação lógica e condição de contorno não têm categorias próprias. |
| P2 | Evolução temporal explícita | Há filtros temporais e timestamps, mas não uma série temporal de evolução validada pelo estudante. |
| P2 | Integração do caderno manual | Registros locais não se tornam eventos do mapa de IA. |
