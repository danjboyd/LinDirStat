# Development

Use the local GNUstep CLI worktree for project operations:

```sh
python3 ~/git/gnustep/gnustep-cli-new/scripts/internal/build.py --json .
python3 ~/git/gnustep/gnustep-cli-new/scripts/internal/run.py --json .
```

The project was initially scaffolded from the `gui-app` template in `~/git/gnustep/gnustep-cli-new`.

Run Objective-C unit tests with GNUstep's `tools-xctest` support:

```sh
. ~/git/gnustep/gnustep-cli-new/scripts/dev/activate-tools-xctest.sh
make -C Tests
```

If `tools-xctest` is being used from a local checkout instead of an installed prefix, pass its root explicitly:

```sh
GNUSTEP_MAKEFILES_DIR=~/.local/share/gnustep-cli/System/Library/Makefiles \
TOOLS_XCTEST_ROOT=~/git/Arlen/vendor/tools-xctest \
make -C Tests
```

Run the compiled test bundle with:

```sh
. ~/.local/share/gnustep-cli/System/Library/Makefiles/GNUstep.sh
LD_LIBRARY_PATH=~/git/Arlen/vendor/tools-xctest/XCTest/obj:${LD_LIBRARY_PATH:-} \
~/git/Arlen/vendor/tools-xctest/obj/xctest Tests/LinDirStatTests.bundle
```

The first fixture-backed scanner tests live under `Tests/Fixtures/basic-tree`.

Phase 4-6 coverage currently includes:

- deterministic treemap layout and point lookup
- stable extension color selection
- directory and extension list data sourced from scan results
- safe reveal/open/trash/permanent-delete action planning

## Packaging

Packaging and distribution use `~/git/gnustep/gnustep-packager`.

Validate the manifest:

```sh
pwsh ~/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Manifest package.manifest.json -Command manifest-check
```

Build and stage through the packager contract:

```sh
pwsh ~/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Manifest package.manifest.json -Command build
pwsh ~/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Manifest package.manifest.json -Command stage
pwsh ~/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Manifest package.manifest.json -Command validate
```

Linux distribution uses the AppImage backend:

```sh
pwsh ~/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Manifest package.manifest.json -Command package -Backend appimage
pwsh ~/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1 -Manifest package.manifest.json -Command validate -Backend appimage -RunSmoke
```

The staged payload, its inputs, the smoke-test display, and the theme default
are described in `docs/packaging.md`.

macOS packaging is intentionally not enabled yet. `gnustep-packager` needs a native DMG-style backend first; see `docs/packaging.md`.

## Adwaita window shadow and rounded corners

The Adwaita theme draws GNOME's window shadow and rounded corners only when
libs-back carries the theme's patches (`Docs/upstream-patches/` in
`~/git/gnustep/plugins-themes-adwaita`). Stock libs-back gives square corners
and no shadow; nothing in LinDirStat controls this.

On this machine the patched backend from `~/git/gnustep/libs-back-series`
(branch `ai-policy/csd-series`) is installed into the `gnustep-cli` prefix:

```sh
. ~/.local/share/gnustep-cli/System/Library/Makefiles/GNUstep.sh
./configure && make && make install GNUSTEP_INSTALLATION_DOMAIN=LOCAL
```

The stock bundle was kept at
`~/.local/share/gnustep-cli/Local/Library/libgnustep-back-032.stock-backup-20261008`.
With the patched backend, window screenshots include the transparent shadow
margin (the window grows by about 30px each way).

## GUI review on a private display

Run GUI checks on a private X server so synthetic input never reaches the
desktop you are working on, and with private defaults so test runs do not
change your LinDirStat settings:

```sh
Xvfb :77 -screen 0 1600x1000x24 &
DISPLAY=:77 DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent XDG_DATA_HOME=/tmp/ld-data \
  LINDIRSTAT_SCAN_PATH=/usr/share/doc scripts/run-isolated.sh /tmp/ld-gnustep-home &
DISPLAY=:77 import -window root /tmp/ld-review.png
```

- `scripts/run-isolated.sh` gives the app its own GNUstep home (defaults),
  seeded with your global domain and linked to your `~/GNUstep/Library` for
  the theme. Neither `$HOME` nor `GNUSTEP_USER_DEFAULTS_DIR` isolates
  gnustep-base (it takes the home from the user database and ignores that
  variable), and `openapp`'s `GNUstep.sh` unsets `GNUSTEP_HOME`, so the script
  sets it again in a wrapper just before the app runs. For processes started
  directly (xctest, the command-line binary, `defaults`), export
  `GNUSTEP_HOME` after sourcing `GNUstep.sh`; `scripts/run-tests.sh` and
  `scripts/test-command-line.sh` do. Check that the mtimes of
  `~/GNUstep/Defaults/*.plist` do not change across a run.
- `XDG_DATA_HOME` gives trash tests their own trash folder.
- The dead D-Bus address keeps the file chooser portal and the file manager
  from opening on your desktop.
- There is no window manager: find windows with `xwininfo -root -tree`, not
  `xdotool search --pid`.
- Drive clicks with `xdotool mousedown`, a short sleep, then `mouseup`;
  instant synthetic clicks are taken as range selections by GNUstep tables.
- For the dark style, point GSettings at a private keyfile:
  `GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME=/tmp/ld-config`, with
  `/tmp/ld-config/glib-2.0/settings/keyfile` containing
  `[org/gnome/desktop/interface]` and `color-scheme='prefer-dark'`.
