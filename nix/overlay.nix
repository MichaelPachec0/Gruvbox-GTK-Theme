final: _prev: {
  gruvbox-gtk-theme = final.callPackage ./package.nix { };
  gruvbox-icon-theme = final.callPackage ./icons.nix { };
  gruvbox-kde-color-schemes = final.callPackage ./kde-package.nix { };
  gruvbox-kde-aurorae = final.callPackage ./aurorae-package.nix { };
}
