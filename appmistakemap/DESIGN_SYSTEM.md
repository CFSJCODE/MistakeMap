# Design system e redesign do app do aluno

Continuação de [PALETA.md](PALETA.md) (cores Aurora Glass) e
[NAVEGACAO.md](NAVEGACAO.md) (destinos, pilhas e Voltar). Aqui ficam as
escalas, os componentes e o plano do redesign, etapa por etapa.

## 1. Auditoria (novembro de 2026)

Fonte: código em `lib/` e capturas geradas por teste de widget em 360, 390,
430 e 1280 px (fonte Inter, dados sintéticos). Cada linha aponta o que foi
visto, não o que foi presumido.

| # | Problema | Onde | Severidade | Situação |
|---|---|---|---|---|
| 1 | Início com cerca de 14 ações tocáveis e **4 botões cheios coloridos** competindo (Começar revisão, Explorar, Enviar, Biblioteca), mais 5 cartões de passo e 3 cartões de número; a página passava dos 2.400 px da captura a 390 px | `TelaInicial`, `StudyTodayPanel` | Alta | Resolvido nesta etapa |
| 2 | Caminhos duplicados no Início: "Enviar exercício" = Passo 1, "Praticar um conceito" = Passo 4, "Explorar conteúdos" ao lado de "Biblioteca" | idem | Alta | Resolvido |
| 3 | Bloco de marca (gradiente "MistakeMap") ocupando o topo do Início sem função | `_cabecalho` | Média | Resolvido |
| 4 | Três parágrafos de método no cartão "Sua semana de revisão" | `StudyTodayPanel` | Média | Resolvido (uma frase + barra + nota) |
| 5 | Tamanhos de fonte soltos: 21 valores distintos (9,5 a 30 sp) em `fontSize:` | todo o `lib/` | Média | Escala `Tipo` criada; migração tela a tela |
| 6 | Cartão "Próximo passo: treinar" do Mapa com o botão ao lado do texto: a 360–390 px o texto virava uma coluna de uma palavra por linha | `_StudyCallout` em `insights_view.dart` | Média | Resolvido (empilha abaixo de 480 px) |
| 7 | `GradientBar` sem altura no preenchimento: a barra aparecia vazia | `glass_surface.dart` | Baixa | Resolvido (`heightFactor: 1`) |
| 8 | Só modo claro: as cores são constantes (`MistakeMapDesign.*`, ~700 usos) e o app força `Brightness.light` | `design_tokens.dart`, `MistakeMapApp` | Média | Pendente (seção 6) |
| 9 | Mapa em Material e o resto em Fluent: duas famílias de controles (chips, botões) | `lib/ai/` | Média | Pendente |
| 10 | Praticar com 12 chips de filtro (~300 px a 390 px) antes do primeiro exercício e um cartão pesado por questão | `banco_exercicios.dart` | Alta | Resolvido na etapa 2 (2 menus: Tipo e Situação; lista num grupo só) |
| 11 | Meus exercícios e Caderno: cartões soltos com fundo tingido, botão "Opções" com moldura em cada cartão, 3 a 4 pílulas por cartão e texto de introdução centralizado | `main.dart` (`_ExercicioCard`), `caderno_erros.dart` | Média | Resolvido na etapa 2 (linhas em `GrupoLista`, sobretítulo matéria · tipo, menu sem moldura com alvo de 48 dp) |
| 12 | "1 certos" no resumo do Praticar | `banco_exercicios.dart` | Baixa | Resolvido (singular) |
| 13 | Sessão de revisão sem progresso visível; botão "Voltar" em texto colado ao título; as 4 autoavaliações em botões brancos de larguras diferentes, sem cor nem ícone; "Ver referência" sem destaque sendo a única ação do passo | `StudyReviewPage` | Média | Resolvido na etapa 3 |
| 14 | Conferir sugestões: mesmos problemas de cabeçalho; três botões quebrando em duas linhas desiguais por sugestão | `StudyDiagnosticsPage` | Baixa | Resolvido na etapa 3 |

Sem problema encontrado: navegação inferior persistente com estado por aba,
Voltar previsível, trilho em tablet e desktop, alvos de toque ≥ 44 px e vidro
só na navegação e barras (ver NAVEGACAO.md). O app não usa Riverpod nem
GoRouter; o redesign não os introduz.

