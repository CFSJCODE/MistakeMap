#!/usr/bin/env python3
"""Gera o ícone do MistakeMap (SVG fonte + PNG/ICO de todas as plataformas).

Conceito: um "M" desenhado como grafo — cinco conceitos ligados por arestas,
como no Mapa do app. O nó do meio (coral) é o erro: o ponto fraco que o
mapa revela, com um anel de foco ao redor. Fundo Abyss/Deep com brilhos
Aurora (Aqua e Violet), na paleta de lib/theme/design_tokens.dart.

Uso (na raiz do repo):  python3 scripts/gerar_icones.py
Precisa de Pillow e Playwright (Chromium) para rasterizar o SVG.
"""
from __future__ import annotations

import io
import pathlib
import sys

from PIL import Image
from playwright.sync_api import sync_playwright

RAIZ = pathlib.Path(__file__).resolve().parents[1]
APP = RAIZ / "appmistakemap"

ABYSS, DEEP, SLATE = "#06141B", "#11212D", "#253745"
AQUA, AZURE, VIOLET, CORAL, MINT = "#36D6C3", "#4C9DFF", "#9B7BFF", "#FF6F7D", "#4FD98B"

# Nós do "M" (coordenadas num quadro de 1024).
NOS = [(304, 704, AQUA), (336, 330, AZURE), (512, 566, CORAL), (688, 330, VIOLET), (720, 704, MINT)]


def fundo(arredondado: bool) -> str:
    rx = 228 if arredondado else 0
    return f"""
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{SLATE}"/>
      <stop offset=".45" stop-color="{DEEP}"/>
      <stop offset="1" stop-color="{ABYSS}"/>
    </linearGradient>
    <radialGradient id="glowV" cx=".82" cy=".14" r=".62">
      <stop offset="0" stop-color="{VIOLET}" stop-opacity=".55"/>
      <stop offset="1" stop-color="{VIOLET}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glowA" cx=".12" cy=".92" r=".6">
      <stop offset="0" stop-color="{AQUA}" stop-opacity=".42"/>
      <stop offset="1" stop-color="{AQUA}" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="forma"><rect width="1024" height="1024" rx="{rx}"/></clipPath>
  </defs>
  <g clip-path="url(#forma)">
    <rect width="1024" height="1024" fill="url(#bg)"/>
    <rect width="1024" height="1024" fill="url(#glowV)"/>
    <rect width="1024" height="1024" fill="url(#glowA)"/>
    <g stroke="#FFFFFF" stroke-opacity=".05" stroke-width="4" fill="none">
      <path d="M0 256H1024M0 512H1024M0 768H1024M256 0V1024M512 0V1024M768 0V1024"/>
    </g>
    <rect x="6" y="6" width="1012" height="1012" rx="{max(rx - 6, 0)}" fill="none"
          stroke="#FFFFFF" stroke-opacity=".10" stroke-width="12"/>
  </g>"""


def grafo(escala: float = 1.0, simples: bool = False, mono: str | None = None) -> str:
    """Desenho do M-grafo. `simples` engrossa traços para 16-32 px."""
    aresta = 74 if simples else 58
    raio = 86 if simples else 68
    pontos = " ".join(f"{x},{y}" for x, y, _ in NOS)
    cor_aresta = mono or "url(#aresta)"
    partes = [f'<g transform="translate(512 512) scale({escala}) translate(-512 -512)">']
    if not mono:
        partes.append(f"""
    <defs>
      <linearGradient id="aresta" x1="300" y1="0" x2="724" y2="0" gradientUnits="userSpaceOnUse">
        <stop offset="0" stop-color="{AQUA}"/>
        <stop offset=".5" stop-color="{AZURE}"/>
        <stop offset="1" stop-color="{VIOLET}"/>
      </linearGradient>
      <filter id="brilho" x="-50%" y="-50%" width="200%" height="200%">
        <feGaussianBlur stdDeviation="22"/>
      </filter>
    </defs>""")
        if not simples:
            partes.append(f'<polyline points="{pontos}" fill="none" stroke="url(#aresta)" '
                          f'stroke-width="{aresta + 30}" stroke-linecap="round" stroke-linejoin="round" '
                          f'opacity=".35" filter="url(#brilho)"/>')
    partes.append(f'<polyline points="{pontos}" fill="none" stroke="{cor_aresta}" '
                  f'stroke-width="{aresta}" stroke-linecap="round" stroke-linejoin="round"/>')
    for x, y, cor in NOS:
        erro = cor == CORAL
        if erro and not simples:
            partes.append(f'<circle cx="{x}" cy="{y}" r="{raio + 40}" fill="none" '
                          f'stroke="{mono or CORAL}" stroke-width="16" stroke-opacity=".55"/>')
        if mono:
            partes.append(f'<circle cx="{x}" cy="{y}" r="{raio}" fill="{mono}"/>')
            continue
        partes.append(f'<circle cx="{x}" cy="{y}" r="{raio}" fill="{cor}"/>')
        miolo = ABYSS if erro else "#FFFFFF"
        partes.append(f'<circle cx="{x}" cy="{y}" r="{raio * (0.36 if erro else 0.3):.1f}" '
                      f'fill="{miolo}" fill-opacity="{0.9 if erro else 0.85}"/>')
    partes.append("</g>")
    return "\n  ".join(partes)


