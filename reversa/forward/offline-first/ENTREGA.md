# MistakeMap: uso offline e sincronização — 26/10/2026

## Comportamento

- Na primeira abertura, "Usar sem conta e sem internet" cria uma identidade local estável, sem credencial ou conta fictícia no servidor.
- Ao entrar, o material local sem conta é vinculado ao usuário autenticado. O aviso aparece antes da escolha na tela de login. Dados de outras contas ficam isolados.
- Início, lista, mapa e exercícios de prática já baixados usam SQLite. O perfil não bloqueia a navegação: começa sem privilégios administrativos; a verificação de papel roda separadamente e com prazo de três segundos.
- Inserções, edições e exclusões criam uma fila SQLite na mesma transação da alteração local. UUIDs permanecem iguais no aparelho e na nuvem.
- Fotos e solicitações de análise ficam em fila persistente. A execução de IA e a geração de novos exercícios continuam no backend e exigem conexão/conta.
- Um ciclo ocorre ao abrir, retornar ao app, alterar dados e a cada 15 segundos enquanto o aplicativo está ativo. Não há promessa de execução com o aplicativo encerrado pelo Android/iOS.
- Envios repetidos não usam UPSERT destrutivo. Atualizações/exclusões com divergência preservam o trabalho local e sinalizam conflito; a fila não é apagada por falhas de rede ou recusa do servidor.
- O snapshot remoto só é aplicado depois de todas as páginas serem obtidas. Dados pendentes ficam protegidos; exclusões remotas só removem cópias locais sem alterações pendentes.

## Persistência e compatibilidade

`mistakemap_local.db` sobe da versão 1 para 2 com `onUpgrade`; as tabelas antigas, IDs e conteúdo do Caderno são preservados. As tabelas `offline_rows`, `offline_outbox` e `offline_jobs` contêm o espelho, as operações e os anexos pendentes. Não armazenam senha nem token de sessão. A sessão continua sob controle do SDK do Supabase.

## Alteração do servidor aplicada

O servidor existente atende subjects/exercises/attempts/attempt_assets/attempt_analyses. O Caderno antes era exclusivamente local e agora usa `notebook_entries`, com RLS por usuário, quatro políticas de CRUD e acesso anônimo revogado. Também foram revogados os privilégios extras padrões, inclusive TRUNCATE para authenticated.

A aplicação foi autorizada explicitamente pelo usuário nesta conversa e registrada no Supabase como `20261027003906_notebook_entries_offline_sync`. O SQL aplicado foi preservado no histórico local de migrations e nesta pasta. `.reversa/reversa-config.json` não foi alterado. Tabelas e registros existentes foram preservados. A versão da migration foi obtida do histórico real do servidor, não estimada pelo relógio local.

## Limites e verificação

Dados nunca baixados não ficam disponíveis offline. Login inicial em uma conta, administração e novas respostas da IA exigem internet. O uso sem conta já permite criar material local. Conflitos são preservados e sinalizados, sem resolução automática silenciosa; a escolha entre versões ainda requer conferência técnica.

Testes em `offline_sync_test.dart` cobrem uso sem rede, separação por conta, adoção de convidado, perda de resposta após INSERT, exclusões remotas, proteção das pendências, conflito, servidor sem a nova tabela, upgrade SQLite, paginação, retomada e reabertura do banco. A suíte completa passou com 183 testes aprovados e 4 ignorados; análise sem avisos e formatação sem alterações.

No emulador Pixel 10 Pro XL: modo avião com Wi-Fi desligado, entrada sem conta, gravação de anotação sintética, encerramento e abertura a frio em 2,102 segundos, persistência confirmada. A anotação sintética foi removida pela interface após o teste e a rede foi restaurada.

No Supabase real: verificados RLS, quatro políticas, acesso anônimo negado e ausência de privilégio TRUNCATE para authenticated. Teste transacional com rollback confirmou inserir/editar/excluir como dono, invisibilidade e bloqueio de alteração/inserção como outra identidade. Nenhum dado sintético persistiu. Os avisos de segurança anteriores do projeto permanecem; nenhum alerta novo para notebook_entries.

A sincronização do aplicativo foi testada com transporte simulado; ainda falta um teste completo com login no emulador e uma conta do usuário contra o servidor real. O aplicativo está em uso sem conta e precisa de login para enviar os dados à nuvem. Não houve commit nem push.
