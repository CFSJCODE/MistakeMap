# Análise de exercícios, mapa e prática

## Visão Geral

Esta unit permite registrar exercícios e resoluções por texto ou imagem, solicitar diagnóstico de IA, consultar agregações de erros e gerar prática direcionada. A análise é uma sugestão e deve ser conferida; o fluxo atual ainda não persiste confirmação do estudante nem oferece métricas de uma rodada de quiz. 🟢/🔴

## Responsabilidades

- Criar/listar tentativas e anexar fotografia corrigida. 🟢
- Exibir correção, transcrição, conceitos e evidências sugeridas. 🟢
- Agregar padrões por matéria, conceito e categoria e filtrar período. 🟢
- Solicitar de 3 a 5 exercícios de prática e ocultar gabarito antes da resolução. 🟢
- Confirmar, corrigir ou rejeitar cada evento de erro. 🔴
- Apresentar rodada com acertos, erros, percentuais e assuntos frágeis. 🔴

## Regras de Negócio

- `is_correct=null` representa resultado inconclusivo, não erro nem acerto. 🟢
- Frequência do mapa conta tentativas distintas; ligações representam coocorrência e não pré-requisito. 🟢
- Fotos JPEG, PNG e WebP são validadas por assinatura e limitadas a 8 MB. 🟢
- Prática admite 3–5 itens; respostas corretas não são entregues ao cliente na geração. 🟢
- Exercícios gerados devem derivar de enunciados existentes e relevantes. 🔴
- Evolução do mapa deve depender de revisão do estudante. 🔴

## Requisitos Funcionais

> RF-01 a RF-05 descrevem o comportamento existente; RF-06 a RF-08 são requisitos-alvo do produto e continuam lacunas 🔴 até implementação e validação.

| ID | Requisito | Prioridade | Critério de Aceite |
|---|---|---|---|
| RF-01 | Registrar tentativa em texto ou foto e associá-la a matéria/exercício. 🟢 | Must | Tentativa fica persistida e acessível ao proprietário. |
| RF-02 | Enviar imagem válida e solicitar análise autenticada. 🟢 | Must | Bytes íntegros são enviados; tentativa recebe estado/resultado do backend. |
| RF-03 | Apresentar resultado, explicação, conceitos, evidências e incerteza da IA. 🟢 | Must | `null` é exibido como inconclusivo, sem afirmar acerto ou erro. |
| RF-04 | Construir mapa temporal filtrável por matéria/período. 🟢 | Must | Agregações evitam dupla contagem da mesma tentativa. |
| RF-05 | Gerar prática de 3–5 itens focalizada em matéria/categoria. 🟢 | Must | Item pode ser respondido sem revelar gabarito antecipadamente. |
| RF-06 | Validar/corrigir/rejeitar eventos de erro antes de atualizar fragilidade. 🔴 | Must | Registrar revisão auditável e usar somente eventos validados na evolução do mapa. |
| RF-07 | Encerrar rodada mostrando contagem e percentual de acertos/erros, tópicos mais frágeis e opção de repetir. 🔴 | Must | Persistir rodada, apresentar métricas e permitir iniciar outra rodada. |
| RF-08 | Derivar toda questão de prática de exercícios-fonte já existentes. 🔴 | Must | Cada questão tem fonte verificável e não é gerada sem fonte elegível. |

## Requisitos Não Funcionais

| Tipo | Requisito inferido | Evidência no código | Confiança |
|---|---|---|---|
| Segurança | Gabarito de prática não é exposto no retorno de geração. | `appmistakemap/lib/ai/analysis_repository.dart`, Edge Function de prática | 🟢 |
| Disponibilidade | Tentativa pode ser enfileirada para envio após reconexão. | `appmistakemap/lib/ai/analysis_repository.dart`, `appmistakemap/lib/sync/` | 🟢 |
| Usabilidade | Formulário permite texto e captura/seleção de foto. | `appmistakemap/lib/ai/exercise_submission_view.dart` | 🟢 |

## Critérios de Aceitação

```gherkin
Dado um exercício e uma resolução em texto
Quando o estudante envia a tentativa
Então ela é persistida e a análise é solicitada

Dado uma foto JPEG, PNG ou WebP menor ou igual a 8 MB
Quando o estudante anexa a foto
Então o app envia o arquivo e solicita análise da tentativa

Dado uma imagem inválida ou acima do limite
Quando o estudante tenta enviá-la
Então o app informa a falha e não trata o upload como concluído

Dado uma análise com is_correct nulo
Quando o detalhe da tentativa é apresentado
Então o resultado permanece inconclusivo e as evidências são identificadas como sugestão

Dado tentativas com erros repetidos em um conceito
Quando o estudante abre o mapa e filtra período/matéria
Então o conceito aparece agregado sem contar duas vezes a mesma tentativa

Dado um conjunto de prática solicitado com quantidade entre 3 e 5
Quando o estudante o recebe
Então as questões são exibidas sem resposta correta antes da resolução

Dado uma rodada de prática finalizada
Quando o estudante solicita métricas agregadas
Então o sistema as apresenta
```

O último cenário é requisito-alvo 🔴, não comportamento existente no legado.

## Prioridade (MoSCoW)

| Requisito | MoSCoW | Justificativa |
|---|---|---|
| Registrar, analisar e apresentar tentativa | Must | Fluxo central do produto e entrada do mapa. |
| Agregar mapa com filtro temporal | Must | Principal visualização da fragilidade. |
| Prática individual sem expor gabarito | Must | Caminho de reforço implementado. |
| Validação humana e rodada de métricas | Must | Caminhos centrais explicitamente descritos no objetivo do produto; ainda não implementados. |
| Exercícios fundamentados em fontes existentes | Must | Restrição explícita do briefing; ainda não garantida pelo gerador atual. |

## Rastreabilidade de Código

| Arquivo | Função / Classe | Cobertura |
|---|---|---|
| `appmistakemap/lib/ai/analysis_repository.dart` | CRUD, upload, análise e geração de prática | 🟢 |
| `appmistakemap/lib/ai/exercise_submission_view.dart` | Formulário de exercício/tentativa | 🟢 |
| `appmistakemap/lib/ai/analysis_models.dart` | Modelos e `ErrorInsights.fromAttempts` | 🟢 |
| `appmistakemap/lib/ai/insights_view.dart` | Mapa e filtros | 🟢 |
| `appmistakemap/lib/ai/ai_material_shell.dart` | Shell de navegação da área de IA | 🟢 |
