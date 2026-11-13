#!/usr/bin/env python3
"""Seed compacto: os dados vão num único jsonb e o SQL genérico expande.
Ids = md5(conta || chave)::uuid. Uso: python3 gerar_compacto.py <email> [...] (gera seed_alunos.sql)"""
import json, sys, hashlib, uuid, math, pathlib, importlib.util
base = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location("g", base / "gerar_seed.py")
sys_argv = sys.argv; sys.argv = ["x", "__USER_ID__"]
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
sys.argv = sys_argv
for f in base.glob("*__USER_I.sql"): f.unlink()
users = sys.argv[1:]
PEND = g.PENDING_UNDER_H; DEC = g.DECISION_DELAY_H
D = {"subjects": [{"k": k, "name": n} for k, n in g.SUBJECTS.items()],
     "concepts": [{"k": k, "s": s, "name": n, "imp": i} for k, (s, n, i) in g.CONCEPTS.items()],
     "edges": [list(e) for e in g.EDGES], "mark": g.MARK}
first = {}
for a, e, h, *_ in g.AT: first[e] = max(first.get(e, 0), h)
D["exercises"] = [{"k": k, "s": s, "diff": d, "prompt": p, "gab": gb, "expl": ex, "concs": c, "h": first[k] + 2}
                  for k, (s, d, p, gb, ex, c) in g.EX.items()]
D["attempts"] = []
events = {}
for a, e, h, ans, ok, errs in g.AT:
    er = []
    for i, (cat, c, ev, cf) in enumerate(errs):
        st = "pending" if h < PEND else "confirmed"
        er.append({"cat": cat, "c": c, "ev": ev, "cf": cf, "st": st})
        if st == "confirmed":
            events.setdefault((c, cat), []).append((h, f"ee:{a}:{i}", a, e, ev))
    D["attempts"].append({"k": a, "e": e, "h": h, "ans": ans, "ok": ok, "errs": er})
items = {}
for key, evs in events.items():
    latest = min(evs)
    ch = max(x[0] for x in evs) - DEC
    items[key] = {"k": f"ri:{key[0]}:{key[1]}", "c": key[0], "cat": key[1], "ev": latest[1], "att": latest[2],
                  "prompt_e": latest[3], "evidence": latest[4], "created_h": ch, "interval": 0, "reps": 0,
                  "lapses": 0, "last_h": None, "due_h": ch}
def sched(iv, r, l, rt):
    p = max(0, min(180, iv))
    d = 1 if rt == "again" else max(1, math.ceil(p * 1.2)) if rt == "hard" else max(3, math.ceil(p * 2.5)) if rt == "easy" else max(1, math.ceil(p * 2) if p else 1)
    return min(180, d), r + 1, l + (rt == "again")
D["sessions"] = []
for sid, h, revs in g.SESSIONS:
    S = {"k": "sess:" + sid, "h": h, "min": 15 if len(revs) <= 3 else 20, "items": []}
    for pos, (c, cat, rt) in enumerate(revs):
        it = items[(c, cat)]
        ah = round(h - 0.03 * (pos + 1), 2)
        it["interval"], it["reps"], it["lapses"] = sched(it["interval"], it["reps"], it["lapses"], rt)
        it["last_h"] = ah; it["due_h"] = round(ah - 24 * it["interval"], 2)
        S["items"].append({"item": it["k"], "pos": pos, "rt": rt, "ah": ah, "next_h": it["due_h"], "att": it["att"],
                           "ev": it["ev"], "e": it["prompt_e"], "evidence": it["evidence"], "cat": cat, "el": 40 + 17 * pos})
    D["sessions"].append(S)
D["items"] = list(items.values())
keep = {it["att"] for it in items.values()}
for a in D["attempts"]:
    a["opt"] = a["k"] not in keep
D["notes"] = [{"k": f"note:{i}", "h": h, "s": s, "t": t, "r": r, "type": ty, "rev": rv} for i, (h, s, t, r, ty, rv) in enumerate(g.NOTES)]
D["study"] = []
for s, m in g.STUDY.items():
    D["study"].append({"s": s, "summary": m["summary"], "flash": m["flashcards"], "h": m["hours"], "src": m["source_count"],
                       "quiz": [dict(q, k=f"quiz:{s}:{i}") for i, q in enumerate(m["quiz"])], "round": m["round"]})
D["qb"] = [{"k": f"qb:{i}", "slug": s, "choice": c, "h": h} for i, (s, c, h) in enumerate(g.QB)]
D["goal"] = "Chegar bem na prova de Sistemas Embarcados e na competição de robótica"
data = json.dumps(D, ensure_ascii=False, separators=(",", ":"))
assert "$d$" not in data
sql = (base / "seed_compacto_template.sql").read_text()
sql = sql.replace("__USERS__", ",".join(f"'{u.lower()}'" for u in users)).replace("__DATA__", data)
(base / "seed_alunos.sql").write_text(sql, encoding="utf-8")
print("ok", len(sql), "bytes")
