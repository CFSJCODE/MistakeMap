# Melhorias de visual, UI e UX — MistakeMap

Estado: inspeção concluída; implementação no aplicativo bloqueada pela configuração atual `allowLegacyEdits: false`. Este documento é uma proposta, não código aplicado nem validação visual do app em execução.

## Evidências atuais

- Não foi encontrado DESIGN.md no inventário do projeto.
- `appmistakemap/lib/main.dart` já usa Fluent UI e Liquid Glass. O componente compartilhado `_PaginaVidro` usa `GlassScrollEdgeStyle.blur`, título de uma linha e barra de 44 pixels. Verificar recorte e sobreposição com fonte ampliada antes de preservar esses parâmetros.
- A tela Sobre usa destaque opaco com gradiente `#142A4A` → `#1E5CA7`, título branco, raio de 16 pixels, espaços de 8/12/24/32 pixels e coluna de leitura limitada a 720 pixels. Essa é a referência principal de identidade.
- `appmistakemap/lib/theme/blue_palette.dart` define outra paleta. Harmonizar pela referência da tela Sobre, evitando substituir a marca por essa paleta divergente.
- `appmistakemap/lib/ai/ai_material_shell.dart` usa um tema Material separado. Alinhar suas superfícies e tipografia ao restante do app.
- `appmistakemap/pubspec.yaml` já declara `fluent_ui` e `liquid_glass_widgets`; não é necessário adicionar bibliotecas apenas para começar essa melhoria.

## Proposta aplicável

1. Centralizar os tokens da identidade da tela Sobre: cores, superfícies, tipografia, raios e espaçamento com ritmo de 4/8 pixels. Escala inicial proposta: corpo 16, legenda 12, seção 20 e destaque 28/32, respeitando ampliação de fonte.
2. Usar Fluent nos controles, foco, hierarquia e estados de interação. Manter o gradiente azul nos destaques principais e superfícies estáveis nos textos, formulários e resultados de IA.
3. Restringir vidro a navegação e controles flutuantes. Desfoque deve afetar somente o fundo, nunca os títulos e ícones. Recortar os efeitos aos limites do componente; não empilhar vidro sobre vidro. Oferecer superfície opaca quando houver necessidade de contraste ou redução de efeitos.
4. Rever `_PaginaVidro`, `_paddingCorpo` e a barra inferior para que o início e o fim do conteúdo permaneçam acessíveis. Validar com rolagem, teclado aberto, fonte ampliada e áreas seguras.
5. Harmonizar início, cadastro, exercícios, adicionar/editar, detalhes, mapa, administração e o fluxo de IA com a mesma linguagem. Reutilizar cabeçalhos e cards sem replicar o destaque grande em todas as telas.
6. Melhorar estados vazios, carregamento, erro e ações principais; manter rótulos claros e erros próximos aos campos. Distinguir processamento de IA, resultado e falha sem depender apenas da cor.

## Validação pendente

- Análise estática e testes dos fluxos afetados após a implementação.
- Revisão visual em larguras de 360, 390, 768 e 1280 pixels; fonte padrão e ampliada; foco por teclado; teclado virtual; rolagem completa.
- Contraste mínimo proposto de 4,5:1 para texto comum e 3:1 para texto grande e componentes relevantes.
- Conferir todas as telas afetadas para títulos borrados, cortados, cobertos por barras, campos inacessíveis e controles sobrepostos. Não atribuir a causa do borrão do anexo sem reproduzir no aplicativo.

## Liberação necessária pelo usuário

Editar exclusivamente pelo usuário `.reversa/reversa-config.json`, preservando outros campos, para `allowLegacyEdits: true` e `allowedPaths: ["appmistakemap/lib/**", "appmistakemap/test/**"]`. Esse escopo permite a implementação e verificações sem liberar todo o projeto. Nenhuma alteração de dependência está prevista inicialmente.

## Referências consultadas

- https://fluent2.microsoft.design/
- https://fluent2.microsoft.design/components/android/ — referência de método; o app atual é Flutter, não Android nativo.
- https://www.apple.com/br/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ — vidro como camada funcional para navegação e controles.
- https://developer.apple.com/br/documentation/technologyoverviews/adopting-liquid-glass — conteúdo não acessível pela leitura web utilizada, pois requer JavaScript.
