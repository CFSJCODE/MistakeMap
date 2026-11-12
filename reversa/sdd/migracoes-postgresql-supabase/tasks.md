# Migrações PostgreSQL e Supabase — Tarefas de Implementação

## Pré-requisitos

- [ ] Reconciliar migrations versionadas com banco remoto antes de novos deploys.
- [ ] Revisar política RLS por tabela e testar com roles `anon`, `authenticated` e serviço.
- [ ] Confirmar ambiente Supabase isolado para validação de migrations.

## Tarefas

- [ ] T-01, Definir tabelas e FKs do domínio acadêmico com ownership consistente.
  - Origem no legado: `appmistakemap/database/supabase/migrations/20260901163259_create_initial_schema.sql`
  - Critério de pronto: referências órfãs e associações entre usuários diferentes são rejeitadas.
  - Confiança: 🟢
- [ ] T-02, Aplicar RLS e grants mínimos a cada tabela do domínio e operação interna.
  - Origem no legado: migrations de RLS em `appmistakemap/database/supabase/migrations/`
  - Critério de pronto: testes de autorização demonstram isolamento e acesso privilegiado somente no backend.
  - Confiança: 🟢
- [ ] T-03, Proteger estado/versão de tentativas e imutabilidade de exercício analisado.
  - Origem no legado: migrations do pipeline em `appmistakemap/database/supabase/migrations/`
  - Critério de pronto: mutações proibidas são rejeitadas por trigger, não apenas pelo cliente.
  - Confiança: 🟢
- [ ] T-04, Configurar limite de uso, cotas, auditoria, Realtime e jobs assíncronos.
  - Origem no legado: `appmistakemap/database/supabase/migrations/20260901174740_add_rate_limiting.sql`, migrations operacionais
  - Critério de pronto: chamadas excedentes são recusadas e jobs não realizam HTTP síncrono em triggers.
  - Confiança: 🟢
- [ ] T-05, Desenhar migration aditiva e trilha de auditoria para revisão humana de erro.
  - Origem no legado: migrations de `error_events` e permissões em `appmistakemap/database/supabase/migrations/`
  - Critério de pronto: transitions autorizadas e autoria/tempo/motivo são consultáveis; sem editar histórico aplicado.
  - Confiança: 🔴
- [ ] T-06, Reconciliar estado remoto com migrations locais e registrar divergências.
  - Origem no legado: `appmistakemap/database/README.md`
  - Critério de pronto: relatório identifica migration aplicada, ausente e divergente sem executar reset destrutivo.
  - Confiança: 🔴

## Tarefas de Teste

- [ ] TT-01, Testar RLS em múltiplas identidades para cada tabela acessível.
- [ ] TT-02, Testar triggers de estado, versionamento e imutabilidade.
- [ ] TT-03, Testar grants para gabaritos, artefatos e tabelas de operação.
- [ ] TT-04, Aplicar migrations em ambiente isolado e executar `db push --dry-run`.
- [ ] TT-05, Validar jobs e rate limits sem chamadas externas síncronas no trigger.

## Tarefas de Migração de Dados

- [ ] TM-01, Criar somente migrations novas e aditivas; nunca reescrever arquivos já aplicados.
- [ ] TM-02, Planejar backfill/reconciliação com backup e validação caso o banco remoto divirja.

## Ordem Sugerida

1. Reconciliar schema remoto e roles antes de propor novas políticas.
2. Especificar teste de isolamento e estado antes da migration de revisão.
3. Executar dry-run e testes em ambiente isolado antes de publicar.

## Lacunas Pendentes (🔴)

Schema implantado e fluxo de revisão humana precisam de confirmação. Não aplicar mudanças ao banco real sem revisão explícita.
