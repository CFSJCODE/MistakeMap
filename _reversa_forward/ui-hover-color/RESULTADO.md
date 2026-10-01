# MistakeMap — hover progressivo e botões de navegação uniformes

Data: 01/10/2026.

## Objetivo e resultado

Aplicar uma transição de cor da superfície original até o azul da marca (#1E5CA7) ao reconhecer hover, com retorno gradual ao retirar o ponteiro. O refinamento adicional do usuário usa o botão Início como referência para todos os destinos do menu.

Após o pedido de tornar o efeito mais lento, o hover compartilhado usa 480 ms e easeInOutCubic, com início e fim mais graduais, tanto ao entrar quanto ao sair. A duração e a curva de abrir/voltar páginas foram preservadas. Navegação mantém os Button e HoverButton nativos do Fluent; os controles principais usam subclasses dos botões Fluent que preservam estilos, foco, atalhos, callbacks e semântica, com preenchimento e tinta coordenados. Material usa backgroundBuilder porque animationDuration sozinho não interpola o preenchimento no SDK instalado. As animações não aplicam zoom ou desfoque adicional.

Textos e ícones usam o contraste do preenchimento efetivamente pintado. Enquanto a superfície escurece, a tinta original escurece somente quando necessário e passa a branco quando o preenchimento permite a leitura. Uma interpolação direta entre tinta azul e branca perderia contraste no meio da transição. Testes verificam contraste mínimo de 4,5:1 em amostras durante o hover dos controles Fluent e Material.

Todos os botões do menu compartilham o gradiente #F4F9FD → #DCEAF8, borda #A9C6E4, superfície de ícone #D2E4F7 com borda #9EBBDD, cantos, respiro e peso semibold do Início. A seta e a semântica continuam identificando a seção selecionada. Desktop, navegação móvel e itens do menu Mais preservam a mesma linguagem visual.

Controles de ação, barra, hyperlinks, cartão de exercício clicável, cinco itens dos menus flutuantes de exercícios/administração e botões das telas de IA seguem o hover progressivo. Os estados desativados não recebem hover; foco de teclado permanece visível; movimento reduzido usa duração zero. Rascunhos, rotas e pausas de animações de telas ocultas implementados anteriormente foram preservados. Os textos Analisar com IA e Sobre ficaram alinhados à esquerda, na mesma posição dos demais destinos, reservando o espaço da seta.

## Arquivos

- appmistakemap/lib/theme/motion.dart — duração compartilhada.
- appmistakemap/lib/theme/design_tokens.dart — tinta legível durante a mudança de cor.
- appmistakemap/lib/theme/control_styles.dart — controles Fluent animados.
- appmistakemap/lib/main.dart — adoção dos controles e remoção de overrides incompatíveis.
- appmistakemap/lib/layout/navigation_shell.dart — hover e uniformização do menu.
- appmistakemap/lib/ai/material_control_styles.dart — novo helper de animação Material.
- appmistakemap/lib/ai/ai_material_shell.dart — temas Material.
- appmistakemap/lib/ai/exercise_submission_view.dart — botões e seleção de fonte de imagem.
- appmistakemap/lib/ai/insights_view.dart — controles, conceitos e tentativas clicáveis.
- appmistakemap/test/hover_color_test.dart — novas verificações da cor efetivamente pintada, contraste, retorno, estados desativados, movimento reduzido, foco e ação única.
- appmistakemap/test/responsive_test.dart — finder aceita subclasses de Button mantendo a verificação de largura do botão Sobre.

## Validação

- Análise completa Flutter: nenhuma ocorrência.
- Novos testes de hover: 14 aprovados.
- Navegação responsiva: 6 aprovados, inclusive 320 px com texto 2×.
- Suíte completa final: 129 aprovados, 4 ignorados por condições previstas, nenhuma falha; registro em tests.log.
- git diff --check: nenhum erro de espaços; aviso de normalização LF/CRLF preexistente no arquivo de teste responsivo.
- Prévia recompilada e recarregada no Edge em http://localhost:8765/. Conferência real do menu uniforme, hover azul/branco no botão Sobre da Home e no botão de adicionar foto da IA, abertura e retorno do formulário sem envio de dados.
- Capturas: menu-uniforme.jpg (tela completa), menu-detalhe.jpg (recorte de navegação), menu-hover.jpg e ia-hover.jpg. A prévia foi deixada no Início.

## Limites

Não houve chamada nova de IA, mudança de dados, autenticação, dependências ou serviço remoto. Campos de seleção do SDK e expansores de conteúdo conservam suas próprias interações; o tratamento novo cobre os botões e superfícies de ação definidos pelo aplicativo. Não foram medidos FPS ou desempenho em aparelho físico.

A prévia local depende do servidor de desenvolvimento já ativo. A disponibilidade do hook global de sincronização não foi confirmada; o resumo final pode não ser sincronizado. Nenhuma chamada manual adicional ao diário foi realizada.
