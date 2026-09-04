<a id="readme-top"></a>

<div align="center">

# MistakeMap — Cliente Flutter 📱

### Aplicativo Multiplataforma para Mapeamento de Padrões de Erro

Cliente móvel e desktop da plataforma **MistakeMap**, desenvolvido em Flutter para captura, classificação, revisão metacognitiva e visualização do grafo de fragilidades e evolução do estudante.

<br>

[![GitHub](https://img.shields.io/badge/GitHub-CFSJCODE%2FMISTAKEMAP-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/CFSJCODE/MISTAKEMAP)
[![Flutter](https://img.shields.io/badge/Flutter-^3.13-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-^3.0-0175C2?style=flat-square&logo=dart&logoColor=white)](https://dart.dev)
![Status](https://img.shields.io/badge/Status-Desenvolvimento%20%2F%20MVP-F59E0B?style=flat-square)
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

O diretório `appmistakemap/` contém a aplicação cliente frontend do **MistakeMap**. O aplicativo é projetado para operar com suporte *offline-first*, permitindo que o estudante:

1. **Capture e Registre**: Fotografar resoluções de exercícios e correções mesmo sem conexão com a internet.
2. **Revise com Human-in-the-Loop**: Conferir e editar transcrições de OCR e sugestões de erro da IA antes de qualquer confirmação.
3. **Navegue no Grafo de Erros**: Visualizar nós de conceitos prioritários, histórico de tentativas e evidências de recuperação ao longo do tempo.
4. **Priorize Estudos**: Consultar a fila de revisão explicável baseada em recência e recorrência de falhas conceituais.

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
| **Interface / Componentes** | Flutter (Fluent UI) | Renderização de telas, formulários, captura de câmera e gráficos |
| **Gerenciamento de Estado** | Riverpod | Injeção de dependências reativa e controle de ciclo de vida de dados |
| **Roteamento** | GoRouter | Navegação declarativa, tratamento de histórico e deep links |
| **Integração de Backend** | `supabase_flutter` | Autenticação e sincronização de banco de dados |
| **Armazenamento de Arquivos** | Cloudflare R2 (S3-compatível) | Upload e armazenamento de fotos de exercícios (10GB grátis, egress zero) |
| **Padronização e Qualidade** | `flutter_lints` / `analysis_options.yaml` | Análise estática contínua de código |

<br>

---

<br>

<a id="arquitetura-of-software"></a>

## 🏛️ Arquitetura de Software

O código em `lib/` adota o padrão **Feature-First**, garantindo alta modularidade, facilidade de manutenção e isolamento de responsabilidades:

```text
lib/
├── app/                  # Configurações globais da aplicação
│   ├── bootstrap/        # Inicialização assíncrona (Supabase, configs locais)
│   ├── router/           # Definição centralizada de rotas (GoRouter)
│   └── theme/            # Definições de tema e cores Fluent UI
│
├── core/                 # Componentes compartilhados transversais
│   ├── errors/           # Classes de tratamento de exceções e falhas
│   ├── services/         # Clientes de rede, armazenamento local e câmera
│   ├── utils/            # Formatadores, constantes e extensões
│   └── widgets/          # Componentes visuais atômicos reutilizáveis
│
├── features/             # Módulos de domínio e funcionalidades de negócio
│   ├── auth/             # Login, cadastro e controle de sessão
│   ├── subjects/         # Gestão de disciplinas e áreas de conhecimento
│   ├── concepts/         # Grafo e catálogo de conceitos
│   ├── exercises/        # Enunciados e registros de problemas
│   ├── capture/          # Captura por câmera e processamento OCR
│   ├── attempts/         # Resoluções e correções de exercícios
│   ├── mistake_map/      # Visualização do mapa de fragilidades e conexões
│   ├── review/           # Fila de revisão e priorização de tópicos
│   └── settings/         # Preferências do usuário e exportação
│
└── main.dart             # Ponto de entrada (entrypoint) da aplicação
```

<br>

---

<br>

<a id="como-executar-o-projeto"></a>

## 🚀 Como Executar o Projeto

### Pré-requisitos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (versão compatível com Dart 3.x)
- Android Studio / VS Code com extensões Flutter e Dart
- Dispositivo Android (ou emulador AVD) / Navegador Chrome / SDK Windows Desktop

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

### Executar Testes Automatizados
```bash
# Executa todos os testes unitários e de widgets
flutter test

# Executa testes com relatório de cobertura
flutter test --coverage
```

> [!TIP]
> **Cobertura Recomendada**: Priorize testes unitários nas regras de pontuação/prioridade e nos modelos de dados, além de testes de widget para os fluxos de captura e revisão de erros.

<br>

---

<br>

<a id="diretrizes-de-desenvolvimento"></a>

## 📋 Diretrizes de Desenvolvimento

- **Offline-First**: Operações de escrita devem salvar rascunhos localmente antes de disparar sincronizações com o backend.
- **Transparência na IA**: Toda inferência de conceitos e classificação de erros deve ser apresentada ao estudante como uma hipótese pendente de validação manual.
- **Clean Code**: Mantenha widgets desacoplados de regras de acesso a dados diretas, utilizando providers do Riverpod.

<br>

---

<div align="center">

Desenvolvido para o **MistakeMap** · [Voltar para a raiz do repositório](../README.md)

</div>
