{ self }:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.gruvbox-gtk-theme;

  themePackage = pkgs.callPackage "${self}/nix/package.nix" {
    inherit (cfg) themeName themeVariants colorVariants sizeVariants tweaks gnomeShellVersion;
  };
  iconPackage = pkgs.callPackage "${self}/nix/icons.nix" { };

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
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = themeNames != [ ];
        message = "programs.gruvbox-gtk-theme.package exposes no themeNames; set gtkThemeName explicitly.";
      }
      {
        assertion = cfg.gtkThemeName == null || lib.elem cfg.gtkThemeName themeNames;
        message = "programs.gruvbox-gtk-theme.gtkThemeName is ${toString cfg.gtkThemeName}, which this package does not build. It builds: ${lib.concatStringsSep ", " themeNames}.";
      }
      {
        assertion = !cfg.iconTheme.enable || cfg.iconThemeName == null || lib.elem cfg.iconThemeName iconThemeNames;
        message = "programs.gruvbox-gtk-theme.iconThemeName is ${toString cfg.iconThemeName}, which this package does not ship. It ships: ${lib.concatStringsSep ", " iconThemeNames}.";
      }
    ];

    # gnome-themes-extra supplies the GTK2 adwaita engine that the theme's
    # gtk-2.0 rc files load. Without it GTK2 apps fall back to unstyled
    # widgets.
    home.packages = [ cfg.package pkgs.gnome-themes-extra ]
      ++ lib.optional cfg.iconTheme.enable cfg.iconTheme.package;

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
