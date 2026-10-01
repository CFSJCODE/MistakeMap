# Falha de sincronização das migrações Supabase

Data: 29/09/2026. Estado: diagnóstico concluído; nenhuma correção aplicada.

## Evidências confirmadas

- Execução #21: https://github.com/CFSJCODE/MistakeMap/actions/runs/36522599067
- Evento push do commit 4d0dfe3c7b7fc744b28c20784894f5b8e511ae21, às 04:39:31 UTC, após a atualização de coautoria.
- Falha em supabase db push: Remote migration versions not found in local migrations directory.
- A execução parou na conferência de histórico, sem aplicar migrações.
- A execução #20 de 15/09/2026 já apresentava a mesma falha para a versão 20260915004644: https://github.com/CFSJCODE/MistakeMap/actions/runs/35012799260
- A comparação dos arquivos de workflow e migrações entre 01ad880d65fb67bbb03fdd2acca3f5be9e7dd51f e 4d0dfe3c7b7fc744b28c20784894f5b8e511ae21 não apresentou diferenças.

## Divergência de versões

O projeto remoto foi identificado como MistakeMap e confirmado por sua referência nos arquivos do repositório. A consulta de metadados retornou somente dois registros em supabase_migrations.schema_migrations:

| Versão remota | Nome | Situação no repositório |
| --- | --- | --- |
| 20260915004644 | create_r2_quota_tracking | A versão não existe. Há SQL de cotas R2 com versão 20260914120000. |
| 20260928194109 | add_role_admin_system | Não existe arquivo com essa versão na pasta de migrações. |

O diretório usado no deploy tem 17 arquivos SQL. Assim, a divergência não se resume a baixar dois arquivos: também é preciso reconciliar o registro das versões antigas com o estado real do banco antes de liberar novo db push.

Consultas somente leitura confirmaram:

- public.r2_quota_usage existe, com as duas políticas previstas no SQL de cotas R2.
- public.profiles existe e tem coluna role.
- O trigger on_auth_user_created existe em auth.users.
- O SQL de cotas R2 local usa CREATE POLICY sem guarda de existência, portanto sua reaplicação direta pode colidir com políticas existentes.
- A presença desses objetos não é uma validação completa de equivalência das 17 migrações. Essa comparação ainda está pendente.

## Diretório do workflow

Arquivo: .github/workflows/supabase-deploy.yml.

- Dispara por push em main com filtro appmistakemap/database/supabase/migrations/**; também aceita workflow_dispatch.
- Executa a CLI a partir de appmistakemap/database.
- Lê appmistakemap/database/supabase/migrations/.
- A migration supabase/migrations/20260928120000_worker_keepalive_cron.sql, na raiz do projeto, está fora desse diretório e do filtro de disparo.

## Correção a preparar antes de nova execução

1. Preservar uma cópia do histórico de migrações e das definições do esquema remoto.
2. Recuperar as duas migrações registradas no Supabase e comparar seu SQL com o repositório; revisar literais antes de versionar qualquer conteúdo extraído.
3. Resolver a diferença de versão da migration R2 sem reaplicar suas políticas já existentes.
4. Comparar as 17 versões locais com o esquema real, incluindo efeitos de dados, permissões e tarefas agendadas; reconciliar o histórico somente após essa comparação.
5. Definir um diretório único de migrações e tratar a migration de monitoramento atualmente fora do deploy.
6. Validar a sequência em ambiente isolado e a lista de operações planejadas; só então executar novo deploy autorizado.

Não executar automaticamente migration repair --status reverted a partir da sugestão do log. Esse comando remove registros do histórico, mas não desfaz o SQL correspondente. Neste caso, objetos das migrações remotas já existem e a reaplicação sem reconciliação pode falhar ou alterar estruturas/permissões.

Documentação oficial: https://supabase.com/docs/guides/deployment/database-migrations#diagnosing-and-fixing-sync-errors

## Limites da execução

Somente consultas ao GitHub, leitura de arquivos e SELECTs de metadados no Supabase. Não foram executados repair, db pull, db push, reset, nova tentativa do workflow, mudanças de permissões, DDL ou DML. A configuração Reversa permanece allowLegacyEdits=false. Este relatório é o único arquivo criado nesta investigação.
