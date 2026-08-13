{ lib
, stdenvNoCC
, sassc
, writeShellScriptBin
, themeName ? "Gruvbox"
, themeVariants ? [ "default" ]
, colorVariants ? [ "dark" "light" ]
, sizeVariants ? [ "standard" ]
, tweaks ? [ ]
, gnomeShellVersion ? null
}:

let
  validThemes = [ "default" "green" "grey" "orange" "pink" "purple" "red" "teal" "yellow" ];
  validColors = [ "light" "dark" ];
  validSizes = [ "standard" "compact" ];
  validTweaks = [ "soft" "medium" "black" "float" "outline" "macos" ];

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
  ctypeSuffix =
    if lib.elem "soft" tweaks then "-Soft"
    else if lib.elem "medium" tweaks then "-Medium"
    else "";

  themeNames = lib.concatMap
    (t: lib.concatMap
      (c: map
        (s: "${themeName}${themeSuffix.${t}}${colorSuffix.${c}}${sizeSuffix.${s}}${ctypeSuffix}")
        sizeVariants)
      colorVariants)
    themeVariants;

  # install.sh derives its GNOME Shell target from `gnome-shell --version`,
  # parsed as the third space-separated field truncated at the first dot, then
  # run through a >= ladder. With no gnome-shell on PATH it pins 48-0.
  gnomeShellShim = writeShellScriptBin "gnome-shell" ''
    echo "GNOME Shell ${toString gnomeShellVersion}.0"
  '';

  root = ../.;
  relativeTo = path: lib.removePrefix (toString root + "/") (toString path);
in

assert lib.all (t: lib.assertOneOf "themeVariants entry" t validThemes) themeVariants;
assert lib.all (c: lib.assertOneOf "colorVariants entry" c validColors) colorVariants;
assert lib.all (s: lib.assertOneOf "sizeVariants entry" s validSizes) sizeVariants;
assert lib.all (t: lib.assertOneOf "tweaks entry" t validTweaks) tweaks;
assert lib.assertMsg (!(lib.elem "soft" tweaks && lib.elem "medium" tweaks))
  "tweaks: soft and medium are mutually exclusive, install.sh keeps only the last one";

stdenvNoCC.mkDerivation {
  pname = "gruvbox-gtk-theme";
  version = "0-unstable-2026-08-13";

  # Filtered to themes/ so that editing an icon does not invalidate this
  # derivation. It does not avoid the flake copying the whole tracked tree
  # into the store; nothing in a monorepo flake can.
  src = lib.cleanSourceWith {
    src = root;
    filter = path: _type:
      let rel = relativeTo path;
      in rel == "themes" || lib.hasPrefix "themes/" rel;
  };

  nativeBuildInputs = [ sassc ]
    ++ lib.optional (gnomeShellVersion != null) gnomeShellShim;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # install.sh reads bare, non-local shell variables. Every nix builder
    # exports `name`, which the script would otherwise use as the theme name,
    # producing $out/share/themes/<derivation name>-Dark. The rest are unset
    # defensively so a future stdenv change cannot alter the build silently.
    unset name dest theme color size ctype window
    unset compact soft medium blackness float outline macos libadwaita

    export HOME="$TMPDIR"
    mkdir -p "$out/share/themes"

    patchShebangs themes/install.sh themes/gtkrc.sh

    themes/install.sh \
      -d "$out/share/themes" \
      -n ${lib.escapeShellArg themeName} \
      -t ${lib.escapeShellArgs themeVariants} \
      -c ${lib.escapeShellArgs colorVariants} \
      -s ${lib.escapeShellArgs sizeVariants} \
      ${lib.optionalString (tweaks != [ ]) "--tweaks ${lib.escapeShellArgs tweaks}"}

    runHook postInstall
  '';

  # Only selectable themes. install.sh also emits <name>-hdpi and <name>-xhdpi
  # siblings holding xfwm4 decorations alone; setting gtk.theme.name to one of
  # those yields an unstyled session.
  passthru = { inherit themeNames; };

  meta = {
    description = "Gruvbox theme for GTK 2/3/4, GNOME Shell, Cinnamon, Metacity and Xfwm4";
    homepage = "https://github.com/MichaelPachec0/Gruvbox-GTK-Theme";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}
