#!/usr/bin/env python3
"""Gera o INSERT de uma versão de documento legal para uma migration nova.

Os textos ficam em appmistakemap/database/legal/<documento>/<versao>.md.
Uso (copie a saída para uma migration nova; migrations antigas nunca mudam):

    python3 scripts/legal_document_sql.py contrato-saas 1.1 2027-01-01
"""
import hashlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LEGAL = ROOT / "appmistakemap" / "database" / "legal"


def title_of(body: str) -> str:
    for line in body.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    raise SystemExit("o texto precisa começar com um título '# ...'")


def insert_sql(document: str, version: str, effective: str) -> str:
    path = LEGAL / document / f"{version}.md"
    body = path.read_text(encoding="utf-8")
    if "$legal$" in body:
        raise SystemExit("o texto não pode conter $legal$")
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
    title = title_of(body).replace("'", "''")
    return (
        "insert into public.legal_document_versions"
        "(document, version, title, body, sha256, effective_at) values (\n"
        f"  '{document}', '{version}', '{title}',\n"
        f"  $legal${body}$legal$,\n"
        f"  '{digest}', '{effective}T00:00:00-03:00');\n"
    )


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    sys.stdout.write(insert_sql(*sys.argv[1:]))
