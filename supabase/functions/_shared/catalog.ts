// Catálogo de exercícios revisados (public.catalog_exercises): cinco por
// matéria/assunto/tema, com gabarito conferido em catalog_answer_keys.
// O generate-practice serve primeiro o catálogo e só chama a IA quando ele
// não cobre a rodada inteira.

export type CatalogRow = {
  id: string;
  theme: string;
  position: number;
  difficulty: string;
  prompt_text: string;
  correct_answer: string;
  explanation: string;
};

export type CatalogPick = CatalogRow & { focus_concept: string };

const key = (s: string) => s.trim().toLowerCase();

/**
 * Escolhe [count] exercícios do catálogo para uma rodada de prática.
 *
 * Com [targets] (conceitos com erro, em ordem de prioridade), só entram temas
 * iguais a um conceito, distribuídos em rodízio a partir do mais prioritário,
 * como a IA faria. Sem alvos, o rodízio passa pelos temas da matéria. Dentro
 * de cada tema vale a ordem de revisão (posição 1 a 5).
 *
 * Devolve null quando o catálogo não fecha a rodada: misturar meia rodada
 * revisada com meia gerada mudaria o contrato de contagem da IA.
 */
export function pickCatalog(
  rows: CatalogRow[],
  targets: string[],
  count: number,
): CatalogPick[] | null {
  const byTheme = new Map<string, CatalogRow[]>();
  for (const row of rows) {
    const k = key(row.theme);
    byTheme.set(k, [...(byTheme.get(k) ?? []), row]);
  }
  for (const list of byTheme.values()) {
    list.sort((a, b) => a.position - b.position);
  }
  // Ordem dos temas: a dos alvos; sem alvos, alfabética para ser estável.
  const order = targets.length
    ? [...new Set(targets.map(key))].filter((k) => byTheme.has(k))
    : [...byTheme.keys()].sort();
  const label = new Map(targets.map((t) => [key(t), t]));
  const picks: CatalogPick[] = [];
  let progress = true;
  while (picks.length < count && progress) {
    progress = false;
    for (const theme of order) {
      if (picks.length >= count) break;
      const next = byTheme.get(theme)!.shift();
      if (!next) continue;
      progress = true;
      picks.push({ ...next, focus_concept: label.get(theme) ?? next.theme });
    }
  }
  return picks.length === count ? picks : null;
}
