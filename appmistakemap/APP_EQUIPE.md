# MistakeMap Equipe

App separado para quem desenvolve e administra o MistakeMap. É o mesmo código do
app dos alunos, compilado com `MISTAKEMAP_TEAM_BUILD=true`: tem o app inteiro
(Início, Exercícios, Mapa, Caderno, Estudar…) e, para contas admin, o painel
Administração. Toda mudança no `main` chega nele automaticamente.

## O que muda em relação ao app dos alunos

| | App dos alunos | MistakeMap Equipe |
|---|---|---|
| Quem entra | Qualquer conta | Só contas com `profiles.role` = `admin` ou `developer` |
| Atalhos no login | Nunca (nem compilados no release) | Releases: só o e-mail; build local: o que estiver no `.env.team.local` |
| Criar conta | Sim | Não |
| Android | `com.example.appmistakemap` | `com.example.appmistakemap.equipe` (instala ao lado) |
| Shorebird | app dos alunos (`shorebird.yaml`) | app próprio (`shorebird.equipe.yaml`) |
| GitHub Releases | `v<versão>`, marcado como Latest | `equipe-v<versão>`, pré-release |

O papel continua sendo decidido no banco. `developer` usa o app como um usuário
comum (`is_admin()` só aceita `admin`); um admin promove pelo painel
Administração (menu do usuário → "Tornar desenvolvedor"). Ninguém troca o
próprio papel (`user_manage_own_profile`).

## Atualização automática

O workflow `.github/workflows/team-app.yml` roda a cada push no `main` que muda
o app:

- versão do `pubspec.yaml` ainda sem release da equipe → release nativo no
  Shorebird e pré-release `equipe-v<versão>` com o APK e o ZIP do Windows;
- versão que já tem release da equipe → patch do Shorebird (o app instalado
  baixa sozinho e usa na próxima abertura), uma linha nova nas notas do
  pré-release e o APK `MistakeMap-Equipe-<versão>-atual-android.apk` com o
  código do commit, substituído a cada patch.

Assim todo push que muda o app deixa um APK no GitHub. O APK `-atual` é um
build Flutter comum: instala a versão mais nova na hora, mas não recebe patches
do Shorebird. Para atualização automática, instale o APK da versão (sem
`-atual`).

O automático gera só o Android. O Windows sai quando você roda o workflow à
mão (Actions → App da equipe → Run workflow) com **incluir_windows** marcado:
o runner Windows gasta o dobro de minutos do Actions. Se a versão ainda não
tem o ZIP do Windows no pré-release, ele faz o release nativo; senão, patch.

Patches dos alunos nunca chegam no app da equipe e vice-versa: cada um tem seu
`app_id`. O app da equipe também avisa quando sai um `equipe-v…` mais novo.

Primeira vez: rode o workflow à mão com **criar_app_shorebird** marcado. Ele cria
o app "MistakeMap Equipe" no Shorebird e mostra o `app_id`; grave em
`appmistakemap/shorebird.equipe.yaml` (`app_id: …`) e faça commit no `main`.

## Build local com atalhos de login

1. Copie `appmistakemap/.env.team.local.example` para
   `appmistakemap/.env.team.local` (o Git ignora o arquivo).
2. Preencha a conta de desenvolvimento e o e-mail admin. Deixe
   `MISTAKEMAP_ADMIN_PASSWORD` vazio: o atalho preenche o e-mail e você digita a
   senha. O que estiver no arquivo vai compilado dentro do APK/EXE local.
3. Na raiz do repositório, no Windows:

```powershell
.\scripts\build-equipe.ps1            # APK e Windows na Área de Trabalho
.\scripts\build-equipe.ps1 -Alvo run  # roda no emulador/dispositivo conectado
```

O APK/ZIP dos Releases (build de CI) também tem os atalhos, mas só com o
e-mail das contas demo (`dev.demo@mistakemap.dev` e `admin.demo@mistakemap.dev`):
o atalho preenche o e-mail e você digita a senha. Senha nunca entra no build de
CI, porque os Releases são públicos.

