{ lib
, stdenvNoCC
, gtk3
}:

let
  root = ../.;
  relativeTo = path: lib.removePrefix (toString root + "/") (toString path);
in

stdenvNoCC.mkDerivation {
  pname = "gruvbox-icon-theme";
  version = "0-unstable-2026-08-13";

  src = lib.cleanSourceWith {
    src = root;
    filter = path: _type:
      let rel = relativeTo path;
      in rel == "icons" || lib.hasPrefix "icons/" rel;
  };

  nativeBuildInputs = [ gtk3 ];

  dontConfigure = true;
  dontBuild = true;
  # 161310 files, none of them binaries worth scanning.
  dontFixup = true;

  # gtk3's setup hook installs a dropIconThemeCache phase that deletes every
  # icon-theme.cache from the output. That is the right default for most
  # packages, since profile and system builds regenerate the caches, but it
  # would make the gtk-update-icon-cache loop below pure waste. These themes
  # carry 67241 icons across five directories, where a prebuilt cache is worth
  # shipping, so opt out the same way papirus-icon-theme does.
  dontDropIconThemeCache = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/icons"

    # cp -a, never cp -r. These themes are symlink farms, 94069 symlinks
    # against 67241 regular files, and GNU cp -r dereferences symlinks in the
    # source, which would materialise every link as a full copy of its target.
    cp -a icons/. "$out/share/icons/"

    for theme in "$out"/share/icons/*/; do
      gtk-update-icon-cache --force --quiet "$theme"
    done

    runHook postInstall
  '';

  # Derived from the source tree rather than hardcoded, so a rebase onto
  # upstream that adds, renames or drops an icon theme cannot silently
  # desync this list from what installPhase actually copies. lib.naturalSort
  # gives a deterministic order; verified to put Gruvbox-Dark first, which
  # the home-manager module relies on as its default icon theme.
  passthru.iconThemeNames = lib.naturalSort (lib.attrNames
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir (root + "/icons"))));

  meta = {
    description = "Gruvbox icon themes";
    homepage = "https://github.com/MichaelPachec0/Gruvbox-GTK-Theme";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}
