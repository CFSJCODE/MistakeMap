# Arquitetura de navegação

Como o MistakeMap organiza destinos, pilhas e o Voltar, e por quê. Vale para
Android, Windows e Web: o app é Flutter, então os "padrões Android" (barra
inferior, trilho, voltar previsível, estado por aba) são widgets do próprio
app, com a identidade Aurora Glass ([PALETA.md](PALETA.md)).

## 1. Diagnóstico da navegação anterior

Fontes: `lib/main.dart` (`_TelaNavegacaoState`), `lib/layout/navigation_shell.dart`,
`lib/ai/ai_material_shell.dart`, `lib/ai/insights_view.dart` e os testes de
navegação. Nada aqui foi presumido: cada item aponta para o código.

| # | Problema | Onde estava | Efeito para o aluno |
|---|---|---|---|
| 1 | A aba **Mapa** não era aba: o toque empurrava uma página inteira (`AiMaterialShell`, um `MaterialApp` aninhado) por cima da navegação | `AppNavigationShell.onErrorMap` → `_abrirIa` | A barra e o trilho sumiam, a localização se perdia e todo o estado do Mapa (filtros, rolagem, texto digitado no painel de análise) era descartado a cada visita |
| 2 | **Destino fantasma**: `TelaMapaConceitual` ("Mapa Conceitual", Fluent) ocupava o índice 2 do `IndexedStack`, mas nenhum toque chegava a ele (o índice 2 era sempre interceptado) | `_telas[2]`, `_destination(index == 2)` | Código vivo, destino morto; duplicava o Mapa de erros |
| 3 | **Dois `WidgetsApp` recebendo o Voltar**: o `MaterialApp` interno precisava de uma rota-base invisível e de um `NavigatorObserver` para se fechar, enquanto o `PopScope` externo bloqueava o pop | `_AiMaterialShellState`, `_CloseAtBase` | Frágil; o *predictive back* do Android não refletia o estado real (a pilha interna avisava ao sistema que "tratava o Voltar" mesmo escondida) |
| 4 | **Sair em três lugares** (ícone na barra do Início, menu Mais, trilho) e **Sobre em três** (botão no fim do Início, Mais, trilho) | `_TelaInicialState.build`, `_more`, trilho | Redundância sem função; o ícone de Sair ficava ao lado do título do Início, um alvo destrutivo na área mais tocada |
| 5 | **Títulos diferentes dos rótulos da navegação**: "Início — Resumo" vs Início; "Meus Exercícios" vs "Meus exercícios"; "Painel Administrativo" vs Administração/Admin; "Mapa Conceitual" vs Mapa de erros | `_PaginaVidro(titulo:)` | Quebra *recognition rather than recall*: o aluno lê um nome na barra e outro no topo |
| 6 | **Nenhum layout entre 600 e 840 px**: tablet em pé, dobrável aberto e celular deitado recebiam a barra inferior de celular | `AppNavigationShell.build` (`desktop = largura ≥ 840`) | Gastava a altura, que é o que falta nesses formatos; Material 3 pede *navigation rail* em janelas médias |
| 7 | **Ação principal escondida no desktop**: Analisar só tinha botão próprio no celular (botão redondo) | `_bottomBar(withAction:)` | No Windows/Web o caminho era Início → passo 1, ou abrir o Mapa e achar o FAB |
| 8 | **Estudar empilhava**: pedir Estudar com o Estudar já aberto (Início, Mais, trilho) abria outro por cima | `_abrirIa(estudar: true)` | Pilha crescia; Voltar passava por telas repetidas |
| 9 | **Recuo duplicado no rodapé**: as páginas somavam `MediaQuery.padding.bottom` ao fim da lista mesmo com a barra já ocupando a área de gestos | `_paddingCorpo` + `SafeArea` da barra | Espaço morto abaixo do último item |
| 10 | Barra e trilho **sem região semântica** de navegação | `AppNavigationShell` | Leitor de tela não anunciava "navegação" ao entrar nos botões |
| 11 | Voltar numa aba que não é o Início **voltava ao Início** (correto), mas dentro do Mapa fechava **o fluxo inteiro** de uma vez quando o pop interno falhava | `PopScope` do shell + `_AiMaterialShellState` | Perda de contexto inesperada |

