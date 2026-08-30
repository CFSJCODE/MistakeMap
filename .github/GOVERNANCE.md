# MistakeMap — Repository Governance

Esta pasta concentra os documentos de **apresentação, governança, licenciamento, atribuição, contribuição, citação e identidade** do repositório MistakeMap.

## Documentos canônicos

| Arquivo | Finalidade |
|---|---|
| [`README.md`](./README.md) | README principal do repositório, exibido nativamente pelo GitHub na página inicial |
| [`LICENSE`](./LICENSE) | Licença PolyForm Noncommercial 1.0.0, copyright e `Required Notice:` |
| [`NOTICE`](./NOTICE) | Avisos formais de autoria, atribuição e contexto do projeto |
| [`USAGE_POLICY.md`](./USAGE_POLICY.md) | Política prática de usos permitidos e não permitidos |
| [`TRADEMARKS.md`](./TRADEMARKS.md) | Política do nome MistakeMap, identidade visual e versões não oficiais |
| [`CITATION.cff`](./CITATION.cff) | Metadados estruturados de citação |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | Regras técnicas e jurídicas para contribuições |

## Compatibilidade com recursos nativos do GitHub

Os arquivos desta pasta são as **fontes canônicas**. Para preservar recursos nativos do GitHub:

- `README.md` permanece exclusivamente em `.github/`, localização reconhecida nativamente pelo GitHub e utilizada como README principal quando não existe um README na raiz;
- `LICENSE` é espelhado automaticamente na raiz para detecção/exibição da licença;
- `CITATION.cff` é espelhado automaticamente na raiz para manter o botão **Cite this repository**;
- `CONTRIBUTING.md` permanece nesta pasta `.github/`, local reconhecido nativamente pelo GitHub para diretrizes de contribuição.

A sincronização dos arquivos que precisam existir na raiz é realizada por [`workflows/sync-repository-metadata.yml`](./workflows/sync-repository-metadata.yml).

> **Regra de manutenção:** edite os documentos canônicos dentro de `.github/`. Não edite manualmente os espelhos `LICENSE` e `CITATION.cff` da raiz, pois eles serão sobrescritos pela automação.

## Estrutura documental

```text
MistakeMap/
├── LICENSE                 # espelho para integração nativa do GitHub
├── CITATION.cff            # espelho para "Cite this repository"
└── .github/
    ├── README.md            # README principal e canônico
    ├── GOVERNANCE.md
    ├── LICENSE
    ├── NOTICE
    ├── USAGE_POLICY.md
    ├── TRADEMARKS.md
    ├── CITATION.cff
    ├── CONTRIBUTING.md
    └── workflows/
        └── sync-repository-metadata.yml
```

## Autores originais

- **Cláudio Francisco Dos Santos Júnior**
- **Lucas Emanuel Simão Silva**

Projeto original: https://github.com/CFSJCODE/MistakeMap
