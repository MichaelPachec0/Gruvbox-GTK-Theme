#!/usr/bin/env bash
# Installs KDE colour schemes generated from the theme's SCSS palette.
#
# Kept separate from themes/install.sh so that script stays byte-identical to
# upstream and rebases cleanly.
set -Eeuo pipefail

# install.sh reads bare globals; a Nix builder exports some of these. Clear
# them so an inherited value can never become the theme name or destination.
unset name dest theme color contrast

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${REPO_DIR}/themes/src"
AWK_SCRIPT="${REPO_DIR}/kde/css2ini.awk"

DEST_DIR="${HOME}/.local/share/color-schemes"
AURORAE_DEST="${HOME}/.local/share/aurorae/themes"
THEME_NAME="Gruvbox"
UNINSTALL="false"

ACCENTS=(default green grey orange pink purple red teal yellow)
COLORS=(light dark)
FRAMES=(normal outline)
BUTTON_STYLES=(legacy macos)
# The contrast states, named exactly as they appear in the scheme name.
# Blackness is not a separate axis on the command line, because it combines
# with the palette rather than replacing it: medium+black is a real, distinct
# colour set for the light variant. `black` is a short alias for `hard-black`,
# hard being the default palette.
CONTRASTS=(hard medium soft hard-black medium-black soft-black black)

accents=()
colors=()
contrasts=()
frames=()
button_styles=()
DO_COLORS="true"
DO_AURORAE="true"

usage() {
    cat <<'EOF'
Usage: kde/install.sh [OPTIONS...]

  -d, --dest DIR      Destination directory
                      (default: ~/.local/share/color-schemes)
  -n, --name NAME     Scheme name prefix (default: Gruvbox)
  -t, --theme VARIANT Accent variant(s):
                      default green grey orange pink purple red teal yellow
                      (default: default)
  -c, --color VARIANT light|dark (default: both)
      --contrast V    hard|medium|soft|hard-black|medium-black|soft-black
                      (default: hard). `black` is accepted as a short alias
                      for hard-black.
                      hard is this repo's default palette. The -black states
                      combine blackness with that palette; for the dark
                      variant blackness replaces the background outright, so
                      all three collapse to one scheme named -Black.
  -r, --remove        Uninstall the schemes this would install
      --aurorae       Install window decorations only
      --colors        Install colour schemes only (default: both)
      --frame V       normal|outline (default: normal)
      --buttons V     legacy|macos (default: legacy)
  -h, --help          Show this help
EOF
}

contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "${item}" == "${needle}" ]] && return 0
    done
    return 1
}

# The palette a contrast state is built on. `black` is short for `hard-black`.
contrast_base() {
    case "$1" in
        black|hard-black) printf 'hard' ;;
        medium-black)     printf 'medium' ;;
        soft-black)       printf 'soft' ;;
        *)                printf '%s' "$1" ;;
    esac
}

# Whether a contrast state turns blackness on.
contrast_is_black() {
    case "$1" in
        black|hard-black|medium-black|soft-black) return 0 ;;
        *) return 1 ;;
    esac
}

cap() {
    printf '%s%s' "$(tr '[:lower:]' '[:upper:]' <<<"${1:0:1}")" "${1:1}"
}

# Gruvbox-Green-Dark-Soft, Gruvbox-Light-Medium-Black, Gruvbox-Dark-Black.
# The contrast word is always present, except that dark+black drops it:
# blackness replaces the background outright for the dark variant, so all
# three palettes collapse to one colour set and three names would imply a
# choice that does not exist. For light they stay distinct.
scheme_name() {
    local accent="$1" color="$2" contrast="$3"
    local base
    base="$(contrast_base "${contrast}")"
    local out="${THEME_NAME}"
    if [[ "${accent}" != "default" ]]; then
        out+="-$(cap "${accent}")"
    fi
    out+="-$(cap "${color}")"
    if contrast_is_black "${contrast}"; then
        if [[ "${color}" == "dark" ]]; then
            out+="-Black"
        else
            out+="-$(cap "${base}")-Black"
        fi
    else
        out+="-$(cap "${base}")"
    fi
    printf '%s' "${out}"
}

