// Conteúdo exibido na tela "Sobre o MistakeMap".
// Substitua [NOME DO ORIENTADOR] pelo nome real antes de publicar.

abstract final class AboutContent {
  // ── Identidade ──────────────────────────────────────────────────────────────

  static const String appName = 'MistakeMap';

  static const String tagline =
      'Mapa dos Padrões de Erro do Estudante';

  static const String version = '1.0 · Agosto de 2026';

  // ── O que é ─────────────────────────────────────────────────────────────────

  static const String description =
      'O MistakeMap transforma exercícios corrigidos em um grafo de '
      'fragilidades conceituais, tipos de erro, recorrência e evolução — '
      'orientando a revisão sem reduzir o estudante a uma nota.\n\n'
      'Ao estudar, o aluno fotografa ou registra sua resolução. '
      'OCR e Inteligência Artificial extraem os conceitos envolvidos e '
      'sugerem padrões de falha. O estudante valida essas sugestões e o '
      'sistema constrói um mapa temporal de onde e como os erros aparecem, '
      'respondendo à pergunta mais útil: "Que padrão existe por trás dos '
      'meus erros e em quais conceitos ele se repete?"';

  // ── Missão ──────────────────────────────────────────────────────────────────

  static const String missionTitle = 'Missão';

  static const String mission =
      'Tornar visível o que o erro tem a ensinar. '
      'Queremos que cada exercício corrigido se transforme em evidência '
      'de aprendizado — não em registro de fracasso — e que o estudante '
      'passe a revisar com intencionalidade, guiado por dados reais sobre '
      'seus próprios padrões conceituais.';

  // ── Visão ───────────────────────────────────────────────────────────────────

  static const String visionTitle = 'Visão';

  static const String vision =
      'Ser a ferramenta de referência para estudantes do Ensino Fundamental II, '
      'Ensino Médio e Graduação que querem entender — e superar — suas '
      'fragilidades conceituais em matemática, física, computação, engenharias '
      'e qualquer disciplina baseada em resolução de problemas.';

  // ── Valores ─────────────────────────────────────────────────────────────────

  static const String valuesTitle = 'Valores';

  static const List<({String titulo, String descricao})> values = [
    (
      titulo: 'O erro é contexto, não rótulo',
      descricao:
          'Cada falha é um evento pontual ligado a um conceito e a uma '
          'operação cognitiva — nunca uma sentença permanente sobre o estudante.',
    ),
    (
      titulo: 'Evidência antes de diagnóstico',
      descricao:
          'Nenhuma classificação automática se torna definitiva sem '
          'confirmação do próprio aluno. O sistema sugere; o estudante decide.',
    ),
    (
      titulo: 'Revisão com propósito',
      descricao:
          'Priorizamos o que tem maior frequência, recência e importância '
          'conceitual — não o que é mais fácil de corrigir.',
    ),
    (
      titulo: 'Transparência algorítmica',
      descricao:
          'A prioridade de revisão é calculada de forma visível e ajustável, '
          'sem comportamentos ocultos ou prescritivos.',
    ),
    (
      titulo: 'Respeito à trajetória do estudante',
      descricao:
          'Uma fragilidade diminui quando novos exercícios demonstram domínio '
          '— nunca por decreto ou por passagem de tempo.',
    ),
  ];

  // ── Disciplina e contexto acadêmico ─────────────────────────────────────────

  static const String academicTitle = 'Disciplina';

  static const String academic =
      'Este aplicativo foi desenvolvido como trabalho prático da disciplina '
      'Projeto Integrado I — Desenvolvimento Móvel, cursada no 4.º semestre '
      'do curso de Engenharia de Software da PUC Minas, no segundo semestre '
      'de 2026.';

  // ── Orientação ──────────────────────────────────────────────────────────────

  static const String advisorTitle = 'Orientação';

  // TODO: substitua pelo nome real do orientador antes de publicar.
  static const String advisor = '[NOME DO ORIENTADOR]';

  static const String advisorLabel =
      'Orientado por $advisor\nPUC Minas · 2026';

  // ── Criadores ───────────────────────────────────────────────────────────────

  static const String creatorsTitle = 'Criadores';

  static const List<({String nome, String papel})> creators = [
    (
      nome: 'Cláudio Francisco Dos Santos Júnior',
      papel: 'Backend · Storage · Apoio a Frontend',
    ),
    (
      nome: 'Lucas Emanuel Simão Silva',
      papel: 'OCR · LLM · Grafo Conceitual · Frontend',
    ),
  ];

  // ── Tecnologia ──────────────────────────────────────────────────────────────

  static const String techTitle = 'Tecnologia';

  static const String tech =
      'Construído com Flutter + Dart para Android, Windows e Web. '
      'Backend híbrido com Supabase (Postgres, Auth, RLS) e '
      'Cloudflare R2 para armazenamento de arquivos. '
      'Pipeline de IA assíncrono via OCR e LLM.';

  // ── Rodapé ──────────────────────────────────────────────────────────────────

  static const String footerOrg = 'CFSJ TECH';

  static const String footerCopyright =
      '© 2026 CFSJ TECH · MistakeMap · Todos os direitos reservados';
}