## 2. Arquitetura da informação

A proposta inicial de cinco áreas (Início, Aprender, Erros, Revisão,
Progresso) foi comparada com o app real:

| Proposta | No app | Decisão |
|---|---|---|
| Início | Início | Mantido; redesenhado (seção 4) |
| Aprender | Exercícios (Praticar + Meus exercícios) e Explorar conteúdos | Mantido como Exercícios |
| Erros | Mapa de erros (diagnóstico) + Caderno de erros (regras do aluno) | Mantidos separados, como decidido no PR #75 |
| Revisão | Estudar (treino) e a sessão de revisão espaçada | Mantido como Estudar |
| Progresso | Faixa de progresso no Início + Mapa | Sem aba própria: os dados de evolução hoje são poucos (tentativas, revisões da semana); uma aba vazia seria pior que uma seção |

Resultado: as abas continuam Início · Exercícios · Mapa · Estudar · Caderno ·
Mais. Trocar nomes que o aluno já aprendeu, sem dado novo que justifique,
quebraria a consistência (lei de Jakob) e a divisão Mapa/Estudar/Caderno.
Perfil, Sobre e Sair seguem no Mais.

## 3. Escalas (tokens)

Em `lib/theme/design_tokens.dart`, depois da paleta:

| Escala | Valores | Uso |
|---|---|---|
| `Espaco` | 4 · 8 · 12 · 16 · 24 · 32 · 48; `pagina` 16, `paginaLarga` 24, `secao` 32, `larguraLeitura` 720, `alvoToque` 48 | Grade de 4 dp, preferência por 8 |
| `Raio` | 8 · 12 · 16 · 20 · pílula | Controle < superfície |
| `Tipo` | `tituloPagina` 24/700 · `tituloSecao` 18/600 · `tituloComponente` 16/600 · `corpo` 15/400 · `secundario` 13/400 · `legenda` 12/400 · `numero` 22/700 · `sobretitulo` 12/700 | Dois pesos de destaque só; todos escalam com a fonte do sistema |
| `Movimento` | 120 · 200 · 300 ms, `easeOutCubic` | Nada de interação acima de 300 ms |

Regra: valor novo sai da escala. Número solto num widget é dívida a migrar.

## 4. Componentes

Em `lib/theme/componentes.dart`:

| Componente | Faz | Regra |
|---|---|---|
| `CartaoProximoPasso` | A ação principal da tela: sobretítulo, título, uma frase e **um** botão cheio | Um por tela |
| `SecaoTitulo` | Título de seção (semântica de cabeçalho) com descrição e ação opcionais | |
| `GrupoLista` + `LinhaLista` | Linhas numa só superfície acrílica, separadas por fio; ícone no acento do destino, título, apoio, valor e seta | Substitui pilhas de cartões; nunca cartão dentro de cartão; linha ≥ 56 dp |
| `FaixaIndicadores` | Números lado a lado numa superfície; empilham quando a largura dividida pela escala de fonte não comporta | Número com rótulo, nunca só cor |
| `AvisoLinha` | Aviso curto com ícone (informação ou erro), região viva para leitor de tela | |

Os componentes antigos (`GlassSurface`, `GlassIconTile`, `GradientBar`,
`GlassSegmented`, `MistakeMapButton`) continuam a base; os novos são
composições deles.

### Início, depois

1. Frase curta de propósito (e o papel, para administradores).
2. **Próximo passo**: uma ação, escolhida pela prioridade pedagógica:
   revisão aberta → revisões vencidas → sugestões da IA para conferir →
   correções de exercícios → definir objetivo → primeira análise → treinar.
   Conta nova continua com o guia da primeira análise, que nesse caso é a
   ação principal.
3. Suas tentativas: três números numa faixa.
4. Seu estudo de hoje: as pendências que não viraram a ação principal e o
   objetivo (toque para ajustar).
5. Sua semana de revisão: uma frase, barra de lembrança relatada e a nota de
   que é autoavaliação.
6. Atalhos em lista: Analisar, Mapa, Estudar, Caderno, Explorar conteúdos,
   Biblioteca/planos/simulados.

