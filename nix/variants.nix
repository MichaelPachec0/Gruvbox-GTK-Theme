# Single source of truth for the theme's variant vocabulary.
#
# themes/install.sh accepts these values and assembles the installed directory
# name from them. Both nix/package.nix, which validates its arguments and
# computes passthru.themeNames, and nix/list-variants.nix, which prints the
# vocabulary for humans, read this file. Keeping one copy is what stops the
# printed list and the accepted list from drifting apart.
lib:

rec {
  themes = [ "default" "green" "grey" "orange" "pink" "purple" "red" "teal" "yellow" ];
  colors = [ "light" "dark" ];
  sizes = [ "standard" "compact" ];
  tweaks = [ "soft" "medium" "black" "float" "outline" "macos" ];

  themeSuffix = {
    default = "";
    green = "-Green";
    grey = "-Grey";
    orange = "-Orange";
    pink = "-Pink";
    purple = "-Purple";
    red = "-Red";
    teal = "-Teal";
    yellow = "-Yellow";
  };
  colorSuffix = { light = "-Light"; dark = "-Dark"; };
  sizeSuffix = { standard = ""; compact = "-Compact"; };

  # install.sh lets a later --tweaks value overwrite ctype, so soft and medium
  # are mutually exclusive rather than additive.
  ctypeSuffixFor = enabledTweaks:
    if lib.elem "soft" enabledTweaks then "-Soft"
    else if lib.elem "medium" enabledTweaks then "-Medium"
    else "";

  # The installed directory name, matching THEME_DIR in themes/install.sh:
  # name + theme + color + size + ctype. The macos tweak selects different
  # window-button assets but does not appear in the directory name, and the
  # black, float and outline tweaks change styling only.
  themeDirName = { themeName, theme, color, size, enabledTweaks ? [ ] }:
    "${themeName}${themeSuffix.${theme}}${colorSuffix.${color}}${sizeSuffix.${size}}${ctypeSuffixFor enabledTweaks}";
}
