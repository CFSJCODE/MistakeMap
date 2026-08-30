# MistakeMap

### Mapa dos padrões de erro do estudante

**Uma plataforma de learning analytics orientada a eventos que transforma exercícios corrigidos em um grafo de fragilidades conceituais, recorrência, recuperação e evolução.**

[![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL-3FCF8E?logo=supabase&logoColor=white)](https://supabase.com/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Data_Model-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![AI](https://img.shields.io/badge/AI-OCR_%2B_LLM-6A5ACD)](#pipeline-de-ia-e-extração)
[![Platforms](https://img.shields.io/badge/Platforms-Android_%7C_Windows_%7C_Web-555555)](#plataformas)
[![Status](https://img.shields.io/badge/Status-Concepção_%2F_MVP-orange)](#roadmap)

</div>

---

> [!IMPORTANT]
> O **MistakeMap não é um corretor que apenas classifica respostas como certas ou erradas**.  
> O objetivo é responder a uma pergunta mais útil: **quais padrões existem por trás dos erros do estudante, em quais conceitos eles reaparecem e como esses padrões evoluem após novas revisões?**

## Sumário

- [Visão geral](#visão-geral)
- [Princípio de projeto](#princípio-de-projeto)
- [Problema](#problema)
- [Objetivos](#objetivos)
- [Escopo funcional](#escopo-funcional)
- [Pipeline de IA e extração](#pipeline-de-ia-e-extração)
- [Modelo matemático de prioridade](#modelo-matemático-de-prioridade)
- [Arquitetura de software](#arquitetura-de-software)
- [Modelo de dados](#modelo-de-dados)
- [Segurança e privacidade](#segurança-e-privacidade)
- [Experiência do usuário](#experiência-do-usuário)
- [Fluxos operacionais](#fluxos-operacionais)
- [Estratégia offline](#estratégia-offline)
- [Arquitetura do projeto Flutter](#arquitetura-do-projeto-flutter)
- [Relatórios e exportações](#relatórios-e-exportações)
- [Roadmap](#roadmap)
- [Critérios de aceitação do MVP](#critérios-de-aceitação-do-mvp)
- [Testes e qualidade](#testes-e-qualidade)
- [Evoluções futuras](#evoluções-futuras)
- [Indicadores de produto](#indicadores-de-produto)
- [Plataformas](#plataformas)
- [Execução do projeto](#execução-do-projeto)
- [Diretrizes de implementação](#diretrizes-de-implementação)

---

## Visão geral

O **MistakeMap** é um aplicativo de aprendizagem orientado a erros. O estudante registra um exercício, seu enunciado, sua resolução, a correção ou gabarito e a disciplina associada. O sistema utiliza **OCR e IA** para estruturar esse material, sugerir conceitos envolvidos e identificar possíveis padrões de falha.

Após a validação do estudante, essas ocorrências são agregadas em um **mapa temporal de conceitos e tipos de erro**, considerando:

- frequência;
- recência;
- importância conceitual;
- evidências de recuperação;
- relações de pré-requisito;
- histórico de tentativas;
- validação explícita do usuário.

O produto é direcionado principalmente a estudos de:

| Área | Exemplos |
|---|---|
| Matemática | Álgebra, cálculo, lógica, equações, funções |
| Física | Unidades, modelagem, condições iniciais, hipóteses |
| Computação | Lógica, algoritmos, estruturas e fundamentos |
| Engenharias | Resolução de problemas e modelagem quantitativa |
| Outras disciplinas | Conteúdos baseados em exercícios e raciocínio estruturado |

### Stack principal

```text
Flutter + Dart
        │
        ├── Riverpod
        ├── GoRouter
        │
        ▼
Supabase
        ├── Auth
        ├── PostgreSQL
        ├── Row Level Security
        ├── Storage
        └── Edge Functions
        │
        ▼
OCR + Parsing + LLM
        │
        ▼
Grafo conceitual + Error Events + Mastery Events
