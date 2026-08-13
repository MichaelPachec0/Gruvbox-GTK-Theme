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

      homeManagerModules.default = import ./nix/hm-module.nix { inherit self; };
      homeManagerModules.gruvbox-gtk-theme = self.homeManagerModules.default;

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

          hm-module-eval =
            let
              # Declares only the home-manager options the module writes to.
              # evalModules refuses assignments to undeclared options, so the
              # stub is required rather than optional.
              stub = { ... }: {
                options = {
                  # evalModules has no built-in assertions option; real
                  # home-manager gets one from its own base modules. The
                  # module writes to it, so the stub must declare it too.
                  assertions = lib.mkOption {
                    type = lib.types.listOf lib.types.unspecified;
                    default = [ ];
                  };
                  home.packages = lib.mkOption {
                    type = lib.types.listOf lib.types.package;
                    default = [ ];
                  };
                  gtk.enable = lib.mkOption { type = lib.types.bool; default = false; };
                  gtk.theme.name = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
                  gtk.theme.package = lib.mkOption { type = lib.types.nullOr lib.types.package; default = null; };
                  gtk.iconTheme.name = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
                  gtk.iconTheme.package = lib.mkOption { type = lib.types.nullOr lib.types.package; default = null; };
                };
              };
              evaluated = lib.evalModules {
                specialArgs = { inherit pkgs; };
                modules = [
                  stub
                  self.homeManagerModules.default
                  { programs.gruvbox-gtk-theme.enable = true; }
                ];
              };
            in
            pkgs.runCommand "check-hm-module-eval" { } ''
              test "${evaluated.config.gtk.theme.name}" = "Gruvbox-Dark"
              test "${lib.boolToString evaluated.config.gtk.enable}" = "true"
              touch $out
            '';
        });
    };
}
