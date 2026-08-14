<h1 align="center">Gruvbox GTK Theme</h1>

<p align="center">
  <img alt"Linux Logo" src="https://img.shields.io/badge/OS-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=yelow"/>
  <img alt"CSS Log" src="https://img.shields.io/badge/Style-CSS-blue?style=for-the-badge&logo=css3&logoColor=blue"/>
  <img alt"GitHub Stars" src="https://img.shields.io/github/stars/Fausto-Korpsvart/Gruvbox-GTK-Theme?&style=for-the-badge&logoColor=red" />
  <img alt"GitHub Forks" src="https://img.shields.io/github/forks/Fausto-Korpsvart/Gruvbox-GTK-Theme?style=for-the-badge" />
  <img alt"GitHub Issues" src="https://img.shields.io/github/issues/Fausto-Korpsvart/Gruvbox-GTK-Theme?style=for-the-badge" />
  <img alt"GNU License" src='https://img.shields.io/github/license/Fausto-Korpsvart/Gruvbox-GTK-Theme?style=for-the-badge&logo=GNU&label=License&color=bd0000&logoColor=white'/>
</p>

A GTK theme based on the colours of [Sainnhe's](https://github.com/sainnhe) great theme: [Gruvbox Material for Neovim](https://github.com/sainnhe/gruvbox-material) <br>
the [VinceLiuice's](https://github.com/vinceliuice) Awesome GTK Themes and the creativity of [Gusbemacbe's](https://github.com/gusbemacbe): [Suru Plus Icon Theme](https://github.com/gusbemacbe/suru-plus).

![Gruvbox](https://raw.githubusercontent.com/Fausto-Korpsvart/Gruvbox-GTK-Theme/master/extra/screenshoots/Gruvbox.png)

> [!NOTE]
> The theme is more focused on the Gnome Desktop, but supports Cinnamon, XFCE, Mate, etc. with generic styles.
> It's great to combine in your TWMs like: XmonadWM, AwesomeWM, BSPWM, etc...

## ⚙️ Requirements

Before installing the themes, make sure to install the following necessary packages:
`sassc` and `gnome-themes-extra` packages for the correct rendering of themes.
The `gnome-themes-extra` package supplies the GTK2 `adwaita` engine used by the
GTK2 part of the theme; the rest of the GTK2 styling relies on the `pixmap`
engine that ships with GTK2 itself, so no extra theme engine is needed.

### Nix

This repository is a flake. Build the theme, or the icon themes, directly:

```sh
nix build github:MichaelPachec0/Gruvbox-GTK-Theme#gruvbox-gtk-theme
nix build github:MichaelPachec0/Gruvbox-GTK-Theme#gruvbox-icon-theme
```

To see every theme, color, size and tweak the flake accepts, along with the
directory name each combination installs as:

```sh
nix run github:MichaelPachec0/Gruvbox-GTK-Theme#list-variants
```

To use it from your own flake, add it as an input; the examples below assume
this input name:

```nix
inputs.gruvbox-gtk-theme.url = "github:MichaelPachec0/Gruvbox-GTK-Theme";
```

`overlays.default` adds `gruvbox-gtk-theme` and `gruvbox-icon-theme` to a
package set, which is the supported way to bring the plain attribute name
into scope for `.override`:

```nix
{
  nixpkgs.overlays = [ inputs.gruvbox-gtk-theme.overlays.default ];
}
```

With the overlay applied, pick variants with `.override`:

```nix
pkgs.gruvbox-gtk-theme.override {
  themeVariants = [ "green" ];
  colorVariants = [ "dark" ];
  tweaks = [ "outline" ];
}
```

With home-manager, import the flake's `homeManagerModules.default` and enable it:

```nix
{
  imports = [ inputs.gruvbox-gtk-theme.homeManagerModules.default ];

  programs.gruvbox-gtk-theme = {
    enable = true;
    themeVariants = [ "green" ];
    colorVariants = [ "dark" ];
    iconTheme.enable = true;
  };
}
```

The module installs `gnome-themes-extra` for you, since the GTK2 part of the
theme loads its `adwaita` engine. Set `gnomeShellVersion` if you run a GNOME
older than 48; the installer cannot detect your GNOME from inside the build
sandbox and otherwise builds shell styles for the newest version it knows.

`nix develop` opens a shell with `sassc` and `gnome-themes-extra` on `PATH`,
for running `themes/install.sh` by hand while working on the SCSS.

### KDE

`gruvbox-kde-color-schemes` generates `.colors` files for System Settings'
Colors page, from the same SCSS palette the GTK theme is built from.

```sh
nix build github:MichaelPachec0/Gruvbox-GTK-Theme#gruvbox-kde-color-schemes
```

The package *installs* schemes; it does not *select* one for you. After
building, or linking the output into `~/.local/share/color-schemes`, pick the
scheme from System Settings yourself, the same way you would for any manually
installed one.

Without Nix, `kde/install.sh` installs directly to
`~/.local/share/color-schemes`:

```sh
./kde/install.sh -t green -c dark --contrast hard
```

The contrast vocabulary is `hard`, `medium`, `soft`, `hard-black`,
`medium-black` and `soft-black`, with `black` accepted as a short alias for
`hard-black`. `hard` is this repository's default palette; the `-black`
states combine blackness with that palette rather than replacing it, so
`medium-black` is a distinct colour set from both `medium` and `hard-black`.

A colour scheme carries most of the visual result on KDE: Plasma resolves
`ColorScheme-*` classes inside its own widget SVGs at render time, so the
stock desktop theme restyles itself to match rather than needing replacement.

#### Window decorations (work in progress)

> [!WARNING]
> `gruvbox-kde-aurorae` is unfinished. It builds, installs and passes its
> checks, and has been confirmed rendering in a Plasma VM, but it has not
> been used on a real desktop for any length of time. Expect rough edges.

`gruvbox-kde-aurorae` generates Aurorae window decorations. It is a separate
package from the colour schemes because their variant axes do not overlap:
colour schemes vary by accent, colour and contrast, while decorations vary by
colour, frame and button style.

```sh
nix build github:MichaelPachec0/Gruvbox-GTK-Theme#gruvbox-kde-aurorae
./kde/install.sh --aurorae -c dark --frame outline --buttons macos
```

The artwork is extracted from this repository's own xfwm4 masters rather than
drawn: they already carry a nine-slice frame and per-state button glyphs under
named ids. Regenerate it with
`themes/src/assets/aurorae/make-aurorae.sh`, which needs Inkscape. The
committed SVGs are the build input, so ordinary builds do not.

Decorations have no contrast axis: the decoration follows whichever colour
scheme is active, so one covers every contrast level. Of the GTK theme's
tweaks, `outline` and `macos` carry over (`--frame outline` and
`--buttons macos`); `float` has no KDE equivalent at all.

Here are some commands to install on some distributions.

- On Fedora run:

```sh
 sudo dnf install sassc adwaita-gtk2-theme
```

- On OpenSUSE run:

```sh
 sudo zypper install sassc gtk2-theming-engine-adwaita
```

- On Arch run:

```sh
sudo pacman -S sassc gnome-themes-extra
```

- On Debian and derivatives run:

```sh
sudo apt install sassc gnome-themes-extra
```

## 📁 Manual Installation

- Download the [themes](https://www.pling.com/u/fkorpsvart) packs and extract them
- Move the extracted files to the following paths:
  - For GTK3: `~/.themes` In this path you must move the entire theme folder.
  - For GTK4: `~/.config/gtk-4.0` The files to move to this path can be found inside the theme directory in the `gtk-4.0` folder,
    copy only the `assets`, `gtk.css` and `gtk-dark.css` files or create a symlinks.

## 🔨 Applying the Theme

- For **GTK3**, apply themes from **Gnome Tweaks**, **Refine** or **Tuner**
- For GTK4 applications it is only necessary to have moved the `assets`, `gtk.css` and `gtk-dark.css` files to the `~/.config/gtk-4.0` path,
  and if you notice that the theme has not been applied, just close and reopen the application.

## 📦 Flatpak Compatibility

- Override flatpak themes to `~/.themes`:

```sh
sudo flatpak override --filesystem=$HOME/.themes
```

- Override flatpak icons to `~/.icons`:

```sh
sudo flatpak override --filesystem=$HOME/.icons
```

- Override flatpak themes to `~/.config/gtk-4.0` locally:

```sh
flatpak override --user --filesystem=xdg-config/gtk-4.0
```

- Override flatpak themes to `~/.config/gtk-4.0` globally:

```sh
sudo flatpak override --filesystem=xdg-config/gtk-4.0
```

> [!TIP]
> 💡 Use [stylepak](https://github.com/refi64/stylepak) for easier Flatpak theming.

## 🛠 CLI Installation

Run the following command in the terminal for a general installation

```sh
./install.sh
```

> The `./install.sh` allows some specific options like:

```sh
./install.sh --tweaks medium macos outline float -t green -l
```

> To customise the name of the theme, you can use the `-n` parameter, e.g.

```sh
./install.sh -n "Gruvbox-Float-Border" --tweaks outline float
```

> [!TIP]
> 🧾 For more information, run: `./install.sh --help`

### Options

```
-d, --dest DIR          Specify destination directory (Default: ~/.themes)

-n, --name NAME         Specify theme name (Default: Gruvbox)

-t, --theme VARIANT...  Specify theme accent color variant(s) [default|green|grey|orange|pink|purple|red|teal|yellow|all] (Default: blue)

-c, --color VARIANT...  Specify color variant(s) [light|dark] (Default: All variants)

-s, --size VARIANT...   Specify size variant [standard|compact] (Default: standard variant)

-l, --libadwaita        Link installed gtk-4.0 theme to config folder for all libadwaita app use this theme

-r, --remove,

-u, --uninstall         Uninstall/Remove installed themes or links

--tweaks                Specify versions for tweaks
                        1. [medium|soft]  Medium|Soft ColorSchemes version
                        2. black          Blackness color version
                        3. float          Floating gnome-shell panel style
                        4. outline        Windows with 2px outline style

-h, --help              Show help
```

## 🔠 Abbreviation Cheat Sheet

This is just to clarify doubts about the abbreviations of the Themes
| Abbreviation example | Explanation of abbreviations |
| -------------------- | ---------------------------- |
| Theme-Name-B-MB | `Bordered` Theme and window `macOS Buttons` |
| Theme-Name-B-LB | `Bordered` Theme and window `Legacy Buttons` |
| Theme-Name-B-GS | `Floating` and `Bordered` Theme for `Gnome Shell` |
| Theme-Name-BL-MB | `Borderless` Theme and window `macOS Buttons` |
| Theme-Name-BL-LB | `Borderless` Theme and window `Legacy Buttons` |
| Theme-Name-BL-GS | `Borderless` Theme decoration for `Gnome Shell` |

## 🔗 More Neovim-Inspired GTK Themes

| Neovim Colorschemes for GTK | GitHub | Pling |
| --------------------------- | ------ | ----- |
| Catppuccin GTK Theme | [Source](https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme) | [Package](https://www.pling.com/p/1715554/) |
| Everforest GTK Theme | [Source](https://github.com/Fausto-Korpsvart/Everforest-GTK-Theme) | [Package](https://www.pling.com/p/1695467/) |
| Gruvbox GTK Theme | [Source](https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme) | [Package](https://www.pling.com/p/1681313/) |
| Kanagawa GTK Theme | [Source](https://github.com/Fausto-Korpsvart/Kanagawa-GKT-Theme) | [Package](https://www.pling.com/p/1810560/) |
| Material GTK Theme | [Source](https://github.com/Fausto-Korpsvart/Material-GTK-Themes) | [Package](https://www.pling.com/p/1706139/) |
| Nightfox GTK Theme | [Source](https://github.com/Fausto-Korpsvart/Nightfox-GTK-Theme) | [Package](https://www.pling.com/p/1929101/) |
| Osaka GTK Theme | [Source](https://github.com/Fausto-Korpsvart/Osaka-GTK-Theme) | [Package](https://www.pling.com/p/2284009/) |
| Rose Pine GTK Theme | [Source](https://github.com/Fausto-Korpsvart/Rose-Pine-GTK-Theme) | [Package](https://www.pling.com/p/1810530/) |
| Tokyonight GTK Theme | [Source](https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme) | [Package](https://www.pling.com/p/1681315/) |

## Acknowledgements to

Thanks to [@telometto](https://github.com/telometto) for the alternative to the application of themes in `Flatpak.`<br>
Thanks to [@f1yn](https://github.com/f1yn) for the solution to the active and inactive borders in the new version of `Cinnamon.`<br>
Thanks to [@eeeXun](https://github.com/eeeXun) for the hint to solve the bug in `Mate Desktop` window control buttons.<br>
Thanks to [@Icy-Thought](https://github.com/Icy-Thought),[@D3vil0p3r](https://github.com/D3vil0p3r) and to those who have packaged these themes for NIX and AUR.

## Support

[![PayPal Support](https://img.shields.io/badge/Donate-PayPal-00457C?style=for-the-badge&logo=paypalColor=white)](https://www.paypal.com/donate/?hosted_button_id=LKVTXNA36FTV4)
