# A throwaway NixOS VM that boots Plasma 6, applies this theme, drives the
# session with xdotool and asserts on what is actually on screen.
#
# Deliberately NOT part of `nix flake check`: it builds a full KDE desktop and
# boots it, which is minutes and gigabytes. Run it explicitly:
#
#   nix run .#vm-test              headless, asserts, writes screenshots
#   nix run .#vm-test-interactive  opens a window you can poke at
#
# Screenshots land in the test's $out, and the runner prints the path.
#
# What this can prove, and what it cannot: a pixel assertion on the titlebar
# proves the colour scheme reached kwin. It does NOT by itself prove the
# Aurorae decoration is active, because a Breeze titlebar under the same
# colour scheme is the same colour. Proving the decoration changed needs the
# before/after comparison below.
#
# GPU: `nix build` runs in a sandbox with no /dev/dri, so a build of this test
# can only ever use llvmpipe, however capable the host is. Verified: the host
# here exposes /dev/dri/card1 and renderD128, and a probe derivation inside
# the sandbox sees neither.
#
# So there are two ways to run it:
#
#   nix build .#vm-test        sandboxed, software GL, reproducible, CI-safe
#   nix run  .#vm-test-gpu     outside the sandbox, real GPU via virtio-gpu-gl
#
# The GPU path passes the host's renderer through with `-device
# virtio-gpu-gl-pci -display egl-headless,gl=core`, both confirmed present in
# qemu 11.0.3.
{ pkgs
, self
, system
, gpu ? false
}:

