# Permissões e isolamento de dados

> Nível: Essencial. Matriz baseada em RLS, grants, autenticação das Edge
> Functions e papéis do cliente.

## Papéis observados

| Ator | Identidade | Escopo |
|---|---|---|
| Visitante | Sem JWT | Não acessa dados do aluno nem operações de IA. `/health` é público e só verifica disponibilidade. |
| Estudante autenticado | `auth.uid()`/JWT validado | Acessa e modifica seus dados segundo RLS; não pode forjar estado da análise nem ler gabaritos de prática. |
| Administrador | Perfil `role='admin'` | Pode ler todos os perfis e atualizar perfis por políticas específicas; o papel não concede acesso geral a tentativas de outros usuários. |
| Backend privilegiado | `service_role`/conexão confiável | Persiste análises, correções, eventos, cotas e gabaritos; credenciais ficam no servidor. |
| Processo de cron | Segredo de cron | Pode acionar `process-batch`; não é um usuário de sessão do app. |
| Armazenamento local | SQLite por usuário | Mantém caderno, cache e fila offline no dispositivo; sincronização é validada novamente pelo servidor. |

## Matriz por operação

| Recurso | Visitante | Estudante autenticado | Administrador | Backend / cron |
|---|---|---|---|---|
| Matérias, conceitos e exercícios | Sem acesso | CRUD dentro da própria matéria/usuário, sujeito às FKs e triggers | Sem política geral de leitura cruzada | Leitura/escrita privilegiada conforme operação |
| Tentativas | Sem acesso | Próprias; cria `uploading`/`pending`, não forja status/version, não muda proprietário/exercício | Sem acesso global implícito | Reivindica processamento e atualiza estados |
| Assets de tentativa | Sem acesso | Lê/cria apenas no próprio escopo; criação exige estado `uploading`, caminho próprio e SHA-256 válido | Sem acesso global implícito | Assina URL R2, verifica integridade e lê bytes |
| Análises e conjuntos de prática | Sem acesso | SELECT dos próprios registros | Sem acesso global implícito | Insere e atualiza como processo confiável |
| Correções, erros e domínio | Sem acesso | SELECT dos próprios eventos; sem INSERT/UPDATE/DELETE | Sem acesso geral via RLS | Escreve eventos sugeridos pela IA |
| Tipos de erro | Sem acesso | SELECT da taxonomia global | SELECT por ser autenticado | Mantém taxonomia em migration |
| Gabaritos de prática | Sem acesso | Sem grants/policies de leitura | Sem acesso direto via cliente | Leitura privada durante análise; cria gabaritos |
| Perfil | Sem acesso | Gerencia o próprio perfil, sem poder trocar o próprio papel | SELECT de todos; UPDATE de qualquer perfil por política própria | Cria perfil padrão `user` no cadastro |
| Cotas R2 e controle de uso de IA | Sem acesso | `r2_quota_usage` permite leitura autenticada; contadores de IA são privados | Não há exceção geral para admin | Atualiza cotas/contadores |
| Jobs, OCR e auditoria interna | Sem acesso | Sem policy de cliente | Sem policy de cliente | Serviço confiável; tabelas com RLS e sem policy pública |
| Caderno local | Sem acesso remoto | CRUD SQLite isolado por `usuario_id`; fila sincroniza quando online | Não se aplica | Servidor aplica RLS às operações remotas |
| Health / lote | `/health` público | Não chama lote administrativo | Não ganha autorização por ser admin | `/process-batch` requer segredo de cron |

## Fronteiras de autenticação

- As funções voltadas ao cliente têm `verify_jwt=false` para responder ao
  preflight do navegador, mas validam o bearer token consultando Supabase Auth
  antes de acessar o banco ou Gemini.
- `process-batch` não aceita claims do cliente: exige `x-cron-secret`. `/health`
  não requer autenticação e não retorna dados acadêmicos.
- RLS é a fronteira para acesso direto ao Postgres; a propriedade de conceitos,
  exercícios e eventos é derivada pelas relações até a matéria ou tentativa.
- `practice_answer_keys`, `ai_daily_usage`, `processing_runs` e artefatos
  internos não têm grants/policies de leitura para o app. Respostas corretas
  não são enviadas no retorno da geração.
- O admin do app não deve ser interpretado como superusuário de dados
  acadêmicos. A política global encontrada é específica a perfis; métricas
  administrativas são fornecidas por RPC próprio.

## Limites e lacunas

- A classificação de erro é visível ao estudante, mas não há permissão nem
  endpoint para ele confirmar, corrigir ou rejeitar o evento. O modelo de
  permissões precisa ser ampliado de forma auditável para implementar essa
  validação.
- A telemetria de quota permite leitura autenticada de `r2_quota_usage`; é dado
  operacional compartilhado, não segregado por usuário.
- O job `process-batch-every-minute` é descrito no `BACKEND.md` como criado
  manualmente e seu segredo estava no comando de `cron.job`; a documentação
  propõe mover para Vault e rotacionar o segredo.