def svg(corpo: str) -> str:
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024">{corpo}\n</svg>\n')


VARIANTES = {
    # Ícone completo (web, Windows, legado Android): quadrado arredondado.
    "icone": svg(fundo(True) + grafo()),
    "icone_pequeno": svg(fundo(True) + grafo(simples=True)),
    # Quadrado cheio (PWA maskable): conteúdo dentro da zona segura de 80%.
    "maskable": svg(fundo(False) + grafo(escala=0.92)),
    # Android adaptativo: camadas separadas, conteúdo na zona segura de 66%.
    "adaptativo_fundo": svg(fundo(False)),
    "adaptativo_frente": svg(grafo(escala=0.74)),
    "adaptativo_mono": svg(grafo(escala=0.74, mono="#FFFFFF")),
}


def rasterizar(pagina, codigo: str, lado: int) -> Image.Image:
    pagina.set_viewport_size({"width": lado, "height": lado})
    pagina.set_content(
        "<html><body style='margin:0;background:transparent'>"
        + codigo.replace('width="1024" height="1024" viewBox', f'width="{lado}" height="{lado}" viewBox', 1)
        + "</body></html>")
    png = pagina.screenshot(omit_background=True, clip={"x": 0, "y": 0, "width": lado, "height": lado})
    return Image.open(io.BytesIO(png)).convert("RGBA")


def main() -> int:
    marca = APP / "branding"
    marca.mkdir(exist_ok=True)
    for nome, codigo in VARIANTES.items():
        (marca / f"mistakemap_{nome}.svg").write_text(codigo, encoding="utf-8")

    res = APP / "android/app/src/main/res"
    with sync_playwright() as p:
        nav = p.chromium.launch()
        pg = nav.new_page()

        def salvar(nome: str, lado: int, destino: pathlib.Path) -> None:
            destino.parent.mkdir(parents=True, exist_ok=True)
            rasterizar(pg, VARIANTES[nome], lado).save(destino, optimize=True)

        # Prévia em alta para revisão.
        salvar("icone", 1024, marca / "mistakemap_icone_1024.png")

        # Android: legado (48 dp) + camadas adaptativas (108 dp).
        densidades = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
        for d, f in densidades.items():
            salvar("icone", round(48 * f), res / f"mipmap-{d}/ic_launcher.png")
            for camada, arq in (("adaptativo_fundo", "ic_launcher_background"),
                                ("adaptativo_frente", "ic_launcher_foreground"),
                                ("adaptativo_mono", "ic_launcher_monochrome")):
                salvar(camada, round(108 * f), res / f"mipmap-{d}/{arq}.png")

        # Web: favicon + PWA.
        web = APP / "web"
        salvar("icone_pequeno", 48, web / "favicon.png")
        salvar("icone", 192, web / "icons/Icon-192.png")
        salvar("icone", 512, web / "icons/Icon-512.png")
        salvar("maskable", 192, web / "icons/Icon-maskable-192.png")
        salvar("maskable", 512, web / "icons/Icon-maskable-512.png")

        # Windows .ico (16 a 256 px; os menores usam traço mais grosso).
        tamanhos = [16, 24, 32, 48, 64, 128, 256]
        imgs = [rasterizar(pg, VARIANTES["icone_pequeno" if t <= 32 else "icone"], t) for t in tamanhos]
        imgs[-1].save(APP / "windows/runner/resources/app_icon.ico", format="ICO",
                      sizes=[(t, t) for t in tamanhos], append_images=imgs[:-1])
        nav.close()

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n', encoding="utf-8")
    print("Ícones gerados.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
