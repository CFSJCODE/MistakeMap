# Auditoria de escopo do commit

Data: 2026-10-01. Inspeção somente leitura do projeto; nenhum stage, commit, fetch ou push executado por esta auditoria.

## Mudanças do aplicativo

Ignorando diferenças de fim de linha, há sete arquivos Flutter existentes com alterações de conteúdo: `lib/main.dart`, quatro arquivos de `lib/ai/` e dois testes. Existem também 23 novos arquivos Dart (15 de aplicação e oito testes) ligados a identidade visual, navegação, animações, monitoramento administrativo, cotas Gemini, foto fornecida e botão LinkedIn.

Esses 30 arquivos são o núcleo recomendado para publicação. A foto incorporada em `lib/assets/profile_photo.dart` foi solicitada pelo usuário e faz parte da interface. Seis imagens novas em `test/previews/*-synthetic.png` são prévias de testes, não fotos de uma sessão real; sua inclusão é opcional.

## Monitoramento administrativo

`_reversa_forward/admin-monitoring/` contém três definições SQL, versões instrumentadas das funções Gemini e teste de telemetria. Esses arquivos são relacionados ao pedido anterior de publicar a telemetria e devem acompanhar o código administrativo para registrar a implementação de servidor.

O adaptador `staged-native/network_source_native.dart` é uma preparação, não o código ativo do APK. O aplicativo atual usa `network_source_stub.dart` em Android: a rede é classificada como desconhecida e o painel usa atualização conservadora de uma hora. O reconhecimento nativo de Wi-Fi requer dependência e configuração ainda não aplicadas.

`verify-provider-sql.mjs` depende de PGlite instalado no pacote de verificação de `_reversa_forward/openai-integration/verification/`. Publicá-lo isoladamente não torna a execução reproduzível; incluir também os manifestos de dependência necessários ou documentar essa preparação, sem incluir `node_modules`.

## Exclusões recomendadas

- Centenas de arquivos `.agents/`, `.claude/`, plataforma, Rust, configuração e documentação têm apenas mudança de fim de linha: excluir para evitar ruído.
- `.reversa/reversa-config.json` registra uma permissão local modificada pelo usuário; excluir desta publicação de funcionalidades.
- `.github/workflows/ci.yml` altera os filtros de pull requests e remove comentário sobre checks obrigatórios. É uma mudança real, mas não está relacionada ao visual/telemetria/LinkedIn; excluir sem autorização específica desse ajuste.
- `_reversa_forward/coautoria-chatgpt-6-astra/` contém backup Git e estado histórico de uma outra tarefa; excluir.
- `_reversa_forward/openai-integration/staged/` contém uma versão anterior alternativa do aplicativo/servidor, não a implementação atual do pedido; excluir para não publicar cópias divergentes.
- `_reversa_forward/web-build-2026-09-29/` contém builds compilados e snapshots antigos; excluir.
- `_reversa_forward/video-review/` e capturas `*.jpg` em pastas de resultados são evidências locais. Podem conter dados de sessão e identificação mostrados na interface: excluir do GitHub; preservar no disco.
- `_reversa_bugs/supabase-migrations-2026-09-29/config-primary-original.json` é um snapshot técnico histórico de configuração: excluir.
- Relatórios antigos podem conter estados de validação superados; preferir um registro final consolidado da publicação.
- Não incluir APK, ZIP, bundle, caches, logs, `.env`, arquivos de chaves ou credenciais.

## Pendências desta auditoria

A seleção final de paths, varredura de segredos, validação, commit e confirmação no GitHub serão feitos pelo agente principal. Esta auditoria não prova que o backend publicado corresponde byte a byte ao estágio local nem substitui a validação do APK.
