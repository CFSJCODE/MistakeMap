# Integração OpenAI do MistakeMap

**Estado: implementação preparada e validada localmente. Não aplicada ao aplicativo nem publicada no Supabase.**

O projeto está protegido por `.reversa/reversa-config.json` com `allowLegacyEdits: false`. Nenhum arquivo original do aplicativo/backend foi substituído. A criação da chave foi interrompida porque o formulário seguro de destino retornou `not_approved`; nenhum segredo foi criado. Não há resultados de chamadas reais à OpenAI nesta entrega.

## Fluxo preparado

1. O aluno informa matéria, enunciado, resposta e, opcionalmente, dificuldade e foto.
2. O Flutter registra a tentativa autenticada; fotos são enviadas diretamente ao R2 com URL temporária. A chave OpenAI permanece no servidor.
3. `analyze-attempt` valida a sessão e a propriedade da tentativa. O processamento em lote usa o mesmo serviço, com autenticação própria de cron.
4. A Responses API retorna JSON estruturado de correção, explicação, conceitos e erros. A aplicação valida limites e coerência antes de persistir.
5. A persistência é transacional: relatório, correção, eventos de erro, conceitos e estado de processamento. Tentativas concorrentes usam versão e lease para evitar resultados duplicados.
6. O mapa, os gráficos e a nuvem contam tentativas distintas. As conexões representam associações observadas em exercícios, não pré-requisitos pedagógicos comprovados.
7. `generate-practice` usa erros anteriores da matéria para gerar de três a cinco exercícios. Os gabaritos permanecem em tabela sem acesso do cliente; o aluno envia uma nova tentativa para receber a correção.

## Organização

- `staged/appmistakemap/`: arquivos Flutter preparados, preservando a paleta e a navegação existentes.
- `staged/supabase/`: funções, código compartilhado e alteração de banco preparada.
- `verification/`: validações locais e dependências isoladas; não é código do aplicativo.
- `apply-integration.mjs`: aplicação local com verificação de permissões, hashes e backup. Não faz deploy, migração remota, criação de segredo, commit ou push.
- `manifest.json`: lista final dos arquivos alterados/novos e hashes de revisão.

## Ativação pendente

1. **Liberação pelo usuário:** o AGENTS.md reserva ao usuário a alteração de `.reversa/reversa-config.json`. Para aplicar os caminhos desta integração, usar `allowLegacyEdits: true` e permitir `appmistakemap/**` e `supabase/**`. Não é necessário liberar todo o projeto.
2. **Chave:** concluir o fluxo seguro do plugin OpenAI Developers e a confirmação do arquivo de destino. Não colar chave em chat, código Flutter, documentação ou Git.
3. **Código local:** revisar o manifesto e executar `node _reversa_forward/openai-integration/apply-integration.mjs` para prévia; `--apply` aplica somente se todos os caminhos estiverem liberados e os arquivos originais/preparados não tiverem mudado. Uma cópia dos arquivos substituídos é guardada na pasta `backups/`.
4. **Banco:** revisar a alteração preparada contra o histórico remoto antes de publicar. O repositório tem históricos em `appmistakemap/database/supabase/migrations/` e `supabase/migrations/`; não executar um `db push` indiscriminado entre essas duas raízes.
5. **Secrets do backend:** configurar `OPENAI_API_KEY`, `OPENAI_MODEL` (padrão preparado: `gpt-4.1-mini`) e `ALLOWED_ORIGINS` com as origens web reais. Preservar os secrets existentes de Supabase/R2/cron. O app móvel não recebe esses secrets.
6. **Publicação:** publicar as funções com todas as dependências relativas e validar a autenticação implementada no corpo, inclusive os tokens ES256 deste projeto. A configuração do gateway deve ser compatível com essa autenticação; nunca publicar uma rota sem validação de sessão/segredo.
7. **Teste real:** usar dados de teste autorizados para exercício textual, foto, correção, erro de rede, geração e nova resolução; validar também acesso negado entre duas contas. Só então marcar a integração como ativada.

## Limites e comportamento

- Sem chave configurada, o servidor retorna indisponibilidade e mantém a tentativa salva; não fabrica análise.
- A análise pode pedir revisão quando o enunciado/resposta estiver ilegível ou incompleto. A correção produzida por IA é uma sugestão e não uma avaliação humana confirmada.
- Os limites preparados de uso por aluno são até 50 análises e 10 gerações por dia; podem ser reduzidos por `AI_ANALYSES_PER_DAY` e `AI_PRACTICE_PER_DAY`. São limites de requisições, não um teto financeiro da conta OpenAI.
- Uploads preparados aceitam JPEG, PNG e WebP até 8 MiB, com URL de 15 minutos. O processamento suporta até três anexos por tentativa; o formulário atual envia uma foto.
- A reserva de armazenamento considera o histórico disponível de todos os meses, conservadoramente. O contador anterior era uma estimativa baseada em downloads; precisa de reconciliação com o inventário real do R2 para representar ocupação exata. URLs assinadas podem ser reutilizadas durante a validade, portanto a reserva não é um limite rígido de operações/custos.
- Testes locais com respostas simuladas verificam contratos e falhas, mas não comprovam qualidade pedagógica nem conectividade/cobrança real da OpenAI.
- A análise é protegida contra processamento repetido da mesma tentativa. A geração de exercícios não tem identificador idempotente: repetir “Gerar” após timeout pode criar outro conjunto e consumir outra chamada. Consulte os exercícios já salvos antes de repetir; o limite diário reduz o impacto, sem eliminar essa possibilidade.

## Validação local

- Backend: verificação de tipos Deno e testes de contratos, autenticação, limite de entrada, resposta inválida/recusa e erros sem vazamento de dados.
- Fluxo vertical: banco PostgreSQL em memória via PGlite, com resposta OpenAI simulada; análise textual, persistência, cache sem nova chamada, rejeição de outro usuário, falha/retry, recuperação de lease expirada e geração com gabaritos privados.
- Banco: migração compilada sobre o esquema-base e testes de RLS, propriedade dos anexos, estados de processamento e proteção do enunciado/gabarito.
- Flutter: testes de agregação, tela estreita, formulário separado, retry sem duplicação, mapa vazio, erro de configuração e exercícios persistidos; capturas de teste usam dados sintéticos.
- Aplicação local: regras de caminho, política inválida, travessia de diretórios e recusa de alteração da configuração são testadas. A configuração atual bloqueia a aplicação conforme esperado.

O PGlite usado nos testes executa PostgreSQL 18.3; o Supabase atual foi consultado como PostgreSQL 17.6.1. Os testes simulam o contexto de autenticação e não substituem verificação no Supabase real. Não houve teste de concorrência com múltiplas sessões reais de PostgreSQL nem upload assinado real ao R2.

## Referências verificadas

- [OpenAI — Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [OpenAI — imagens](https://developers.openai.com/api/docs/guides/images-vision)
- [OpenAI — GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini)
- [OpenAI — proteção e operação da API](https://developers.openai.com/api/docs/guides/production-best-practices)
- [Supabase — autenticação das Edge Functions](https://supabase.com/docs/guides/functions/auth-legacy-jwt)
- [aws4fetch — assinatura de requisições](https://github.com/mhart/aws4fetch)
