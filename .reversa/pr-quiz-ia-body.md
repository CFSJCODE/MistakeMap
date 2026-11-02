## Resumo

- Corrige a abertura de Estudar, o destaque na barra e os itens do trilho compacto; distingue falha de carregamento de lista vazia.
- Gera novas perguntas ao refazer o quiz da mesma matéria e preserva o resultado anterior em caso de falha.
- Adiciona provedores Anthropic e OpenRouter, seleção baseada em evidências configuradas e Claude como alternativa quando o provedor principal falha.
- Reserva orçamento de forma transacional antes de chamar o Claude, com teto de US$ 100 em janela móvel de 31 dias para chamadas registradas pelo MistakeMap. Reservas sem custo confirmado permanecem contabilizadas.

## Limites conhecidos

- A escolha por qualidade depende de avaliações comparáveis configuradas; elas ainda não foram fornecidas, portanto não há seleção baseada em qualidade ativa.
- O teto não inclui consumo de outras aplicações da organização, e a tarifa do Claude precisa ser revisada antes de dezembro de 2026.
- A migração e as funções correspondentes já foram publicadas no Supabase; a validação completa do fluxo com uma conta real no aplicativo permanece pendente.
- Este PR inclui a correção de navegação também presente no PR #35.

## Validação

- Flutter: 220 testes passaram, 4 ignorados; `flutter analyze --no-pub` sem problemas; formatação verificada.
- Edge Functions: `deno check --frozen */index.ts` e 53 testes passaram.
- APK Android release gerado e instalado no emulador; aplicativo iniciado.
- Reservas e permissões verificadas no banco com rollback; contagem de tokens e resposta estruturada verificadas com a API Claude em teste sintético.
