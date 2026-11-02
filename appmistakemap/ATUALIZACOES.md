# Atualizações do app sem reinstalar

O MistakeMap instalado (Android e Windows) se atualiza sozinho por duas vias.
A web não precisa de nada disso: cada deploy na Vercel já é a versão nova para
todo mundo.

| Via | O que muda | Como chega ao aparelho | Precisa reinstalar? |
|---|---|---|---|
| **Patch de código** (Shorebird) | Código Dart: telas, regras de UI, textos, correções | Download em segundo plano; vale no próximo início do app | Não |
| **Release nativo** (GitHub Releases) | Plugin novo, `AndroidManifest`, código nativo, versão do Flutter, ícone | O app avisa e oferece o APK/ZIP em *Sobre o App* | Sim, por cima da atual (os dados ficam) |

## Como funciona no aparelho

Código em `lib/atualizacao/`:

- `atualizacao_codigo.dart` — `AtualizadorCodigo` consulta o Shorebird
  (`checkForUpdate`) e, se houver patch, baixa (`update`). Consultas
  simultâneas viram uma só e há intervalo mínimo de 30 min entre elas.
- `versao_nativa.dart` — `VerificadorVersaoNativa` lê
  `GET https://api.github.com/repos/CFSJCODE/MistakeMap/releases/latest`
  (repo público, sem token) no máximo a cada 6 h e compara o build da tag
  `v<versão>+<build>` com o instalado.
- `servico_atualizacao.dart` — `ServicoAtualizacao` liga tudo ao ciclo de
  vida: verifica ao abrir, ao voltar para o app, ao ir para segundo plano
  (`onPause`/`onHide`) e de hora em hora com o app aberto. Iniciado no `main`
  depois do `runApp`; nunca bloqueia a abertura.
- `versao_app.dart` — versão e build embutidos no binário. **Precisam casar
  com o `version:` do `pubspec.yaml`** (o teste `atualizacao_test.dart` falha
  se não casarem).

Na interface: um aviso (toast) quando o patch termina de baixar ou quando
existe release nativo novo, e o cartão **Versão do App** no fim de *Sobre o
App*, com a versão, o patch atual, o botão *Baixar versão X* e *Procurar
atualizações*.

O código em execução nunca é trocado no meio do uso. No Android o sistema
costuma encerrar o app em segundo plano; na próxima abertura o patch já está
aplicado. No Windows, vale ao fechar e abrir de novo.

Builds de `flutter run`/`flutter build` (e o modo debug) não têm o motor do
Shorebird: o cartão mostra que as atualizações automáticas só valem para o
release oficial, e nada é consultado.

## Configuração (uma vez só)

Precisa ser feito pelo Cláudio, na máquina dele (`D:\MistakeMap`):

1. **Conta e CLI do Shorebird**
   ```powershell
   # Instalar (PowerShell)
   Set-ExecutionPolicy RemoteSigned -scope CurrentUser
   iwr -UseBasicParsing 'https://raw.githubusercontent.com/shorebirdtech/install/main/install.ps1' | iex
   shorebird login
   ```
2. **Inicializar o projeto** (gera `appmistakemap/shorebird.yaml` com o
   `app_id` e o adiciona aos `assets` do `pubspec.yaml`):
   ```powershell
   cd D:\MistakeMap\appmistakemap
   shorebird init
   shorebird flutter versions list   # confirme que 3.47.2 está na lista
   ```
   Faça commit do `shorebird.yaml` e do `pubspec.yaml`. O `app_id` não é
   segredo.
3. **Token de CI**: `shorebird login:ci` imprime um token. Salve como secret
   **`SHOREBIRD_TOKEN`** em *GitHub → Settings → Secrets and variables →
   Actions*. Não grave o token em arquivo nenhum do repo.
4. **Chave de assinatura Android** (todo APK distribuído precisa da mesma
   chave, senão o Android recusa instalar por cima):
   ```powershell
   keytool -genkey -v -keystore $env:USERPROFILE\mistakemap-release.jks `
     -keyalg RSA -keysize 2048 -validity 10000 -alias mistakemap
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\mistakemap-release.jks")) | Set-Clipboard
   ```
   Secrets: `ANDROID_KEYSTORE_BASE64` (o texto copiado),
   `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`mistakemap`) e
   `ANDROID_KEY_PASSWORD`. Guarde o `.jks` fora do repo e com backup: perder a
   chave obriga todos a desinstalar e instalar de novo.
   Para builds locais assinados, crie `appmistakemap/android/key.properties`
   (já ignorado pelo Git) com `storeFile`, `storePassword`, `keyAlias` e
   `keyPassword`. Sem esse arquivo o release continua usando a chave de
   debug, como antes.

> O APK atual (assinado com a chave de debug do PC) não aceita o novo por
> cima. Na primeira instalação do release oficial, desinstale o antigo.
> Os dados do Supabase voltam ao entrar; o caderno local não sincronizado se
> perde, então sincronize antes.

## Publicar

### Primeiro release (ou qualquer mudança nativa)

1. Suba a versão em `pubspec.yaml` (`version: 1.0.1+2`) **e** em
   `lib/atualizacao/versao_app.dart` (`versaoApp = '1.0.1'`, `buildApp = 2`).
   No primeiro release pode manter `1.0.0+1`.
2. Merge no `main`.
3. *Actions → Release nativo (Shorebird) → Run workflow*. O workflow:
   - roda `shorebird release android --artifact apk` e
     `shorebird release windows` (Flutter 3.47.2);
   - publica `MistakeMap-<versão>-android.apk` e
     `MistakeMap-<versão>-windows.zip` no release `v<versão>+<build>`.
4. Os apps antigos passam a mostrar *Baixar versão X* em Sobre o App.

### Patch (só código Dart)

- **Automático**: depois do primeiro release, crie a variável de repositório
  `SHOREBIRD_AUTO_PATCH = true` (*Settings → Secrets and variables → Actions →
  Variables*). Cada push no `main` que mexe em `appmistakemap/lib/**` publica
  um patch para o release da versão atual do pubspec.
- **Manual**: *Actions → Patch de código (Shorebird) → Run workflow*. O track
  `staging` serve para testar antes (o app consulta o `stable`).
- Para testar um patch no emulador antes de liberar:
  `shorebird preview --release-version 1.0.0+1`.

Quando o patch falha de propósito:

- **Mudança nativa detectada** (plugin novo, Gradle, manifest): faça um
  release nativo novo.
- **Release da versão não existe**: a versão do pubspec subiu; rode o release
  nativo primeiro.

Se um patch sair com problema, desative ou volte o patch no console do
Shorebird (console.shorebird.dev); os aparelhos removem o patch na próxima
consulta.

## Limites

- iOS fica fora por enquanto (sem Mac); o Shorebird suporta quando houver.
- Assets novos (imagens, fontes) vão no patch; mudanças nativas não.
- O plano gratuito do Shorebird tem limite mensal de instalações com patch;
  confira o plano atual em shorebird.dev/pricing.
