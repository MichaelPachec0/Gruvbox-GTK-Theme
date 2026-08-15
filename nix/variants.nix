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

  # The contrast states, matching CONTRASTS in kde/install.sh. Blackness and
  # the palette are two axes that combine, not one axis with four values:
  # medium-black is a distinct colour set from medium and from hard-black for
  # the light variant. The `black` alias is a CLI convenience only and is
  # deliberately absent here.
  contrasts = [ "hard" "medium" "soft" "hard-black" "medium-black" "soft-black" ];

  contrastBase = contrast: lib.removeSuffix "-black" contrast;
  contrastIsBlack = contrast: lib.hasSuffix "-black" contrast;

  # Mirrors scheme_name() in kde/install.sh. The contrast word is always
  # present, except that dark plus blackness drops it: blackness replaces the
  # dark background outright, so all three palettes collapse to one scheme.
  colorSchemeName = { themeName, theme, color, contrast }:
    let
      accent = themeSuffix.${theme};
      colorWord = colorSuffix.${color};
      baseWord = "-" + lib.toSentenceCase (contrastBase contrast);
      contrastWord =
        if contrastIsBlack contrast then
          (if color == "dark" then "-Black" else baseWord + "-Black")
        else baseWord;
    in
    "${themeName}${accent}${colorWord}${contrastWord}";

  # Every distinct scheme name, deduplicated: dark+black yields one name per
  # accent rather than three.
  allColorSchemeNames = themeName:
    lib.unique (lib.concatMap
      (theme: lib.concatMap
        (color: map
          (contrast: colorSchemeName { inherit themeName theme color contrast; })
          contrasts)
        colors)
      themes);
}
