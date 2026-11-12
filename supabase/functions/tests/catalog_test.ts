import { strict as assert } from "node:assert";
import { type CatalogRow, pickCatalog } from "../_shared/catalog.ts";

const row = (theme: string, position: number): CatalogRow => ({
  id: `${theme}-${position}`,
  theme,
  position,
  difficulty: "media",
  prompt_text: `${theme} ${position}`,
  correct_answer: "x",
  explanation: "y",
});

const tema = (theme: string) => [1, 2, 3, 4, 5].map((p) => row(theme, p));

Deno.test("catálogo alterna entre os conceitos com erro, por prioridade", () => {
  const rows = [...tema("Porcentagem"), ...tema("Equação do 1º grau")];
  const picks = pickCatalog(rows, ["equação do 1º grau", "Porcentagem"], 5)!;
  assert.deepEqual(picks.map((p) => p.id), [
    "Equação do 1º grau-1",
    "Porcentagem-1",
    "Equação do 1º grau-2",
    "Porcentagem-2",
    "Equação do 1º grau-3",
  ]);
  // O foco usa o nome do conceito como veio da análise.
  assert.equal(picks[0].focus_concept, "equação do 1º grau");
});

Deno.test("catálogo respeita a ordem de revisão dentro do tema", () => {
  const rows = [row("MRUV", 3), row("MRUV", 1), row("MRUV", 2)];
  assert.deepEqual(
    pickCatalog(rows, ["MRUV"], 3)!.map((p) => p.position),
    [1, 2, 3],
  );
});

Deno.test("catálogo ignora temas fora dos conceitos com erro", () => {
  const rows = [...tema("Porcentagem"), ...tema("MRUV")];
  const picks = pickCatalog(rows, ["MRUV"], 4)!;
  assert.ok(picks.every((p) => p.theme === "MRUV"));
});

Deno.test("catálogo sem alvos percorre os temas da matéria", () => {
  const rows = [...tema("Porcentagem"), ...tema("Equação do 1º grau")];
  const picks = pickCatalog(rows, [], 3)!;
  assert.deepEqual(picks.map((p) => p.id), [
    "Equação do 1º grau-1",
    "Porcentagem-1",
    "Equação do 1º grau-2",
  ]);
  assert.equal(picks[1].focus_concept, "Porcentagem");
});

Deno.test("catálogo devolve null quando não fecha a rodada", () => {
  assert.equal(
    pickCatalog([row("MRUV", 1), row("MRUV", 2)], ["MRUV"], 3),
    null,
  );
  assert.equal(pickCatalog(tema("MRUV"), ["Porcentagem"], 3), null);
  assert.equal(pickCatalog([], [], 3), null);
});
