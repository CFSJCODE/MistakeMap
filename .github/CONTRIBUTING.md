# Contribuindo com o MistakeMap

Obrigado pelo interesse em contribuir com o **MistakeMap**.

O projeto foi concebido como uma plataforma de aprendizagem orientada a erros, com foco em Flutter/Dart, Supabase/PostgreSQL, OCR/LLM, análise de aprendizagem e grafo conceitual. As contribuições devem preservar a arquitetura, a segurança, a rastreabilidade dos dados educacionais e a filosofia do projeto: **o erro é um evento contextual de aprendizagem, não um rótulo permanente sobre o estudante**.

Este documento estabelece os requisitos técnicos, jurídicos e operacionais para contribuições.

---

## 1. Autores originais

O MistakeMap é um projeto originalmente desenvolvido por:

- **Cláudio Francisco Dos Santos Júnior**
- **Lucas Emanuel Simão Silva**

Projeto original:

https://github.com/CFSJCODE/MistakeMap

A realização de contribuições, forks, correções ou extensões não altera a autoria original do MistakeMap.

Contribuidores podem e devem receber crédito pelas suas próprias contribuições, mas não devem remover, substituir, ocultar ou falsificar a identificação dos autores originais.

---

## 2. Licença do projeto

O código-fonte do MistakeMap é disponibilizado sob a:

**PolyForm Noncommercial License 1.0.0**

SPDX:

`PolyForm-Noncommercial-1.0.0`

Consulte:

- [`LICENSE`](./LICENSE)
- [`NOTICE`](./NOTICE)
- [`USAGE_POLICY.md`](./USAGE_POLICY.md)
- [`TRADEMARKS.md`](./TRADEMARKS.md)
- [`CITATION.cff`](./CITATION.cff)

Toda contribuição incorporada ao repositório deve ser compatível com a licença vigente do projeto e com as licenças das dependências utilizadas.

---

## 3. Condição para contribuir

Ao enviar uma contribuição, você declara que:

1. possui o direito de submeter o conteúdo;
2. o conteúdo foi criado por você ou você possui autorização suficiente para contribuí-lo;
3. a contribuição não viola direitos autorais, patentes, marcas, segredos comerciais ou outros direitos de terceiros;
4. você informou adequadamente qualquer código, modelo, dataset, asset, fonte, ícone, biblioteca ou material de terceiro incluído;
5. a contribuição pode ser integrada ao MistakeMap sob os termos definidos neste documento;
6. você não está submetendo conteúdo confidencial ou proprietário sem autorização;
7. você não removeu avisos de copyright, licença ou atribuição de terceiros.

Não envie código copiado de repositórios, fóruns, livros, cursos, ferramentas de IA ou outros projetos sem verificar sua origem e licença.

---

## 4. Licenciamento das contribuições

### 4.1 Licença de distribuição do projeto

Ao submeter uma contribuição e solicitar sua incorporação ao MistakeMap, você concorda que essa contribuição poderá ser distribuída como parte do projeto sob a licença vigente do MistakeMap.

Atualmente:

`PolyForm-Noncommercial-1.0.0`

### 4.2 Titularidade da contribuição

Salvo acordo separado, o contribuidor permanece titular dos direitos autorais que possuir sobre sua contribuição.

A contribuição não transfere ao contribuidor a autoria ou titularidade sobre o MistakeMap original.

### 4.3 Licença concedida aos mantenedores

Para permitir manutenção, distribuição, evolução, publicação de releases e eventual adoção de modelos de licenciamento adicionais, ao enviar uma contribuição você concede aos mantenedores do MistakeMap uma licença:

- mundial;
- não exclusiva;
- perpétua;
- irrevogável na medida permitida pela legislação;
- gratuita e livre de royalties;

para usar, reproduzir, modificar, adaptar, preparar trabalhos derivados, distribuir, disponibilizar, executar, exibir, sublicenciar e relicenciar a contribuição como parte do MistakeMap ou de versões derivadas do projeto.

