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
THEME_NAME="Gruvbox"
UNINSTALL="false"

ACCENTS=(default green grey orange pink purple red teal yellow)
COLORS=(light dark)
CONTRASTS=(hard medium soft black)

accents=()
colors=()
contrasts=()

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
      --contrast V    hard|medium|soft|black (default: hard)
                      hard is this repo's default palette; black is the
                      near-black background and supersedes the other three
                      for the dark variant.
  -r, --remove        Uninstall the schemes this would install
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

# Gruvbox-Green-Dark-Soft. The contrast word is always present, except that
# dark+black drops it: blackness replaces the background outright, so the
# three contrast palettes collapse to one colour set and three names would
# imply a choice that does not exist.
scheme_name() {
    local accent="$1" color="$2" contrast="$3"
    local out="${THEME_NAME}"
    [[ "${accent}" != "default" ]] && out+="-$(tr '[:lower:]' '[:upper:]' <<<"${accent:0:1}")${accent:1}"
    out+="-$(tr '[:lower:]' '[:upper:]' <<<"${color:0:1}")${color:1}"
    if [[ "${color}" == "dark" && "${contrast}" == "black" ]]; then
        out+="-Black"
    elif [[ "${contrast}" == "black" ]]; then
        out+="-Hard-Black"
    else
        out+="-$(tr '[:lower:]' '[:upper:]' <<<"${contrast:0:1}")${contrast:1}"
    fi
    printf '%s' "${out}"
}

# Writes _tweaks-temp.scss for one combination. The file is tracked, so
# restore_tweaks must run before the script exits.
write_tweaks() {
    local accent="$1" contrast="$2"
    cp -f "${SRC_DIR}/sass/_tweaks.scss" "${SRC_DIR}/sass/_tweaks-temp.scss"
    case "${contrast}" in
        soft|medium)
            sed -i "/@import/s/color-palette-default/color-palette-${contrast}/" \
                "${SRC_DIR}/sass/_tweaks-temp.scss"
            sed -i "/\$colorscheme:/s/default/${contrast}/" \
                "${SRC_DIR}/sass/_tweaks-temp.scss"
            ;;
        black)
            sed -i "/\$blackness:/s/false/true/" "${SRC_DIR}/sass/_tweaks-temp.scss"
            ;;
    esac
    if [[ "${accent}" != "default" ]]; then
        sed -i "/\$theme:/s/default/${accent}/" "${SRC_DIR}/sass/_tweaks-temp.scss"
    fi
}

restore_tweaks() {
    cp -f "${SRC_DIR}/sass/_tweaks.scss" "${SRC_DIR}/sass/_tweaks-temp.scss"
}
trap restore_tweaks EXIT

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

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -d|--dest)     DEST_DIR="${2}"; shift 2 ;;
        -n|--name)     THEME_NAME="${2}"; shift 2 ;;
        -r|--remove)   UNINSTALL="true"; shift ;;
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

if [[ "${UNINSTALL}" == "false" ]]; then
    mkdir -p "${DEST_DIR}"
fi

# Dark + black collapses the three contrast palettes onto one colour set, so
# emitting all of them would write the same file three times under three
# names. Track what has been written and skip repeats.
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
