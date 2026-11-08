import { strict as assert } from "node:assert";
import {
  achievementsFor,
  freezeDates,
  localDay,
  mondayOf,
  shiftDay,
  streakFor,
} from "../_shared/study_milestones.ts";

Deno.test("datas usam o fuso do estudante, viradas de mês e semana ISO", () => {
  const at = new Date("2026-11-06T01:30:00Z");
  assert.equal(localDay(at, "America/Sao_Paulo"), "2026-11-05");
  assert.equal(localDay(at, "UTC"), "2026-11-06");
  assert.equal(
    localDay(new Date("2026-03-08T04:59:00Z"), "America/New_York"),
    "2026-03-07",
  );
  assert.equal(
    localDay(new Date("2026-03-08T05:01:00Z"), "America/New_York"),
    "2026-03-08",
  );
  assert.equal(shiftDay("2028-03-01", -1), "2028-02-29");
  assert.equal(mondayOf("2026-01-01"), "2025-12-29");
});

Deno.test("pausa só protege intervalo entre dias de estudo e não conta como dia concluído", () => {
  const studied = new Set(["2026-11-07", "2026-11-09"]);
  const frozen = { date: "2026-11-08", week_start: "2026-11-02" };
  assert.deepEqual(freezeDates("2026-11-09", studied, []), [frozen.date]);
  assert.deepEqual(
    freezeDates("2026-11-09", new Set(["2026-11-07"]), []),
    [],
    "Sem retorno não há pausa para pontuar",
  );
  assert.deepEqual(
    freezeDates("2026-11-09", studied, [{
      date: "2026-11-03",
      week_start: "2026-11-02",
    }]),
    [],
    "Uma pausa por semana ISO",
  );
  assert.equal(streakFor("2026-11-09", studied, []).current_days, 1);
  const recovered = streakFor("2026-11-09", studied, [frozen]);
  assert.equal(recovered.current_days, 2);
  assert.equal(recovered.protected_days, 1);
  assert.equal(
    streakFor("2026-11-10", studied, [frozen]).current_days,
    2,
    "Hoje ainda pode estudar",
  );
  assert.equal(
    streakFor("2026-11-11", studied, [frozen]).current_days,
    0,
    "Nova lacuna interrompe sequência",
  );
});

Deno.test("conquistas têm evidência e limiares independentes", () => {
  assert.deepEqual(achievementsFor(0, 0, 0).map((a) => a.earned), [
    false,
    false,
    false,
  ]);
  assert.deepEqual(achievementsFor(10, 1, 4).map((a) => a.earned), [
    true,
    false,
    false,
  ]);
  assert.deepEqual(achievementsFor(3, 3, 5).map((a) => a.earned), [
    true,
    true,
    true,
  ]);
});
