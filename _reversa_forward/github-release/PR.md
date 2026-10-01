O aplicativo passa a usar navegação segmentada, controles consistentes e transições graduais, com apresentação mais clara das funções de IA e das métricas administrativas.

- Uniformiza o menu e os botões Fluent/Material, preserva o estado das páginas e melhora a navegação em telas compactas e desktop.
- Acrescenta métricas de funcionamento, limites por modelo, consumo observado de IA e consulta administrativa restrita.
- Preserva os SQLs e as funções instrumentadas de telemetria em `_reversa_forward/admin-monitoring/`, com documentação e teste específico.
- Atualiza a tela Sobre com foto, link animado do LinkedIn e remoção do rodapé solicitado.

Validação local: `flutter analyze --no-pub` sem problemas; formatação dos 24 arquivos de aplicação verificada; **137 testes Flutter aprovados** e quatro prévias ignoradas; **dois testes de telemetria aprovados**. O link do LinkedIn foi conferido no Edge. APK universal release 1.0.0+1 compilado e validado quanto a manifesto, integridade e assinatura.

No Android/iOS, a conectividade nativa ainda usa a classificação desconhecida e o painel atualiza a cada hora. O adaptador de Wi-Fi está preparado em staging. O APK mantém a assinatura Android Debug já configurada no projeto e ainda não foi instalado em dispositivo nesta entrega.
