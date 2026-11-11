# MistakeMap Equipe

App separado para quem desenvolve e administra o MistakeMap. É o mesmo código do
app dos alunos, compilado com `MISTAKEMAP_TEAM_BUILD=true`: tem o app inteiro
(Início, Exercícios, Mapa, Caderno, Estudar…) e, para contas admin, o painel
Administração. Toda mudança no `main` chega nele automaticamente.

## O que muda em relação ao app dos alunos

| | App dos alunos | MistakeMap Equipe |
|---|---|---|
| Quem entra | Qualquer conta | Só contas com `profiles.role` = `admin` ou `developer` |
| Atalhos no login | Nunca (nem compilados no release) | Só no build local, com `.env.team.local` |
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
  baixa sozinho e usa na próxima abertura) e uma linha nova nas notas do
  pré-release.

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

O build de CI não leva e-mail nem senha.

## Observação

O login com Google volta pelo esquema `io.supabase.mistakemap://`. Num celular
com os dois apps, o Android pode perguntar qual abrir; escolha
"MistakeMap Equipe".
