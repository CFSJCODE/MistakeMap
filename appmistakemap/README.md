<a id="readme-top"></a>

<div align="center">

# MistakeMap — Cliente Flutter 📱

### Aplicativo Multiplataforma para Mapeamento de Padrões de Erro

Cliente móvel e desktop da plataforma **MistakeMap**, desenvolvido em Flutter para captura, classificação, revisão metacognitiva e visualização do grafo de fragilidades e evolução do estudante.

<br>

[![GitHub](https://img.shields.io/badge/GitHub-CFSJCODE%2FMISTAKEMAP-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/CFSJCODE/MISTAKEMAP)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-^3.13-0175C2?style=flat-square&logo=dart&logoColor=white)](https://dart.dev)
![Versão](https://img.shields.io/badge/Versão-1.0.0-0A7F5A?style=flat-square)
![Status](https://img.shields.io/badge/Status-MVP%20funcional-F59E0B?style=flat-square)
![PUC Minas](https://img.shields.io/badge/PUC%20Minas-Engenharia%20de%20Computação-003B71?style=flat-square)

<br>

<p>
  <img src="https://img.shields.io/badge/Android-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android">
  <img src="https://img.shields.io/badge/Windows-0078D4?style=flat-square&logo=windows11&logoColor=white" alt="Windows">
  <img src="https://img.shields.io/badge/Web-4285F4?style=flat-square&logo=googlechrome&logoColor=white" alt="Web">
  <img src="https://img.shields.io/badge/iOS-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS">
</p>

</div>

<br>

---

<br>

<a id="sumario"></a>

## 📑 Sumário

- [Sobre o Módulo](#sobre-o-modulo)
- [Identificação Acadêmica](#identificacao-academica)
- [Stack Tecnológica](#stack-tecnologica)
- [Funcionalidades](#funcionalidades)
- [Arquitetura de Software](#arquitetura-de-software)
- [Estrutura de Diretórios](#estrutura-de-diretorios)
- [Como Executar o Projeto](#como-executar-o-projeto)
- [Qualidade e Testes](#qualidade-e-testes)
- [Diretrizes de Desenvolvimento](#diretrizes-de-desenvolvimento)

<br>

---

<br>

<a id="sobre-o-modulo"></a>

## 🎯 Sobre o Módulo

O diretório `appmistakemap/` contém a aplicação cliente frontend do **MistakeMap**. O aplicativo permite que o estudante:

1. **Capture e Registre**: Cadastrar exercícios e fotografar a resolução para envio à análise.
2. **Receba a Análise da IA**: Ver a transcrição, os erros por categoria, o conceito envolvido, a evidência e a confiança de cada sugestão.
3. **Navegue no Mapa de Erros**: Visualizar o grafo de conceitos, a frequência de cada categoria de erro e o histórico de tentativas.
4. **Pratique**: Pedir de 3 a 5 exercícios direcionados aos erros mais recentes de uma disciplina.

> [!NOTE]
> Modo *offline-first*, confirmação manual de cada erro sugerido e fila de revisão por prioridade fazem parte do roadmap e ainda não estão implementados. O estado completo está no [README principal](../.github/README.md#estado-atual).

> [!IMPORTANT]
> **Privacidade e Segurança**: Nenhuma chave com privilégios administrativos (`service_role`) deve ser incluída no bundle do aplicativo. Todo o controle de acesso e isolamento entre usuários é garantido via Row Level Security (RLS) no backend.

<br>

---

<br>

<a id="identificacao-academica"></a>

## 🎓 Identificação Acadêmica

| Campo | Informação |
|:---|:---|
| **Instituição** | Pontifícia Universidade Católica de Minas Gerais — **PUC Minas** |
| **Curso** | Engenharia de Computação |
| **Disciplina** | Projeto Integrado I: Desenvolvimento Móvel |
| **Autores** | **Cláudio Francisco Dos Santos Júnior** · **Lucas Emanuel Simão Silva** |
| **Orientação** | **Prof. Ilo Amy Saldanha Rivero** |

<br>

---

<br>

<a id="stack-tecnologica"></a>

## 🛠️ Stack Tecnológica

<div align="center">
<table>
  <tr>
    <td align="center" width="145">
      <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/flutter/flutter-original.svg" width="46" height="46" alt="Flutter"><br>
      <strong>Flutter</strong><br><sub>UI Framework</sub>
    </td>
    <td align="center" width="145">
      <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/dart/dart-original.svg" width="46" height="46" alt="Dart"><br>
      <strong>Dart</strong><br><sub>Linguagem</sub>
    </td>
    <td align="center" width="145">
      <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/supabase/supabase-original.svg" width="46" height="46" alt="Supabase"><br>
      <strong>Supabase</strong><br><sub>Client SDK</sub>
    </td>
    <td align="center" width="145">
      <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/windows8/windows8-original.svg" width="46" height="46" alt="Fluent UI"><br>
      <strong>Fluent UI</strong><br><sub>Design System</sub>
    </td>
    <td align="center" width="145">
      <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/cloudflare/cloudflare-original.svg" width="46" height="46" alt="Cloudflare R2"><br>
      <strong>Cloudflare R2</strong><br><sub>File Storage</sub>
    </td>
  </tr>
</table>
</div>

| Camada | Tecnologia / Padrão | Responsabilidade |
|:---|:---|:---|
| **Interface / Componentes** | Flutter (`fluent_ui`) | Renderização de telas, formulários, captura de câmera e gráficos |
| **Camada Flutuante** | `liquid_glass_widgets` | Barras superiores, botões da barra e avisos (toasts) |
| **Telas de IA** | Material 3 isolado (`AiMaterialShell`) | Envio, mapa de erros, correção e prática, com os tokens da marca |
| **Gerenciamento de Estado** | `StatefulWidget` + `setState` | Estado local por tela |
| **Roteamento** | `Navigator` + `AppNavigationShell` | Barra inferior no celular e menu lateral a partir de 840 px |
| **Integração de Backend** | `supabase_flutter` | Autenticação (e-mail/senha e Google), banco e chamadas às Edge Functions |
| **Captura de Imagem** | `image_picker` + `crypto` | Câmera/galeria e hash SHA-256 exigido pelo contrato de upload |
| **Armazenamento de Arquivos** | Cloudflare R2 (S3-compatível) | Upload via URL pré-assinada pela função `upload-url` (10GB grátis, egress zero) |
| **Padronização e Qualidade** | `flutter_lints` / `analysis_options.yaml` | Análise estática contínua de código |

<br>

---

<br>

<a id="funcionalidades"></a>

## ✨ Funcionalidades

| Tela | O que faz |
|:---|:---|
| **Login / Cadastro** | E-mail e senha ou conta Google; cria o perfil com papel `user` |
| **Início** | Resumo de exercícios, itens para revisar e evolução |
| **Lista** | Exercícios do estudante com status; ver detalhes, editar ou excluir |
| **Mapa** | Frequência por disciplina; abre o mapa de erros da IA |
| **Novo** | Cadastro de exercício com disciplina, enunciado, resposta e foto |
| **Analisar com IA** | Envio da tentativa e acompanhamento da análise |
| **Correção e evidências** | Transcrição, erros identificados e nova tentativa de análise |
| **Prática** | Exercícios gerados a partir dos erros, com gabarito |
| **Admin** | Papéis de usuários e uso das cotas de IA por modelo (somente administradores) |
| **Sobre** | Missão, equipe e stack do projeto |

<br>

---

<br>

<a id="arquitetura-de-software"></a>

## 🏛️ Arquitetura de Software

O cliente não contém lógica de negócio de IA: transcrição, classificação de erros e geração de exercícios rodam nas **Supabase Edge Functions**, que chamam o Google Gemini. O aplicativo autentica o usuário, grava exercícios e tentativas no PostgreSQL (com RLS), envia a foto direto para a R2 com uma URL pré-assinada e exibe os resultados.

```text
Flutter ──► Supabase Auth / PostgreSQL (RLS)
   │
   ├──► upload-url ──► URL pré-assinada ──► PUT da foto na Cloudflare R2
   ├──► analyze-attempt ──► Gemini ──► attempt_analyses + error_events
   └──► generate-practice ──► Gemini ──► practice_sets
```

<br>

<a id="estrutura-de-diretorios"></a>

## 📂 Estrutura de Diretórios

O MVP concentra as telas Fluent em `main.dart` e separa em pastas os módulos mais novos. A evolução prevista é extrair as telas para uma estrutura **Feature-First** (descrita no [README principal](../.github/README.md#arquitetura-flutter)).

```text
lib/
├── main.dart                 # Bootstrap do Supabase, AuthGate e telas Fluent
│
├── about/                    # Botão do LinkedIn e abertura de perfis externos
├── admin/                    # Painel de métricas, cotas por modelo e política de atualização
├── ai/                       # Fluxo de IA (rota Material isolada)
│   ├── ai_material_shell.dart        # Tema Material com os tokens da marca
│   ├── analysis_repository.dart      # Contrato com Supabase e Edge Functions
│   ├── analysis_models.dart          # Tentativas, análises, erros e prática
│   ├── exercise_submission_view.dart # Envio da tentativa e da foto
│   └── insights_view.dart            # Mapa de erros, correção e prática
├── assets/                   # Foto de perfil embutida
├── auth/                     # Login com Google e verificação do OAuth
├── layout/                   # Classes de largura, dobráveis e shell de navegação
└── theme/                    # Tokens de design, paleta, estilos de controles e movimento

test/                         # Testes de widget, contrato, layout e prévias visuais
database/                     # Migrações canônicas do Supabase (ver database/README.md)
```

<br>

---

<br>

<a id="como-executar-o-projeto"></a>

## 🚀 Como Executar o Projeto

### Pré-requisitos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) estável (validado com Flutter 3.47 / Dart 3.13)
- Android Studio / VS Code com extensões Flutter e Dart
- Dispositivo Android (ou emulador AVD) / Navegador Chrome / SDK Windows Desktop

> [!TIP]
> No Windows, mantenha o projeto em um caminho **sem acentos** (por exemplo, `D:\MistakeMap`). Caminhos com acentos fazem `flutter analyze` e o build AOT falharem.

### Passos de Instalação

1. **Acesse o diretório do aplicativo:**
   ```bash
   cd appmistakemap
   ```

2. **Baixe todas as dependências do projeto:**
   ```bash
   flutter pub get
   ```

3. **Verifique se seu ambiente está configurado corretamente:**
   ```bash
   flutter doctor
   ```

4. **Execute o aplicativo no dispositivo/alvo desejado:**

   - **Android:**
     ```bash
     flutter run -d android
     ```
   - **Navegador Web (Chrome):**
     ```bash
     flutter run -d chrome
     ```
   - **Windows Desktop:**
     ```bash
     flutter run -d windows
     ```

> [!NOTE]
> **Versão web publicada:** [mistakemap-tau.vercel.app](https://mistakemap-tau.vercel.app). O workflow `.github/workflows/web-deploy-vercel.yml` gera `flutter build web --release` e publica na Vercel a cada push no `main` que altera `appmistakemap/`. Os cabeçalhos e o roteamento ficam em `web/vercel.json`.

<br>

---

<br>

<a id="qualidade-e-testes"></a>

## 🧪 Qualidade e Testes

Para garantir a estabilidade do produto e integridade das regras de negócio:

### Análise Estática
Execute o analisador do Dart para verificar advertências e conformidade com as regras do linter:
```bash
flutter analyze
```

### Formatação
```bash
dart format --set-exit-if-changed lib/
```

### Executar Testes Automatizados
```bash
# Executa todos os testes unitários e de widgets (o mesmo comando do CI)
flutter test --reporter compact

# Executa testes com relatório de cobertura
flutter test --coverage

# Regenera as prévias visuais em test/previews/ (não versionadas)
flutter test test/responsive_test.dart --update-goldens --dart-define=GENERATE_PREVIEWS=true --plain-name "Prévias"
```

| Arquivo de teste | Cobertura |
|:---|:---|
| `analysis_test.dart`, `repository_contract_test.dart`, `upload_contract_test.dart` | Modelos da IA e contratos com Supabase e Edge Functions |
| `ai_navigation_test.dart`, `navigation_shell_test.dart` | Navegação entre telas Fluent e telas de IA |
| `responsive_test.dart`, `layout_adaptativo_test.dart` | Layout de 320 a 1440 px, dobráveis e telas duplas |
| `hover_color_test.dart`, `motion_test.dart` | Contraste do texto no hover e animações |
| `metrics_panel_test.dart`, `metrics_policy_test.dart`, `model_quota_card_test.dart` | Painel administrativo |
| `google_sign_in_test.dart`, `external_profile_test.dart`, `linkedin_profile_button_test.dart` | Login com Google e links externos |

> [!TIP]
> O CI (`.github/workflows/ci.yml`) roda `flutter analyze`, `dart format` e `flutter test` em todo pull request. Os três precisam passar para o merge no `main`.

<br>

---

<br>

<a id="diretrizes-de-desenvolvimento"></a>

## 📋 Diretrizes de Desenvolvimento

- **Sem lógica de IA no cliente**: OCR, LLM e regras de análise ficam nas Edge Functions; o aplicativo só chama as funções e exibe o resultado.
- **Sem segredos no bundle**: o cliente usa apenas a chave pública (`anon`) do Supabase; `service_role` e chaves de IA ficam nos segredos do backend.
- **Transparência na IA**: Toda inferência de conceitos e classificação de erros deve ser apresentada ao estudante como uma hipótese, com evidência e confiança visíveis.
- **Design System único**: telas novas usam os tokens de `lib/theme/` (cores, raios, espaçamento em ritmo de 4/8 px e movimento), inclusive na rota Material das telas de IA.
- **Clean Code**: Mantenha widgets desacoplados do acesso a dados; novas integrações seguem o padrão de repositório de `lib/ai/analysis_repository.dart`.
- **Qualidade**: Todo arquivo Dart deve passar em `flutter analyze` sem avisos.
- **Offline-First** *(roadmap)*: Operações de escrita deverão salvar rascunhos localmente antes de sincronizar com o backend.

<br>

---

<div align="center">

Desenvolvido para o **MistakeMap** · [Voltar para a raiz do repositório](../.github/README.md)

</div>
