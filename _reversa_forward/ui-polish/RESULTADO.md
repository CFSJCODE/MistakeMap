# Ajustes de apresentação — 30/09/2026

## Resultado

Foto original adicionada ao avatar de Cláudio na tela Sobre, mantendo 52 × 52 pixels, formato circular e identificação acessível. Os bytes incorporados são idênticos ao JPEG fornecido. O avatar do outro integrante permanece com suas iniciais.

Cartões de Gemini reorganizados com nome do modelo, selo de plano gratuito, títulos de corpo, consumo em destaque, limite em tamanho secundário, percentual, barra de progresso e saldo por período. Dados indisponíveis e contagens parciais não recebem saldo fictício. O consumo se refere somente às chamadas observadas pelo aplicativo desde a ativação da telemetria. Valores dos prints históricos não são importados como consumo atual. O diagnóstico não repete as três cotas dos modelos já apresentados.

Botões Fluent e Material e menus de navegação receberam superfícies claras, bordas/reflexos discretos, cantos arredondados, estados de hover/pressionado/foco/desabilitado. A identidade azul da marca foi preservada. Os textos não recebem desfoque de fundo. Seletores da IA têm menus arredondados e altura adaptada à tela.

Corrigido o fechamento do menu móvel antes de abrir as telas de análise ou Sobre. Mantida a remoção do botão de análise na Home; a função continua no menu de IA.

## Arquivos desta etapa

- appmistakemap/lib/main.dart
- appmistakemap/lib/assets/profile_photo.dart
- appmistakemap/lib/theme/control_styles.dart
- appmistakemap/lib/layout/navigation_shell.dart
- appmistakemap/lib/ai/ai_material_shell.dart
- appmistakemap/lib/ai/insights_view.dart
- appmistakemap/lib/admin/metrics_panel.dart
- appmistakemap/lib/admin/model_quota_card.dart
- appmistakemap/test/model_quota_card_test.dart
- appmistakemap/test/responsive_test.dart
- Capturas reais do navegador em screenshots/admin-cotas.jpg, screenshots/sobre-foto.jpg e screenshots/botoes-ia.jpg.

## Validação

- Análise Flutter sem problemas; análise adicional do menu e controles após correção sem problemas.
- Suíte completa: 106 testes aprovados, 4 ignorados por condições já existentes, nenhuma falha.
- Cobertura de telas de 320 px com texto 2×, 390 px e desktop; retorno da IA ao menu; limites parciais/indisponíveis; atualização de hora em hora com painel visível; permissões de administração na navegação.
- Conferência real no navegador: foto da equipe, Home sem botão de análise, menu segmentado, dados administrativos carregados, cartões de cotas e controles do formulário de IA. Não foram enviadas tentativas novas para consumir a cota da API.
- Prévia local atualizada: http://localhost:8765/.

## Pendências anteriores preservadas

A política atual .reversa/reversa-config.json permite alterações somente em appmistakemap/lib/** e appmistakemap/test/**. Nenhum pubspec ou arquivo canônico do backend foi modificado nesta etapa.

O adaptador nativo de Wi-Fi/dados móveis continua preparado em _reversa_forward/admin-monitoring/staged-native/network_source_native.dart, mas sua integração depende da liberação de appmistakemap/pubspec.yaml e appmistakemap/pubspec.lock para a dependência de conectividade. Quando o tipo de conexão é desconhecido, o painel mantém atualização de hora em hora. O fluxo Wi-Fi em dispositivo real não foi validado.

As versões instrumentadas de IA publicadas na etapa anterior estão preservadas em _reversa_forward/admin-monitoring/staged/functions/. A sincronização com os caminhos canônicos supabase/functions/** e appmistakemap/database/supabase/migrations/** continua pendente de liberação desses caminhos; as cópias canônicas antigas não devem substituir a telemetria publicada.

Não houve novo deploy, alteração de faturamento, mudança de autenticação, commit ou push nesta etapa. A sincronização do resumo pelo hook global não foi verificada.
