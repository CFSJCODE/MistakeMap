# Plataforma de estudos — implementação

Data: 6 de novembro de 2026. Base: roadmap do PR #63 e autorização para implementar suas sugestões. Esta entrega mantém a cobrança desativada por decisão explícita do usuário.

## O que mudou

| Área | Implementação |
|---|---|
| Início | Painel “Seu estudo de hoje”, objetivo, tempo disponível, revisões, retomada e conferência de sugestões; biblioteca, planos e simulados acessíveis sem mudar as sete abas |
| Começo guiado | Perfil editável com etapa, matérias, objetivo, tempo, fuso e data opcional de prova; aproveita os exemplos já existentes |
| Revisão | Agenda persistente no servidor, sessão retomável, referência antes da autoavaliação e fila offline por usuário com identificadores estáveis |
| Diagnósticos | Confirmar, corrigir categoria/importância e rejeitar; a decisão atualiza recomendações e Mapa, preservando o JSON original da IA |
| Progresso | Separa análises concluídas, autoavaliações de revisão e equivalência com gabarito em questões do catálogo; mostra período, amostra e limites |
| Biblioteca e percursos | Busca por matéria, assunto e tema; percursos de prática sobre questões revisadas com temática de tecnologia |
| Provas | Objetivos com data e disponibilidade, agenda semanal no servidor, reorganização com prioridade para temas que pedem conferência, prática vinculada ao plano e simulados persistentes com retomada |
| Hábitos de estudo | Resumo semanal, conquistas por ações reais, sequência de dias com estudo concluído e preservação opcional de uma pausa por semana |
| Ajuda | Pistas graduais em prática e resolução comentada; pistas indisponíveis em modo prova; ajuda registrada no resultado |
| Caderno e materiais | Anotações conectadas a conceito/tentativa/questão; links HTTPS com página de referência e declaração de autorização de uso |
| Turmas | Habilitação de professor pelo administrador, código de convite, seleção de questões para tarefas e consentimentos separados para progresso, respostas e notas |
| Professor | Relatório condicionado ao compartilhamento atual e feedback sobre sessões finalizadas de tarefas da própria turma |
| Curadoria | Rascunho editável, submissão, solicitação de correção e publicação administrativa com conferência explícita de gabarito e contexto tecnológico |
| Conta e limites | Plano e consumo visíveis, cota serializada no servidor, CSV e exportação paginada por conjunto, sem ativar pagamentos |
| Exclusão | Pedido com login recente e confirmação, cancelamento enquanto pendente e worker retentável que remove arquivos antes da conta |
| Polimento | Mensagens de falha e retomada, formulários preservados em recusas, controles responsivos e acessíveis, validação do Caderno ao digitar e foco da prática persistido |

## Decisões técnicas e limites pedagógicos

- O Flutter apresenta dados e coleta respostas. Agenda, prioridade, correção, cotas e autorização ficam no servidor.
- A agenda usa **mm-intervals-v1**, uma política determinística e versionada. Não foi implementado FSRS e não há alegação de eficácia equivalente a ele. A integração de um agendador externo exige seleção e validação específicas.
- Revisão com “Lembrei” é autoavaliação. Equivalência textual conservadora com resposta revisada não demonstra domínio e não marca automaticamente uma resposta diferente como errada.
- Importância é escolhida explicitamente; grau do grafo não é usado como prova de pré-requisito curricular.
- Erros pendentes continuam sugestões indefinidamente. Não há confirmação por silêncio.
- O banco mantém o diagnóstico bruto e uma view com as decisões aplicadas à apresentação. Rejeições e correções são refletidas no Mapa sem apagar a origem.
- A fila de revisão offline só usa sessões e referências já preparadas. Novos simulados, planos, convites e publicações exigem conexão; o app informa falhas e mantém o formulário quando recusado.
- O início de sessão no catálogo reutiliza o pedido após perda de resposta; respostas de revisão reutilizam `event_id`. O servidor impede consumo e avanço duplicados.
- O catálogo permanece a fonte dos exercícios revisados. Nenhuma chamada adicional a IA paga foi feita durante o desenvolvimento.

## Dados e autorização

Migrations novas, na ordem:

1. `20261106010000_study_review.sql` — perfil, agenda, sessões e histórico.
2. `20261106020000_learning_platform_commercial.sql` — objetivos, simulados, materiais, turmas, cotas e pedidos de privacidade.
3. `20261106030000_content_editor.sql` — autoria e revisão de conteúdo.
4. `20261106040000_account_lifecycle.sql` — processamento retentável de exclusão.
5. `20261106050000_practice_focus.sql` — foco público do exercício, sem gabarito.
6. `20261106060000_teacher_feedback.sql` — feedback autorizado do professor.
7. `20261106070000_student_attempt_analyses.sql` — visão do diagnóstico com decisões humanas.
8. `20261106080000_study_milestones.sql` — pausas de sequência por usuário e semana.

