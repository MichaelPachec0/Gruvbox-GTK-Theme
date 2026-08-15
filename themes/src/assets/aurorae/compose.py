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
#
# #11111b and #1e1e2e are Catppuccin Mocha tones left behind in
# assets-Macos.svg by whatever theme it was copied from. They are dark
# background tones on the traffic-light button circles, so they follow the
# scheme background rather than baking a foreign palette into the output.
BACKGROUND_FILLS = {"#1d2021", "#141617", "#11111b", "#1e1e2e"}
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


def classify_fill(value):
    """Return the ColorScheme class for a lowercase hex fill, or None to
    leave it as a literal (KEEP_LITERAL colours have no scheme equivalent)."""
    if value in KEEP_LITERAL:
        return None
    if value in BACKGROUND_FILLS:
        return "ColorScheme-Background"
    if value in TEXT_FILLS:
        return "ColorScheme-Text"
    raise SystemExit("compose.py: unmapped fill %s" % value)


def recolour(xml):
    """Rewrite flat fills into currentColor plus a ColorScheme class.

    Elements in the masters carry fill either in a style="...fill:#hex..."
    property or in a bare fill="#hex" presentation attribute, and a handful
    of elements carry both at once (the style always wins visually, per the
    SVG cascade, so the bare attribute is otherwise dead markup). Both forms
    are rewritten together, per element, into a single class attribute so
    the composed document never ends up with two class="..." attributes on
    one element, which would be invalid XML.
    """

    def sub_tag(match):
        tag = match.group(0)
        klass = None

        style_match = re.search(r'style="([^"]*)"', tag)
        if style_match:
            style = style_match.group(1)
            fill = re.search(r"fill:(#[0-9a-fA-F]{6})", style)
            if fill:
                value = fill.group(1).lower()
                found = classify_fill(value)
                if found:
                    klass = found
                    style = style.replace("fill:" + fill.group(1), "fill:currentColor")
                    tag = tag.replace(style_match.group(0), 'style="%s"' % style, 1)

        attr_match = re.search(r'\sfill="(#[0-9a-fA-F]{6})"', tag)
        if attr_match:
            value = attr_match.group(1).lower()
            found = classify_fill(value)
            if found:
                klass = klass or found
                tag = tag.replace(attr_match.group(0), ' fill="currentColor"', 1)

        if klass:
            name_end = re.match(r"<[a-zA-Z][\w:-]*", tag).end()
            tag = tag[:name_end] + ' class="%s"' % klass + tag[name_end:]

        return tag

    return re.sub(r"<[a-zA-Z][^<>]*>", sub_tag, xml)


def namespace_ids(xml, prefix):
    """Make a fragment's internal ids unique, references included.

    Every extracted fragment is a standalone document that Inkscape gave its
    own ids (a "layer1" wrapper, "rect1", "path1725", and so on), and those
    ids collide once several fragments are concatenated into one composed
    document, which is invalid SVG even though it stays well-formed XML.
    Prefixing each fragment's ids with its own Aurora name keeps them
    globally unique while keeping any internal url(#...)/href="#..."
    references pointed at the right (renamed) target.
    """
    ids = set(re.findall(r'\sid="([^"]+)"', xml))
    for old in sorted(ids, key=len, reverse=True):
        new = "%s__%s" % (prefix, old)
        xml = xml.replace('id="%s"' % old, 'id="%s"' % new)
        xml = xml.replace("url(#%s)" % old, "url(#%s)" % new)
        xml = xml.replace('href="#%s"' % old, 'href="#%s"' % new)
    return xml


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
        inner = namespace_ids(recolour(inner), name)
        parts.append(
            '  <g id="%s" transform="translate(%g,0)">%s  </g>\n'
            % (name, x, inner)
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
