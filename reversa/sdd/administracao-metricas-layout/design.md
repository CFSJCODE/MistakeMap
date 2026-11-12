# Administração, métricas e layout — Design Técnico

## Interface

| Símbolo | Entrada | Retorno | Observação |
|---|---|---|---|
| `_AdminMetricsPanelState._sync` | estado da tela/rede | `void` | Coordena atualização e ciclo de vida. 🟢 |
| `_AdminMetricsPanelState._refresh` | nenhuma | `Future<void>` | Consulta snapshot administrativo e fallback permitido. 🟢 |
| `MetricsPolicy.live` | `NetworkKind` | `bool` | Determina se atualização ao vivo é adequada. 🟢 |
| `MetricsPolicy.due` | rede, última consulta e data atual | `bool` | Limita polling conforme rede. 🟢 |
| `MistakeMapDesign.hoverInk` | cores de fundo/tinta | `Color` | Escolhe tinta de contraste em hover. 🟢 |
| `TelaSobre.build` | `BuildContext` | `Widget` | Apresenta missão, visão, valores, equipe e stack. 🟢 |

## Fluxo Principal

1. Navegação verifica `AppUser.role` e só constrói a aba Admin para `admin`. 🟢 (`appmistakemap/lib/main.dart`)
2. Painel sincroniza estado, conectividade, ciclo de vida e aba ativa. 🟢 (`metrics_panel.dart`)
3. Atualização consulta RPC global; se falhar, usa somente contagens permitidas por RLS e indica que não são globais. 🟢
4. Realtime é debounced; polling é condicionado à rede e ao tempo desde a última consulta. 🟢 (`metrics_policy.dart`)
5. Cartões apresentam dados de IA/armazenamento; campos ausentes permanecem indisponíveis. 🟢 (`model_quota_card.dart`)
6. Design tokens/control styles/motion padronizam controles e layout. 🟢 (`appmistakemap/lib/theme/`)
7. A tela Sobre é aberta como rota separada. 🟢 (`appmistakemap/lib/main.dart`)

## Fluxos Alternativos

- **Offline:** não consulta métricas e não apresenta snapshot desatualizado como atual sem indicação. 🟢
- **Rede móvel/desconhecida:** polling fica limitado a uma hora. 🟢
- **Falha de RPC:** fallback RLS não é rotulado como global. 🟢
- **Cotas incompletas:** cada valor desconhecido aparece como indisponível. 🟢

## Dependências

- Supabase RPC/RLS/Realtime: métricas e notificações de atualização. 🟢
- `fluent_ui`: componentes do app. 🟢
- `url_launcher` e interoperabilidade Web: links/ações da página Sobre. 🟢
- Estado de autenticação: controla visibilidade do painel. 🟢

## Decisões de Design Identificadas

| Decisão | Evidência no código | Confiança |
|---|---|---|
| Fallback distingue RPC global de dados limitados por RLS | `appmistakemap/lib/admin/metrics_panel.dart` | 🟢 |
| Frequência depende de rede e atualização tem debounce | `appmistakemap/lib/admin/metrics_policy.dart` | 🟢 |
| Valor de cota ausente não é calculado artificialmente | `appmistakemap/lib/admin/model_quota_card.dart` | 🟢 |
| Tema oferece tokens e adaptação a movimento/hover | `appmistakemap/lib/theme/` | 🟢 |

## Estado Interno

O painel mantém snapshot de contagens, última atualização e estado de carregamento/erro. As atualizações são suspensas conforme conexão e ciclo de vida. 🟢

## Observabilidade

O estado de atualização/falha é visível no painel. Logs estruturados ou tracing para essa unit não foram confirmados. 🟡

## Riscos e Lacunas

- 🟡 Permissões de admin no banco e fallback devem continuar sincronizados; a UI não substitui RLS.
- 🟢 Métricas parciais precisam manter rótulo de escopo para não induzir leitura global.
- 🟡 Conteúdo da equipe/links de Sobre depende de dados mantidos no código e pode ficar desatualizado.
