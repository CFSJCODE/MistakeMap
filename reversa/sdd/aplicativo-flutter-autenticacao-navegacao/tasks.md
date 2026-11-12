# Aplicativo Flutter: autenticação e navegação — Tarefas de Implementação

## Pré-requisitos

- [ ] Configurar URL e chave pública do Supabase no ambiente Flutter.
- [ ] Configurar callback OAuth no Supabase e nas plataformas que o habilitam.

## Tarefas

- [ ] T-01, Construir o gate de sessão com estados de carregamento, visitante e usuário autenticado.
  - Origem no legado: `appmistakemap/lib/main.dart`
  - Critério de pronto: sessão válida e ausente levam às telas corretas; erros de refresh não eliminam sessão existente.
  - Confiança: 🟢
- [ ] T-02, Implementar autenticação por e-mail/senha e estado de confirmação de cadastro.
  - Origem no legado: `appmistakemap/lib/main.dart`
  - Critério de pronto: login/cadastro reportam sucesso e falha sem mostrar detalhes internos.
  - Confiança: 🟢
- [ ] T-03, Carregar papel do perfil usando fallback não privilegiado.
  - Origem no legado: `appmistakemap/lib/main.dart`
  - Critério de pronto: falha ou ausência de perfil nunca mostra Administração.
  - Confiança: 🟢
- [ ] T-04, Integrar OAuth Google com callback web e nativo e mensagens de configuração.
  - Origem no legado: `appmistakemap/lib/auth/google_sign_in.dart`
  - Critério de pronto: callback correto em cada plataforma habilitada e erro exposto com mensagem adequada.
  - Confiança: 🟢
- [ ] T-05, Implementar navegação principal responsiva e rota Sobre.
  - Origem no legado: `appmistakemap/lib/layout/navigation_shell.dart`, `appmistakemap/lib/layout/adaptativo.dart`, `appmistakemap/lib/main.dart`
  - Critério de pronto: destinos principais acessíveis em larguras de telefone e desktop; rota Sobre abre e retorna.
  - Confiança: 🟢

## Tarefas de Teste

- [ ] TT-01, Testar inicialização sem sessão e com sessão válida.
- [ ] TT-02, Testar refresh com falha mantendo sessão válida e perfil indisponível sem privilégio.
- [ ] TT-03, Testar callbacks OAuth Web/Android e mensagens de erro.
- [ ] TT-04, Testar navegação em larguras distintas, destino administrativo e rota Sobre.

## Ordem Sugerida

1. Implementar gate e autenticação antes do shell, pois a navegação depende da identidade.
2. Cobrir fallback do perfil antes de liberar o destino administrativo.
3. Implementar OAuth e navegação adaptativa; finalizar com testes de integração/widget.

## Lacunas Pendentes (🔴)

Recuperação de senha não foi encontrada no legado; validar escopo antes de adicioná-la.
