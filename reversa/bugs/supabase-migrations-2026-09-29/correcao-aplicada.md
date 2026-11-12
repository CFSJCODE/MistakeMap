# Correção aplicada — histórico e publicação Supabase

Concluída em 29/09/2026 no projeto MistakeMap.

## Resultado

- Commit publicado em main: `f255e26e30a91a599b376208ec37db95124b1669`.
- Execução real concluída com sucesso: https://github.com/CFSJCODE/MistakeMap/actions/runs/36524681311
- As 16 versões antigas foram registradas em uma transação, com bloqueio e
  verificação prévia do histórico. Seus comandos SQL não foram reexecutados.
- O histórico agora contém 18 versões, todas correspondentes aos arquivos do
  diretório canônico. A prévia retornou `upToDate: true`, sem migrações pendentes.
- Os dois registros remotos preexistentes foram comparados integralmente com o
  backup anterior e permaneceram idênticos.

## Preservação do esquema

O fingerprint agregado da consulta documentada em `validacao-esquema.md`
permaneceu `dadc3677ece726bd58bf1c21c827d6c5` antes e depois da reconciliação.
Isso inclui relações, constraints, índices, políticas, funções, triggers,
extensões e definições de cron. O escopo não inclui o conteúdo das linhas.
Nenhuma operação desta correção alterou dados de aplicação ou autenticação.

As mudanças anteriores de coautoria foram preservadas. Esta publicação foi
incremental, sem nova reescrita do histórico. O checkout primário e seus cinco
arquivos Flutter já modificados foram preservados; a correção foi publicada
pela worktree `codex/supabase-migrations-reconcile`.

## Arquivos publicados

- `.github/workflows/supabase-deploy.yml`: versão fixa da CLI, publicações
  serializadas, comparação de conteúdo, prévia e exclusão da sincronização Vault.
- `appmistakemap/database/README.md`: procedimento, reconciliação e limites.
- Migração R2 renomeada de `20260914120000` para `20260915004644`, com o SQL remoto.
- `20260928194109_add_role_admin_system.sql`: reconstrução pública sanitizada;
  a diferença no bootstrap administrativo está explícita no README. A versão
  remota, já aplicada, não foi reaplicada nem alterada.
- `BACKEND.md`: localização e pendência real do monitor de saúde.

## Validações e pendências

Workflow: YAML válido, sintaxe Bash válida, sete cenários do guard conferidos,
diff sem erros de whitespace e execução real do GitHub com todas as etapas
concluídas com sucesso. Não houve migração SQL aplicada durante esse deploy.

O monitor de saúde permanece sem agendamento. A função `health` não estava na
lista de funções implantadas e o endereço público retornou HTTP404. Ativá-lo
exige primeiro implantar e validar essa função e então promover sua migração
para o diretório canônico. O arquivo proposto na raiz foi preservado.

Não foi validado bootstrap em banco vazio, login, ingestão ou operações no R2.
O banco existente foi validado para continuidade das migrações. Os backups
integrais do histórico ficam fora do versionamento; contêm dados privados e
não devem ser publicados.