Essa autorização inclui a possibilidade de os mantenedores disponibilizarem versões do MistakeMap sob modelos de licenciamento diferentes ou adicionais, inclusive licenciamento comercial, sem retirar do contribuidor a titularidade sobre a contribuição original.

> [!IMPORTANT]
> Se você não concordar com esta autorização de relicenciamento da sua contribuição, não envie a contribuição para integração no repositório principal.

### 4.4 Contribuições substanciais

Para contribuições extensas, módulos completos, integrações estratégicas ou código de terceiros, os mantenedores podem exigir um **Contributor License Agreement (CLA)** separado antes do merge.

---

## 5. Patentes

Ao contribuir com código sobre o qual você possua direitos de patente relevantes, você concede aos usuários e mantenedores do MistakeMap, na medida necessária para utilizar a contribuição integrada ao projeto, uma licença de patente mundial, não exclusiva e livre de royalties sobre as reivindicações de patente necessariamente infringidas pela sua contribuição isoladamente ou em combinação com o projeto ao qual foi submetida.

Caso você não possa conceder essa autorização, informe isso explicitamente antes de enviar a contribuição.

---

## 6. Atribuição obrigatória

As linhas iniciadas por `Required Notice:` presentes no `LICENSE` e/ou `NOTICE` não devem ser removidas.

Toda redistribuição do projeto deve continuar identificando os autores originais:

**Cláudio Francisco Dos Santos Júnior**  
**Lucas Emanuel Simão Silva**

Contribuidores podem acrescentar seus próprios créditos de maneira separada.

Exemplo:

```text
MistakeMap
Original authors:
Cláudio Francisco Dos Santos Júnior
Lucas Emanuel Simão Silva

Additional contribution:
Fulano de Tal — implementação do módulo X
```

Não substitua a autoria original pelos nomes dos modificadores.

---

## 7. O que pode ser contribuído

São bem-vindas contribuições relacionadas a:

- correção de bugs;
- melhoria de desempenho;
- refatoração;
- testes;
- acessibilidade;
- UX/UI;
- documentação;
- internacionalização;
- Flutter/Dart;
- gerenciamento de estado;
- navegação;
- Supabase;
- PostgreSQL;
- Row Level Security;
- sincronização offline;
- OCR;
- parsing;
- modelos de IA;
- classificação de erros;
- explicabilidade;
- visualização do grafo conceitual;
- relatórios;
- exportações;
- segurança;
- privacidade;
- observabilidade;
- automação de CI/CD;
- qualidade de código.

Contribuições que alterem regras centrais de domínio devem incluir justificativa técnica.

---

## 8. Princípios de domínio que devem ser preservados

Contribuições não devem quebrar os seguintes princípios:

### 8.1 Erro como evento, não como rótulo

O MistakeMap deve tratar o erro como evidência contextual ligada a uma tentativa.

Não introduza funcionalidades que rotulem permanentemente o estudante como:

- "ruim";
- "incapaz";
- "fraco";
- "sem domínio";

ou equivalentes.

### 8.2 Human-in-the-loop

Classificações geradas por IA devem permanecer revisáveis.

Não transforme sugestões automáticas em fatos definitivos sem validação apropriada.

### 8.3 Preservação de evidência

Não elimine silenciosamente:

- tentativa original;
- correção;
- evidência;
- classificação anterior;
- histórico relevante.

### 8.4 Recuperação e evolução

Um erro antigo pode perder prioridade quando novas evidências demonstram domínio.

Não implemente mecanismos que tratem erros históricos como penalização permanente.

### 8.5 Sem diagnóstico de aprendizagem

O sistema não deve inferir ou declarar:

- transtornos;
- deficiências;
- condições médicas;
- diagnósticos psicológicos;
- diagnósticos educacionais clínicos.

---

## 9. Segurança e privacidade

Dados educacionais podem incluir:

- provas;
- exercícios;
- respostas;
- notas;
- fotografias;
- PDFs;
- padrões de desempenho;
- histórico de estudo.

Contribuições devem adotar privacidade por padrão.

### Requisitos mínimos

