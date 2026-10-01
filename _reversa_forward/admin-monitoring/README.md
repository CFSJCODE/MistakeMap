# Monitoramento administrativo e telemetria de IA

Este diretório preserva as definições SQL e as funções instrumentadas preparadas durante a implementação do painel administrativo. O código ativo do cliente está em `appmistakemap/lib/admin/`.

- `private_metrics_events.sql`: registros técnicos de funcionamento e permissões administrativas.
- `admin_metrics_snapshot.sql`: consulta consolidada para o painel administrativo.
- `provider_telemetry.sql`: chamadas do provedor, métricas observadas e consumo por modelo.
- `staged/functions/`: versões instrumentadas das funções de IA e utilitários compartilhados.
- `staged/provider_monitor_test.ts`: preservação das respostas, falhas e ausência de conteúdo sensível na telemetria.
- `staged-native/`: preparação para identificar Wi-Fi no Android/iOS. Esse adaptador ainda não está ativado no aplicativo.

As consultas de métricas são restritas a administradores. A telemetria registra modelo, horário, duração, status HTTP e contagem de tokens, sem armazenar chave da API ou conteúdo de exercícios. Credenciais são obtidas pelo ambiente do servidor.

## Teste da instrumentação

Na raiz do repositório, com Deno instalado:

```sh
deno test --config _reversa_forward/admin-monitoring/staged/functions/analyze-attempt/deno.json --allow-env _reversa_forward/admin-monitoring/staged/provider_monitor_test.ts
```

Esse teste usa um registrador substituto e não faz gravações em um projeto Supabase real. A existência deste estágio e seus testes não comprova equivalência com a versão atualmente publicada. Uma publicação futura exige revisar o contrato ativo e as permissões antes de aplicar SQL ou funções.

## Política de atualização

O cliente aplica atualização frequente quando a fonte de conectividade confirma Wi-Fi. Em dados móveis ou rede desconhecida, usa intervalo conservador de uma hora. Na versão Android atual, a conectividade usa a fonte desconhecida; reconhecer Wi-Fi nativo depende da ativação do adaptador preparado em `staged-native/` e de sua dependência correspondente.

Os limites dos modelos exibidos no aplicativo são os informados pelo usuário a partir do AI Studio. Os contadores representam as chamadas observadas pela telemetria do aplicativo e não incluem usos externos ao projeto/registro.
