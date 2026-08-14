#!/usr/bin/env bash
# Regenerates the Aurorae artwork from the xfwm4 masters.
#
# Not run at build time. Like themes/src/assets/xfwm4/render-assets.sh, this
# is a maintainer tool whose outputs are committed. Requires inkscape.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XFWM4="${HERE}/../xfwm4"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

extract() {
    local src="$1" id="$2" out="$3"
    # Several ids (the "-active" title segments) are <use> elements pointing
    # at a shared #headerbar-bg group. Inkscape 1.4.4 segfaults when
    # --export-id-only is asked to export a <use> directly, so the clone is
    # unlinked into a standalone copy first via --actions; this is Inkscape
    # itself resolving the reference, the same way it already resolves the
    # ancestor matrix() transforms, not hand-authored geometry. Unlinking a
    # plain (non-clone) element such as a corner group is a no-op.
    inkscape --actions="select-by-id:${id};object-unlink-clones;\
export-filename:${out};export-plain-svg;export-type:svg;\
export-id:${id};export-id-only;export-do" \
        "${src}" >/dev/null 2>&1
    if [[ ! -s "${out}" ]]; then
        echo "make-aurorae: inkscape produced nothing for ${id}" >&2
        exit 1
    fi
}

# The nine-slice frame. title-3 is the stretchable middle titlebar segment;
# the other title-N segments exist for xfwm4's own layout and are not needed,
# because Aurorae stretches decoration-top itself.
FRAME=(
    "decoration-topleft=top-left"
    "decoration-top=title-3"
    "decoration-topright=top-right"
    "decoration-left=left"
    "decoration-right=right"
    "decoration-bottomleft=bottom-left"
    "decoration-bottom=bottom"
    "decoration-bottomright=bottom-right"
)

build_frame() {
    local master="$1" out="$2"
    local args=()
    local pair target source state

    for state in active inactive; do
        for pair in "${FRAME[@]}"; do
            target="${pair%%=*}"
            source="${pair#*=}"
            [[ "${state}" == inactive ]] && target="${target/decoration-/decoration-inactive-}"
            extract "${master}" "${source}-${state}" "${WORK}/${target}.svg"
            args+=("${target}=${WORK}/${target}.svg")
        done
    done

    "${HERE}/compose.py" "${out}" "${args[@]}"
}

# The outline variant: same slices, plus a 2px accent bar on the outer edge of
# each edge and corner slice. Both the bar and the frame stay scheme-aware, so
# one outlined decoration still serves every colour scheme.
add_outline() {
    local file="$1"
    python3 - "$file" <<'PY'
import re
import sys

# Outer edges per slice, as (x, y, width, height) with 0 meaning "stretch to
# the slice bound". Only edge and corner slices get a bar; centre does not.
BARS = {
    "topleft":     [("0", "0", "100%", "2"), ("0", "0", "2", "100%")],
    "top":         [("0", "0", "100%", "2")],
    "topright":    [("0", "0", "100%", "2"), ("-2", "0", "2", "100%")],
    "left":        [("0", "0", "2", "100%")],
    "right":       [("-2", "0", "2", "100%")],
    "bottomleft":  [("0", "-2", "100%", "2"), ("0", "0", "2", "100%")],
    "bottom":      [("0", "-2", "100%", "2")],
    "bottomright": [("0", "-2", "100%", "2"), ("-2", "0", "2", "100%")],
}

path = sys.argv[1]
doc = open(path, encoding="utf-8").read()

def bars_for(slice_name):
    out = []
    for x, y, w, h in BARS[slice_name]:
        out.append(
            '    <rect class="ColorScheme-Highlight" fill="currentColor" '
            'x="%s" y="%s" width="%s" height="%s"/>\n' % (x, y, w, h)
        )
    return "".join(out)

def inject(match):
    gid = match.group(1)
    slice_name = gid.replace("decoration-inactive-", "").replace("decoration-", "")
    if slice_name not in BARS:
        return match.group(0)
    return match.group(0) + "\n" + bars_for(slice_name)

doc = re.sub(r'<g id="(decoration[a-z-]*)"[^>]*>', inject, doc)
open(path, "w", encoding="utf-8").write(doc)
PY
}

build_frame "${XFWM4}/assets.svg" "${HERE}/decoration.svg"
echo "wrote ${HERE}/decoration.svg"

build_frame "${XFWM4}/assets.svg" "${HERE}/decoration-outline.svg"
add_outline "${HERE}/decoration-outline.svg"
echo "wrote ${HERE}/decoration-outline.svg"
