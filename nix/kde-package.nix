{ lib
, stdenvNoCC
, sassc
, gawk
, themeName ? "Gruvbox"
, themeVariants ? [ "default" ]
, colorVariants ? [ "dark" "light" ]
, contrastVariants ? [ "hard" ]
}:

let
  variants = import ./variants.nix lib;

  colorSchemeNames = lib.unique (lib.concatMap
    (theme: lib.concatMap
      (color: map
        (contrast: variants.colorSchemeName {
          inherit themeName theme color contrast;
        })
        contrastVariants)
      colorVariants)
    themeVariants);

  root = ../.;
  relativeTo = path: lib.removePrefix (toString root + "/") (toString path);
in

assert lib.assertMsg (themeVariants != [ ]) "themeVariants must not be empty";
assert lib.assertMsg (colorVariants != [ ]) "colorVariants must not be empty";
assert lib.assertMsg (contrastVariants != [ ]) "contrastVariants must not be empty";
assert lib.all (t: lib.assertOneOf "themeVariants entry" t variants.themes) themeVariants;
assert lib.all (c: lib.assertOneOf "colorVariants entry" c variants.colors) colorVariants;
assert lib.all (c: lib.assertOneOf "contrastVariants entry" c variants.contrasts) contrastVariants;

stdenvNoCC.mkDerivation {
  pname = "gruvbox-kde-color-schemes";
  version = "0-unstable-2026-08-13";

  src = lib.cleanSourceWith {
    src = root;
    filter = path: _type:
      let rel = relativeTo path;
      in rel == "themes" || lib.hasPrefix "themes/" rel
        || rel == "kde" || lib.hasPrefix "kde/" rel;
  };

  nativeBuildInputs = [ sassc gawk ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # kde/install.sh unsets these itself, but a builder-exported `name`
    # reaching the script at all is worth preventing here too.
    unset name dest theme color contrast

    export HOME="$TMPDIR"
    mkdir -p "$out/share/color-schemes"

    patchShebangs kde/install.sh

    # --colors is required, not decorative. -d moves BOTH the colour-scheme
    # and the Aurorae destination, and passing neither flag means "install
    # both", so without this the Aurorae themes are written as directories
    # into share/color-schemes alongside the .colors files.
    kde/install.sh --colors \
      -d "$out/share/color-schemes" \
      -n ${lib.escapeShellArg themeName} \
      -t ${lib.escapeShellArgs themeVariants} \
      -c ${lib.escapeShellArgs colorVariants} \
      --contrast ${lib.escapeShellArgs contrastVariants}

    runHook postInstall
  '';

  passthru = { inherit colorSchemeNames; };

  meta = {
    description = "Gruvbox colour schemes for KDE Plasma and Qt applications";
    homepage = "https://github.com/MichaelPachec0/Gruvbox-GTK-Theme";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}