- nunca inserir `service_role` no aplicativo Flutter;
- nunca commitar secrets;
- utilizar variáveis de ambiente;
- respeitar Row Level Security;
- evitar buckets públicos para dados privados;
- utilizar URLs temporárias quando necessário;
- evitar logs com tokens;
- evitar logs com documentos privados;
- evitar telemetria desnecessária;
- limitar coleta de dados;
- não expor dados entre usuários.

Pull Requests que alterem autenticação, RLS, Storage ou processamento de dados sensíveis devem explicar explicitamente o impacto de segurança.

---

## 10. Conteúdo de terceiros

Qualquer dependência, asset ou material externo deve ter licença compatível.

Antes de adicionar:

- pacote Flutter;
- código externo;
- modelo de IA;
- dataset;
- fonte;
- ícone;
- imagem;
- biblioteca JavaScript;
- biblioteca nativa;
- ferramenta de OCR;

verifique:

1. licença;
2. obrigação de atribuição;
3. compatibilidade com o MistakeMap;
4. restrições de redistribuição;
5. restrições comerciais;
6. restrições de uso de dados.

Inclua a licença ou aviso correspondente quando necessário.

---

## 11. Conteúdo gerado com Inteligência Artificial

Ferramentas de IA podem ser utilizadas como apoio ao desenvolvimento, mas o contribuidor continua responsável pelo conteúdo enviado.

Ao submeter código ou documentação gerados ou significativamente auxiliados por IA, o contribuidor deve:

- revisar o resultado;
- testar o conteúdo;
- verificar possíveis problemas de licença;
- verificar possível reprodução indevida de código de terceiros;
- validar segurança;
- validar lógica;
- assumir responsabilidade pela contribuição.

Não envie código que você não compreende.

---

## 12. Padrão de código

### Dart / Flutter

O código deve:

- seguir `dart format`;
- passar por `flutter analyze`;
- evitar warnings novos;
- utilizar null safety;
- evitar `dynamic` sem necessidade;
- preservar tipagem;
- manter funções coesas;
- evitar lógica de negócio dentro de widgets;
- evitar duplicação desnecessária;
- utilizar nomes descritivos.

Antes do Pull Request:

```bash
dart format .
flutter analyze
flutter test
```

---

## 13. Arquitetura

O MistakeMap adota organização **feature-first**, separando apresentação, domínio e dados.

Estrutura esperada:

```text
lib/
├── app/
│   ├── router/
│   ├── theme/
│   └── bootstrap/
├── core/
│   ├── errors/
│   ├── utils/
│   ├── services/
│   └── widgets/
├── features/
│   ├── auth/
│   ├── subjects/
│   ├── concepts/
│   ├── exercises/
│   ├── capture/
│   ├── attempts/
│   ├── corrections/
│   ├── errors/
│   ├── mistake_map/
│   ├── review/
│   ├── reports/
│   └── settings/
└── main.dart
```

Evite criar dependências circulares entre features.

Regras de negócio devem permanecer fora da camada puramente visual.

---

## 14. Gerenciamento de estado e navegação

O projeto prioriza consistência.

Ao contribuir:

- utilize o padrão principal de gerenciamento de estado adotado pelo projeto;
- evite introduzir um segundo framework de estado sem justificativa;
- utilize o roteador principal;
- evite navegação imperativa dispersa;
- mantenha deep links consistentes.

Mudanças de arquitetura devem ser discutidas antes de um PR extenso.

---

## 15. Banco de dados

Alterações no banco devem ser versionadas.

Não altere manualmente produção sem migration correspondente.

Mudanças devem considerar:

- integridade referencial;
- RLS;
- índices;
- constraints;
- rollback;
- compatibilidade com dados existentes;
- migrations idempotentes quando aplicável.

Tabelas principais podem incluir:

- `subjects`;
- `concepts`;
- `concept_edges`;
- `exercises`;
- `exercise_concepts`;
- `attempts`;
- `corrections`;
- `error_types`;
- `error_events`;
- `mastery_events`.

---