let
  colorSchemes = self.packages.${system}.gruvbox-kde-color-schemes;

  # Tasks 7 to 11 of the plan add this. Until they land, the decoration
  # subtests are skipped rather than silently passing.
  hasAurorae = self.packages.${system} ? gruvbox-kde-aurorae;
  aurorae = self.packages.${system}.gruvbox-kde-aurorae or null;

  scheme = "Gruvbox-Dark-Hard";
  auroraeTheme = "Gruvbox-Dark";

  # $background for the dark hard palette, which both [WM] activeBackground
  # and [Colors:Window] BackgroundNormal resolve to. Verified against the
  # generated scheme and against the GTK theme's @define-color theme_bg_color.
  expectedTitlebar = "29,32,33";

  # These scripts run with an explicit PATH, so every tool they use has to be
  # listed here. The scripts are also the only place they are used, which is
  # why a missing entry shows up as "command not found" at runtime rather
  # than at build time.
  toolPath = pkgs.lib.makeBinPath [
    pkgs.xdotool
    pkgs.xprop
    pkgs.imagemagick
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
  ];

  # Prints "X Y WIDTH HEIGHT TOP" for the managed toplevel matching $1.
  #
  # Two things here are load-bearing and were both learned the hard way.
  #
  # First, `xdotool search --name` returns every window whose name matches,
  # including unmapped and non-toplevel ones. Taking the first is a coin
  # flip. Activating the match and then asking the root window which window
  # is active yields the window kwin actually manages, which is the only one
  # carrying frame extents.
  #
  # Second, when the property is absent xprop prints "_NET_FRAME_EXTENTS:
  # not found." rather than failing. Feeding that through sed and cut leaves
  # a non-numeric string that only explodes later, inside an arithmetic
  # expansion, as an "unbound variable" error pointing at the wrong line.
  # Validate it here, where the message can say what actually went wrong.
  windowGeometry = pkgs.writeShellScript "window-geometry" ''
    set -Eeuo pipefail
    export PATH=${toolPath}
    export DISPLAY=:0.0

    # Walk _NET_CLIENT_LIST rather than searching by name.
    #
    # This is the difference between working and not. A client creates
    # several X windows, and the one carrying a matching WM_NAME is not
    # necessarily the one the window manager manages. Measured in this VM:
    # `xdotool search --name Konsole` returns 44040197 ("Qt Selection Owner
    # for konsole") and 44040202, while _NET_CLIENT_LIST names 44040200 as
    # the managed toplevel. Only 44040200 carries _NET_FRAME_EXTENTS, and
    # the name search never returns it.
    #
    # _NET_CLIENT_LIST is the authoritative EWMH list of managed toplevels,
    # so match names within it instead.
    clients=$(xprop -root _NET_CLIENT_LIST 2>/dev/null \
      | sed 's/.*# //' | tr -d ' ' | tr ',' '\n' | grep -v '^$' || true)
    if [ -z "$clients" ]; then
      echo "window-geometry: _NET_CLIENT_LIST is empty; no window manager?" >&2
      exit 1
    fi

    win=""
    for id in $clients; do
      dec=$(printf '%d' "$id" 2>/dev/null || echo "")
      [ -n "$dec" ] || continue
      name=$(xdotool getwindowname "$dec" 2>/dev/null || true)
      case "$name" in
        *"$1"*) win="$dec"; break ;;
      esac
    done

    if [ -z "$win" ]; then
      echo "window-geometry: no managed window whose title contains '$1'" >&2
      for id in $clients; do
        dec=$(printf '%d' "$id" 2>/dev/null || echo "?")
        name=$(xdotool getwindowname "$dec" 2>/dev/null || echo "<no name>")
        echo "  managed $id ($dec): $name" >&2
      done
      exit 1
    fi

    extents=$(xprop -id "$win" _NET_FRAME_EXTENTS 2>&1 || true)
    case "$extents" in
      "" | *"not found"* | *"no such"*)
        echo "window-geometry: managed window $win has no _NET_FRAME_EXTENTS" >&2
        echo "  xprop said: $extents" >&2
        exit 1
        ;;
    esac

    xdotool windowactivate --sync "$win" 2>/dev/null || true
    eval "$(xdotool getwindowgeometry --shell "$win")"

    top=$(printf '%s' "$extents" | sed 's/.*= //' | tr -d ' ' | cut -d, -f3)
    case "$top" in
      "" | *[!0-9]*)
        echo "window-geometry: unparseable frame extents for '$1': $extents" >&2
        exit 1
        ;;
    esac
    if [ "$top" -eq 0 ]; then
      echo "window-geometry: '$1' has a zero-height titlebar" >&2
      exit 1
    fi

    printf '%s %s %s %s %s\n' "$X" "$Y" "$WIDTH" "$HEIGHT" "$top"
  '';

  # Reads the dominant colour of a window's titlebar.
  #
  # Not a single pixel. The title text is centred in the titlebar, so
  # sampling the midpoint reads the glyph rather than the background: this
  # test passed once and then reported 0,0,0 on the next run with no code
  # change, because the sample landed on a letter. Taking the most frequent
  # colour across the whole strip is stable against text, button glyphs and
  # the one-pixel border.
  sampleTitlebar = pkgs.writeShellScript "sample-titlebar" ''
    set -Eeuo pipefail
    export PATH=${toolPath}
    export DISPLAY=:0.0

    read -r X Y WIDTH HEIGHT TOP < <(${windowGeometry} "$1")

    import -window root -silent /tmp/sample.png
    magick /tmp/sample.png \
      -crop "''${WIDTH}x''${TOP}+''${X}+$(( Y - TOP ))" +repage \
      /tmp/sample-strip.png

    # histogram:info: lines look like "  12345: (29,32,33) #1D2021 srgb(...)".
    # The largest count is the background.
    #
    # awk rather than `head -1`: head closes the pipe as soon as it has its
    # line, sort takes SIGPIPE, and under `set -o pipefail` that turns a
    # correct answer into exit 2. awk drains the stream instead.
    magick /tmp/sample-strip.png -format %c histogram:info:- \
      | sort -rn \
      | awk 'NR == 1 { sub(/^ +/, ""); print }'
  '';

  # Saves the titlebar strip of a window, so two decorations can be compared
  # as images rather than by eye.
  cropTitlebar = pkgs.writeShellScript "crop-titlebar" ''
    set -Eeuo pipefail
    export PATH=${toolPath}
    export DISPLAY=:0.0

    read -r X Y WIDTH HEIGHT TOP < <(${windowGeometry} "$1")

    import -window root -silent /tmp/full.png
    magick /tmp/full.png -crop "''${WIDTH}x''${TOP}+''${X}+$(( Y - TOP ))" \
      +repage "$2"
  '';
in

