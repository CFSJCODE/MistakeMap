<a id="readme-top"></a>

<div align="center">

# MistakeMap

### Transforme cada erro em um mapa do que estudar a seguir.

O **MistakeMap** lê a sua resolução, aponta **onde** e **por que** você errou, conecta esses erros aos conceitos certos e monta um plano de estudo a partir deles. Funciona no celular, no computador e no navegador, inclusive sem internet.

[![Abrir a versão web](https://img.shields.io/badge/Experimente%20agora-mistakemap--tau.vercel.app-000000?style=for-the-badge&logo=vercel&logoColor=white)](https://mistakemap-tau.vercel.app/)

![Flutter](https://img.shields.io/badge/Flutter-3.47.2-02569B?style=flat-square&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?style=flat-square&logo=dart&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-Auth%20%C2%B7%20Postgres%20%C2%B7%20Realtime-3FCF8E?style=flat-square&logo=supabase&logoColor=white)
![Deno](https://img.shields.io/badge/Edge%20Functions-Deno%202-000000?style=flat-square&logo=deno&logoColor=white)
![Gemini](https://img.shields.io/badge/IA-Google%20Gemini-8E75B2?style=flat-square&logo=googlegemini&logoColor=white)
![Claude](https://img.shields.io/badge/IA-Claude%20Sonnet%205.5-D97757?style=flat-square&logo=anthropic&logoColor=white)
![OpenRouter](https://img.shields.io/badge/IA-OpenRouter-6566F1?style=flat-square&logo=openrouter&logoColor=white)
![Cloudflare R2](https://img.shields.io/badge/Arquivos-Cloudflare%20R2-F38020?style=flat-square&logo=cloudflare&logoColor=white)
![SQLite](https://img.shields.io/badge/Offline-SQLite-003B57?style=flat-square&logo=sqlite&logoColor=white)
![Shorebird](https://img.shields.io/badge/Atualiza%C3%A7%C3%B5es-Shorebird-2F6FE4?style=flat-square)
![Vercel](https://img.shields.io/badge/Web-Vercel-000000?style=flat-square&logo=vercel&logoColor=white)
![Plataformas](https://img.shields.io/badge/Plataformas-Android%20%C2%B7%20Windows%20%C2%B7%20Web-3DDC84?style=flat-square)

![Status](https://img.shields.io/badge/Status-MVP%20funcional-F59E0B?style=flat-square)
![Versão](https://img.shields.io/badge/Versão-1.0.0-0A7F5A?style=flat-square)
[![Licença](https://img.shields.io/badge/Licença-PolyForm%20Noncommercial%201.0.0-6B7280?style=flat-square)](LICENSE)
![PUC Minas](https://img.shields.io/badge/Projeto%20Acadêmico-PUC%20Minas-003B71?style=flat-square)

[Por que o MistakeMap](#por-que) · [Como funciona](#como-funciona) · [Funcionalidades](#funcionalidades) · [Arquitetura](#arquitetura) · [Atualizações](#atualizacoes) · [Começar](#comecar) · [Roadmap](#roadmap)

</div>

---

<a id="por-que"></a>

## Por que o MistakeMap

> **A nota diz que você errou. O MistakeMap diz o que fazer com isso.**

Quem estuda resolvendo exercícios conhece o ciclo: a prova volta corrigida, o aluno olha a nota, guarda a folha e repete o mesmo deslize semanas depois. O problema não é falta de esforço. É que **ninguém organiza os erros**: eles ficam espalhados em cadernos, provas e listas, e o padrão por trás deles nunca aparece.

O MistakeMap trata cada erro como um **dado de aprendizagem**:

| Sem o MistakeMap | Com o MistakeMap |
|:---|:---|
| "Errei a questão 4." | "Pela terceira vez em duas semanas, troquei o sinal ao isolar a variável em Cálculo." |
| Revisar tudo, ou revisar o que parece mais difícil | Revisar primeiro o que **mais se repete, mais recentemente e com menos sinal de recuperação** |
| Exercícios genéricos do livro | Exercícios **gerados para o seu tipo de erro**, com gabarito conferido no servidor |
| Anotações soltas que se perdem | Um **caderno de erros** que funciona offline e acompanha você em qualquer aparelho |

### Para quem

- **Estudantes** do ensino fundamental (7º ao 9º ano), do ensino médio, do ensino superior e **autodidatas**: a tela Aprender já organiza as matérias dessas quatro etapas.
- **Cursos de exatas e engenharias**, onde o erro de procedimento (sinal, unidade, condição de contorno) custa caro e se repete.
- **Professores, tutores e instituições** (próxima fase): visão agregada dos padrões de erro de uma turma, sempre com compartilhamento explícito e revogável pelo aluno.

### O que torna o produto diferente

| Diferencial | O que significa na prática |
|:---|:---|
| 🧭 **Erro com evidência** | Cada erro apontado pela IA vem com o trecho da resolução que o justifica e um nível de confiança. Nada de "está errado" sem explicação. |
| 🧑‍🏫 **O aluno decide** | A IA sugere hipóteses ("padrão sugerido"), o estudante confirma. O mapa nunca vira rótulo permanente. |
| 📶 **Offline de verdade** | Exercícios, tentativas e o caderno funcionam sem rede e sincronizam sozinhos quando a conexão volta. |
| 🔁 **Recuperação conta** | Acertar de novo um conceito reduz o peso dele no plano de estudo. O mapa mostra melhora, não só fragilidade. |
| 🔒 **Privado por padrão** | Os dados educacionais pertencem ao estudante. Isolamento por conta no próprio banco (RLS) e gabaritos que o cliente nunca enxerga. |
| 🔄 **Sempre atualizado** | No Android e no Windows, correções chegam sozinhas em segundo plano e valem na próxima abertura, sem reinstalar. Na web, cada publicação já é a versão nova. |
| 🤖 **A IA certa para cada tarefa** | Ler a foto, diagnosticar o erro, montar o material de estudo e gerar exercícios são tarefas diferentes, e cada uma vai para o modelo que se saiu melhor nela em avaliação medida, entre Gemini, Claude Sonnet 5.5 e OpenRouter. Com qualidade empatada, vence o mais barato e rápido. O Gemini é o ponto de partida enquanto não há avaliação que indique outro. |
| 💸 **Custo de operação próximo de zero** | A infraestrutura roda em camadas gratuitas (Supabase, Cloudflare R2, Gemini, Vercel); o Claude, único modelo pago no padrão, só entra com reserva de custo e teto mensal controlados no banco. |

---

<a id="como-funciona"></a>

## Como funciona

O app guia o estudante por um ciclo de cinco passos, sempre visível na tela inicial em **"O que fazer agora"**:

```mermaid
flowchart LR
    A["1 · Analisar<br/>foto ou texto da resolução"] --> B["2 · Revisar<br/>correção com evidências"]
    B --> C["3 · Mapa de erros<br/>padrões por tipo e conceito"]
    C --> D["4 · Estudar<br/>resumo, cartões, quiz e prática"]
    D --> E["5 · Caderno<br/>a regra aprendida, para revisar depois"]
    E -.-> A
```

1. **Analisar.** O estudante fotografa a resolução (ou digita) e envia. A imagem vai direto para um bucket privado por URL assinada; a IA transcreve, compara com o esperado e classifica cada erro.
2. **Revisar.** A correção mostra cada erro com a categoria, o conceito envolvido, o trecho que serve de evidência e a confiança da IA. O exercício pode ser editado a qualquer momento.
3. **Mapa de erros.** Os erros se acumulam em um grafo de conceitos e em gráficos de frequência por tipo, mostrando o que se repete e em quais matérias.
4. **Estudar.** Para a matéria escolhida, a IA prepara um material no estilo NotebookLM: resumo, cartões de memorização e um quiz corrigido no servidor. Do quiz o aluno vai direto para a **prática direcionada**, escolhendo o tipo de erro que quer reforçar.
5. **Caderno.** O estudante registra, com as próprias palavras, a regra que aprendeu. O caderno vive no aparelho, funciona sem internet e sincroniza entre dispositivos.

### Taxonomia de erros

A IA classifica cada ocorrência em uma de **7 categorias**, a mesma usada para escolher a prática:

| `calculo` | `conceito` | `sinal` | `interpretacao` | `procedimento` | `unidade` | `outro` |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| conta errada | ideia mal aplicada | troca de sinal | enunciado mal lido | passo omitido ou fora de ordem | unidade ou dimensão | demais casos |

---

<a id="funcionalidades"></a>

## Funcionalidades

### Disponível hoje

| Área | O que o estudante tem | Onde está no código |
|:---|:---|:---|
| **Conta** | Cadastro e login com e-mail/senha ou **Google**, sessão persistente | `lib/auth/`, `lib/main.dart` |
| **Exercícios** | Criar, listar, editar, excluir e ver detalhes; lista e detalhe lado a lado em telas largas | `lib/main.dart` |
| **Análise por IA** | Transcrição da foto, erros por categoria e conceito, evidência e confiança; fila em lote processada pelo servidor | `analyze-attempt`, `process-batch` |
| **Mapa de erros** | Grafo de conceitos, frequência por tipo de erro, evidências por conceito | `lib/ai/insights_view.dart` |
| **Material de estudo** | Resumo, cartões e quiz gerados pela IA, com gabarito guardado e corrigido no servidor | `study-material`, `lib/ai/study_material_view.dart` |
| **Prática direcionada** | 3 a 5 exercícios por pedido, filtrados por tipo de erro; conceitos ranqueados por **frequência × recência** (meia-vida de 14 dias), descontando a recuperação já demonstrada | `generate-practice` |
| **Catálogo revisado** | 30 exercícios escritos e revisados por pessoas (5 por matéria/assunto/tema), servidos antes da IA quando cobrem a rodada | `catalog_exercises`, `_shared/catalog.ts` |
| **Aprender** | Catálogo de matérias por etapa (Ensino Fundamental 7º–9º ano, Ensino Médio 1º–3º ano, Engenharia de Computação e estudo independente) e publicações curadas de eletrônica, informática, robótica, projetos e dicas, com link para o material; administradores publicam e editam pela própria tela | `lib/learning_platform.dart`, `learning_subjects`, `knowledge_posts` |
| **Caderno de erros** | Registro livre de erros e regras, com filtros que ficam salvos | `lib/caderno_erros.dart`, `lib/local/` |
| **Offline-first** | Tudo continua funcionando sem rede; o que foi feito offline sobe sozinho ao reconectar, e uma edição recusada pelo servidor fica guardada na fila em vez de se perder | `lib/sync/` |
| **Vários aparelhos** | Caderno, exercícios e exclusões chegam em tempo real aos outros dispositivos | Supabase Realtime, `lib/sync/caderno_sync.dart` |
| **Atualização sem reinstalar** | Patches de código pelo Shorebird baixados em segundo plano; versões nativas novas oferecidas em *Sobre o App* a partir do GitHub Releases | `lib/atualizacao/`, [`ATUALIZACOES.md`](../appmistakemap/ATUALIZACOES.md) |
| **Painel administrativo** | Papéis de usuário, métricas de uso, cotas e consumo da IA por modelo | `lib/admin/` |
| **Interface adaptativa** | Celular, tablet, desktop, dobráveis e telas duplas, com navegação própria para cada largura | `lib/layout/` |

### Plataformas

| Plataforma | Situação |
|:---|:---|
| 🌐 **Web** | Publicada em [mistakemap-tau.vercel.app](https://mistakemap-tau.vercel.app/): a própria Vercel compila o Flutter a cada atualização do `main` |
| 🤖 **Android** | APK distribuído pelo GitHub Releases, com patches de código pelo Shorebird; assinatura de loja pendente para a Play Store |
| 🪟 **Windows** | Pacote ZIP distribuído pelo GitHub Releases, com patches de código pelo Shorebird |
| 🍎 **iOS** | Adiado até haver Mac ou conta Apple Developer |

---

<a id="arquitetura"></a>

## Arquitetura

### Visão geral

```mermaid
flowchart TB
    subgraph Cliente["Cliente Flutter · Android, Windows, Web"]
        UI["Telas Fluent 2 + Liquid Glass"]
        SYNC["Sincronizador offline-first"]
        LOCAL[("SQLite local<br/>cache, caderno, fila_sync")]
        UI --> SYNC --> LOCAL
    end

    subgraph Supabase["Supabase"]
        AUTH["Auth · JWT ES256<br/>e-mail/senha e Google"]
        PG[("PostgreSQL + RLS<br/>pg_cron · pg_net")]
        RT["Realtime"]
        EF["Edge Functions · Deno"]
    end

    R2[("Cloudflare R2<br/>bucket privado")]
    AI["Provedores de IA<br/>Gemini · Claude · OpenRouter"]

    SYNC <-->|"consultas e upserts"| PG
    RT -->|"mudanças de outros aparelhos"| SYNC
    UI -->|"login"| AUTH
    UI -->|"chamadas autenticadas"| EF
    UI -->|"PUT por URL assinada"| R2
    EF --> PG
    EF -->|"leitura da imagem"| R2
    EF -->|"JSON Schema"| AI
    PG -->|"pg_cron → process-batch"| EF
```

**Princípio central:** o Flutter só apresenta e coleta. **OCR, LLM, correção de quiz, ranking e cotas ficam no servidor**, onde podem ser auditados, testados e protegidos. A chave `service_role` nunca entra no app.

### Stack

| Camada | Tecnologia | Papel |
|:---|:---|:---|
| Interface | Flutter 3.47 + Dart 3.13, `fluent_ui`, `liquid_glass_widgets` | Um único código para Android, Windows e Web |
| Estado | `StatefulWidget` + `setState` | Estado local por tela, sem framework extra |
| Banco local | SQLite (`sqflite`, `sqflite_common_ffi`, `sqflite_common_ffi_web`) + `shared_preferences` | Cache offline, caderno e fila de envio |
| Autenticação | Supabase Auth | E-mail/senha e Google OAuth; JWT ES256 |
| Banco | PostgreSQL (Supabase) | 31 migrations versionadas, RLS em todas as tabelas |
| Tempo real | Supabase Realtime | Propaga mudanças entre aparelhos |
| Backend | Supabase Edge Functions (Deno 2, TypeScript) | IA, upload, prática, estudo, lote e saúde |
| Jobs | `pg_cron` + `pg_net` | Processamento em lote sem HTTP síncrono em trigger |
| Arquivos | Cloudflare R2 | Fotos dos exercícios, compatível com S3, sem custo de saída |
| IA | Google Gemini (padrão), Anthropic Claude Sonnet 5.5, OpenRouter | OCR, classificação de erros, material e exercícios, cada tarefa no modelo de melhor qualidade e eficiência para ela ([detalhes](#provedores-ia)) |
| Web | Vercel | Build do Flutter na própria Vercel (`vercel.json` + `scripts/vercel-build.sh`) e hospedagem com rota SPA |
| Atualizações | Shorebird (`shorebird_code_push`) + GitHub Releases | Patches de código Dart sem reinstalar; releases nativos com APK e ZIP |
| CI/CD | GitHub Actions | Testes, migrations, funções, releases e patches |

### Edge Functions

| Função | Método | O que faz |
|:---|:---:|:---|
| `upload-url` | `POST` | Valida a sessão, registra o SHA-256 calculado no app, reserva cota e assina um `PUT` na R2 |
| `analyze-attempt` | `POST` | Lê a imagem, confere o SHA-256, chama a IA com saída em JSON Schema, valida e grava a análise em uma única operação (ou devolve o resultado em cache) |
| `generate-practice` | `POST` | Escolhe os conceitos prioritários e serve o catálogo revisado ou gera exercícios novos, guardando o gabarito fora do alcance do cliente |
| `study-material` | `POST` | Gera resumo, cartões e quiz da matéria e corrige as respostas do quiz no servidor |
| `process-batch` | `POST` | Chamado pelo `pg_cron` com segredo próprio; analisa a fila de tentativas pendentes com *lease* e idempotência |
| `health` | `GET` | Verifica banco e R2 para o monitor de saúde |

Código compartilhado em `supabase/functions/_shared/`: contrato e validação da IA, HTTP/CORS/autenticação, cliente do provedor, catálogo, orçamento de IA (`claude_budget.ts`) e roteador de modelos (`model_router.ts`).

### Pipeline de IA

```mermaid
sequenceDiagram
    participant App as App Flutter
    participant UP as upload-url
    participant R2 as Cloudflare R2
    participant AN as analyze-attempt
    participant DB as PostgreSQL
    participant AI as Provedor de IA

    App->>UP: pedido de upload (SHA-256, tamanho)
    UP->>DB: valida sessão e reserva cota
    UP-->>App: URL assinada (PUT)
    App->>R2: envia a foto direto ao bucket
    App->>AN: analisar tentativa
    AN->>DB: claim com lease e cota diária
    AN->>R2: lê a imagem e confere o SHA-256
    AN->>AI: prompt + JSON Schema
    AI-->>AN: transcrição, erros, evidências
    AN->>AN: valida o JSON contra o contrato
    AN->>DB: grava análise e error_events
    AN-->>App: diagnóstico
```

Salvaguardas do pipeline:

- **Saída estruturada e validada.** A resposta do modelo precisa passar pelo contrato em `ai_contract.ts`; o que não valida não é gravado.
- **Idempotência e concorrência.** `processing_runs` com *lease* evita análise duplicada; uma tentativa já analisada devolve o diagnóstico em cache.
- **Cotas e orçamento.** Limite diário por usuário (`ai_daily_usage`), reserva de custo antes de chamar provedores pagos (`ai_budget_reservations`) e falha fechada quando a tabela de preços precisa de revisão.
- **Modelo escolhido por tarefa, com evidência.** Cada tarefa vai para o modelo de melhor qualidade naquela tarefa, comparado em avaliação com pelo menos 20 amostras, qualidade ≥ 0,8 e dados com menos de 30 dias; dentro de 2 pontos de qualidade, vence o mais barato e rápido (veja abaixo).
- **Reserva só para indisponibilidade.** Se o modelo escolhido estiver fora do ar, sem cota ou sem orçamento, o pedido segue para uma reserva sem expor o erro ao aluno. A reserva protege a disponibilidade; não é ela que decide qual IA atende.
- **Contexto educacional.** Todo exercício tem temática de tecnologia (robótica, eletrônica, elétrica, hardware, software, programação, redes…), com o dispositivo ou sistema gerando os dados do problema: o catálogo revisado, os exemplos da conta nova, a prática e o material de estudo, sem mudar a matéria nem a dificuldade; matérias de domínio claro (como IoT) recebem tópicos de orientação próprios.
- **Recusas tratadas.** Bloqueios de segurança do provedor viram uma mensagem clara ao aluno (HTTP 422); resposta truncada ou fora do contrato nunca é gravada.

<a id="provedores-ia"></a>

### Provedores e modelos de IA

Todas as chamadas passam por um único ponto, `structuredResponse()` em [`_shared/gemini.ts`](../supabase/functions/_shared/gemini.ts), usado pela análise, pelo material de estudo e pela prática. A escolha do modelo acontece só no servidor, que grava o modelo usado em `attempt_analyses.model` e `practice_sets.model`.

| Provedor | Modelo | Papel | Saída estruturada | Ativação |
|:---|:---|:---|:---|:---|
| **Google Gemini** | `gemini-flash-latest` | **Padrão** de cada tarefa enquanto a avaliação não indicar outro modelo; candidato do roteador | `responseFormat` com JSON Schema, *thinking* `LOW` | `GEMINI_API_KEY`, `GEMINI_MODEL` |
| **Google Gemini** | `gemini-3.6-flash` | 1ª reserva do Gemini (só em indisponibilidade) | idem | `GEMINI_FALLBACK_MODEL` |
| **Google Gemini** | `gemini-3.5-flash-lite` | 2ª reserva do Gemini, roda em capacidade separada e costuma responder quando os Flash estão sobrecarregados | idem | `GEMINI_LITE_MODEL` (`off` desliga) |
| **Anthropic** | `claude-sonnet-5-5` | Candidato do roteador em qualquer tarefa (único pago, com teto de custo); opcionalmente também **última reserva** quando todo o Gemini falha | `output_config` com JSON Schema, imagens em base64 | Rota direta: `AI_PROVIDER=anthropic` + `ANTHROPIC_API_KEY` + `ANTHROPIC_MODEL=claude-sonnet-5-5` (obrigatório; o controle de custo só aceita esse modelo). Última reserva: `AI_CLAUDE_FALLBACK_ENABLED=true` + `ANTHROPIC_API_KEY` (o modelo é definido internamente) |
| **OpenRouter** | configurável (`openrouter/free` ou modelos `:free` no roteador automático) | Candidato do roteador com modelos gratuitos de terceiros; também pode ser a rota fixa de uma tarefa | `response_format` `json_schema` estrito, `require_parameters` | `AI_PROVIDER=openrouter` + `OPENROUTER_API_KEY` + `OPENROUTER_MODEL` (obrigatório) |
| **OpenAI** | `gpt-4.1-mini` (Responses API) | Integração preparada e validada localmente, **ainda não ativada** | Structured Outputs | pendente de chave e publicação ([`_reversa_forward/openai-integration`](../_reversa_forward/openai-integration/README.md)) |

**Uma escolha para cada tarefa.** O servidor separa as chamadas em quatro tarefas, cada uma com exigências próprias: `VISION` (ler a foto da resolução), `ANALYSIS` (diagnosticar o erro a partir do texto), `STUDY` (material de estudo) e `PRACTICE` (exercícios). Para cada pedido, o roteador ([`_shared/model_router.ts`](../supabase/functions/_shared/model_router.ts)) escolhe o modelo assim:

1. **Só entram modelos testados naquela tarefa.** A evidência vem de avaliações independentes (`AI_ROUTING_EVIDENCE`, nunca dados de alunos): pelo menos 20 amostras, qualidade ≥ 0,8, medição com menos de 30 dias, suporte a imagem quando a tarefa é `VISION`, custo de até US$ 1 por pedido e chave do provedor configurada.
2. **A comparação precisa ser justa.** Pelo menos dois modelos diferentes avaliados no mesmo conjunto de dados; sem isso, o roteador não troca nada.
3. **Qualidade primeiro.** Ficam só os modelos a até 2 pontos percentuais do melhor resultado, para não trocar precisão por uma diferença pequena de preço.
4. **Depois, eficiência.** Entre esses, vence o de menor custo por pedido, com o tempo de resposta como desempate.

Assim a mesma interface pode usar, por exemplo, um modelo para ler fotos e outro para gerar exercícios, cada um onde rende mais. Quando não há evidência suficiente para uma tarefa, vale a rota configurada dela (`AI_<ROTA>_PROVIDER` e `AI_<ROTA>_MODEL`) ou, sem isso, `AI_PROVIDER` (padrão `gemini`).

**Ordem de decisão** (a reserva só entra quando o modelo escolhido não responde):

```mermaid
flowchart TD
    REQ["Pedido ao servidor"] --> CAT{"Prática coberta pelo<br/>catálogo revisado?"}
    CAT -->|"sim"| OUT["Resposta validada"]
    CAT -->|"não ou outra tarefa"| EV{"Há evidência de avaliação<br/>(AI_ROUTING_EVIDENCE)?"}
    EV -->|"sim"| AUTO["Melhor modelo para a tarefa<br/>Gemini · Claude · OpenRouter grátis"]
    AUTO -->|"ok"| OUT
    AUTO -->|"indisponível ou sem orçamento"| ROTA
    EV -->|"não"| ROTA["Rota configurada<br/>AI_ROTA_PROVIDER ou AI_PROVIDER"]
    ROTA -->|"Gemini"| G1["gemini-flash-latest"]
    G1 -->|"404, 429, 5xx ou rede"| G2["gemini-3.6-flash"]
    G2 -->|"falha"| G3["gemini-3.5-flash-lite"]
    G1 -->|"ok"| OUT
    G2 -->|"ok"| OUT
    G3 -->|"ok"| OUT
    ROTA -->|"Claude ou OpenRouter"| OP["Provedor configurado"]
    OP -->|"ok"| OUT
    G3 -->|"falha"| CL{"AI_CLAUDE_FALLBACK_ENABLED?"}
    OP -->|"falha"| CL
    CL -->|"sim"| SON["claude-sonnet-5-5<br/>com reserva de orçamento"]
    SON -->|"ok"| OUT
    CL -->|"não"| ERR["Erro amigável ao aluno<br/>tentativa continua salva"]
    SON -->|"falha"| ERR
```

1. **Catálogo primeiro.** Na prática, se o catálogo revisado cobre a rodada, nenhuma IA é chamada.
2. **Melhor modelo para a tarefa.** Com evidência de avaliação, o roteador escolhe, para aquela tarefa, entre o Gemini, o Claude Sonnet 5.5 e modelos gratuitos do OpenRouter pelos critérios acima. Se o escolhido estiver indisponível, sem cota ou sem orçamento, a chamada volta para a rota configurada da tarefa.
3. **Reserva do Gemini (só em indisponibilidade).** Até três tentativas, cada uma em um modelo diferente (principal → `gemini-3.6-flash` → `gemini-3.5-flash-lite`), com espera exponencial (0,5 s, 1 s) e um prazo total de 110 s para caber no limite de 150 s das Edge Functions.
4. **Última reserva opcional: Claude.** Com `AI_CLAUDE_FALLBACK_ENABLED=true`, falhas de indisponibilidade, limite de taxa ou saída inválida/incompleta são repetidas no `claude-sonnet-5-5`.
5. **Sem resposta válida,** o aluno recebe uma mensagem amigável e a tentativa continua salva para uma nova análise.

**Controle de custo do Claude** (`_shared/claude_budget.ts` + migration `ai_budget_reservations`):

- conta os tokens de entrada antes de chamar (`count_tokens`) e recusa pedidos acima de 100 mil tokens de entrada ou 16 mil de saída;
- reserva US$ 1 por pedido e acerta o valor real depois da resposta;
- teto de **US$ 100 em qualquer janela móvel de 31 dias**, verificado no banco com trava (`reserve_claude_budget`);
- **falha fechada**: se a contagem não puder ser feita ou se a tabela de preços passar da validade (01/12/2026), a chamada paga não acontece.

> [!WARNING]
> Esse controle de custo vale **só para o Claude**. O roteador automático só considera modelos gratuitos do OpenRouter, mas um modelo pago configurado explicitamente em `OPENROUTER_MODEL` ou `AI_<ROTA>_MODEL` não passa pela reserva de US$ 1 nem pelo teto de US$ 100. Limite os gastos desses modelos na própria conta do OpenRouter.

**Observabilidade.** Retentativas e erros dos provedores aparecem nos logs (`ai_provider_retry`, `ai_provider_error`) só com código e status, nunca com conteúdo do aluno. O painel administrativo mostra as cotas do plano gratuito do Gemini por modelo (RPM, TPM e RPD); a telemetria detalhada por provedor está preparada em [`_reversa_forward/admin-monitoring`](../_reversa_forward/admin-monitoring/README.md).

> [!NOTE]
> Na camada gratuita do Gemini, o Google pode usar prompts e imagens para melhorar seus produtos. Fotos com nome ou matrícula devem ser recortadas antes do envio, ou deve-se usar uma camada paga.

### Priorização da revisão

A prioridade de um conceito segue o modelo:

$$
P = F \times R \times I \times (1 - M)
$$

| Termo | Significado | Situação |
|:---:|:---|:---:|
| $F$ | Frequência normalizada do erro | ✅ |
| $R$ | Recência, com meia-vida de 14 dias sobre `attempted_at` | ✅ |
| $I$ | Importância do conceito | 🔜 |
| $M$ | Evidência de recuperação entre 0 e 1 (`mastery_events`; três acertos tiram o foco do conceito) | ✅ |

Hoje $F$, $R$ e $M$ já ordenam a prática direcionada. O objetivo é **ordenar a revisão**, nunca dar uma nota à capacidade do estudante.

### Offline-first e sincronização

```mermaid
flowchart LR
    UI["Telas"] --> S["Sincronizador"]
    S -->|"com rede"| SB["Supabase"]
    S -->|"sem rede"| DB["SQLite"]
    DB --> Q["fila_sync"]
    Q -->|"ao reconectar"| SB
    SB -->|"Realtime"| S
```

- **Leitura:** o app consulta o Supabase primeiro e cai no SQLite quando não há rede.
- **Escrita offline:** vai para a `fila_sync` com UUIDs gerados no aparelho; o envio é um *upsert* idempotente, então repetir não duplica.
- **Tempo real:** `subjects`, `attempts`, `attempt_analyses`, `error_notes` e `deleted_records` chegam aos outros aparelhos pelo Realtime.
- **Caderno:** espelhado em `error_notes`; vence a última escrita por `updated_at`, e a exclusão vence sempre (tombstone `deleted_at`).
- **Exclusões:** registradas em `deleted_records`. O trigger `block_deleted_reinsert` responde com SQLSTATE `MM410` se uma fila antiga tentar recriar algo apagado, e o outro aparelho mostra "excluído em outro aparelho".

Detalhes do esquema local e das versões do banco em [`BANCO_LOCAL.md`](../appmistakemap/BANCO_LOCAL.md).

### Modelo de dados

| Grupo | Tabelas principais |
|:---|:---|
| Estudo | `subjects`, `exercises`, `attempts`, `attempt_assets`, `corrections` |
| Conhecimento | `concepts`, `concept_edges`, `exercise_concepts`, `error_types`, `learning_subjects`, `knowledge_posts` |
| Diagnóstico | `attempt_analyses`, `error_events`, `ocr_artifacts`, `processing_runs`, `mastery_events` |
| Prática e estudo | `practice_sets`, `practice_answer_keys`, `catalog_exercises`, `catalog_answer_keys`, `study_materials`, `study_quiz_rounds`, `study_quiz_keys` |
| Caderno e sync | `error_notes`, `notebook_entries`, `deleted_records` |
| Operação | `profiles`, `ai_daily_usage`, `ai_budget_reservations`, `ai_api_events`, `rate_limits`, `audit_log`, `r2_quota_usage` |

As migrations ficam em [`appmistakemap/database/supabase/migrations/`](../appmistakemap/database/supabase/migrations/) e são **imutáveis**: toda correção vira uma migration nova, aplicada automaticamente no merge do `main`.

### Segurança e privacidade

| Mecanismo | Como é aplicado |
|:---|:---|
| **Row Level Security** | Todas as tabelas com RLS; cada aluno só enxerga as próprias linhas. Diagnósticos são somente leitura para o dono e escritos pelo servidor |
| **Gabaritos protegidos** | `practice_answer_keys`, `catalog_answer_keys` e `study_quiz_keys` não têm acesso do cliente; a correção acontece no servidor |
| **Segredos** | `service_role` e chaves de IA/R2 só existem nas Edge Functions, configuradas como *secrets*; nada disso fica no Git |
| **Arquivos** | Bucket R2 privado, upload por URL assinada de curta duração, integridade por SHA-256 |
| **Jobs** | `process-batch` exige um segredo próprio; nada de HTTP síncrono dentro de trigger |
| **Publicações** | `knowledge_posts`: todos os alunos leem, só administradores criam, editam e excluem (RLS com `is_admin()`) |
| **Auditoria** | `audit_log` *append-only* para mutações sensíveis |
| **Dados educacionais** | Sem ranking público e sem exposição automática de fragilidades. O mapa pertence ao estudante; compartilhar deve ser explícito, granular e revogável |

Decisões de backend e o histórico da migração do worker Rust para as Edge Functions estão em [`BACKEND.md`](../docs/BACKEND.md).

---

<a id="atualizacoes"></a>

## Atualizações e distribuição

| Via | O que muda | Como chega |
|:---|:---|:---|
| **Web (Vercel)** | Tudo | A integração Git da Vercel roda `scripts/vercel-build.sh` (Flutter 3.47.2, `flutter build web --release`) a cada push no `main`; quem abrir o site já recebe a versão nova |
| **Patch de código (Shorebird)** | Código Dart: telas, regras de interface, textos, correções | O app consulta ao abrir, ao voltar, ao ir para segundo plano e de hora em hora; baixa em segundo plano e aplica no próximo início |
| **Release nativo (GitHub Releases)** | Plugins, código nativo, versão do Flutter, ícone | O app compara a tag `v<versão>+<build>` com o instalado e oferece o APK ou ZIP em *Sobre o App*; os dados ficam |

O código em execução nunca é trocado no meio do uso. Builds de desenvolvimento (`flutter run`) não recebem patches. Configuração, assinatura Android e renovação anual da chave do Shorebird em [`ATUALIZACOES.md`](../appmistakemap/ATUALIZACOES.md).

---

<a id="design"></a>

## Design e experiência

- **Identidade Obsidian Glass em modo claro.** Fundo claro com brilhos suaves e acentos vivos com função: Aqua (Início e ações principais), Azure (Lista), Violeta (Mapa e IA), Âmbar (Caderno), Mint (acerto) e Coral (erro). Texto colorido usa variantes "Ink" com contraste **≥ 4,5:1**. Paleta em [`PALETA.md`](../appmistakemap/PALETA.md).
- **Fluent 2 + Liquid Glass.** Componentes Fluent para a estrutura e vidro líquido nas barras e avisos, sempre legível mesmo sem translucidez.
- **Toque uniforme.** Todos os botões respondem com a mesma animação (escala 0,97 em 120 ms).
- **Navegação por largura de tela** ([`NAVEGACAO.md`](../appmistakemap/NAVEGACAO.md)):

| Largura | Navegação |
|:---|:---|
| < 600 px (celular) | Barra de vidro de ponta a ponta com 7 fatias: **Início · Lista · Mapa · Estudar · Caderno · Sobre · Mais** |
| 600 – 840 px (tablet, dobrável) | Trilho compacto com ícone e rótulo, e botão Analisar no topo |
| ≥ 840 px (desktop, web) | Trilho largo com seções, Estudar logo abaixo do Mapa e Analisar em destaque |

O Mapa é uma aba com pilha própria (a barra não some ao navegar dentro dele) e o Voltar é previsível em todas as plataformas.

---

<a id="qualidade"></a>

## Qualidade e engenharia

| Prática | Como é garantida |
|:---|:---|
| **Testes do app** | 26 arquivos de teste Flutter (widgets, navegação, layout, banco local, sincronização com SQLite em memória, atualizações, contratos) |
| **Testes do backend** | 7 suítes `deno test` (contrato da IA, catálogo, orçamento, roteador de modelos, estudo, tópicos de aprendizado, upload) |
| **Análise estática** | `flutter analyze` sem avisos e `dart format` obrigatórios; `deno check` nas funções |
| **Migrations** | Imutáveis, versionadas e aplicadas pelo CI; o histórico do repositório é conferido com o do banco publicado |
| **Revisão** | PRs pequenos e focados, com revisão automática e checks obrigatórios no `main` |

| Workflow | Quando roda | O que faz |
|:---|:---|:---|
| [`ci.yml`](workflows/ci.yml) | Push e PR no `main` | `deno check`/`deno test`, `flutter analyze`, `dart format` e `flutter test` |
| [`supabase-deploy.yml`](workflows/supabase-deploy.yml) | Push no `main` que altera migrations | Aplica as migrations no Supabase |
| [`supabase-functions-deploy.yml`](workflows/supabase-functions-deploy.yml) | Push no `main` que altera `supabase/` | Publica as Edge Functions |
| [`shorebird-release.yml`](workflows/shorebird-release.yml) | Manual | Gera o release nativo (APK Android e ZIP Windows) e publica no GitHub Releases |
| [`shorebird-patch.yml`](workflows/shorebird-patch.yml) | Manual, ou push no `main` que altera `lib/` quando `SHOREBIRD_AUTO_PATCH=true` | Publica um patch de código Dart pelo Shorebird |
| [`web-deploy-vercel.yml`](workflows/web-deploy-vercel.yml) | Manual (reserva) | Deploy web pela CLI; o caminho normal é a integração Git da Vercel |
| [`sync-repository-metadata.yml`](workflows/sync-repository-metadata.yml) | Mudanças em `LICENSE` ou `CITATION.cff` | Garante que as cópias da raiz batem com as de `.github/` |

---

<a id="comecar"></a>

## Começar

### Experimentar sem instalar

Abra **[mistakemap-tau.vercel.app](https://mistakemap-tau.vercel.app/)**, crie uma conta (ou entre com Google) e siga os passos de "O que fazer agora".

### Rodar localmente

Pré-requisitos: Flutter estável (validado com **3.47.2 / Dart 3.13**), o SDK da plataforma de destino (Android SDK, Visual Studio para Windows ou Chrome) e, só para as Edge Functions, **Deno 2**.

```bash
git clone https://github.com/CFSJCODE/MistakeMap.git
cd MistakeMap/appmistakemap
flutter pub get
flutter run -d chrome        # ou: -d android / -d windows
```

O app já aponta para o projeto Supabase publicado; **nenhuma chave privada é necessária** para rodar o cliente.

> [!TIP]
> No Windows, clone em um caminho **sem acentos** (por exemplo, `D:\MistakeMap`). Acentos no caminho quebram o `flutter analyze` e o build AOT.

### Validar como o CI

```bash
# em appmistakemap/
flutter analyze
dart format --set-exit-if-changed lib/
flutter test --reporter compact

# em supabase/functions/
deno check --frozen */index.ts
deno test --frozen --allow-env
```

> [!NOTE]
> Na Web, `web/sqlite3.wasm` precisa casar com a versão do pacote `sqlite3` registrada no `pubspec.lock`. Evite adicionar `path_provider`: ele puxa `jni` e quebra o build Windows sem JDK.

---

<a id="estrutura"></a>

## Estrutura do repositório

```text
MistakeMap/
├── appmistakemap/               # App Flutter (Android, Windows, Web)
│   ├── lib/
│   │   ├── main.dart            # Bootstrap, Auth e telas principais
│   │   ├── caderno_erros.dart   # Caderno de erros
│   │   ├── learning_platform.dart   # Tela Aprender (catálogo e publicações)
│   │   ├── about/  admin/  auth/  assets/
│   │   ├── atualizacao/         # Shorebird e aviso de release nativo
│   │   ├── ai/                  # Envio, correção, mapa, material de estudo e prática
│   │   ├── layout/              # Larguras, dobráveis e shell de navegação
│   │   ├── local/               # SQLite (io e web), DAO do caderno, conta offline
│   │   ├── sync/                # Sincronizador, fila, Realtime, sync do caderno
│   │   └── theme/               # Tokens de design, paleta e movimento
│   ├── test/                    # Testes Flutter
│   ├── database/supabase/migrations/   # Migrations canônicas do Supabase
│   ├── shorebird.yaml           # app_id do Shorebird (não é segredo)
│   └── ATUALIZACOES.md · BANCO_LOCAL.md · NAVEGACAO.md · PALETA.md · GOOGLE_AUTH.md
├── supabase/
│   ├── functions/               # Edge Functions (Deno) + _shared + tests
│   └── config.toml
├── scripts/vercel-build.sh      # Build web usado pela Vercel
├── vercel.json                  # Build, rota SPA e cabeçalhos da versão web
├── docs/                        # Documentação técnica
│   ├── BACKEND.md               # Decisões de arquitetura do backend
│   └── ai/                      # Portal dos agentes de IA (Claude, Codex, Gemini, Reversa)
├── archive/worker/              # Worker Rust original (arquivado)
├── .github/                     # README, CI/CD, licença, citação e políticas
└── AGENTS.md · CLAUDE.md · GEMINI.md   # Regras e decisões para agentes de código
```

---

<a id="roadmap"></a>

## Roadmap

| Fase | Entregas | Situação |
|:---|:---|:---:|
| **0 · Fundação** | Flutter, Fluent UI, Supabase, Auth | ✅ |
| **1 · Matérias e exercícios** | Cadastro de matérias e exercícios; catálogo de matérias por etapa de ensino na tela Aprender | ✅ |
| **2 · Tentativas** | Fotos, correções e histórico | ✅ |
| **3 · Erros** | Taxonomia de 7 categorias e eventos de erro | ✅ |
| **4 · IA** | OCR, erros com evidência, material de estudo e prática | ✅ |
| **5 · Offline e multi-aparelho** | SQLite, fila de envio, Realtime, caderno sincronizado | ✅ |
| **5b · Distribuição** | Web na Vercel, releases no GitHub e patches pelo Shorebird | ✅ |
| **6 · Prioridade** | Fila de revisão explicável com $P = F \times R \times I \times (1 - M)$ | 🟡 F, R e M prontos; falta I e a fila |
| **7 · Validação humana** | Confirmar, corrigir ou rejeitar cada erro sugerido | 🔜 |
| **8 · Relatórios** | PDF/CSV e compartilhamento seletivo com professor ou tutor | 🔜 |
| **9 · Lojas** | Play Store (chave de assinatura própria) e iOS | 🔜 |

Próximos passos conhecidos: tela própria para navegar no catálogo e mais temas; mostrar nos insights o que ainda está na fila de envio; manter o foco da prática ao recarregar; remover da R2 as fotos de tentativas excluídas.

---

<a id="historico"></a>

## Histórico recente

| PR | Entrega |
|:---:|:---|
| [#17](https://github.com/CFSJCODE/MistakeMap/pull/17) | Análise da IA gravada como objeto JSON e fallback do Gemini ampliado |
| [#18](https://github.com/CFSJCODE/MistakeMap/pull/18) | Caderno de erros offline em SQLite, com CRUD e filtros persistidos |
| [#20](https://github.com/CFSJCODE/MistakeMap/pull/20) | Prática por tipo de erro e ranking por frequência × recência com desconto de recuperação |
| [#22](https://github.com/CFSJCODE/MistakeMap/pull/22) · [#23](https://github.com/CFSJCODE/MistakeMap/pull/23) | Navegação repensada e identidade Obsidian Glass em modo claro |
| [#24](https://github.com/CFSJCODE/MistakeMap/pull/24) | Offline-first: Supabase primeiro, SQLite sem rede, fila de envio e Realtime |
| [#27](https://github.com/CFSJCODE/MistakeMap/pull/27) | Material de estudo estilo NotebookLM na aba Estudar |
| [#29](https://github.com/CFSJCODE/MistakeMap/pull/29) · [#30](https://github.com/CFSJCODE/MistakeMap/pull/30) | Ciclo de estudo guiado no Início, app inteiro offline e barra em vidro líquido |
| [#31](https://github.com/CFSJCODE/MistakeMap/pull/31) | Mapa como aba com pilha própria, trilho em janelas médias e Voltar previsível |
| [#32](https://github.com/CFSJCODE/MistakeMap/pull/32) · [#34](https://github.com/CFSJCODE/MistakeMap/pull/34) · [#35](https://github.com/CFSJCODE/MistakeMap/pull/35) · [#37](https://github.com/CFSJCODE/MistakeMap/pull/37) | Barra inferior de 7 fatias e trilho compacto completo |
| [#36](https://github.com/CFSJCODE/MistakeMap/pull/36) | Estudo atualizado, múltiplos provedores de IA e orçamento por reserva |
| [#38](https://github.com/CFSJCODE/MistakeMap/pull/38) | Caderno entre aparelhos, exclusões em tempo real com barreira `MM410` e catálogo de 30 exercícios revisados |
| [#39](https://github.com/CFSJCODE/MistakeMap/pull/39) | Histórico de migrations alinhado ao banco publicado e prática que segue para a IA quando o catálogo não basta |
| [#41](https://github.com/CFSJCODE/MistakeMap/pull/41) | Vercel passa a compilar o Flutter no próprio build e o site volta ao ar |
| [#42](https://github.com/CFSJCODE/MistakeMap/pull/42) · [#46](https://github.com/CFSJCODE/MistakeMap/pull/46) · [#47](https://github.com/CFSJCODE/MistakeMap/pull/47) | Atualização sem reinstalar: patches pelo Shorebird, aviso de release nativo e renovação da chave |
| [#43](https://github.com/CFSJCODE/MistakeMap/pull/43) · [#45](https://github.com/CFSJCODE/MistakeMap/pull/45) | README reescrito e documentação de todos os provedores de IA |
| [#44](https://github.com/CFSJCODE/MistakeMap/pull/44) | Tela Aprender, contexto educacional na IA e edições offline preservadas |

---

<a id="equipe"></a>

## Equipe e contexto acadêmico

O MistakeMap nasceu na disciplina **Projeto Integrado I: Desenvolvimento Móvel** do curso de **Engenharia de Computação da PUC Minas**.

| | |
|:---|:---|
| **Autores** | **Cláudio Francisco Dos Santos Júnior** · **Lucas Emanuel Simão Silva** |
| **Orientação** | **Ilo Amy Saldanha Rivero** |
| **Instituição** | Pontifícia Universidade Católica de Minas Gerais (PUC Minas) |
| **Versão** | 1.0.0 · novembro de 2026 |

---

<a id="licenca"></a>

## Licença, uso e citação

O código é distribuído sob a **[PolyForm Noncommercial License 1.0.0](LICENSE)**: uso pessoal, educacional e de pesquisa é permitido; **uso comercial** (SaaS, white-label, incorporação em produto pago) exige uma licença comercial separada, concedida pelos autores. Interessados em licenciar o MistakeMap para uma escola, curso ou plataforma podem abrir uma [issue](https://github.com/CFSJCODE/MistakeMap/issues) ou falar diretamente com os autores.

- [Política de uso e atribuição](USAGE_POLICY.md)
- [Marcas](TRADEMARKS.md) · [Governança](GOVERNANCE.md) · [Avisos](NOTICE)
- [Como contribuir](CONTRIBUTING.md)
- Para citar em trabalhos acadêmicos, use o [`CITATION.cff`](CITATION.cff) (botão **Cite this repository** do GitHub).

---

<div align="center">

**O erro não é o fim da resolução. É um sinal.**

[Experimentar o MistakeMap](https://mistakemap-tau.vercel.app/) · [Ver o código](https://github.com/CFSJCODE/MistakeMap) · [Decisões de backend](../docs/BACKEND.md)

<sub>Flutter · Dart · Fluent 2 · Liquid Glass · Supabase · PostgreSQL · Realtime · SQLite · Edge Functions · Cloudflare R2 · Gemini · Claude · OpenRouter · Vercel</sub>

<p align="right"><a href="#readme-top">↑ Voltar ao topo</a></p>

</div>