## 16. Modelagem de eventos

O MistakeMap utiliza abordagem orientada a eventos.

Evite transformar informações históricas em simples estado destrutivo.

Exemplo:

Em vez de apagar um `error_event` quando a classificação muda, prefira um mecanismo de revisão, substituição ou `superseded`, preservando rastreabilidade.

---

## 17. IA, OCR e classificação

Contribuições relacionadas a IA devem:

- tratar resultados como sugestões;
- expor confiança quando aplicável;
- preservar evidência;
- permitir correção manual;
- tolerar métodos alternativos corretos;
- evitar inferir intenção cognitiva sem evidência;
- documentar limitações;
- evitar linguagem excessivamente prescritiva.

O sistema deve continuar útil mesmo quando IA ou OCR falharem.

---

## 18. Testes

Contribuições de código devem incluir testes quando aplicável.

Tipos esperados:

### Unitários

Para:

- domínio;
- validações;
- cálculos;
- prioridade;
- decaimento temporal;
- parsing;
- transformações.

### Widget

Para:

- formulários;
- navegação;
- filtros;
- estados vazios;
- erros;
- acessibilidade.

### Integração

Para:

- autenticação;
- Supabase;
- PostgreSQL;
- Storage;
- sincronização;
- RLS.

### Segurança

Mudanças em RLS devem ser testadas com:

- usuário autorizado;
- usuário não autorizado;
- usuário diferente;
- dados privados de outra conta.

---

## 19. Cobertura de regressão

Toda correção de bug relevante deve, quando possível, incluir um teste que falhe antes da correção e passe depois dela.

Isso reduz a chance de regressão.

---

## 20. Performance

Evite otimizações prematuras, mas não introduza regressões evidentes.

Considere:

- rebuilds desnecessários;
- consultas N+1;
- imagens grandes;
- uso excessivo de memória;
- processamento síncrono pesado na UI;
- consultas sem índices;
- grafos muito densos;
- serialização repetitiva.

Mudanças de performance relevantes devem incluir medição ou justificativa.

---

## 21. Acessibilidade

Contribuições de interface devem considerar:

- contraste;
- tamanho de toque;
- navegação por teclado;
- labels semânticos;
- leitores de tela;
- estados de foco;
- responsividade;
- zoom;
- densidade de informação.

Não dependa exclusivamente de cor para comunicar estado.

---

## 22. Documentação

Mudanças que alterem comportamento devem atualizar documentação relacionada.

Isso pode incluir:

- `README.md`;
- documentação de arquitetura;
- migrations;
- exemplos;
- comentários técnicos;
- `USAGE_POLICY.md`;
- documentação de API.

Comentários devem explicar **por que** algo existe, não repetir literalmente o código.

---

## 23. Antes de abrir uma Issue

Verifique:

1. se já existe Issue equivalente;
2. se o comportamento é realmente bug;
3. se a documentação responde à dúvida;
4. se consegue reproduzir o problema;
5. se utiliza versão atual.

---

## 24. Relatório de bug

Inclua:

- descrição;
- comportamento esperado;
- comportamento observado;
- passos para reproduzir;
- plataforma;
- versão Flutter;
- versão Dart;
- versão do app;
- logs relevantes;
- screenshots quando úteis.

Remova:

- tokens;
- senhas;
- dados pessoais;
- documentos privados;
- secrets.

---

## 25. Solicitação de funcionalidade

Explique:

- problema real;
- contexto;
- usuário afetado;
- proposta;
- alternativas;
- impacto arquitetural;
- impacto de segurança;
- impacto de privacidade.

Evite solicitações baseadas apenas em preferência visual sem problema associado.

---

## 26. Fluxo de contribuição

Fluxo recomendado:

```bash
git clone https://github.com/CFSJCODE/MistakeMap.git
cd MistakeMap

git checkout -b feat/minha-funcionalidade
```

Implemente e teste.

Depois:

```bash
dart format .
flutter analyze
flutter test
git status
```

Commit:

```bash
git add .
git commit -m "feat: descrição objetiva da alteração"
```