# Writes _tweaks-temp.scss for one combination. The file is tracked, so
# cleanup must run before the script exits.
# The palette and blackness are set independently, because they combine.
write_tweaks() {
    local accent="$1" contrast="$2"
    local base
    base="$(contrast_base "${contrast}")"
    cp -f "${SRC_DIR}/sass/_tweaks.scss" "${SRC_DIR}/sass/_tweaks-temp.scss"
    case "${base}" in
        soft|medium)
            sed -i "/@import/s/color-palette-default/color-palette-${base}/" \
                "${SRC_DIR}/sass/_tweaks-temp.scss"
            sed -i "/\$colorscheme:/s/default/${base}/" \
                "${SRC_DIR}/sass/_tweaks-temp.scss"
            ;;
    esac
    if contrast_is_black "${contrast}"; then
        sed -i "/\$blackness:/s/false/true/" "${SRC_DIR}/sass/_tweaks-temp.scss"
    fi
    if [[ "${accent}" != "default" ]]; then
        sed -i "/\$theme:/s/default/${accent}/" "${SRC_DIR}/sass/_tweaks-temp.scss"
    fi
}

# Everything this script writes outside the destination directory is removed
# here, on EXIT, so that a failure partway through a variant leaves the
# working tree exactly as it was found. build_one's own rm at the end of a
# successful pass is not enough: if sassc or the awk redirection fails, that
# line is never reached and the generated entry point is left behind in a
# tracked directory.
cleanup() {
    cp -f "${SRC_DIR}/sass/_tweaks.scss" "${SRC_DIR}/sass/_tweaks-temp.scss"
    rm -f "${SRC_DIR}"/main/kde/.generated-*.scss \
          "${SRC_DIR}"/main/kde/.generated-*.scss.css
}
trap cleanup EXIT

build_one() {
    local accent="$1" color="$2" contrast="$3"
    local id
    id="$(scheme_name "${accent}" "${color}" "${contrast}")"
    local display="${id//-/ }"

    local entry_src entry_tmp
    case "${color}" in
        dark)  entry_src="${SRC_DIR}/main/kde/color-scheme-Dark.scss" ;;
        light) entry_src="${SRC_DIR}/main/kde/color-scheme-Light.scss" ;;
    esac
    entry_tmp="${SRC_DIR}/main/kde/.generated-${color}.scss"

    write_tweaks "${accent}" "${contrast}"
    sed -e "s/^\$kde-scheme-id:.*/\$kde-scheme-id: '${id}';/" \
        -e "s/^\$kde-scheme-name:.*/\$kde-scheme-name: '${display}';/" \
        "${entry_src}" > "${entry_tmp}"

    sassc -t expanded "${entry_tmp}" "${entry_tmp}.css"
    awk -f "${AWK_SCRIPT}" < "${entry_tmp}.css" > "${DEST_DIR}/${id}.colors"
    rm -f "${entry_tmp}" "${entry_tmp}.css"
    echo "Installed ${DEST_DIR}/${id}.colors"
}

remove_one() {
    local id
    id="$(scheme_name "$1" "$2" "$3")"
    if [[ -f "${DEST_DIR}/${id}.colors" ]]; then
        rm -f "${DEST_DIR}/${id}.colors"
        echo "Removed ${DEST_DIR}/${id}.colors"
    fi
}

# Gruvbox-Dark-Outline-Macos. Contrast is deliberately absent: the decoration
# follows the active colour scheme, so one theme covers all contrast levels.
aurorae_name() {
    local color="$1" frame="$2" buttons="$3"
    local out="${THEME_NAME}"
    out+="-$(tr '[:lower:]' '[:upper:]' <<<"${color:0:1}")${color:1}"
    [[ "${frame}" == "outline" ]] && out+="-Outline"
    [[ "${buttons}" == "macos" ]] && out+="-Macos"
    printf '%s' "${out}"
}

