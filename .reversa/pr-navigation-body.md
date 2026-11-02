## Resumo

- Restaura Estudar e Sobre no menu do trilho compacto, evitando um menu vazio em tablets sem opções de conta.
- Mantém os atalhos na barra inferior de celular e ajusta os testes aos pontos de mudança entre barra e trilhos.
- Remove uma comparação desnecessária que gerava aviso no analisador.

## Validação

- `flutter test --no-pub --reporter expanded`: 219 testes passaram, 4 ignorados.
- `flutter analyze --no-pub`: sem problemas.
- `dart format --output=none --set-exit-if-changed lib/`: sem alterações necessárias.

A documentação de navegação ainda descreve cinco fatias; está fora dos caminhos de edição liberados na configuração Reversa.
