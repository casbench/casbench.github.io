#!/usr/bin/env python3
"""Generate the brand files of the project site: python3 -I assets/brand/gen_brand.py OUTDIR

    casbench-banner.svg  1280 x 320, the hero of the home page and of the README
    casbench-mark.svg    the mark alone (a results matrix), follows light and dark

Plain SVG, no external font: the text falls back to the viewer's monospace. The
mark is a results matrix, three systems by three problems, with the three
verdicts the site uses: filled (verified), hollow (returned, not verified or
wrong) and absent (no such operation). The right side is a dot plot like the
one of every bench page: time per case and system, on a log axis.
"""
import pathlib
import sys

INK, GRID, PAPER, STEEL = "#1E2329", "#8A949E", "#F4F1EA", "#8A949E"
ACCENT = "#F2B705"              # the shared accent of the project sites
OK, WRONG = "#2E9E5B", "#D64541"
SYSTEMS = ["#4EA8DE", "#F2B705", "#9B8CF2", "#F28C6B"]   # four systems, one colour each (decoration, no verdict)
MONO = '"IBM Plex Mono", "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace'


def mark(x, y, s, stroke_only=False):
    """A 3 x 3 results matrix of side s at (x, y): rows are problems, columns systems."""
    cells = [["ok", "ok", "hollow"], ["ok", "none", "ok"], ["hollow", "ok", "ok"]]
    c = s / 3.0
    out = [f'<g transform="translate({x} {y})">']
    out.append(f'<rect x="0" y="0" width="{s}" height="{s}" rx="{s * 0.06:.1f}" fill="none" stroke="{STEEL}" stroke-opacity="0.5" stroke-width="{s * 0.02:.1f}"/>')
    for i, row in enumerate(cells):
        for j, v in enumerate(row):
            cx, cy, r = (j + 0.5) * c, (i + 0.5) * c, c * 0.28
            if v == "ok":
                out.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="{OK}"/>')
            elif v == "hollow":
                out.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="none" stroke="{ACCENT}" stroke-width="{c * 0.09:.1f}"/>')
    out.append("</g>")
    return "\n".join(out)


def dotplot(x, y, w, h):
    """Five problems, four systems, log axis: the signature figure of the bench pages."""
    rows = ["integrate", "factor", "gbasis", "limit", "expand"]
    ticks = ["10 µs", "1 ms", "100 ms", "10 s"]
    # positions in [0, 1] along the axis; None = unsolved, drawn hollow at its time
    data = [[0.30, 0.55, 0.62, None], [0.22, 0.48, 0.41, 0.58], [0.36, None, 0.70, 0.85],
            [0.28, 0.52, None, None], [0.18, 0.44, 0.35, 0.50]]
    hollow = {(0, 3): 0.80, (2, 1): 0.92, (3, 2): 0.75}
    ml, rh = 86, h / len(rows)
    out = []
    for k, t in enumerate(ticks):
        tx = x + ml + (w - ml) * k / (len(ticks) - 1)
        out.append(f'<line x1="{tx:.0f}" y1="{y}" x2="{tx:.0f}" y2="{y + h}" stroke="{STEEL}" stroke-opacity="0.25"/>')
        out.append(f'<text x="{tx:.0f}" y="{y + h + 18}" class="m s" text-anchor="middle">{t}</text>')
    for i, name in enumerate(rows):
        cy = y + rh * (i + 0.5)
        out.append(f'<text x="{x + ml - 10}" y="{cy + 4:.0f}" class="m s" text-anchor="end">{name}</text>')
        for j, v in enumerate(data[i]):
            if v is None:
                hv = hollow.get((i, j))
                if hv is not None:
                    cx = x + ml + (w - ml) * hv
                    out.append(f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="6" fill="none" stroke="{SYSTEMS[j]}" stroke-width="2"/>')
                continue
            cx = x + ml + (w - ml) * v
            out.append(f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="6.5" fill="{SYSTEMS[j]}"/>')
    return "\n".join(out)


def banner():
    W, H = 1280, 320
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-labelledby="t">
  <title id="t">Computer algebra system benchmarks: reproducible, verified, dated</title>
  <style>
    .m {{ font-family: {MONO}; }}
    .s {{ font-size: 13px; fill: {STEEL}; }}
  </style>
  <defs><pattern id="grid" width="8" height="8" patternUnits="userSpaceOnUse"><path d="M8 0H0V8" fill="none" stroke="{GRID}" stroke-opacity="0.13" stroke-width="0.5"/></pattern></defs>
  <rect width="{W}" height="{H}" fill="{INK}"/>
  <rect width="{W}" height="{H}" fill="url(#grid)"/>
{mark(56, 62, 196)}
  <text x="300" y="118" class="m" font-size="50" font-weight="700" fill="{PAPER}">CAS <tspan font-weight="400" fill="{ACCENT}">benchmarks</tspan></text>
  <text x="302" y="152" class="m" font-size="17" fill="{STEEL}">computer algebra systems compared</text>
  <text x="302" y="178" class="m" font-size="17" fill="{STEEL}">reproducible · verified · dated</text>
  <text x="302" y="224" class="m" font-size="13" fill="{STEEL}">every answer checked by a system-neutral test</text>
  <text x="302" y="244" class="m" font-size="13" fill="{STEEL}">every input shown next to its output</text>
  <text x="302" y="264" class="m" font-size="13" fill="{STEEL}">every run dated, its environment pinned</text>
{dotplot(780, 50, 450, 210)}
</svg>
'''


def mark_file():
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96" width="96" height="96" role="img" aria-label="Computer algebra system benchmarks">
  <style>:root {{ color: {INK}; }} @media (prefers-color-scheme: dark) {{ :root {{ color: {PAPER}; }} }}</style>
  <rect x="4" y="4" width="88" height="88" rx="8" fill="none" stroke="currentColor" stroke-opacity="0.6" stroke-width="3"/>
  <circle cx="19" cy="19" r="8" fill="{OK}"/><circle cx="48" cy="19" r="8" fill="{OK}"/><circle cx="77" cy="19" r="8" fill="none" stroke="{ACCENT}" stroke-width="3"/>
  <circle cx="19" cy="48" r="8" fill="{OK}"/><circle cx="77" cy="48" r="8" fill="{OK}"/>
  <circle cx="19" cy="77" r="8" fill="none" stroke="{ACCENT}" stroke-width="3"/><circle cx="48" cy="77" r="8" fill="{OK}"/><circle cx="77" cy="77" r="8" fill="{OK}"/>
</svg>
'''


if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "assets/brand")
    out.mkdir(parents=True, exist_ok=True)
    (out / "casbench-banner.svg").write_text(banner(), encoding="utf-8")
    (out / "casbench-mark.svg").write_text(mark_file(), encoding="utf-8")
    print("wrote", out / "casbench-banner.svg", out / "casbench-mark.svg")
