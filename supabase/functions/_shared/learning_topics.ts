/**
 * Tópicos de orientação derivados do sumário de material acadêmico revisado.
 * Não contém textos, exercícios, respostas ou dados pessoais da biblioteca.
 * Só retorna contexto quando a matéria identifica claramente o domínio.
 */
export function learningTopics(subject: string): string[] {
  const normalized = subject.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .toLowerCase().trim();
  if (/\b(iot|internet das coisas)\b/.test(normalized)) {
    return [
      "Dispositivos conectados, sensores e aplicações de Internet das Coisas",
      "Arquiteturas de redes e protocolos de comunicação para IoT",
      "Levantamento de requisitos e tecnologias para sistemas conectados",
    ];
  }
  return [];
}
