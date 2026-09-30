# Login Google — configuração e validação

O aplicativo consulta as configurações públicas do Supabase antes de iniciar o
OAuth. Se o Google não estiver habilitado, permanece na tela de login e informa
a indisponibilidade, oferecendo o acesso por e-mail e senha. Falhas de rede ou
respostas inválidas são informadas separadamente e permitem uma nova tentativa.

Esta correção do cliente **não habilita o provedor Google** e não configura um
cliente OAuth no Google Cloud. Essa configuração deve ser feita por quem
administra o projeto, sem colocar o client secret no aplicativo ou no Git.

## URLs e configuração administrativa

1. No Google Cloud, configure um cliente OAuth do tipo aplicativo Web e adicione
   exatamente este URI de redirecionamento autorizado:

   ```text
   https://bmdjicshcjpknuaywaph.supabase.co/auth/v1/callback
   ```

   Esse é o retorno do Google para o Supabase, não a URL local do aplicativo.

2. No projeto Supabase `bmdjicshcjpknuaywaph`, abra Authentication → Sign In /
   Providers → Google. Configure o client ID e o client secret no painel e
   habilite o provedor. Restrinja a audiência e os usuários de teste conforme
   o estado do aplicativo OAuth no Google Cloud.

3. Em Authentication → URL Configuration, defina o Site URL da hospedagem real
   e inclua em Redirect URLs os retornos efetivamente usados. A prévia local
   desta entrega usa:

   ```text
   http://127.0.0.1:65360/
   ```

   Uma prévia iniciada manualmente na porta 8080 usa:

   ```text
   http://127.0.0.1:8080/
   ```

   `localhost` e `127.0.0.1` são hosts diferentes; cadastre o endereço que estiver
   usando. Para hospedagem em subpasta, cadastre a URL incluindo esse caminho.
   A aplicação web retorna ao mesmo caminho atual, sem query ou fragmento.
   Não cadastre um curinga global apenas para fazer o teste passar.

4. Para o aplicativo Android, preserve também o retorno existente:

   ```text
   io.supabase.mistakemap://login-callback/
   ```

   O Android registra esse esquema em seu manifesto. O helper preserva o mesmo
   retorno nativo; a configuração de links de iOS, macOS e outros sistemas não
   foi validada nesta correção.

## Verificação

- O endpoint público `https://bmdjicshcjpknuaywaph.supabase.co/auth/v1/settings`,
  consultado com a chave pública no header `apikey`, deve informar
  `external.google: true`. Isso comprova somente a habilitação, não o OAuth
  completo. A chave administrativa `service_role` nunca é necessária no cliente.
- Clique em “Continue com Google”. Com o provedor desabilitado, o aplicativo
  deve apresentar a explicação e permanecer no login.
- Com o provedor habilitado e os retornos cadastrados, faça o fluxo com uma conta
  autorizada: escolha de conta, consentimento quando solicitado, retorno à mesma
  origem web e sessão autenticada no aplicativo. Somente essa sequência valida
  o login de ponta a ponta.
- Timeout, falha HTTP ou resposta inválida da consulta pública devem apresentar
  indisponibilidade temporária, sem afirmar que o provedor está desabilitado.

Os testes locais usam respostas simuladas e não criam contas, alteram usuários
ou configuram provedores remotos:

```sh
flutter test test/google_sign_in_test.dart
```

Referências oficiais: [Google OAuth](https://supabase.com/docs/guides/auth/social-login/auth-google),
[Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls),
[Flutter signInWithOAuth](https://supabase.com/docs/reference/dart/auth-signinwithoauth)
e [configurações públicas do Auth](https://github.com/supabase/auth/blob/master/README.md).