Mantidos por funcionarem: a cápsula de vidro com pílula deslizante e botão
redondo de analisar (PR #30), o guia "O que fazer agora" do Início (PR #29),
lista e detalhe lado a lado em janelas expandidas e em telas duplas
(`DoisPaineis`), as páginas de detalhe/edição/registro como rotas empilhadas
com Voltar na barra.

## 2. Mapa da arquitetura proposta

```
NÍVEL PRIMÁRIO — sempre à vista (barra inferior, trilho compacto ou trilho largo)
├── ⚡ Analisar exercício  (ação principal, não é destino)
│       celular: botão redondo de vidro ao lado da cápsula (≥ 360 px)
│       trilho compacto: botão redondo no topo
│       trilho largo: botão cheio no acento, acima dos destinos
├── Início (aqua)               raiz do app; Voltar aqui sai do app
├── Meus exercícios (azure)
├── Mapa de erros (violeta)     ← aba com pilha própria
└── Caderno de erros (âmbar)

NÍVEL SECUNDÁRIO — dentro de cada destino
├── Início → passos do ciclo de estudo (atalhos para os destinos abaixo)
├── Meus exercícios
│   ├── Detalhe   (painel ao lado em ≥ 840 px ou com dobra; página em compacto)
│   │   ├── Editar          (página)
│   │   └── Ver correção    (página de IA)
│   └── Opções do cartão: Ver detalhes · Editar · Excluir (menu contextual)
├── Mapa de erros  (pilha própria: a barra continua à vista)
│   ├── Painel "Analisar exercício com IA"   (recolhível, na própria página)
│   ├── Estudar com a IA → resumo · cartões · quiz → Praticar  (empilhado)
│   ├── Correção e evidências de uma tentativa                 (empilhado)
│   └── Evidências de um tipo de erro / conceito               (bottom sheet)
└── Caderno de erros
    ├── Novo registro / editar registro  (página)
    └── Filtro "ocultar revisados"       (ação na barra)

NÍVEL TERCIÁRIO — menu Mais (celular e trilho compacto) · seção CONTA (trilho largo)
├── Administração  (só administradores; aba oculta no celular, destino no trilho)
├── Estudar com a IA  (atalho para dentro do Mapa; não é destino)
├── Sobre o App    (página)
└── Sair           (diálogo de confirmação)
```

### Voltar (botão, gesto e *predictive back*)

1. Com algo empilhado dentro do Mapa (Estudar, correção), o Voltar fecha
   essa tela e mostra o Mapa; a aba não muda.
2. Numa aba que não é o Início, o Voltar leva ao Início.
3. No Início, o Voltar sai do app, e só aí o sistema recebe
   `setFrameworkHandlesBack(false)`: a animação de *predictive back* mostra a
   tela inicial do aparelho apenas quando o app vai mesmo fechar.
4. Tocar na aba atual leva a página dela de volta à raiz (como nas barras do
   Android e do iOS).
5. Páginas abertas por cima de tudo (Sobre, Detalhe, Editar, Registro, Ver
   correção) fecham com o Voltar do sistema ou da barra, uma por vez.

### Larguras (divididas pela escala de fonte, `InfoTela.escalaDeTexto`)

| Largura efetiva | Componente | Observações |
|---|---|---|
| < 600 px | Cápsula inferior de vidro líquido | 4 abas + Mais; botão redondo de analisar a partir de 360 px; some com o teclado aberto |
| 600 – 840 px | Trilho compacto (88 px) | Mesmos 4 destinos e Mais, ícone sobre rótulo, pílula no destino atual, analisar no topo; o mesmo padrão do `NavigationRail` do Material 3 |
| ≥ 840 px | Trilho largo (224 px) | Rótulos inteiros em duas seções (SEU ESTUDO, CONTA), Estudar como atalho logo abaixo do Mapa, Analisar como botão cheio |

Dobráveis e telas duplas continuam tratados por `DoisPaineis` e `ForaDaDobra`
(`lib/layout/adaptativo.dart`).

## 3. Decisões e justificativas

- **Mapa como aba com `Navigator` próprio, sem `MaterialApp` aninhado**
  (`ErrorMapTab`). Um segundo `WidgetsApp` também recebe o Voltar do
  sistema e disputa com o shell; um `Navigator` simples, com o tema Material
  do fluxo de IA aplicado por `Theme`, mantém as telas Material intactas e
  deixa o Voltar numa só mão. Um `NotificationListener<NavigationNotification>`
  impede a pilha da aba de avisar ao sistema que "trata o Voltar" quando ela
  está fora da tela. Resultado: estado preservado por aba (*Consistency and
  Standards*, *Cognitive Load*: o aluno não refaz filtros nem perde o que
  digitou).
- **`ErrorMapController` para os atalhos** (botão de analisar, Estudar, passos
  do Início). O pedido troca para a aba, leva a pilha até a raiz e abre o que
  foi pedido; pedir Estudar com o Estudar já aberto apenas o mostra. Um
  pedido feito antes de a aba existir espera por ela. Sem rotas fictícias:
  tudo aponta para telas reais.
- **Ação principal visível em toda largura** (*Fitts*: alvo grande e sempre
  no mesmo lugar; *Hick-Hyman*: um botão, não um menu). No trilho largo é um
  botão cheio acima dos destinos, para não ser lido como aba selecionada,
  seguindo o lugar do FAB no `NavigationRail` do Material 3.
- **Trilho compacto para janelas médias**: Material 3 reserva a barra
  inferior para < 600 px e o *rail* para 600–840 px. O trilho reusa os mesmos
  destinos compactos da cápsula e o mesmo Mais; a pílula do destino atual
  acende no próprio botão (não há espaço medido para deslizar).
- **Sair e Sobre só na navegação** (Mais e seção CONTA). Removidos do Início:
  eram redundantes e competiam com o ciclo de estudo; Sair deixou de ser um
  ícone ao lado do título (*Progressive Disclosure*: operações raras ficam no
  nível terciário).
- **Títulos iguais aos rótulos**: Início, Meus exercícios, Mapa de erros,
  Caderno de erros, Administração (*Recognition rather than Recall*).
- **Voltar previsível** (`_voltar` em `_TelaNavegacaoState`): primeiro a
  pilha da aba, depois o Início, depois o sistema. Nenhuma troca de aba
  inesperada e nenhum fechamento em bloco.
- **Rodapé sem recuo duplicado**: quando a barra está na tela, o conteúdo
  recebe `MediaQuery.removePadding(removeBottom: true)`; a barra é quem
  respeita a área de gestos.
- **Microinterações mantidas, não ampliadas**: pílula deslizante (240 ms),
  pressão a 97 % em 120 ms, brilho que segue o dedo e `HapticFeedback.
  selectionClick` ao trocar de aba; tudo respeita "reduzir movimento"
  (`MediaQuery.disableAnimations`) e alto contraste (vidro vira superfície
  sólida).
- **Acessibilidade**: barra e trilhos são uma região semântica "Navegação
  principal"; cada destino mantém `Semantics(selected:)` e `Tooltip`; alvos de
  toque ≥ 44 px em todas as larguras (coberto por teste); foco de teclado
  com contorno aqua de 2 px.

## 4. O que mudou no código

| Arquivo | Mudança |
|---|---|
| `lib/layout/navigation_shell.dart` | Trilho compacto (600–840 px), painel acrílico comum aos trilhos, ação principal no trilho, pílula reutilizada (`_pill`/`_pilled`), `onErrorMap` removido (o Mapa é destino como os outros), toque na aba atual avisa de novo, região semântica, recuo do rodapé sem duplicar |
| `lib/ai/ai_material_shell.dart` | `ErrorMapTab`: o Mapa como aba com `Navigator` próprio e tema Material, sem `MaterialApp` aninhado |
| `lib/ai/insights_view.dart` | `ErrorMapController`/`ErrorMapRequest`, rota nomeada do Estudar, botão flutuante opcional (a barra já tem a ação), recarga sem apagar o mapa |
| `lib/main.dart` | `_TelaNavegacaoState` com a pilha do Mapa, `_voltar`, `_irAoMapa` e retorno tátil; Início sem Sair/Sobre; títulos iguais aos rótulos |
| `test/navigation_shell_test.dart` | Cenário de 768 px (trilho compacto), toque na aba atual, Analisar à vista em 390/768/1280 |
| `test/responsive_test.dart` | Voltar do sistema pelo canal do engine, atalhos sem empilhar, Estudar dentro da aba do Mapa com Voltar em dois passos |

`TelaMapaConceitual` (o antigo "Mapa Conceitual" Fluent) continua no código,
mas segue sem destino, como já estava antes deste redesign: remover ou
reaproveitar é uma decisão à parte.

## 5. Fluxos antes e depois

| Fluxo | Antes | Depois |
|---|---|---|
| Analisar um exercício (de qualquer aba) | celular 1 toque; desktop 2 (Início → passo 1) ou abrir o Mapa e achar o FAB | 1 toque em toda largura; o Mapa fica aberto no painel de análise |
| Ver o Mapa e depois a Lista | Mapa (página) → Voltar (cai no Início, não na Lista) → Lista = 3 | Mapa → Lista = 2; o Mapa continua carregado |
| Estudar e voltar ao Mapa | funcionava, mas sem a barra; pedir Estudar de novo empilhava outro | Estudar abre dentro da aba; Voltar mostra o Mapa; pedir de novo só mostra o que já está aberto |
| Sair | 3 pontos de entrada, um deles ao lado do título do Início | 1 por layout, na área de conta, com confirmação |
| Tablet em pé / celular deitado | barra inferior ocupando altura | trilho compacto na lateral |

## 6. Validação

- `flutter test --reporter compact`: todos os testes passam (as 4 prévias
  golden continuam puladas sem `GENERATE_PREVIEWS`).
- `flutter analyze`: sem avisos. `dart format --set-exit-if-changed lib/`: ok.
- Emulador Pixel 10 Pro XL (`emulator-5554`, build de depuração instalado por
  cima da sessão já aberta, sem digitar senha):
  - Início com título "Início", sem Sair na barra e sem Sobre no fim; cápsula
    com Início · Lista · Mapa · Caderno · Mais e o botão redondo de analisar.
  - Mapa como aba: pílula violeta em "Mapa", cápsula à vista, dados reais
    carregados, sem FAB repetido.
  - Mais com Estudar com a IA · Sobre o App · Sair (sem Admin: a conta de
    teste não é administradora).
  - Estudar aberto pelo Mais dentro da aba do Mapa; Voltar do sistema mostrou
    o Mapa com os filtros intactos; segundo Voltar levou ao Início.
  - Botão redondo: Mapa já rolado até o painel "Analisar exercício com IA".
  - Janela média (`wm density 280` → 768 dp): trilho compacto à esquerda com
    analisar no topo, quatro destinos e Mais. Janela expandida (paisagem,
    ~997 dp): trilho largo com Analisar cheio, SEU ESTUDO e os destinos.
  - Três defeitos encontrados só no aparelho e corrigidos: o painel do trilho
    compacto não preenchia a altura (a `Row` não esticava os filhos); em
    paisagem, o recorte da câmera à esquerda comia 38 dp do trilho largo e
    "Meus exercícios" quebrava no meio da palavra (o trilho agora soma o
    recuo esquerdo da área segura à sua largura); e as páginas Material
    (Mapa, Estudar) deixavam os ícones da barra de status brancos, piscando
    de cor a cada troca de aba e sumindo sobre o trilho claro (o tema
    Material agora usa `SystemUiOverlayStyle.dark`, como as páginas Fluent).
  - Nota: lançar o build de depuração com `flutter test` ou `flutter build`
    rodando em paralelo deixa o emulador sem CPU para o primeiro quadro:
    captura preta e ANR "Application does not have a focused window". Não é
    defeito do app; relançado sozinho, o app abre em ~15 s.

Não validado neste ciclo: tablet e dobrável físicos, leitor de tela real
(TalkBack) e Windows/Web com mouse além dos testes de hover já existentes.
