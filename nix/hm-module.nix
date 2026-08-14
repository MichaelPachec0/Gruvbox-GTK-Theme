{ self }:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.gruvbox-gtk-theme;

  themePackage = pkgs.callPackage "${self}/nix/package.nix" {
    inherit (cfg) themeName themeVariants colorVariants sizeVariants tweaks gnomeShellVersion;
  };
  iconPackage = pkgs.callPackage "${self}/nix/icons.nix" { };
  kdeColorSchemePackage = pkgs.callPackage "${self}/nix/kde-package.nix" {
    inherit (cfg) themeName themeVariants colorVariants;
    contrastVariants = cfg.kdeColorSchemes.contrastVariants;
  };

  # Read from variants.nix rather than repeating the list. A hardcoded copy
  # here went stale once already: it still held the four-value vocabulary
  # after the contrast axis was corrected, which both rejected the valid
  # medium-black and soft-black and accepted the CLI-only `black` alias that
  # kde-package.nix then refused with a raw assertOneOf trace.
  kdeContrasts = (import "${self}/nix/variants.nix" lib).contrasts;

  themeNames = cfg.package.themeNames or [ ];
  iconThemeNames = cfg.iconTheme.package.iconThemeNames or [ ];

  resolvedThemeName =
    if cfg.gtkThemeName != null then cfg.gtkThemeName
    else lib.head themeNames;
  resolvedIconThemeName =
    if cfg.iconThemeName != null then cfg.iconThemeName
    else lib.head iconThemeNames;
in
{
  options.programs.gruvbox-gtk-theme = {
    enable = lib.mkEnableOption "the Gruvbox GTK theme";

    package = lib.mkOption {
      type = lib.types.package;
      default = themePackage;
      defaultText = lib.literalMD "the flake's theme package, built from the variant options below";
      description = "Theme package to install. Setting this ignores the variant options.";
    };

    themeName = lib.mkOption {
      type = lib.types.str;
      default = "Gruvbox";
      description = "Prefix of every generated theme directory name.";
    };

    themeVariants = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "default" ];
      description = "Accent variants: default green grey orange pink purple red teal yellow.";
    };

    colorVariants = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "dark" "light" ];
      description = "Color variants: light dark.";
    };

    sizeVariants = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "standard" ];
      description = "Size variants: standard compact.";
    };

    tweaks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Tweaks: soft medium black float outline macos. soft and medium are mutually exclusive.";
    };

    gnomeShellVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "46";
      description = ''
        GNOME Shell major version to build shell styles for. Null builds for
        the newest version the installer knows, currently 48, because the
        installer's own probe cannot see a running GNOME from inside the
        build sandbox. Set this if you run an older GNOME.
      '';
    };

    iconTheme = {
      enable = lib.mkEnableOption "the Gruvbox icon themes";

      package = lib.mkOption {
        type = lib.types.package;
        default = iconPackage;
        defaultText = lib.literalMD "the flake's icon package";
        description = "Icon theme package to install.";
      };
    };

    setGtkTheme = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to point gtk.theme and gtk.iconTheme at the installed themes.";
    };

    gtkThemeName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "Gruvbox-Dark";
      description = ''
        Which built theme directory to activate. Null takes the first entry of
        the package's themeNames. A name that matches no installed directory
        produces no error and no theming, just an unstyled session, which is
        why the assertion below rejects unknown names.
      '';
    };

    iconThemeName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "Gruvbox-Dark";
      description = "Which icon theme directory to activate. Null takes the first entry of the package's iconThemeNames.";
    };

    kdeColorSchemes = {
      enable = lib.mkEnableOption "the Gruvbox KDE colour schemes";

      package = lib.mkOption {
        type = lib.types.package;
        default = kdeColorSchemePackage;
        defaultText = lib.literalMD "the flake's KDE colour scheme package";
        description = "Colour scheme package to install.";
      };

      contrastVariants = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "hard" ];
        description =
          "Contrast variants: "
          + lib.concatStringsSep " " kdeContrasts
          + ". Blackness combines with the palette, so medium-black is a "
          + "distinct scheme from both medium and hard-black.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # themeNames is only empty when package was overridden to something
        # without a passthru.themeNames. gtkThemeName is the documented escape
        # hatch for that case, so this only fires when neither gives us a
        # theme directory to activate.
        assertion = themeNames != [ ] || cfg.gtkThemeName != null;
        message = "programs.gruvbox-gtk-theme.package exposes no themeNames and gtkThemeName is not set; set gtkThemeName explicitly.";
      }
      {
        # Skipped when themeNames is empty: that case is already covered by
        # the assertion above, and checking membership against an empty list
        # would reject every gtkThemeName, including a correct one for a
        # custom package.
        assertion = cfg.gtkThemeName == null || themeNames == [ ] || lib.elem cfg.gtkThemeName themeNames;
        message = "programs.gruvbox-gtk-theme.gtkThemeName is ${toString cfg.gtkThemeName}, which this package does not build. It builds: ${lib.concatStringsSep ", " themeNames}.";
      }
      {
        # Mirrors the themeNames assertion above for the icon side: an
        # iconTheme.package with no passthru.iconThemeNames and no explicit
        # iconThemeName has no icon theme directory to activate.
        assertion = !cfg.iconTheme.enable || iconThemeNames != [ ] || cfg.iconThemeName != null;
        message = "programs.gruvbox-gtk-theme.iconTheme.package exposes no iconThemeNames and iconThemeName is not set; set iconThemeName explicitly.";
      }
      {
        assertion = !cfg.iconTheme.enable || cfg.iconThemeName == null || iconThemeNames == [ ] || lib.elem cfg.iconThemeName iconThemeNames;
        message = "programs.gruvbox-gtk-theme.iconThemeName is ${toString cfg.iconThemeName}, which this package does not ship. It ships: ${lib.concatStringsSep ", " iconThemeNames}.";
      }
      {
        # Read from variants.nix rather than repeating the list. A hardcoded
        # copy here went stale once already: it still held the four-value
        # vocabulary after the contrast axis was corrected, which both
        # rejected the valid medium-black and soft-black and accepted the
        # CLI-only `black` alias that kde-package.nix then refused with a raw
        # assertOneOf trace.
        assertion = !cfg.kdeColorSchemes.enable
          || lib.all (c: lib.elem c kdeContrasts) cfg.kdeColorSchemes.contrastVariants;
        message = "programs.gruvbox-gtk-theme.kdeColorSchemes.contrastVariants "
          + "accepts only: "
          + lib.concatStringsSep " " kdeContrasts;
      }
    ];

    # gnome-themes-extra supplies the GTK2 adwaita engine that the theme's
    # gtk-2.0 rc files load. Without it GTK2 apps fall back to unstyled
    # widgets.
    home.packages = [ cfg.package pkgs.gnome-themes-extra ]
      ++ lib.optional cfg.iconTheme.enable cfg.iconTheme.package
      ++ lib.optional cfg.kdeColorSchemes.enable cfg.kdeColorSchemes.package;

    gtk = lib.mkIf cfg.setGtkTheme ({
      enable = true;
      theme = {
        name = resolvedThemeName;
        package = cfg.package;
      };
    } // lib.optionalAttrs cfg.iconTheme.enable {
      iconTheme = {
        name = resolvedIconThemeName;
        package = cfg.iconTheme.package;
      };
    });
  };
}
