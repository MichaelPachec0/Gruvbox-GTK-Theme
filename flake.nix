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
        gruvbox-kde-color-schemes = pkgs.callPackage ./nix/kde-package.nix { };
        gruvbox-kde-aurorae = pkgs.callPackage ./nix/aurorae-package.nix { };
        list-variants = pkgs.callPackage ./nix/list-variants.nix { };

        # Building this RUNS the VM test; $out holds the screenshots it took.
        # Kept out of `checks` on purpose: it builds and boots a full Plasma
        # desktop, which is far too heavy for `nix flake check`.
        vm-test = import ./nix/vm-test.nix {
          inherit pkgs self;
          system = pkgs.stdenv.hostPlatform.system;
        };

        default = gruvbox-gtk-theme;
      });

      apps = forAllSystems (pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
        in
        {
          list-variants = {
            type = "app";
            program = lib.getExe self.packages.${system}.list-variants;
            meta.description = "List the theme, color, size and tweak options this flake accepts";
          };

          # Runs the same test outside the build sandbox, which is the only
          # way it can reach the host GPU: `nix build` hides /dev/dri, so a
          # sandboxed run is always llvmpipe no matter what the host has.
          vm-test-gpu =
            let
              driver = (import ./nix/vm-test.nix {
                inherit pkgs self system;
                gpu = true;
              }).driver;
            in
            {
              type = "app";
              # The driver writes screenshots to $out, falling back to the
              # working directory, which drops PNGs into the repository root.
              # Point it at a directory of its own instead.
              program = lib.getExe (pkgs.writeShellApplication {
                name = "vm-test-gpu";
                text = ''
                  shots=''${VM_TEST_OUT:-$PWD/vm-test-screenshots}
                  mkdir -p "$shots"
                  echo "screenshots will be written to $shots"
                  # The driver takes an explicit flag for this. Setting $out
                  # does nothing: out_dir comes from --output_directory,
                  # which defaults to the working directory, which is how
                  # PNGs ended up in the repository root.
                  exec ${driver}/bin/nixos-test-driver \
                    --output_directory "$shots" "$@"
                '';
              });
              meta.description = "Run the Plasma VM test on the host GPU (virtio-gpu-gl)";
            };

          # Boots the same VM but hands you the driver's Python REPL, so you
          # can drive the session by hand. Start it with `start_all()`, then
          # use machine.screenshot("name") and machine.succeed(...).
          vm-test-interactive = {
            type = "app";
            program = "${(import ./nix/vm-test.nix {
              inherit pkgs self system;
              gpu = true;
            }).driverInteractive}/bin/nixos-test-driver";
            meta.description = "Boot the Plasma VM on the GPU and drive it interactively";
          };
        });

      overlays.default = import ./nix/overlay.nix;

      homeManagerModules.default = import ./nix/hm-module.nix { inherit self; };
      homeManagerModules.gruvbox-gtk-theme = self.homeManagerModules.default;

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [ pkgs.sassc pkgs.gnome-themes-extra ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);

      checks = forAllSystems (pkgs:
        let
          theme = self.packages.${pkgs.stdenv.hostPlatform.system}.gruvbox-gtk-theme;
          green = theme.override {
            themeVariants = [ "green" ];
            colorVariants = [ "dark" ];
          };
          icons = self.packages.${pkgs.stdenv.hostPlatform.system}.gruvbox-icon-theme;
          lister = self.packages.${pkgs.stdenv.hostPlatform.system}.list-variants;

          kdeSchemes = self.packages.${pkgs.stdenv.hostPlatform.system}.gruvbox-kde-color-schemes;
          kdeAll = kdeSchemes.override {
            themeVariants = variants.themes;
            colorVariants = variants.colors;
            contrastVariants = variants.contrasts;
          };

          aurorae = (self.packages.${pkgs.stdenv.hostPlatform.system}.gruvbox-kde-aurorae).override {
            colorVariants = [ "dark" "light" ];
          };
          # The traffic-light assertion needs the macos set, which is not the
          # default button style.
          auroraeMacos = (self.packages.${pkgs.stdenv.hostPlatform.system}.gruvbox-kde-aurorae).override {
            colorVariants = [ "dark" "light" ];
            buttonVariants = [ "macos" ];
          };

          # What list-variants is expected to print, derived from the same file
          # it reads. Each value is tied to the row it belongs on rather than
          # searched for anywhere in the output: the prose below those rows
          # names several tweaks, so a document-wide search would pass even if
          # a row were missing them.
          variants = import ./nix/variants.nix lib;
          expectedRows = [
            { label = "themes (-t)"; words = variants.themes; }
            { label = "colors (-c)"; words = variants.colors; }
            { label = "sizes (-s)"; words = variants.sizes; }
            { label = "tweaks"; words = variants.tweaks; }
            { label = "contrasts (--contrast)"; words = variants.contrasts; }
          ];

          # The complete enumeration, compared line for line rather than
          # sampled, so a missing, extra or misspelled name fails the check.
          expectedNames = variants.allThemeDirNames "Gruvbox";
          expectedNamesFile = pkgs.writeText "expected-theme-names"
            (lib.concatMapStringsSep "\n" (n: "  ${n}") expectedNames + "\n");

          expectedSchemeNames = variants.allColorSchemeNames "Gruvbox";
          expectedSchemeNamesFile = pkgs.writeText "expected-scheme-names"
            (lib.concatMapStringsSep "\n" (n: "  ${n}") expectedSchemeNames + "\n");

          # Declares only the home-manager options the module writes to.
          # evalModules refuses assignments to undeclared options, so the
          # stub is required rather than optional. Shared by both hm-module
          # checks below.
          hmStub = { ... }: {
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
        in
        {
          # The drift guard for list-variants: adding a value to
          # nix/variants.nix without it reaching the printed row fails here.
          list-variants-covers-vocabulary =
            pkgs.runCommand "check-list-variants-covers-vocabulary" { } ''
              ${lib.getExe lister} > listed.txt

              row_has() {
                label="$1"
                shift
                # Anchored at column 1 so the indented "tweaks = [ ... ]" line
                # in the copy-paste snippet cannot be mistaken for the row.
                line=$(awk -v l="  $label" 'index($0, l) == 1 { print; exit }' listed.txt)
                if [ -z "$line" ]; then
                  echo "list-variants prints no '$label' row at all" >&2
                  exit 1
                fi
                for word in "$@"; do
                  case " $line " in
                    *" $word "*) ;;
                    *) echo "the '$label' row never lists $word" >&2; exit 1 ;;
                  esac
                done
              }

              ${lib.concatMapStringsSep "\n              "
                (r: "row_has ${lib.escapeShellArgs ([ r.label ] ++ r.words)}")
                expectedRows}

              # Theme directory names and colour scheme names live in disjoint
              # sections of the printed output, headed by "All N installable
              # theme names" and "All N KDE colour scheme names:"
              # respectively. Scoping each grep to its own section by header
              # is required, not cosmetic: a theme directory name and a
              # colour scheme name can be the exact same string (for example
              # Gruvbox-Light-Soft names both a GTK theme directory and a KDE
              # colour scheme), so a suffix-based split cannot tell them
              # apart, but the section they print in always can.
              awk '/^All [0-9]+ installable theme names$/,/^All [0-9]+ KDE colour scheme names:$/' listed.txt \
                | grep -E '^  Gruvbox' > printed-names.txt

              if ! diff -u ${expectedNamesFile} printed-names.txt; then
                echo "the printed theme names do not match the ${toString (builtins.length expectedNames)} names variants.nix computes" >&2
                exit 1
              fi

              awk '/^All [0-9]+ KDE colour scheme names:$/,/^Build one directly:$/' listed.txt \
                | grep -E '^  Gruvbox' | sort > printed-scheme-names.txt
              sort ${expectedSchemeNamesFile} > expected-scheme-names.txt

              if ! diff -u expected-scheme-names.txt printed-scheme-names.txt; then
                echo "the printed colour scheme names do not match the ${toString (builtins.length expectedSchemeNames)} names variants.nix computes" >&2
                exit 1
              fi
              touch $out
            '';

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
              evaluated = lib.evalModules {
                specialArgs = { inherit pkgs; };
                modules = [
                  hmStub
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

          # lib.evalModules does not enforce config.assertions the way a real
          # NixOS or home-manager build does; that enforcement lives in the
          # consuming build, which is absent here. So the assertion that
          # rejects an unknown gtkThemeName could be inverted or broken and
          # hm-module-eval above would still pass. This check evaluates the
          # module with a bogus gtkThemeName and asserts explicitly that
          # exactly one assertion entry fails, with an actionable message,
          # proving the safety net still works.
          hm-module-rejects-unknown-theme =
            let
              evaluated = lib.evalModules {
                specialArgs = { inherit pkgs; };
                modules = [
                  hmStub
                  self.homeManagerModules.default
                  {
                    programs.gruvbox-gtk-theme = {
                      enable = true;
                      gtkThemeName = "Gruvbox-Nonexistent";
                    };
                  }
                ];
              };
              failing = builtins.filter (a: !a.assertion) evaluated.config.assertions;
              failingMessages = lib.concatStringsSep "\n" (map (a: a.message) failing);
            in
            pkgs.runCommand "check-hm-module-rejects-unknown-theme"
              {
                passAsFile = [ "failingMessages" ];
                failingMessages = failingMessages;
              } ''
              test "${toString (builtins.length failing)}" = "1"
              grep -qF "Gruvbox-Nonexistent" "$failingMessagesPath"
              grep -qF "Gruvbox-Dark" "$failingMessagesPath"
              grep -qF "Gruvbox-Light" "$failingMessagesPath"
              touch $out
            '';

          kde-colors-well-formed = pkgs.runCommand "check-kde-colors-well-formed" { } ''
            # BOTH variants, and the light one is not optional. $text is
            # already opaque for a dark background, so a missing flatten()
            # produces byte-identical output in the Dark file and the alpha
            # leak is invisible there. It appears only in Light, where $text
            # is rgba(29,32,33,0.87). Checking Dark alone made this check
            # unable to fail for the defect it exists to catch.
            for f in ${kdeSchemes}/share/color-schemes/Gruvbox-Dark-Hard.colors \
                     ${kdeSchemes}/share/color-schemes/Gruvbox-Light-Hard.colors; do
              test -s "$f"

              count=$(grep -c '^\[' "$f")
              if [ "$count" != 13 ]; then
                echo "$f: expected 13 INI sections, found $count" >&2
                exit 1
              fi

              # The check that catches an un-flattened alpha value.
              if grep -nE 'rgba|#[0-9a-fA-F]{3}' "$f"; then
                echo "$f: a colour leaked through unflattened or as hex" >&2
                exit 1
              fi

              # Every colour value is an opaque triple with components <= 255.
              grep -oE '^[A-Za-z]+=[0-9]+,[0-9]+,[0-9]+$' "$f" |
                sed 's/.*=//' | tr ',' '\n' |
                while read -r n; do
                  if [ "$n" -gt 255 ]; then
                    echo "$f: colour component out of range: $n" >&2
                    exit 1
                  fi
                done

              # No key may repeat within a section. KDE resolves a duplicate
              # last-wins, so a wrong first value would sit there silently.
              # This shipped once already, in Colors:Selection.
              if ${pkgs.gawk}/bin/awk '
                /^\[/ { sec = $0; delete seen; next }
                /=/   {
                  split($0, kv, "=")
                  if (kv[1] in seen) {
                    print FILENAME ": duplicate key " kv[1] " in " sec > "/dev/stderr"
                    bad = 1
                  }
                  seen[kv[1]] = 1
                }
                END { exit bad }
              ' "$f"; then :; else
                echo "$f: duplicate INI keys" >&2
                exit 1
              fi
            done

            # Proof that flatten() is actually compositing, which none of the
            # arms above can establish. rgbtriple() calls Sass red/green/blue,
            # which ignore alpha, so dropping flatten() does not leak "rgba("
            # into the file: it silently emits the raw uncomposited channels.
            #
            # The invariant: in the LIGHT scheme $text is rgba(29,32,33,0.87),
            # so it composites to a different value over Colors:Window's
            # background than over Colors:View's. If flatten() were removed
            # both would collapse to the raw 29,32,33 and become equal.
            # Deliberately not asserted for Dark, where $text is opaque and
            # the two are legitimately identical.
            light=${kdeSchemes}/share/color-schemes/Gruvbox-Light-Hard.colors
            win=$(sed -n '/^\[Colors:Window\]/,/^\[/p' "$light" \
              | grep -m1 '^ForegroundNormal=' | cut -d= -f2)
            view=$(sed -n '/^\[Colors:View\]/,/^\[/p' "$light" \
              | grep -m1 '^ForegroundNormal=' | cut -d= -f2)
            if [ "$win" = "$view" ]; then
              echo "light ForegroundNormal is $win in both Colors:Window and Colors:View" >&2
              echo "a translucent text colour must composite differently over different" >&2
              echo "section backgrounds, so flatten() is not being applied" >&2
              exit 1
            fi
            touch $out
          '';

          # The only test that fails if the mapping drifts from the GTK theme.
          kde-colors-match-gtk = pkgs.runCommand "check-kde-colors-match-gtk" { } ''
            gtk=$(grep -m1 '@define-color theme_bg_color' \
              ${theme}/share/themes/Gruvbox-Dark/gtk-3.0/gtk.css |
              grep -oE '#[0-9a-fA-F]{6}')
            kde=$(sed -n '/^\[Colors:Window\]/,/^\[/p' \
              ${kdeSchemes}/share/color-schemes/Gruvbox-Dark-Hard.colors |
              grep -m1 '^BackgroundNormal=' | cut -d= -f2)

            r=$(printf '%d' "0x''${gtk:1:2}")
            g=$(printf '%d' "0x''${gtk:3:2}")
            b=$(printf '%d' "0x''${gtk:5:2}")

            if [ "$kde" != "$r,$g,$b" ]; then
              echo "KDE window background $kde does not match GTK $gtk ($r,$g,$b)" >&2
              exit 1
            fi
            echo "KDE and GTK agree on $gtk"
            touch $out
          '';

          kde-colors-matrix-distinct = pkgs.runCommand "check-kde-colors-matrix-distinct" { } ''
            dir=${kdeAll}/share/color-schemes
            files=$(ls "$dir" | wc -l)
            if [ "$files" != 90 ]; then
              echo "expected 90 colour schemes, found $files" >&2
              exit 1
            fi

            # Bijective: no two names share a palette, none is orphaned.
            uniq=$(md5sum "$dir"/*.colors | awk '{print $1}' | sort -u | wc -l)
            if [ "$uniq" != 90 ]; then
              echo "90 names cover only $uniq distinct palettes" >&2
              exit 1
            fi
            touch $out
          '';

          kde-colors-contrast-vocabulary = pkgs.runCommand "check-kde-colors-contrast-vocabulary" { } ''
            dir=${kdeAll}/share/color-schemes
            for word in Hard Medium Soft Black; do
              if ! ls "$dir" | grep -q -- "-$word"; then
                echo "no generated scheme carries the $word contrast" >&2
                exit 1
              fi
            done
            touch $out
          '';

          aurorae-element-contract = pkgs.runCommand "check-aurorae-element-contract" { } ''
            d=${aurorae}/share/aurorae/themes/Gruvbox-Dark
            for s in top bottom left right topleft topright bottomleft bottomright center; do
              grep -q "id=\"decoration-$s\"" "$d/decoration.svg" || {
                echo "decoration.svg is missing the decoration-$s nine-slice id" >&2
                exit 1
              }
            done
            for b in close maximize restore minimize alldesktops keepabove keepbelow; do
              test -f "$d/$b.svg"
              grep -q 'id="active-center"' "$d/$b.svg" || {
                echo "$b.svg has no active-center element" >&2
                exit 1
              }
            done
            touch $out
          '';

          # The property that lets one decoration serve all 90 schemes.
          aurorae-scheme-aware = pkgs.runCommand "check-aurorae-scheme-aware" { } ''
            d=${aurorae}/share/aurorae/themes/Gruvbox-Dark
            grep -q 'id="current-color-scheme"' "$d/decoration.svg" || {
              echo "decoration.svg lost its current-color-scheme stylesheet" >&2
              exit 1
            }
            grep -q 'class="ColorScheme-' "$d/decoration.svg" || {
              echo "decoration.svg no longer references any ColorScheme class" >&2
              exit 1
            }
            touch $out
          '';

          # The traffic lights live only in the macos button set. The legacy
          # set is monochrome and scheme-aware, so it carries no literal hex
          # and cannot be compared this way; its own invariant is checked
          # below instead.
          aurorae-buttons-match-gtk = pkgs.runCommand "check-aurorae-buttons-match-gtk" { } ''
            dark=$(grep -oE '#(ea6962|c14a4a)' \
              ${auroraeMacos}/share/aurorae/themes/Gruvbox-Dark-Macos/close.svg | head -1)
            light=$(grep -oE '#(ea6962|c14a4a)' \
              ${auroraeMacos}/share/aurorae/themes/Gruvbox-Light-Macos/close.svg | head -1)

            if [ "$dark" != "#ea6962" ]; then
              echo "dark macos close button is $dark, expected #ea6962 (\$titlebutton-close)" >&2
              exit 1
            fi
            if [ "$light" != "#c14a4a" ]; then
              echo "light macos close button is $light, expected #c14a4a (\$titlebutton-close)" >&2
              exit 1
            fi
            if [ "$dark" = "$light" ]; then
              echo "light and dark close buttons are identical; \$topbar is not tracking \$variant" >&2
              exit 1
            fi
            touch $out
          '';

          # The legacy buttons must stay scheme-aware. If an edit bakes a
          # literal colour into them they stop following the colour scheme,
          # which is silent: they would still render, just always in one
          # colour regardless of the active scheme.
          aurorae-legacy-buttons-scheme-aware = pkgs.runCommand "check-aurorae-legacy-buttons-scheme-aware" { } ''
            for b in close maximize restore minimize alldesktops keepabove keepbelow; do
              f=${aurorae}/share/aurorae/themes/Gruvbox-Dark/$b.svg
              test -f "$f"
              grep -q 'ColorScheme-' "$f" || {
                echo "$b.svg no longer references any ColorScheme class" >&2
                exit 1
              }
              # Outside the stylesheet block, no literal fill may remain.
              if sed '/<style/,/<\/style>/d' "$f" | grep -oE 'fill:#[0-9a-fA-F]{6}|fill="#[0-9a-fA-F]{6}"'; then
                echo "$b.svg has a literal fill outside its stylesheet" >&2
                exit 1
              fi
            done
            touch $out
          '';
        });
    };
}