pkgs.testers.runNixOSTest {
  name = "gruvbox-kde";

  nodes.machine = { ... }: {
    imports = [ ];

    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
      password = "alice";
      extraGroups = [ "wheel" ];
    };

    services.xserver.enable = true;
    services.displayManager.plasma-login-manager.enable = true;
    # X11 rather than Wayland on purpose: xdotool can address windows and
    # synthesise input there, which is what makes the mouse half of this
    # test possible at all.
    services.displayManager.defaultSession = "plasmax11";
    services.desktopManager.plasma6.enable = true;
    services.displayManager.autoLogin = {
      enable = true;
      user = "alice";
    };

    environment.systemPackages = [
      colorSchemes
      pkgs.xdotool
      pkgs.imagemagick
      pkgs.xprop
      pkgs.dbus
      pkgs.kdePackages.kconfig
      pkgs.kdePackages.plasma-workspace
    ] ++ pkgs.lib.optional hasAurorae aurorae;

    # There is no GPU in this VM, and kwin exits rather than run without a
    # compositor, which leaves every window unmanaged and undecorated: no
    # _NET_FRAME_EXTENTS at all.
    #
    # Give it OpenGL through llvmpipe rather than trying to select a
    # different compositor. KWIN_COMPOSE=Q asks for the QPainter backend,
    # which KWin 6 removed, and kwin responds by exiting with
    # "Could not fulfill the requested compositing mode". Do not set it.
    hardware.graphics.enable = true;

    # Only force software GL when there is genuinely no GPU to use. Setting
    # LIBGL_ALWAYS_SOFTWARE alongside virtio-gpu-gl would throw away the
    # passthrough the GPU mode exists to provide.
    environment.variables = pkgs.lib.optionalAttrs (!gpu) {
      LIBGL_ALWAYS_SOFTWARE = "1";
      QT_QUICK_BACKEND = "software";
    };

    virtualisation = {
      memorySize = 4096;
      cores = 2;
      diskSize = 8192;
      qemu = {
        options =
          if gpu then [
            "-device virtio-gpu-gl-pci"
            "-display egl-headless,rendernode=/dev/dri/renderD128"
          ] else [
            "-vga std"
          ];
      }
      # The test framework already pins qemu_test, a stripped build with no
      # EGL support that rejects `-display egl-headless` outright, so this
      # has to override rather than merely set it. Left untouched in
      # software mode so the sandboxed run keeps the framework's default.
      // pkgs.lib.optionalAttrs gpu {
        package = pkgs.lib.mkForce pkgs.qemu;
      };
    };
  };

  testScript = ''
    import re

    SCHEME = "${scheme}"
    AURORAE_THEME = "${auroraeTheme}"
    EXPECTED = "${expectedTitlebar}"
    HAS_AURORAE = ${if hasAurorae then "True" else "False"}


    def as_user(cmd):
        """Run a command in alice's session with DISPLAY set."""
        return machine.succeed(
            f"su - alice -c 'DISPLAY=:0.0 DBUS_SESSION_BUS_ADDRESS="
            f"unix:path=/run/user/1000/bus {cmd}'"
        )


    def rgb_of(pixel):
        """srgb(29,32,33) or #1D2021 -> '29,32,33'."""
        m = re.search(r"\((\d+),(\d+),(\d+)", pixel)
        if m:
            return ",".join(m.groups())
        m = re.search(r"#([0-9A-Fa-f]{6})", pixel)
        if m:
            h = m.group(1)
            return ",".join(str(int(h[i:i + 2], 16)) for i in (0, 2, 4))
        raise Exception(f"cannot parse pixel value: {pixel!r}")


    with subtest("Boot into a Plasma session"):
        start_all()
        machine.wait_for_file("/run/user/1000/xauth_*")
        machine.wait_until_succeeds("test -s /run/user/1000/xauth_*")
        machine.succeed("xauth merge /run/user/1000/xauth_*")
        machine.succeed("su - alice -c 'xauth merge /run/user/1000/xauth_*'")
        machine.wait_until_succeeds("pgrep plasmashell")
        machine.wait_for_window("^Desktop ")

    with subtest("The colour schemes are installed where KDE looks"):
        machine.succeed(
            f"test -f /run/current-system/sw/share/color-schemes/{SCHEME}.colors"
        )
        # 13 sections and no leaked alpha, asserted on the file KDE will read
        # rather than on the one the build produced.
        sections = machine.succeed(
            f"grep -c '^\\[' /run/current-system/sw/share/color-schemes/{SCHEME}.colors"
        ).strip()
        assert sections == "13", f"expected 13 INI sections, found {sections}"
        machine.fail(
            f"grep -qE 'rgba|#[0-9a-fA-F]{{3}}' "
            f"/run/current-system/sw/share/color-schemes/{SCHEME}.colors"
        )

    def geometry(name):
        """(x, y, width, height, titlebar_height) for a managed toplevel."""
        out = machine.succeed(f"${windowGeometry} {name}").split()
        return tuple(int(v) for v in out)


    with subtest("Open a window and record the stock decoration"):
        machine.execute("su - alice -c 'DISPLAY=:0.0 konsole >&2 &'")
        machine.wait_for_window("Konsole")

        def survey():
            """Everything that has ever gone wrong here, in one dump.

            wait_until_succeeds swallows the output of failing attempts, so
            without this a failure reports only a timeout and says nothing
            about which of the compositor, the client or the window
            selection is at fault.
            """
            print("=== session survey ===")
            for label, cmd in [
                ("konsole procs", "pgrep -a konsole || echo NONE"),
                ("kwin procs", "pgrep -a kwin || echo NONE"),
                ("plasmashell", "pgrep -a plasmashell || echo NONE"),
                ("wm check", "xprop -root _NET_SUPPORTING_WM_CHECK || echo NONE"),
                ("client list", "xprop -root _NET_CLIENT_LIST || echo NONE"),
            ]:
                print(f"  {label}: {machine.execute(cmd)[1].strip()}")

            print("  managed windows and their frame extents:")
            clients = machine.execute(
                "xprop -root _NET_CLIENT_LIST | sed 's/.*# //' | tr -d ' ' "
                "| tr ',' '\\n'"
            )[1].split()
            for cid in clients[:15]:
                name = machine.execute(
                    f"xdotool getwindowname {cid} 2>/dev/null"
                )[1].strip()
                ext = machine.execute(
                    f"xprop -id {cid} _NET_FRAME_EXTENTS 2>/dev/null"
                )[1].strip()
                print(f"    {cid} {name!r} -> {ext}")

            status, out = machine.execute("${windowGeometry} Konsole 2>&1")
            print(f"  window-geometry exit={status}:\n{out}")

        # A window manager must be running and owning the EWMH check property
        # before any window can carry frame extents. Match on a substring:
        # Plasma 6.7 split the X11 session out of the kwin package, and the
        # binary is not necessarily called exactly "kwin_x11".
        machine.wait_until_succeeds("pgrep -f kwin", timeout=90)
        print("kwin processes: " + machine.succeed("pgrep -a kwin || true").strip())

        # wait_for_window returns as soon as the window exists, which can be
        # before kwin has decorated it and published _NET_FRAME_EXTENTS.
        # Poll the geometry helper instead of sleeping a guessed interval.
        # kwin can register with X and then exit seconds later, leaving a
        # stale _NET_SUPPORTING_WM_CHECK behind. Checking it is alive at the
        # moment we need decorations distinguishes "compositor died" from
        # "picked the wrong window", which look identical downstream.
        machine.succeed(
            "pgrep -f kwin >/dev/null || "
            "{ echo 'kwin exited after starting; see the journal for "
            "compositing errors' >&2; exit 1; }"
        )

        try:
            machine.wait_until_succeeds("${windowGeometry} Konsole", timeout=90)
        except Exception:
            survey()
            machine.execute(
                "journalctl -b --no-pager | grep -iE 'kwin' | tail -40 >&2 || true"
            )
            raise
        machine.screenshot("01-before-theme")
        machine.succeed("${cropTitlebar} Konsole /tmp/titlebar-stock.png")

    with subtest("Apply the colour scheme"):
        as_user(f"plasma-apply-colorscheme {SCHEME}")
        machine.sleep(5)
        machine.screenshot("02-colour-scheme-applied")

    with subtest("The titlebar is actually painted in the theme colour"):
        pixel = machine.succeed("${sampleTitlebar} Konsole").strip()
        got = rgb_of(pixel)
        assert got == EXPECTED, (
            f"titlebar is {got}, expected {EXPECTED}. "
            "The colour scheme did not reach kwin."
        )
        print(f"titlebar colour {got} matches the scheme")

    with subtest("Drive the mouse over the window controls"):
        # Same helper as the pixel sampling, so the two cannot disagree about
        # which window they are looking at.
        x, y, w, h, top = geometry("Konsole")

        # The close button is the rightmost control in the titlebar.
        close_x = x + w - 18
        close_y = y - top // 2

        as_user(f"xdotool mousemove {close_x} {close_y}")
        machine.sleep(2)
        machine.screenshot("03-hover-close-button")

        # Move to the middle button and press without releasing, to catch the
        # pressed state, then release outside so the window survives.
        as_user(f"xdotool mousemove {close_x - 36} {close_y} mousedown 1")
        machine.sleep(2)
        machine.screenshot("04-pressed-maximise-button")
        as_user(f"xdotool mousemove {x + w // 2} {y + 100} mouseup 1")
        machine.sleep(1)

        # Park the pointer away from the decoration so later screenshots are
        # not showing a hover state by accident.
        as_user(f"xdotool mousemove {x + w // 2} {y + 100}")

    with subtest("Keyboard drives the window menu"):
        # Send to the focused window rather than a captured id: the geometry
        # helper already activated it, and --window delivers synthetic events
        # that some clients ignore.
        as_user("xdotool key alt+F3")
        machine.sleep(2)
        machine.screenshot("05-window-menu")
        as_user("xdotool key Escape")
        machine.sleep(1)

    if HAS_AURORAE:
        with subtest("Apply the Aurorae decoration"):
            machine.succeed(
                f"test -d /run/current-system/sw/share/aurorae/themes/{AURORAE_THEME}"
            )
            # kwin 6.7 reads org.kde.kdecoration3; the 2 group is written too
            # so this keeps working either side of that rename.
            for group in ("org.kde.kdecoration2", "org.kde.kdecoration3"):
                as_user(
                    f"kwriteconfig6 --file kwinrc --group {group} "
                    f"--key library org.kde.kwin.aurorae"
                )
                as_user(
                    f"kwriteconfig6 --file kwinrc --group {group} "
                    f"--key theme __aurorae__svg__{AURORAE_THEME}"
                )
            as_user(
                "dbus-send --session --dest=org.kde.KWin --type=method_call "
                "/KWin org.kde.KWin.reconfigure"
            )
            machine.sleep(8)

        with subtest("kwin is configured for our decoration"):
            lib = as_user(
                "kreadconfig6 --file kwinrc --group org.kde.kdecoration3 --key library"
            ).strip()
            assert lib == "org.kde.kwin.aurorae", f"kwin decoration library is {lib!r}"
            theme = as_user(
                "kreadconfig6 --file kwinrc --group org.kde.kdecoration3 --key theme"
            ).strip()
            assert theme == f"__aurorae__svg__{AURORAE_THEME}", (
                f"kwin decoration theme is {theme!r}"
            )

        with subtest("The decoration actually changed on screen"):
            machine.screenshot("06-aurorae-applied")
            machine.succeed("${cropTitlebar} Konsole /tmp/titlebar-aurorae.png")
            # If the titlebar image is identical to the stock one, the
            # decoration did not take effect, whatever the config says.
            identical = machine.execute(
                "magick compare -metric AE /tmp/titlebar-stock.png "
                "/tmp/titlebar-aurorae.png null: 2>&1"
            )[1].strip()
            assert identical not in ("0", ""), (
                "the titlebar is pixel-identical before and after applying "
                "Aurorae, so the decoration is not active"
            )
            print(f"titlebar changed, {identical} differing pixels")

        with subtest("Aurorae titlebar still uses the theme colour"):
            pixel = machine.succeed("${sampleTitlebar} Konsole").strip()
            got = rgb_of(pixel)
            assert got == EXPECTED, (
                f"Aurorae titlebar is {got}, expected {EXPECTED}. "
                "The decoration is not following the colour scheme."
            )

        with subtest("Hover the Aurorae close button"):
            as_user(f"xdotool mousemove {close_x} {close_y}")
            machine.sleep(2)
            machine.screenshot("07-aurorae-hover-close")
    else:
        print(
            "SKIPPED: the Aurorae subtests. "
            "self.packages.<system>.gruvbox-kde-aurorae does not exist yet; "
            "it arrives with Tasks 7 to 11 of the plan."
        )

    with subtest("Collect a final desktop shot"):
        as_user("xdotool key super")
        machine.sleep(3)
        machine.screenshot("08-desktop")
  '';
}
