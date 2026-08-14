# `nix run .#list-variants` - print the theme's variant vocabulary.
#
# Every value printed here is read from nix/variants.nix, the same file
# nix/package.nix validates against, and the example directory names are built
# by calling its themeDirName rather than being typed out. A variant added to
# the vocabulary therefore shows up here without anyone remembering to update
# this file.
{ lib
, writeShellApplication
}:

let
  variants = import ./variants.nix lib;

  # Two columns, so the lists line up regardless of how long the labels get.
  # lib.fixedWidthString pads on the left, which right-aligns; these columns
  # want the padding on the right.
  padRight = width: s:
    s + lib.concatStrings (lib.genList (_: " ") (lib.max 0 (width - lib.stringLength s)));

  labelWidth = 14;
  row = label: values: "  ${padRight labelWidth label}${lib.concatStringsSep " " values}";

  # Every name the theme can install, not a sample. Printed one per line so the
  # output pipes cleanly into grep or a fuzzy finder.
  allNames = variants.allThemeDirNames "Gruvbox";
  nameLines = map (n: "  ${n}") allNames;

  text = ''
    Gruvbox GTK theme variants

    ${row "themes (-t)" variants.themes}
    ${row "colors (-c)" variants.colors}
    ${row "sizes (-s)" variants.sizes}
    ${row "tweaks" variants.tweaks}

    soft and medium are mutually exclusive; install.sh keeps only the last one.
    black, float, outline and macos change styling without changing the name.

    All ${toString (builtins.length allNames)} installable theme names
    (themeName + theme + color + size + ctype, with themeName defaulting to
    Gruvbox; pass -n or themeName to change the prefix):

    ${lib.concatStringsSep "\n" nameLines}

    Build one directly:

      nix build .#gruvbox-gtk-theme
      nix build .#gruvbox-icon-theme

    Pick variants through the overlay:

      pkgs.gruvbox-gtk-theme.override {
        themeVariants = [ "green" ];
        colorVariants = [ "dark" ];
        sizeVariants = [ "compact" ];
        tweaks = [ "outline" ];
      }

    Or with the home-manager module:

      programs.gruvbox-gtk-theme = {
        enable = true;
        themeVariants = [ "green" ];
        colorVariants = [ "dark" ];
        sizeVariants = [ "compact" ];
        tweaks = [ "outline" ];
        iconTheme.enable = true;
      };
  '';
in

writeShellApplication {
  name = "list-variants";
  text = ''
    cat <<'VARIANTS'
    ${text}
    VARIANTS
  '';

  meta = {
    description = "List the Gruvbox GTK theme's variant, size and tweak options";
    mainProgram = "list-variants";
  };
}