# Builds one Aurorae theme: decoration frame, seven buttons, rc and metadata.
build_aurorae() {
    local color="$1" frame="$2" buttons="$3"
    local id
    id="$(aurorae_name "$1" "$2" "$3")"

    local out="${AURORAE_DEST}/${id}"
    mkdir -p "${out}"

    local entry="${SRC_DIR}/main/kde/aurorae-Dark.scss"
    [[ "${color}" == "light" ]] && entry="${SRC_DIR}/main/kde/aurorae-Light.scss"

    write_tweaks default hard
    local css="${out}/.aurorae.css"
    sassc -t expanded "${entry}" "${css}"

    local active inactive close max min
    active=$(grep -m1 'ActiveTextColor:' "${css}" | sed 's/.*: *//;s/;//;s/, */,/g')
    inactive=$(grep -m1 'InactiveTextColor:' "${css}" | sed 's/.*: *//;s/;//;s/, */,/g')
    close=$(grep -m1 'ButtonClose:' "${css}" | sed 's/.*: *//;s/;//')
    max=$(grep -m1 'ButtonMax:' "${css}" | sed 's/.*: *//;s/;//')
    min=$(grep -m1 'ButtonMin:' "${css}" | sed 's/.*: *//;s/;//')
    rm -f "${css}"

    local src_frame="${SRC_DIR}/assets/aurorae/decoration.svg"
    [[ "${frame}" == "outline" ]] && src_frame="${SRC_DIR}/assets/aurorae/decoration-outline.svg"
    cp -f "${src_frame}" "${out}/decoration.svg"

    # Substitute the traffic-light hexes with this variant's.
    #
    # This is meaningful only for the macos button set. The legacy buttons are
    # monochrome and were made scheme-aware at extraction time, so they carry
    # no literal fill and these expressions are a no-op on them. Running the
    # same loop over both styles keeps one code path rather than branching.
    local b
    for b in close maximize restore minimize alldesktops keepabove keepbelow; do
        sed -e "s/#ea6962/${close}/g" \
            -e "s/#a9b665/${max}/g" \
            -e "s/#e78a4e/${min}/g" \
            "${SRC_DIR}/assets/aurorae/buttons/${buttons}/${b}.svg" > "${out}/${b}.svg"
    done

    local border=0
    [[ "${frame}" == "outline" ]] && border=2

    # The vertical metrics MUST sum to the height of the extracted titlebar
    # art, which is 34px: TitleEdgeTop 5 + TitleHeight 24 + TitleEdgeBottom 5.
    # These were originally copied from another theme's rc and summed to 36,
    # and the 2px surplus showed up as a strip of wallpaper between the
    # titlebar and the client area. Every static check passed with it: only
    # looking at a rendered window caught it.
    #
    # ButtonWidth is 36 because that is the width of the extracted button
    # cells; a smaller value scales the glyphs down.
    cat > "${out}/${id}rc" <<EOF
[General]
TitleAlignment=Center
TitleVerticalAlignment=Center
ActiveTextColor=${active}
InactiveTextColor=${inactive}
UseTextShadow=false
Shadow=true
Animation=1

[Layout]
BorderLeft=${border}
BorderRight=${border}
BorderBottom=${border}
TitleEdgeTop=5
TitleEdgeBottom=5
TitleEdgeLeft=16
TitleEdgeRight=16
TitleBorderLeft=12
TitleBorderRight=12
TitleHeight=24
ButtonWidth=36
EOF

    cat > "${out}/metadata.json" <<EOF
{
    "KPackageStructure": "aurorae",
    "KPlugin": {
        "Category": "Plasma 6 Window Decorations",
        "Description": "${id} window decorations",
        "EnabledByDefault": true,
        "Id": "${id}",
        "License": "GPL v3",
        "Name": "${id}",
        "ServiceTypes": [
            "aurorae"
        ],
        "Version": "1.0",
        "X-KDE-PluginInfo-blur": false
    }
}
EOF

    cat > "${out}/metadata.desktop" <<EOF
[Desktop Entry]
Name=${id}
X-KDE-PluginInfo-Name=${id}
X-KDE-PluginInfo-Version=1.0
X-KDE-PluginInfo-License=GPL_V3
X-KDE-PluginInfo-EnabledByDefault=true
X-KDE-PluginInfo-blur=false
EOF

    echo "Installed ${out}"
}

