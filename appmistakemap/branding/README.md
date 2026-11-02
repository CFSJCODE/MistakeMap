# Ícone do MistakeMap

Um "M" desenhado como grafo: cinco conceitos ligados por arestas, como no Mapa
do app. O nó do meio, em coral com anel de foco, é o erro que o mapa revela.
Fundo Abyss/Deep com brilhos Aurora (Aqua e Violet), na paleta de
`lib/theme/design_tokens.dart`.

| Arquivo | Uso |
|---|---|
| `mistakemap_icone.svg` | Fonte principal (quadrado arredondado) |
| `mistakemap_icone_pequeno.svg` | Traço mais grosso, para 16 a 48 px |
| `mistakemap_maskable.svg` | PWA maskable (quadrado cheio, zona segura de 80%) |
| `mistakemap_adaptativo_*.svg` | Camadas do ícone adaptativo do Android |

Para regenerar todos os PNG/ICO (Android, Windows e web), na raiz do repo:

```bash
python3 scripts/gerar_icones.py   # precisa de Pillow e Playwright (Chromium)
```

Ícone e nome mudam arquivos nativos: só chegam aos apps instalados por um
**release nativo**, não por patch do Shorebird.