Push:

```bash
git push origin feat/minha-funcionalidade
```

Abra um Pull Request.

---

## 27. Nomes de branches

Padrão recomendado:

```text
feat/nome
fix/nome
docs/nome
refactor/nome
test/nome
chore/nome
security/nome
```

Exemplos:

```text
feat/offline-drafts
fix/error-event-validation
docs/database-model
security/rls-attempts
```

---

## 28. Commits

Preferencialmente utilize Conventional Commits.

Exemplos:

```text
feat: add offline exercise drafts
fix: prevent cross-user concept access
docs: document error event lifecycle
refactor: isolate review priority service
test: add mastery decay tests
security: tighten storage policies
```

Commits devem ser:

- objetivos;
- pequenos quando possível;
- semanticamente coerentes;
- sem arquivos gerados desnecessários;
- sem secrets.

---

## 29. Pull Requests

Todo Pull Request deve explicar:

### O que mudou?

Descreva a implementação.

### Por quê?

Explique o problema resolvido.

### Como foi testado?

Liste testes executados.

### Impacto

Informe se afeta:

- banco;
- migrations;
- segurança;
- privacidade;
- API;
- UX;
- compatibilidade;
- performance.

### Screenshots

Inclua quando houver alterações visuais.

---

## 30. Checklist de Pull Request

Use como referência:

```markdown
- [ ] Li o CONTRIBUTING.md.
- [ ] Tenho direito de submeter esta contribuição.
- [ ] Concordo com os termos de licenciamento de contribuições.
- [ ] Preservei LICENSE, NOTICE e Required Notice.
- [ ] Não incluí secrets.
- [ ] Não incluí dados pessoais.
- [ ] Executei dart format.
- [ ] Executei flutter analyze.
- [ ] Executei flutter test.
- [ ] Adicionei/atualizei testes quando necessário.
- [ ] Atualizei documentação quando necessário.
- [ ] Verifiquei licenças de novas dependências.
- [ ] Avaliei impacto de segurança e privacidade.
```

---

## 31. Declaração de contribuição

Ao abrir um Pull Request destinado a ser incorporado ao repositório principal, o contribuidor declara que leu e aceita este `CONTRIBUTING.md`.

Recomenda-se adicionar ao corpo do Pull Request:

```text
I certify that I have the right to submit this contribution and that I agree
to the contribution licensing terms described in CONTRIBUTING.md.
```

Opcionalmente, commits podem utilizar:

```text
Signed-off-by: Nome do Contribuidor <email@example.com>
```

O uso de `Signed-off-by` não substitui eventual CLA quando os mantenedores o exigirem.

---

## 32. Revisão de código

Um Pull Request pode ser recusado ou solicitar alterações quando:

- viola arquitetura;
- não possui testes suficientes;
- introduz vulnerabilidade;
- prejudica privacidade;
- duplica funcionalidade;
- adiciona dependência desnecessária;
- possui licença incompatível;
- reduz acessibilidade;
- quebra regras de domínio;
- mistura alterações não relacionadas;
- não apresenta justificativa técnica suficiente.

A aprovação técnica não implica obrigação de merge.

---

## 33. Dependências novas

Antes de adicionar dependência, explique:

- por que é necessária;
- alternativa sem dependência;
- manutenção do pacote;
- licença;
- tamanho;
- suporte às plataformas;
- impacto de segurança.

Dependências abandonadas ou com licença incompatível podem ser recusadas.

---

## 34. Mudanças arquiteturais

Mudanças grandes devem ser discutidas antes da implementação completa.

Exemplos:

- troca de Riverpod;
- troca de GoRouter;
- troca de Supabase;
- mudança do modelo de eventos;
- nova estratégia offline;
- novo provedor de IA;
- alteração profunda na taxonomia;
- mudança de licença.

Abra uma Issue ou discussão técnica antes de investir em um PR grande.

---

## 35. Segurança

Não publique vulnerabilidades críticas em Issue pública antes de permitir análise responsável pelos mantenedores.

