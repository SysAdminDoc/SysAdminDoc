"""Render the profile's static showcase assets.

Buttons are hand-built SVGs (assets/buttons/*.svg). Banners are HTML templates in
design/showcase/ rendered to PNG with headless Chromium (assets/showcase/*.png).

    py -3.13 scripts/render-showcase-assets.py            # everything
    py -3.13 scripts/render-showcase-assets.py buttons    # buttons only
    py -3.13 scripts/render-showcase-assets.py banners    # banners only

Banners need Playwright's Chromium (`py -3.13 -m playwright install chromium`).
The README references these files by relative path, so re-run this and commit the
output whenever a template or a button label changes.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import ImageFont

ROOT = Path(__file__).resolve().parent.parent
BUTTONS = ROOT / "assets" / "buttons"
BANNERS = ROOT / "assets" / "showcase"
TEMPLATES = ROOT / "design" / "showcase"

# 24x24 stroke icons, drawn for these buttons. No third-party marks.
ICONS = {
    "download": "M12 4v11M7 10.5l5 5 5-5M5 20h14",
    "phone": "M8 3h8a1.5 1.5 0 0 1 1.5 1.5v15A1.5 1.5 0 0 1 16 21H8a1.5 1.5 0 0 1-1.5-1.5v-15A1.5 1.5 0 0 1 8 3zM11 18h2",
    "refresh": "M19.5 12a7.5 7.5 0 0 1-13 5.1M4.5 12a7.5 7.5 0 0 1 13-5.1M17.5 3.5v3.6h-3.6M6.5 20.5v-3.6h3.6",
    "puzzle": "M9 4.5a2 2 0 0 1 4 0V6h4v4h1.5a2 2 0 0 1 0 4H17v5H5v-5h1.5a2 2 0 0 0 0-4H5V6h4z",
    "bolt": "M13 3L5.5 13.5H12L11 21l7.5-10.5H12z",
    "globe": "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM3 12h18M12 3c2.5 2.6 3.7 5.6 3.7 9S14.5 18.4 12 21M12 3C9.5 5.6 8.3 8.6 8.3 12s1.2 6.4 3.7 9",
    "code": "M8.5 7L3.5 12l5 5M15.5 7l5 5-5 5M13.5 4.5l-3 15",
    "book": "M12 6.5C10.3 5 7.8 4.5 4 4.5v14c3.8 0 6.3.5 8 2 1.7-1.5 4.2-2 8-2v-14c-3.8 0-6.3.5-8 2zM12 6.5v14",
    "search": "M10.5 4a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13zM15.5 15.5L20 20",
}

# name: (label, icon, fill). Colors hold at least 4.5:1 against white text and read on
# both GitHub themes.
BUTTON_SPECS = {
    "windows": ("Download for Windows", "download", "#1F6FEB"),
    "download": ("Download", "download", "#1F6FEB"),
    "apk": ("Get the APK", "phone", "#1A7F37"),
    "obtainium": ("Obtainium", "refresh", "#57606A"),
    "extension": ("Get the extension", "puzzle", "#6639BA"),
    "userscript": ("Install userscript", "bolt", "#0E7C86"),
    "web": ("Open the app", "globe", "#8250DF"),
    "source": ("View source", "code", "#32383F"),
    "guide": ("Read the guide", "book", "#32383F"),
    "search": ("Search every tool", "search", "#8250DF"),
}

FONT_FAMILY = "'Segoe UI',Inter,'Helvetica Neue',Arial,sans-serif"
FONT_SIZE = 13
HEIGHT = 32
PAD_X = 12
ICON = 16
GAP = 7


def text_width(label: str) -> int:
    for candidate in ("segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            font = ImageFont.truetype(candidate, FONT_SIZE)
            return round(font.getlength(label))
        except OSError:
            continue
    return round(len(label) * FONT_SIZE * 0.6)


def button_svg(label: str, icon: str, fill: str) -> str:
    tw = text_width(label)
    width = PAD_X + ICON + GAP + tw + PAD_X
    ix, iy = PAD_X, (HEIGHT - ICON) / 2
    tx = PAD_X + ICON + GAP
    scale = ICON / 24
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{HEIGHT}" '
        f'viewBox="0 0 {width} {HEIGHT}" role="img" aria-label="{label}">'
        f"<title>{label}</title>"
        f'<rect width="{width}" height="{HEIGHT}" rx="7" fill="{fill}"/>'
        f'<rect x="0.5" y="0.5" width="{width - 1}" height="{HEIGHT - 1}" rx="6.5" fill="none" stroke="#ffffff" stroke-opacity=".14"/>'
        f'<g transform="translate({ix} {iy}) scale({scale})" fill="none" stroke="#ffffff" '
        f'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="{ICONS[icon]}"/></g>'
        f'<text x="{tx}" y="{HEIGHT / 2 + 4.6:.1f}" fill="#ffffff" font-family="{FONT_FAMILY}" '
        f'font-size="{FONT_SIZE}" font-weight="700" textLength="{tw}" lengthAdjust="spacingAndGlyphs">{label}</text>'
        "</svg>\n"
    )


def render_buttons() -> None:
    BUTTONS.mkdir(parents=True, exist_ok=True)
    for name, (label, icon, fill) in BUTTON_SPECS.items():
        (BUTTONS / f"{name}.svg").write_bytes(button_svg(label, icon, fill).encode("utf-8"))
        print(f"assets/buttons/{name}.svg")


# template file -> (output file, width, height, color scheme)
BANNER_SPECS = [
    ("profile-hero.html", "profile-hero-dark.png", 1600, 560, "dark"),
    ("profile-hero.html", "profile-hero-light.png", 1600, 560, "light"),
    ("opentasker.html", "opentasker.png", 1280, 640, "dark"),
    ("nvme-patcher.html", "nvme-patcher.png", 1280, 640, "dark"),
]


def render_banners() -> None:
    from playwright.sync_api import sync_playwright

    BANNERS.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for template, output, width, height, scheme in BANNER_SPECS:
            page = browser.new_page(viewport={"width": width, "height": height}, color_scheme=scheme)
            page.goto((TEMPLATES / template).as_uri())
            page.wait_for_load_state("networkidle")
            page.evaluate("document.fonts.ready")
            page.screenshot(path=str(BANNERS / output), clip={"x": 0, "y": 0, "width": width, "height": height})
            page.close()
            print(f"assets/showcase/{output}")
        browser.close()


if __name__ == "__main__":
    targets = set(sys.argv[1:]) or {"buttons", "banners"}
    if "buttons" in targets:
        render_buttons()
    if "banners" in targets:
        render_banners()
