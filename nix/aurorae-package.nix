{ lib
, stdenvNoCC
, sassc
, themeName ? "Gruvbox"
, colorVariants ? [ "dark" "light" ]
, frameVariants ? [ "normal" ]
, buttonVariants ? [ "legacy" ]
}:

let
  variants = import ./variants.nix lib;

  frames = [ "normal" "outline" ];
  buttonStyles = [ "legacy" "macos" ];

  # Mirrors aurorae_name() in kde/install.sh. Contrast is absent by design:
  # the decoration follows the active colour scheme.
  auroraeThemeNames = lib.concatMap
    (color: lib.concatMap
      (frame: map
        (buttons:
          themeName
          + variants.colorSuffix.${color}
          + (if frame == "outline" then "-Outline" else "")
          + (if buttons == "macos" then "-Macos" else ""))
        buttonVariants)
      frameVariants)
    colorVariants;

  root = ../.;
  relativeTo = path: lib.removePrefix (toString root + "/") (toString path);
in

assert lib.assertMsg (colorVariants != [ ]) "colorVariants must not be empty";
assert lib.assertMsg (frameVariants != [ ]) "frameVariants must not be empty";
assert lib.assertMsg (buttonVariants != [ ]) "buttonVariants must not be empty";
assert lib.all (c: lib.assertOneOf "colorVariants entry" c variants.colors) colorVariants;
assert lib.all (f: lib.assertOneOf "frameVariants entry" f frames) frameVariants;
assert lib.all (b: lib.assertOneOf "buttonVariants entry" b buttonStyles) buttonVariants;

stdenvNoCC.mkDerivation {
  pname = "gruvbox-kde-aurorae";
  version = "0-unstable-2026-08-13";

  src = lib.cleanSourceWith {
    src = root;
    filter = path: _type:
      let rel = relativeTo path;
      in rel == "themes" || lib.hasPrefix "themes/" rel
        || rel == "kde" || lib.hasPrefix "kde/" rel;
  };

  nativeBuildInputs = [ sassc ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    unset name dest theme color contrast

    export HOME="$TMPDIR"
    mkdir -p "$out/share/aurorae/themes"

    patchShebangs kde/install.sh

    kde/install.sh --aurorae \
      -d "$out/share/aurorae/themes" \
      -n ${lib.escapeShellArg themeName} \
      -c ${lib.escapeShellArgs colorVariants} \
      --frame ${lib.escapeShellArgs frameVariants} \
      --buttons ${lib.escapeShellArgs buttonVariants}

    runHook postInstall
  '';

  passthru = { inherit auroraeThemeNames; };

  meta = {
    description = "Gruvbox Aurorae window decorations for KDE Plasma";
    homepage = "https://github.com/MichaelPachec0/Gruvbox-GTK-Theme";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}
