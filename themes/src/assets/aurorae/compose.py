#!/usr/bin/env python3
"""Compose Aurorae SVGs from elements extracted out of the xfwm4 masters.

Each input element arrives as a standalone plain SVG produced by
`inkscape --export-id-only`, sized to that element. This script lays them out
left to right in one document, wraps each in a group carrying the Aurorae id,
and rewrites the flat xfwm4 fills into ColorScheme-* classes so that a single
file follows whatever colour scheme is active.

Usage:
    compose.py OUT.svg NAME=EXTRACTED.svg [NAME=EXTRACTED.svg ...]
"""

import re
import sys

# The xfwm4 masters use six flat fills and no gradients. Backgrounds become
# ColorScheme-Background, everything else becomes ColorScheme-Text; each
# element's existing opacity is preserved, which is what carries the visual
# hierarchy between active, inactive and hover states.
BACKGROUND_FILLS = {"#1d2021", "#141617"}
TEXT_FILLS = {"#ffffff", "#666666", "#525252", "#363636"}

# Traffic-light colours in the macos master are NOT scheme colours: KDE has no
# key for "close button red". They are left as literal hex for kde/install.sh
# to substitute per variant.
KEEP_LITERAL = {"#ea6962", "#a9b665", "#e78a4e", "#6c782e", "#c14a4a", "#c35e0a"}

STYLESHEET = """  <defs>
    <style id="current-color-scheme" type="text/css">
      .ColorScheme-Background { color: #1d2021; }
      .ColorScheme-Text       { color: #fbf1c7; }
      .ColorScheme-Highlight  { color: #7daea3; }
    </style>
  </defs>
"""


def read_element(path):
    """Return (width, height, inner_xml) for an inkscape-extracted element."""
    doc = open(path, encoding="utf-8").read()
    width = float(re.search(r'\swidth="([0-9.]+)"', doc).group(1))
    height = float(re.search(r'\sheight="([0-9.]+)"', doc).group(1))
    # Everything after the metadata block is the drawable content.
    end = doc.find("</metadata>")
    inner = doc[end + len("</metadata>"):] if end != -1 else doc
    inner = inner[:inner.rfind("</svg>")]
    return width, height, inner


def recolour(xml):
    """Rewrite flat fills into currentColor plus a ColorScheme class."""

    def sub_style(match):
        style = match.group(1)
        fill = re.search(r"fill:(#[0-9a-fA-F]{6})", style)
        if not fill:
            return match.group(0)
        value = fill.group(1).lower()
        if value in KEEP_LITERAL:
            return match.group(0)
        if value in BACKGROUND_FILLS:
            klass = "ColorScheme-Background"
        elif value in TEXT_FILLS:
            klass = "ColorScheme-Text"
        else:
            raise SystemExit("compose.py: unmapped fill %s" % value)
        style = style.replace("fill:" + fill.group(1), "fill:currentColor")
        return 'class="%s" style="%s"' % (klass, style)

    return re.sub(r'style="([^"]*)"', sub_style, xml)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    out_path = sys.argv[1]
    pairs = [arg.split("=", 1) for arg in sys.argv[2:]]

    parts = []
    x = 0.0
    max_h = 0.0
    for name, path in pairs:
        width, height, inner = read_element(path)
        parts.append(
            '  <g id="%s" transform="translate(%g,0)">%s  </g>\n'
            % (name, x, recolour(inner))
        )
        x += width
        max_h = max(max_h, height)

    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        handle.write(
            '<svg xmlns="http://www.w3.org/2000/svg" width="%g" height="%g" '
            'viewBox="0 0 %g %g">\n' % (x, max_h, x, max_h)
        )
        handle.write(STYLESHEET)
        handle.writelines(parts)
        handle.write("</svg>\n")


if __name__ == "__main__":
    main()