## Perfis

Nos dois apps, toda abertura (depois da apresentação) e todo "voltar ao
início" passam pela mesma ordem:

1. "Como você vai entrar?": os 7 perfis (estudante, estudante + equipe,
   professor, responsável, dono, coordenação, TI).
2. Login com e-mail e senha da conta desse perfil. Uma sessão salva no
   aparelho não pula esta etapa. Nessa entrada não há login com Google.
3. O app consulta o servidor (user_signups, school_members, vínculos de
   responsável, sob RLS) e só abre se a conta tiver o perfil escolhido
   (`motivoPerfilRecusado` em `lib/school/perfil_modelos.dart`). Sem o perfil,
   sai da conta e avisa. O modo estudante vale para toda conta; conta nova
   segue para o "Quem é você?".

Sem internet só dá para entrar como estudante, com a conta que já entrou no
aparelho, porque o servidor não pode conferir papel de escola.

O app da equipe nunca mostra o "Quem é você?". As contas dev.demo e
admin.demo têm os 6 papéis da escola demo, então entram em qualquer perfil. O
seletor "Perfil" no topo troca entre os papéis da conta sem outro login, e a
seta ao lado dele volta ao início.

## Central da Equipe

No app da equipe, admin e desenvolvedor têm o destino **Central da Equipe**
(no lugar de Administração; para admins, a Administração abre de dentro dela).
Tudo vem de funções do banco que conferem o papel (`is_team_member()`), com
agregados técnicos apenas: nada de e-mail de aluno, conteúdo ou credencial.

| Seção | O que mostra | Backend |
|---|---|---|
| Saúde | Semáforo, uso (contas, ativos, tentativas, análises), IA (modelos e chamadas), pg_cron, fila, banco, cobrança | `team_console_snapshot()` |
| Erros | Falhas 429/5xx das Edge Functions por função e código, incluindo `invalid_ai_output` (30 dias). Erros do app (aluno e equipe) por versão/build/patch e por assinatura (tipo + arquivo:linha), com contas afetadas, para conferir se um patch resolveu ou trouxe um erro | `team_error_events` (gravada por `ai_http.failure()`), `app_error_events` (gravada pelo app via `report_app_error`), `team_app_errors()` |
| Diagnóstico | **Validar deploy**: teste de fumaça sem custo de cada Edge Function (chamada só de leitura ou ação inválida que precisa voltar 400; sem IA, sem cobrança, sem escrita) e sonda de leitura das tabelas fechadas com a sessão do app. Executor: sessão, latência, `health`, RLS, gabaritos fechados, search_path, pg_cron, fila, exclusões, escola demo sem cobrança real, IA. Copia o relatório para colar num bug | `team_run_diagnostics()` + checagens do app |
| Ferramentas de QA | Conta e papel, volta à escolha de perfil, recomeçar os dados (só contas `@mistakemap.dev`), evento de teste `qa_probe` | `team_reset_own_demo_data()`, `team_log_probe()` |
| Build | Versão, build, patch do Shorebird, modo, plataforma e servidor, com botão de copiar | — |

Migrations: `20261113030000_team_console.sql` e
`20261113060000_app_error_events.sql`.

O relato de erros do app fica em `lib/team/relato_erros.dart` e só roda fora
do modo debug: liga `FlutterError.onError` e `PlatformDispatcher.onError`,
envia tipo, arquivo:linha do primeiro quadro do app, versão, build, patch e
plataforma (nunca a mensagem da exceção), no máximo 3 vezes por assinatura e
20 por abertura do app; o servidor aceita até 30 por conta por hora.

## Observação

O login com Google volta pelo esquema `io.supabase.mistakemap://`. Num celular
com os dois apps, o Android pode perguntar qual abrir; escolha
"MistakeMap Equipe".