Todas as funções anteriores continuam a um toque; nenhuma regra de negócio
ou consulta mudou (as mesmas chamadas ao Supabase e ao `StudyRepository`).

## 5. Validação desta etapa

- `flutter test --reporter compact`: 410 passam, 9 pulados (prévias que
  exigem `GENERATE_PREVIEWS`).
- `flutter analyze`: sem avisos. `dart format --set-exit-if-changed lib/`: ok.
- Capturas antes/depois em 360, 390, 430 e 1280 px geradas por teste de
  widget com dados sintéticos (não fazem parte do repositório).
- Início a 390 px: de mais de 2.400 px de altura e 4 botões cheios para ~1.400 px e
  1 botão cheio, medidos nas capturas.

Não verificado nesta etapa: aparelho físico, TalkBack real, desempenho em
modo profile (nenhum ganho de desempenho é declarado), e as telas que o
teste não alimenta com dados (Exercícios e Caderno aparecem vazios nas
capturas).

### Etapa 2: Exercícios e Caderno

- Praticar: filtros "Tipo" e "Situação" viraram dois menus suspensos
  (`Key('filtro-tipo')`, `Key('filtro-situacao')`); "Limpar filtros"
  continua no estado sem resultado. Cada questão é uma linha do grupo:
  sobretítulo matéria · tipo, enunciado em duas linhas, situação e
  tema · dificuldade.
- Meus exercícios: mesma linha, com a inicial da matéria num bloco claro;
  data ao lado da situação (não corta com nome de matéria longo).
- Caderno: resumo "N regras · N para revisar" no topo, introdução alinhada à
  esquerda e uma linha por regra (sobretítulo disciplina · tipo na cor do
  tipo, título, regra em duas linhas, situação e data). Textos do PR #75
  mantidos.
- Botão "Opções" das linhas: `_BotaoOpcoesLinha`, sem moldura, 48 dp.
- Validação: 410 testes passam (5 pulados), `flutter analyze` e
  `dart format` ok; capturas a 390 px antes/depois geradas por teste de
  widget (fora do repositório).

### Etapa 3: revisão e conferência em modo foco

As duas telas já abriam por cima da navegação do app; agora se comportam
como modo foco:

- `_FocoCabecalho`: fechar (X, 48 dp, "Sair da revisão"), título, onde o
  aluno está ("2 de 4 · Eletrônica") e barra de progresso da rodada.
- Um passo por vez com **uma** ação principal: responder → "Ver
  referência" (cheio) → "Como foi lembrar?" → "Próximo conceito".
- `_GradeAvaliacao`: as quatro autoavaliações em grade 2×2 de mesmo
  tamanho, cada uma com ícone, rótulo e cor (coral, âmbar, menta, aqua);
  `Key('study-rating-<again|hard|good|easy>')`. O texto "autoavaliação, não
  correção automática" continua.
- Referência num bloco com sobretítulo; retorno com ícone de sucesso (ou de
  fila offline) e a próxima data em destaque.
- Conferir sugestões: sobretítulo da matéria, sugestão em âmbar, "Confirmar"
  em largura total e "Corrigir"/"Rejeitar" lado a lado.

Nenhuma chamada ao `StudyRepository` mudou. 410 testes passam.

## 6. Próximas etapas

| Etapa | Escopo | Observação |
|---|---|---|
| 2 | Exercícios e Caderno: listas compactas, filtros em menu | Feita (itens 10 a 12 da auditoria). Estados vazios mantidos como estavam |
| 3 | Estudar e sessão de revisão: modo foco, menos navegação visível durante a sessão | Feita para a revisão e a conferência (itens 13 e 14). A aba Estudar (material da IA, em Material) fica com a etapa 4 |
| 4 | Mapa: chips e botões Material com a mesma aparência dos Fluent; visão em lista como alternativa ao grafo | |
| 5 | Modo escuro: trocar as constantes `MistakeMapDesign.*` por cores lidas do tema (`ThemeExtension`), tela a tela | Mudança grande; cada etapa precisa sair sem deixar o app misto |
| 6 | Migrar `fontSize:` soltos para `Tipo` nas telas de escola, TI e professor | |

Lembrete de publicação: todo merge no `main` que toca `lib/` vira patch do
Shorebird, que não pode trazer assets novos; este redesign não adiciona
assets nem dependências.
