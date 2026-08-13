{
  description = "Gruvbox theme for GTK 2/3/4, GNOME Shell, Cinnamon, Metacity and Xfwm4";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        gruvbox-gtk-theme = pkgs.callPackage ./nix/package.nix { };
        gruvbox-icon-theme = pkgs.callPackage ./nix/icons.nix { };
        default = gruvbox-gtk-theme;
      });

      overlays.default = import ./nix/overlay.nix;

      checks = forAllSystems (pkgs:
        let
          theme = self.packages.${pkgs.stdenv.hostPlatform.system}.gruvbox-gtk-theme;
          green = theme.override {
            themeVariants = [ "green" ];
            colorVariants = [ "dark" ];
          };
          icons = self.packages.${pkgs.stdenv.hostPlatform.system}.gruvbox-icon-theme;
        in
        {
          theme-layout = pkgs.runCommand "check-theme-layout" { } ''
            dir=${theme}/share/themes/Gruvbox-Dark
            test -s "$dir/gtk-3.0/gtk.css"
            test -f "$dir/gtk-2.0/gtkrc"
            test "$(head -1 "$dir/index.theme")" = "[Desktop Entry]"
            touch $out
          '';

          override-variants = pkgs.runCommand "check-override-variants" { } ''
            test -d ${green}/share/themes/Gruvbox-Green-Dark
            if [ -e ${green}/share/themes/Gruvbox-Dark ]; then
              echo "override leaked the default variant into the output" >&2
              exit 1
            fi
            touch $out
          '';

          icons-preserve-symlinks = pkgs.runCommand "check-icons-preserve-symlinks" { } ''
            count=$(find ${icons}/share/icons -type l | wc -l)
            if [ "$count" -lt 10000 ]; then
              echo "expected tens of thousands of symlinks, found $count" >&2
              echo "the install phase probably used cp -r and dereferenced them" >&2
              exit 1
            fi
            test -f ${icons}/share/icons/Gruvbox-Dark/index.theme
            test -f ${icons}/share/icons/Gruvbox-Dark/icon-theme.cache
            touch $out
          '';
        });
    };
}
