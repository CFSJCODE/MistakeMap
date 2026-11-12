# MistakeMap — navegação e efeitos suaves

Inclui o refinamento solicitado após o vídeo: efeito ao passar o mouse e velocidade das transições.

## Resultado

Transições compartilhadas de 240 ms ao abrir uma tela e 180 ms ao voltar, com easeOutCubic, opacidade e deslocamento de até 6 px. Seleção das seções usa uma entrada de 180 ms, deslocamento de até 3 px e variação discreta de opacidade de 0,985 a 1. Conteúdo não recebe zoom nem desfoque animado. O builder das rotas é reutilizado durante os quadros da animação.

O destaque ao passar o mouse usa 180 ms; seleção e controles usam 160 ms. A propriedade fasterAnimationDuration do Fluent controla a decoração dos botões e foi ajustada explicitamente: o ajuste anterior de fastAnimationDuration não alterava esse efeito, que mantinha o padrão de 83 ms do SDK instalado. O destaque recebeu cores menos intensas; ícones mantêm a cor do desenho durante a transição, e o espaço da seta fica reservado para evitar deslocar rótulos ao selecionar uma seção. Botões Material da IA preservam o tratamento anterior. Rotas, seleção de seções e controles respeitam a preferência de reduzir animações; a entrada em curso é encerrada ao ativar essa preferência, preservando o estado do conteúdo. Interações do vidro usam escala 0,98, sem estiramento, e não permanecem pressionadas durante arraste nos botões da barra.

As seções são inicializadas somente na primeira visita e permanecem montadas para preservar rascunhos e rolagem. Tickers das telas ocultas são pausados, inclusive quando IA ou Sobre está aberta. Os destinos têm RepaintBoundary para separar repinturas. Lista e mapa mantêm os dados já carregados visíveis durante atualização. A captura do fundo estático pelo vidro foi desativada nos dois GlassScaffold; a identidade visual, os títulos nítidos e as superfícies claras foram preservados.

IA e Sobre bloqueiam novas aberturas enquanto uma rota já está aberta. O bloqueio é liberado em finally, com verificação de mounted. O fechamento do menu móvel antes de abrir a rota, implementado anteriormente, foi preservado.

## Arquivos alterados nesta etapa

- appmistakemap/lib/theme/motion.dart (novo)
- appmistakemap/lib/main.dart
- appmistakemap/lib/layout/navigation_shell.dart
- appmistakemap/lib/ai/ai_material_shell.dart
- appmistakemap/lib/ai/exercise_submission_view.dart
- appmistakemap/lib/ai/insights_view.dart
- appmistakemap/test/motion_test.dart (novo)
- appmistakemap/test/responsive_test.dart
- appmistakemap/test/navigation_shell_test.dart (refinamento após o vídeo)

## Validação

- flutter analyze --no-pub: nenhuma ocorrência.
- Suíte completa atualizada: 115 testes aprovados, 4 ignorados por condições previstas, nenhuma falha. Registro em refinement-tests.log.
- Nove verificações novas ao longo desta etapa: reutilização do builder em push/pop; movimento reduzido sem espera; trocas rápidas e estado; interrupção da entrada por acessibilidade; visita sob demanda e rascunho; pausa/retomada dos tickers; inicialização sob demanda e prevenção de clique duplo no menu real; passagem rápida do mouse com geometria estável; a mesma passagem com movimento reduzido.
- Cobertura responsiva existente preservada: 320 px, texto ampliado 2×, 390 px e desktop, abertura e retorno da IA, lista/detalhe e painel administrativo.
- Prévia local recompilada e recarregada em http://localhost:8765/. Após o refinamento, conferência real no Edge do destaque ao passar o mouse, seleção de Meus exercícios, abertura de Sobre, retorno mantendo a seção anterior e volta ao Início. Formulário da IA foi conferido na etapa anterior. Nenhuma tentativa nova foi enviada à API.
- Captura real atualizada: menu-refinado.jpg. A prévia foi deixada aberta no Início. O servidor atual depende da sessão de terminal; detalhes e iniciador manual em ../desktop-preview/RESULTADO.md.

## Limites e pendências

Não foram medidos FPS, tempo por quadro ou desempenho em aparelho nativo. Os resultados verificam correção e retenção de estado; não representam garantia de ausência de engasgos em todo dispositivo. O custo de rede e da resposta da IA continua dependendo dos serviços.

Nenhum pacote, pubspec, autenticação, faturamento ou serviço remoto foi alterado. As pendências anteriores de integração nativa de conectividade e sincronização dos arquivos canônicos do backend permanecem registradas em ../ui-polish/RESULTADO.md. A política Reversa permitiu somente lib/** e test/**; artefatos desta validação estão na pasta própria do framework.

A disponibilidade do hook global de sincronização não foi confirmada; o resumo final pode não ser sincronizado.
