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

  # The ctype dimension is soft, medium, or neither. The remaining tweaks
  # (black, float, outline, macos) change styling or assets without changing
  # the directory name, so they do not multiply the list below.
  ctypeChoices = [ [ ] [ "soft" ] [ "medium" ] ];

  # Every directory name install.sh can produce, in vocabulary order:
  # themes x colors x sizes x ctypes.
  allThemeDirNames = themeName:
    lib.concatMap
      (theme: lib.concatMap
        (color: lib.concatMap
          (size: map
            (enabledTweaks: themeDirName { inherit themeName theme color size enabledTweaks; })
            ctypeChoices)
          sizes)
        colors)
      themes;
}