As tabelas novas têm RLS e isolamento por conta. Escritas sensíveis passam pelas funções. Convites e rascunhos não são uma forma de obter gabaritos de sessões ativas. O consentimento é conferido na leitura e no envio de feedback; revogá-lo impede novos acessos, sem prometer apagar cópias já recebidas por terceiros.

## Publicação

Esta entrega não aplicou migrations nem fez chamadas a R2/Auth de produção. A validação local não comprova que o ambiente publicado já oferece estas funções.

1. Revisar e aplicar as oito migrations pelo fluxo do repositório.
2. Publicar `review-queue`, `study-platform` e o uploader atualizado. Os endpoints do estudante autenticam o JWT no handler antes de acessar o banco; o gateway precisa permitir o preflight OPTIONS, como nas funções existentes.
3. `supabase/config.toml` registra `review-queue`, `study-platform` e `account-data` para a publicação contínua. O gateway permite o preflight das funções do estudante, que autenticam os pedidos no próprio handler. O worker de exclusão exige um segredo dedicado.
4. O script `scripts/deploy-study-platform.ps1` oferece publicação explícita, exige confirmação de migrations aplicadas e suporta `-WhatIf`. Não publica implicitamente nem cria credenciais.
5. Configurar o segredo dedicado e o agendador do worker de exclusão conforme [account-lifecycle.md](account-lifecycle.md). Usar Vault e chamadas assíncronas; não inserir segredos em migrations.
6. Validar em ambiente de homologação com duas contas de aluno, uma de professor e uma de administrador, incluindo queda de rede, retomada entre aparelhos e revogação.

## Verificações

- Flutter: 296 testes passaram e 5 opcionais foram pulados na suíte padrão; análise sem avisos e formatação de `lib/` aprovada.
- Edge Functions: os 9 pontos de entrada passaram em `deno check --frozen`; 93 testes passaram em `deno test --frozen --allow-env`.
- O build Web completo foi gerado localmente; a compilação não fez deploy.
- PostgreSQL embarcado/PGlite: `verify-study-review.mjs`, `verify-platform.mjs`, `verify-student-analysis-view.mjs`, `verify-study-milestones.mjs` e `verify-account-lifecycle.mjs` exercitam SQL real e RLS, sem usar o banco publicado. Os scripts exigem uma instalação isolada do módulo indicada por `PGLITE_MODULE`; nenhuma dependência foi adicionada ao aplicativo.
- Prévia opcional: `flutter test --no-pub --dart-define=GENERATE_PLATFORM_PREVIEWS=true test/platform_previews_test.dart` passou e gerou [Hoje no celular](../../docs/platforma-estudos/screenshots/hoje-mobile.png) e [biblioteca no desktop](../../docs/platforma-estudos/screenshots/biblioteca-desktop.png), com dados ilustrativos e a interface real. As imagens não demonstram conexão com produção.

## Frentes que continuam dependendo de trabalho ou recursos externos

| Frente | Estado real |
|---|---|
| Cobrança | Desativada por escolha do usuário. Não há checkout, assinatura comprável ou validação de compra de loja nesta entrega |
| Contratos, titularidade e privacidade | Exigem definição entre titulares e revisão apropriada. Não foram alterados LICENSE, autoria ou documentos jurídicos |
| Público menor de idade | A adequação contratual dos provedores e as proteções aplicáveis precisam ser resolvidas antes da oferta; o código não torna essa oferta automaticamente adequada |
| PDF | Há organização de links e páginas; não há importação, OCR, indexação ou perguntas sobre um PDF enviado |
| Lembretes nativos | Não há FCM, notificação nativa agendada ou credenciais de push configuradas |
| Distribuição de resumos | Resumo, conquistas e pausa de sequência estão disponíveis no app. Não há envio automático por e-mail ou push |
| Instituições e integrações | Turmas e feedback estão implementados. Contratos institucionais, SSO de organizações, Classroom, LTI/Moodle e API pública continuam para demanda validada |
| Lojas e instalações | Não foram alterados applicationId, assinatura, conta Play/Apple, ficha de loja ou aplicativos instalados. iOS continua adiado |
| Observabilidade externa | Logs de erro são sanitizados, e testes verificam recusas; não foi contratado ou configurado Sentry/PostHog nem prometida conformidade por simples uso de ferramentas |
| Agendador de revisão avançado | FSRS não foi integrado; política atual explícita e testes não substituem validação pedagógica longitudinal |

Essas pendências não devem ser apresentadas como funções prontas nem como plataforma comercial já publicada. O próximo gate é homologar o conjunto implementado com estudantes e preparar os recursos externos autorizados.
