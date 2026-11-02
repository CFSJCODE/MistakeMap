# Administração, métricas e layout — Tarefas de Implementação

## Pré-requisitos

- [ ] RPC administrativa e RLS disponíveis no Supabase.
- [ ] Papel do perfil carregado antes de construir navegação.
- [ ] Tokens e estilos acessíveis disponíveis ao app.

## Tarefas

- [ ] T-01, Condicionar destino e painel ao papel administrativo.
  - Origem no legado: `appmistakemap/lib/main.dart`
  - Critério de pronto: perfil `user` não vê nem abre Administração.
  - Confiança: 🟢
- [ ] T-02, Consultar snapshot global por RPC e indicar escopo no fallback RLS.
  - Origem no legado: `appmistakemap/lib/admin/metrics_panel.dart`
  - Critério de pronto: falha da RPC não apresenta contagem parcial como global.
  - Confiança: 🟢
- [ ] T-03, Aplicar política de polling por rede, aba ativa e ciclo de vida.
  - Origem no legado: `appmistakemap/lib/admin/metrics_policy.dart`, `appmistakemap/lib/admin/metrics_panel.dart`
  - Critério de pronto: Wi-Fi, móvel/desconhecida e offline seguem frequência prevista sem duplicar consultas.
  - Confiança: 🟢
- [ ] T-04, Apresentar cotas parciais sem estimar valores ausentes.
  - Origem no legado: `appmistakemap/lib/admin/model_quota_card.dart`
  - Critério de pronto: campo sem valor é explicitamente indisponível.
  - Confiança: 🟢
- [ ] T-05, Implementar tela Sobre e componentes visuais responsivos.
  - Origem no legado: `appmistakemap/lib/main.dart`, `appmistakemap/lib/theme/design_tokens.dart`, `appmistakemap/lib/theme/control_styles.dart`
  - Critério de pronto: tela abre/retorna e controles permanecem legíveis em diferentes larguras.
  - Confiança: 🟢

## Tarefas de Teste

- [ ] TT-01, Testar acesso por papel e fallback de métricas.
- [ ] TT-02, Testar política de rede, debounce, ciclo de vida e aba inativa.
- [ ] TT-03, Testar cotas ausentes/parciais.
- [ ] TT-04, Testar Sobre e controles em tamanhos móveis/desktop.

## Tarefas de Migração de Dados

Não aplicável à unit de apresentação; RPC/RLS são pré-requisitos externos. 🟢

## Ordem Sugerida

1. Confirmar autorização no backend e papel no cliente.
2. Construir snapshot/fallback com rótulo correto de escopo.
3. Aplicar política de atualização e só então ligar Realtime/polling.
4. Finalizar tela Sobre e validação visual em breakpoints.

## Lacunas Pendentes (🔴)

Nenhuma lacuna funcional impeditiva foi identificada para os fluxos observados; validar conteúdo institucional de Sobre antes de publicação.
