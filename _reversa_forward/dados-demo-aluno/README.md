# Dados de demonstração (aluno)

Histórico realista de um aluno para preencher Mapa, Estudar, Caderno, Praticar e Material de estudo.

- `seed-compacto.sql`: aplica o seed nas contas listadas no início do bloco (ids determinísticos `md5(conta || chave)::uuid`; pula conta já semeada).
- `remover-compacto.sql`: desfaz o seed por conta (notas do caderno viram tombstone).

Aplicado em produção em 2026-11-09 nas contas de teste e do Lucas. Os geradores Python ficam na pasta compartilhada do projeto (`dados-demo-aluno/`), fora do repositório.
