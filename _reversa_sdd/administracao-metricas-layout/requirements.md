# Administração, métricas e layout

## Visão Geral

Esta unit reúne o painel administrativo de métricas e cotas, política de atualização, tela Sobre e componentes visuais responsivos. A área administrativa é habilitada por papel e não deve transformar uma leitura limitada por RLS em métrica global. 🟢

## Responsabilidades

- Atualizar métricas globais por RPC administrativa quando autorizado. 🟢
- Usar contagens limitadas por RLS sem declarar escopo global quando RPC falha. 🟢
- Limitar atualização por conectividade, ciclo de vida, aba e política de rede. 🟢
- Mostrar cotas ausentes como indisponíveis, sem inventar saldo. 🟢
- Apresentar informações do aplicativo, equipe e tecnologias na tela Sobre. 🟢
- Aplicar tokens, movimento e estilos consistentes em layouts adaptáveis. 🟢

## Regras de Negócio

- A navegação administrativa requer `role=admin`; a autorização dos dados continua no backend/RLS. 🟢
- Em Wi-Fi, o painel pode usar Realtime/atualizações mais frequentes; rede móvel/desconhecida limita polling a uma hora e offline pausa leituras. 🟢
- Cotas não recebidas são representadas como indisponíveis. 🟢

## Requisitos Funcionais

| ID | Requisito | Prioridade | Critério de Aceite |
|---|---|---|---|
| RF-01 | Exibir Administração somente para perfil `admin`. 🟢 | Must | Papel comum não alcança painel pela navegação. |
| RF-02 | Carregar snapshot administrativo pela RPC e atualizar mediante política de rede. 🟢 | Should | Painel respeita conectividade e ciclo de vida. |
| RF-03 | Em falha da RPC, apresentar apenas dados permitidos por RLS e identificar seu escopo. 🟢 | Must | Interface não rotula contagem parcial como global. |
| RF-04 | Apresentar cotas e uso sem inventar valores quando a resposta é parcial. 🟢 | Must | Campo ausente aparece indisponível. |
| RF-05 | Apresentar página Sobre com identidade e informações do projeto. 🟢 | Should | Tela abre pela navegação e retorna sem perder sessão. |
| RF-06 | Adaptar layout, tipografia, hover e movimento às preferências/viewport. 🟢 | Should | Controles permanecem legíveis e utilizáveis. |

## Requisitos Não Funcionais

| Tipo | Requisito inferido | Evidência no código | Confiança |
|---|---|---|---|
| Segurança | Dados globais dependem de RPC autorizada; fallback não afirma escopo maior que o permitido. | `appmistakemap/lib/admin/metrics_panel.dart` | 🟢 |
| Desempenho | Atualizações são limitadas por rede e debounce de eventos. | `appmistakemap/lib/admin/metrics_policy.dart` | 🟢 |
| Acessibilidade | Tokens/estilos contemplam escala de texto, contraste e movimento reduzido. | `appmistakemap/lib/theme/` | 🟢 |

## Critérios de Aceitação

```gherkin
Dado um estudante com papel user
Quando a navegação é montada
Então Administração não aparece

Dado um administrador em Wi-Fi com painel ativo
Quando chega evento de atualização
Então o snapshot atualiza respeitando debounce

Dado que a RPC administrativa falha
Quando o painel usa dados disponíveis via RLS
Então identifica o escopo limitado e não informa total global

Dado uma resposta de cotas parcial
Quando os cartões são apresentados
Então valores ausentes aparecem como indisponíveis

Dado um usuário em rede móvel ou offline
Quando o painel avalia polling
Então limita consultas conforme política ou pausa a atualização

Dado um usuário autenticado
Quando abre Sobre e usa voltar
Então retorna à aplicação sem encerrar a sessão
```

## Prioridade (MoSCoW)

| Requisito | MoSCoW | Justificativa |
|---|---|---|
| Autorização visual e escopo verdadeiro de métricas | Must | Evita exposição e interpretação enganosa. |
| Atualização condicionada a rede | Should | Reduz chamadas e consumo de dados. |
| Cartões de cota com valor indisponível explícito | Must | Não inferir saldo que o servidor não forneceu. |
| Tela Sobre e tokens visuais | Should | Necessários para entrega e consistência da experiência. |

## Rastreabilidade de Código

| Arquivo | Função / Classe | Cobertura |
|---|---|---|
| `appmistakemap/lib/admin/metrics_panel.dart` | Painel, refresh e fallback de métricas | 🟢 |
| `appmistakemap/lib/admin/metrics_policy.dart` | Política de rede/polling | 🟢 |
| `appmistakemap/lib/admin/model_quota_card.dart` | Exibição de cotas | 🟢 |
| `appmistakemap/lib/about/linkedin_profile_button.dart` | Elemento da tela Sobre | 🟢 |
| `appmistakemap/lib/theme/design_tokens.dart` | Tokens e contraste | 🟢 |
| `appmistakemap/lib/main.dart` | Acesso administrativo e tela Sobre | 🟢 |
