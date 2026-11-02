# Aplicativo Flutter: autenticação e navegação

## Visão Geral

Esta unit controla a entrada do estudante no MistakeMap, a restauração da sessão, o carregamento do perfil e a navegação responsiva pelas áreas disponíveis. A navegação administrativa depende do papel do perfil. 🟢

## Responsabilidades

- Observar a sessão do Supabase e exibir carregamento, cadastro/login ou a aplicação autenticada. 🟢
- Autenticar por e-mail/senha e oferecer OAuth Google nas plataformas habilitadas. 🟢
- Carregar perfil com papel padrão seguro e construir os destinos adaptáveis. 🟢
- Permitir acesso à tela Sobre sem misturá-la às rotas principais. 🟢

## Regras de Negócio

- Apenas o papel `admin` habilita a área administrativa. 🟢
- Falha de atualização do stream não deve apagar uma sessão ainda presente no cliente Supabase. 🟢
- O callback Web preserva origem e caminho atuais, removendo query e fragmento; OAuth Google é exposto em Web e Android. 🟢
- O fluxo de recuperação de senha não foi localizado. 🔴

## Requisitos Funcionais

| ID | Requisito | Prioridade | Critério de Aceite |
|---|---|---|---|
| RF-01 | Observar a sessão e encaminhar o usuário para a tela adequada. 🟢 | Must | Sessão ausente mostra autenticação; sessão válida carrega o shell. |
| RF-02 | Permitir cadastro e login por e-mail/senha, incluindo estado de confirmação de e-mail. 🟢 | Must | Resultado da autenticação atualiza a tela sem expor exceções internas. |
| RF-03 | Resolver papel do perfil com fallback não privilegiado. 🟢 | Must | Falha de leitura nunca concede acesso administrativo. |
| RF-04 | Oferecer OAuth Google apenas em plataformas suportadas e montar callback adequado. 🟢 | Should | Web retorna à origem/caminho; Android usa callback configurado. |
| RF-05 | Apresentar navegação adaptada ao espaço disponível e ao papel. 🟢 | Must | Destinos permanecem acessíveis em largura móvel e desktop. |
| RF-06 | Recuperar senha pela interface. 🔴 | Could | Não foi solicitado explicitamente nem localizado no código; considerar em evolução futura. |

## Requisitos Não Funcionais

| Tipo | Requisito inferido | Evidência no código | Confiança |
|---|---|---|---|
| Segurança | Papel ausente ou falha de perfil não concede privilégios. | `appmistakemap/lib/main.dart` | 🟢 |
| Disponibilidade | Falha de refresh conserva a sessão local ainda válida. | `appmistakemap/lib/main.dart` | 🟢 |
| Usabilidade | Navegação responde à largura da janela e escala de texto. | `appmistakemap/lib/layout/adaptativo.dart` | 🟢 |

## Critérios de Aceitação

```gherkin
Dado um estudante com sessão válida
Quando o AuthGate recebe a sessão
Então carrega o perfil e apresenta a navegação autenticada apropriada

Dado um estudante sem sessão
Quando o aplicativo termina a inicialização
Então apresenta cadastro/login sem exibir áreas protegidas

Dado um stream de autenticação com falha de refresh e sessão ainda válida
Quando o AuthGate atualiza a interface
Então mantém a sessão e não retorna ao estado de visitante

Dado um perfil cuja consulta falhou
Quando o shell autenticado é construído
Então usa papel não administrativo e oculta a área de administração
```

## Prioridade (MoSCoW)

| Requisito | MoSCoW | Justificativa |
|---|---|---|
| Restauração e proteção da sessão | Must | Porta de entrada de todas as áreas autenticadas. |
| Login/cadastro e navegação principal | Must | Fluxo crítico para uso do app. |
| Navegação adaptativa | Should | Necessária para suportar dispositivos móveis e desktop. |
| OAuth Google | Should | Alternativa de autenticação já implementada. |
| Recuperação de senha | Could | Funcionalidade não confirmada e fora do escopo atual do briefing. |

## Rastreabilidade de Código

| Arquivo | Função / Classe | Cobertura |
|---|---|---|
| `appmistakemap/lib/main.dart` | `AuthGate`, `_carregarPerfil`, navegação autenticada | 🟢 |
| `appmistakemap/lib/auth/google_sign_in.dart` | `GoogleSignInService.signIn`, `googleOAuthRedirect` | 🟢 |
| `appmistakemap/lib/layout/navigation_shell.dart` | Shell de navegação | 🟢 |
| `appmistakemap/lib/layout/adaptativo.dart` | Layout responsivo | 🟢 |