remove_aurorae() {
    local id
    id="$(aurorae_name "$1" "$2" "$3")"
    if [[ -d "${AURORAE_DEST}/${id}" ]]; then
        rm -rf "${AURORAE_DEST:?}/${id}"
        echo "Removed ${AURORAE_DEST}/${id}"
    fi
}

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -d|--dest)
            DEST_DIR="${2}"
            AURORAE_DEST="${2}"
            shift 2
            ;;
        -n|--name)     THEME_NAME="${2}"; shift 2 ;;
        -r|--remove)   UNINSTALL="true"; shift ;;
        --aurorae)     DO_COLORS="false"; DO_AURORAE="true";  shift ;;
        --colors)      DO_COLORS="true";  DO_AURORAE="false"; shift ;;
        -h|--help)     usage; exit 0 ;;
        -t|--theme)
            shift
            while [[ $# -gt 0 ]] && contains "${1}" "${ACCENTS[@]}"; do
                accents+=("${1}"); shift
            done
            ;;
        -c|--color)
            shift
            while [[ $# -gt 0 ]] && contains "${1}" "${COLORS[@]}"; do
                colors+=("${1}"); shift
            done
            ;;
        --contrast)
            shift
            while [[ $# -gt 0 ]] && contains "${1}" "${CONTRASTS[@]}"; do
                contrasts+=("${1}"); shift
            done
            ;;
        --frame)
            shift
            while [[ $# -gt 0 ]] && contains "${1}" "${FRAMES[@]}"; do
                frames+=("${1}"); shift
            done
            ;;
        --buttons)
            shift
            while [[ $# -gt 0 ]] && contains "${1}" "${BUTTON_STYLES[@]}"; do
                button_styles+=("${1}"); shift
            done
            ;;
        *)
            echo "Unrecognised option: ${1}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

[[ ${#accents[@]}   -eq 0 ]] && accents=(default)
[[ ${#colors[@]}    -eq 0 ]] && colors=("${COLORS[@]}")
[[ ${#contrasts[@]} -eq 0 ]] && contrasts=(hard)
if [[ ${#frames[@]}        -eq 0 ]]; then frames=(normal); fi
if [[ ${#button_styles[@]} -eq 0 ]]; then button_styles=(legacy); fi

if [[ "${DO_COLORS}" == "true" ]]; then
    if [[ "${UNINSTALL}" == "false" ]]; then
        mkdir -p "${DEST_DIR}"
    fi

    # Dark + black collapses the three contrast palettes onto one colour set,
    # so emitting all of them would write the same file three times under
    # three names. Track what has been written and skip repeats.
    declare -A written=()

    for accent in "${accents[@]}"; do
        for color in "${colors[@]}"; do
            for contrast in "${contrasts[@]}"; do
                id="$(scheme_name "${accent}" "${color}" "${contrast}")"
                [[ -n "${written[${id}]:-}" ]] && continue
                written[${id}]=1
                if [[ "${UNINSTALL}" == "true" ]]; then
                    remove_one "${accent}" "${color}" "${contrast}"
                else
                    build_one "${accent}" "${color}" "${contrast}"
                fi
            done
        done
    done
fi

if [[ "${DO_AURORAE}" == "true" ]]; then
    for color in "${colors[@]}"; do
        for frame in "${frames[@]}"; do
            for buttons in "${button_styles[@]}"; do
                if [[ "${UNINSTALL}" == "true" ]]; then
                    remove_aurorae "${color}" "${frame}" "${buttons}"
                else
                    build_aurorae "${color}" "${frame}" "${buttons}"
                fi
            done
        done
    done
fi
