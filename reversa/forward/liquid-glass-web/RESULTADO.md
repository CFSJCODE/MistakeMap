# Liquid Glass + Fluent na web — prints

Build web de release (Flutter 3.47.2, CanvasKit) aberto no Chromium, 1440×900 e 390×844.
Para mostrar o app sem login, o build local trocou só o `home:` por `TelaNavegacao` com um usuário fictício (sem Supabase, por isso "Modo offline").

| Arquivo | O que mostra |
|---|---|
| `antes-desktop.png` | main antes do PR: barra de rolagem fina dentro da coluna de 1120 px |
| `depois-desktop.png` | barra colada na borda direita, trilho flutuante de vidro, barra superior com desfoque saturado |
| `depois-desktop-hover-barra.png` | barra de rolagem sob o ponteiro (mais grossa) |
| `depois-celular.png` | web no celular: barra inferior de 7 botões igual, barra de rolagem na borda |