Em relatórios de segurança, inclua:

- componente;
- impacto;
- forma de reprodução;
- versão afetada;
- mitigação sugerida.

Nunca inclua credenciais reais.

---

## 36. Código de terceiros sem licença clara

Código sem licença explícita deve ser considerado não reutilizável até que sua situação jurídica seja esclarecida.

Não copie código apenas porque está publicamente acessível.

**Código público não significa código livre para reutilização.**

---

## 37. Contribuições acadêmicas

Trabalhos acadêmicos podem contribuir com:

- provas de conceito;
- algoritmos;
- benchmarks;
- modelos;
- relatórios;
- avaliações de usabilidade;
- experimentos.

Caso material acadêmico possua restrições institucionais ou de publicação, isso deve ser resolvido antes do envio ao repositório.

---

## 38. Dados de pesquisa

Não envie datasets contendo:

- nomes de estudantes;
- matrículas;
- notas identificáveis;
- provas privadas;
- documentos pessoais;
- informações sensíveis.

Utilize dados sintéticos ou devidamente anonimizados quando possível.

---

## 39. Traduções

Traduções são bem-vindas.

Devem preservar:

- significado;
- acessibilidade;
- terminologia técnica;
- referências jurídicas.

Não traduza o texto oficial de uma licença e apresente a tradução como se fosse juridicamente equivalente ao texto oficial.

---

## 40. Compatibilidade multiplataforma

O MistakeMap prevê suporte a:

- Android;
- Windows;
- Web.

Contribuições devem evitar dependência desnecessária de uma única plataforma.

Quando uma funcionalidade for específica, documente explicitamente.

---

## 41. Critérios mínimos para merge

Uma contribuição pode ser integrada quando:

- resolve problema claro;
- está tecnicamente consistente;
- possui licença compatível;
- preserva atribuição;
- passa análise estática;
- passa testes relevantes;
- não introduz risco de segurança conhecido;
- mantém privacidade;
- possui documentação suficiente;
- recebe aprovação dos mantenedores.

---

## 42. Reconhecimento de contribuidores

Contribuições relevantes podem ser reconhecidas em:

- histórico Git;
- Pull Requests;
- release notes;
- seção de contribuidores;
- documentação;
- arquivos específicos quando aplicável.

Esse reconhecimento não altera a autoria original do MistakeMap.

---

## 43. Conduta

Discussões técnicas devem manter:

- respeito;
- objetividade;
- colaboração;
- foco no problema;
- crítica ao código, não à pessoa.

Divergências técnicas são esperadas e devem ser resolvidas por:

- requisitos;
- evidências;
- testes;
- arquitetura;
- segurança;
- impacto no usuário.

---

## 44. Hierarquia documental

Em caso de dúvida:

1. `LICENSE` — termos jurídicos de licenciamento;
2. `NOTICE` — atribuição e avisos;
3. `USAGE_POLICY.md` — interpretação operacional;
4. `TRADEMARKS.md` — identidade e nome do projeto;
5. `CONTRIBUTING.md` — regras de contribuição;
6. documentação técnica — arquitetura e implementação.

---

## 45. Resumo jurídico para contribuidores

Ao contribuir, você:

- mantém, salvo acordo em contrário, os direitos que possuir sobre sua contribuição;
- autoriza sua distribuição como parte do MistakeMap;
- concede aos mantenedores direitos suficientes para manter, modificar, sublicenciar e relicenciar sua contribuição;
- declara possuir direito de enviar o conteúdo;
- aceita preservar a atribuição aos autores originais;
- não adquire autoria sobre o projeto original;
- pode receber crédito pelas suas próprias contribuições.

---

## 46. Autores originais

**MistakeMap**

Originalmente desenvolvido por:

- **Cláudio Francisco Dos Santos Júnior**
- **Lucas Emanuel Simão Silva**

Projeto original:

https://github.com/CFSJCODE/MistakeMap

Licença:

**PolyForm Noncommercial License 1.0.0**

SPDX:

`PolyForm-Noncommercial-1.0.0`
