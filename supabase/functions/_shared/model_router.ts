/** Resultados agregados de avaliação independente, nunca dados do estudante. */
export type RoutingEvidence = {
  provider: "gemini" | "anthropic" | "openrouter";
  model: string;
  task: string;
  datasetId: string;
  vision: boolean;
  samples: number;
  quality: number;
  latencyMs: number;
  costUsdPerRequest: number;
  evaluatedAt: string;
};

/** Seleciona somente modelos testados na tarefa e com qualidade mínima. */
export function selectModel(
  records: RoutingEvidence[],
  task: string,
  needsVision: boolean,
  now: number,
  maxCostUsd: number,
): RoutingEvidence | undefined {
  if (!Number.isFinite(maxCostUsd) || maxCostUsd < 0) return undefined;
  const eligible = records.filter((r) => {
    if (!r || typeof r !== "object" || typeof r.evaluatedAt !== "string") {
      return false;
    }
    const age = now - Date.parse(r.evaluatedAt);
    return ["gemini", "anthropic", "openrouter"].includes(r.provider) &&
      typeof r.model === "string" && r.model.trim().length > 0 &&
      r.task === task && (!needsVision || r.vision === true) &&
      typeof r.datasetId === "string" && r.datasetId.trim().length > 0 &&
      Number.isInteger(r.samples) && r.samples >= 20 &&
      Number.isFinite(r.quality) && r.quality >= .8 && r.quality <= 1 &&
      Number.isFinite(r.latencyMs) && r.latencyMs > 0 &&
      Number.isFinite(r.costUsdPerRequest) && r.costUsdPerRequest >= 0 &&
      r.costUsdPerRequest <= maxCostUsd && Number.isFinite(age) &&
      age >= 0 && age <= 30 * 86400000;
  });
  // A comparison requires at least two distinct models on the same dataset.
  if (
    new Set(eligible.map((r) => `${r.provider}/${r.model}`)).size < 2 ||
    new Set(eligible.map((r) => r.datasetId)).size !== 1
  ) return undefined;
  const bestQuality = Math.max(...eligible.map((r) => r.quality));
  return eligible.filter((r) => r.quality >= bestQuality - .02).sort((a, b) => {
    // Qualidade tem prioridade: só compara custo e tempo dentro de 2 pontos
    // percentuais, evitando trocar precisão por uma diferença pequena de preço.
    const aScore = a.costUsdPerRequest + a.latencyMs / 1000 * .00001;
    const bScore = b.costUsdPerRequest + b.latencyMs / 1000 * .00001;
    return aScore - bScore || b.quality - a.quality;
  })[0];
}
