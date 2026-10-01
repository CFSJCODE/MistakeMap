# Correções de Google e acesso à IA — 30/09/2026

## Diagnóstico e correção

- O método de login em main.dart enviava o deep link nativo também na web. Foi ligado ao helper googleOAuthRedirect existente: web retorna à origem, porta e caminho atuais, sem parâmetros de sessão; nativo mantém seu deep link.
- Limite de dez segundos apenas para iniciar OAuth, tratamento de falha de lançamento e proteção contra cliques duplicados. Esse limite não mede nem interrompe o tempo de escolha da conta ou consentimento no Google.
- As telas de IA existiam mas não eram alcançáveis pela navegação do app inspecionado. Foram conectadas à navegação real com SupabaseAnalysisRepository, usuário autenticado e retorno ao app.
- Novos acessos no início (Analisar exercício com IA), menu desktop (Analisar com IA e Mapa de erros (IA)) e menu Mais no celular. Fluxos manuais preservados.

## Validação

- Configuração pública do Supabase: Google habilitado, consulta respondeu em 687 ms. Não mede latência total do OAuth e não confirma lista de URLs de retorno autorizadas.
- 25 testes de helper OAuth, telas IA e shell passaram.
- Dois testes adicionais na TelaNavegacao real passaram em 390 e 1280 pixels: abrir análise e mapa IA e retornar ao início.
- Suíte completa: 95 aprovados, quatro testes de prévia ignorados e quatro falhas anteriores de lista/detalhe e métricas administrativas.
- Análise estática sem problemas após ajustes de formatação.
- Prévia web recompilada em localhost:8765; acessos IA confirmados visualmente no navegador. Prévia sintética atualizada.
- Login Google completo após seleção da conta, configurações remotas de retorno e inferência real de IA continuam sem validação ponta a ponta. Não foram feitas alterações de Auth remoto, publicação ou submissão de dados para análise.

## Arquivos alterados

- appmistakemap/lib/main.dart
- appmistakemap/lib/layout/navigation_shell.dart
- appmistakemap/test/responsive_test.dart
- appmistakemap/test/previews/navegacao-{390,1280}-synthetic.png

Referência técnica: https://supabase.com/docs/reference/dart/auth-signinwithoauth
