# Aplicativo Flutter: autenticação e navegação — Design Técnico

## Interface

| Símbolo | Assinatura / entrada | Retorno | Observação |
|---|---|---|---|
| `AuthGate.build` | `BuildContext` | `Widget` | Observa estado de autenticação e seleciona a árvore de telas. 🟢 |
| `_carregarPerfil` | `User supaUser` | `Future<AppUser>` | Lê `profiles.role`; falha resulta em papel `user`. 🟢 |
| `_entrarComEmailSenha` | Dados do formulário | `Future<void>` | Envia credenciais ao Supabase Auth. 🟢 |
| `GoogleSignInService.signIn` | Plataforma e URI atual | `Future<void>` | Pré-verifica provedor e inicia OAuth. 🟢 |
| `googleOAuthRedirect` | `isWeb`, URI atual | `String` | Callback Web conserva origem/caminho; nativo usa scheme do app. 🟢 |

## Fluxo Principal

1. `MistakeMapApp` monta `AuthGate` e assina `onAuthStateChange`. 🟢 (`appmistakemap/lib/main.dart`)
2. Enquanto a sessão é resolvida, a interface apresenta carregamento. 🟢
3. Sem sessão, mostra `TelaCadastro`, que alterna login e cadastro por e-mail/senha. 🟢
4. Após autenticar, `_carregarPerfil` consulta papel do usuário; se falhar, usa `user`. 🟢
5. `TelaNavegacao` monta destinos principais e adiciona Administração somente para `admin`. 🟢
6. O shell seleciona trilho lateral em desktop ou navegação inferior/menu em telas menores. 🟢

## Fluxos Alternativos

- **Cadastro sem sessão imediata:** mantém a tela e solicita confirmação de e-mail. 🟢
- **Refresh do stream falha:** consulta sessão atual e conserva o usuário se a sessão ainda existe. 🟢
- **OAuth indisponível ou não habilitado:** apresenta mensagem específica antes de iniciar fluxo inválido. 🟢
- **Sobre:** abre rota própria, separada dos destinos principais. 🟢
- **Recuperação de senha:** não há fluxo confirmado; não inferir tela ou endpoint. 🔴

## Dependências

- `supabase_flutter`: sessão, Auth e consulta do perfil. 🟢
- `fluent_ui`: estrutura principal da interface. 🟢
- `http`: pré-verificação de configuração OAuth. 🟢
- `appmistakemap/lib/layout/adaptativo.dart`: decisões de breakpoint e escala visual. 🟢

## Decisões de Design Identificadas

| Decisão | Evidência no código | Confiança |
|---|---|---|
| A sessão é observada por stream e protegida contra erro transitório de refresh. | `appmistakemap/lib/main.dart` | 🟢 |
| A falha de perfil aplica papel padrão `user`, evitando promoção de privilégio. | `appmistakemap/lib/main.dart` | 🟢 |
| A navegação altera apresentação conforme largura e papel. | `appmistakemap/lib/main.dart`, `appmistakemap/lib/layout/adaptativo.dart` | 🟢 |
| O OAuth valida configuração antes de abrir o provedor. | `appmistakemap/lib/auth/google_sign_in.dart` | 🟢 |

## Estado Interno

O SDK Supabase mantém a sessão; `AppUser` expõe `id`, `email` e `role`. A seleção do destino é mantida pelo shell de navegação. 🟢

## Observabilidade

Erros de autenticação e OAuth são convertidos em mensagens de interface; logs estruturados ou métricas específicas desta unit não foram confirmados. 🟡

## Riscos e Lacunas

- 🔴 Não foi localizado fluxo de recuperação de senha.
- 🟡 A consulta do perfil usa fallback seguro, mas pode mascarar indisponibilidade como papel `user`.
- 🟢 Os testes cobrem gate de sessão, falha de refresh, OAuth e navegação responsiva; execução Flutter não foi confirmada nesta análise.
