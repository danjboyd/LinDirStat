# Packaging

LinDirStat uses `~/git/gnustep/gnustep-packager` for packaging and distribution.

The downstream package contract lives in:

`package.manifest.json`

Current packaging scope:

- Linux packaging uses the `appimage` backend.
- Windows MSI is disabled for this project unless explicitly revisited.
- macOS packaging is planned, but `gnustep-packager` does not currently have a macOS target.

## Linux AppImage

### Requirements

- `pwsh` (PowerShell 7) for the packager, plus `readelf`, `ldd`, `strip`,
  `dpkg` and `python3` (the stage script uses them).
- `gnustep-packager` with AppImage support for apps without file
  associations: branch `appimage-no-associations` (see
  `docs/gnustep-packager-upstream-requests.md`) until it is merged.
- The build inputs the stage script copies from, each overridable by an
  environment variable:
  - `GNUSTEP_CLI_ROOT`: the `gnustep-cli-new` install
    (default `~/.local/share/gnustep-cli`): GNUstep base, gui, back,
    resources, `libobjc2`, `libdispatch`, and the `defaults`, `gpbs`, `gdnc`
    tools.
  - `OPENSAVE_ROOT`: the `libs-OpenSave` build
    (default `~/git/gnustep/libs-OpenSave`, library in `Source/obj`).
  - `ADWAITA_THEME`: the built Adwaita GNUstep theme bundle
    (default `~/git/gnustep/plugins-themes-adwaita/Adwaita.theme`).

### Commands

From the repository root:

```sh
PACKAGER=~/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1
pwsh $PACKAGER -Manifest package.manifest.json -Command manifest-check
pwsh $PACKAGER -Manifest package.manifest.json -Command build
pwsh $PACKAGER -Manifest package.manifest.json -Command stage
pwsh $PACKAGER -Manifest package.manifest.json -Command validate
pwsh $PACKAGER -Manifest package.manifest.json -Command package -Backend appimage
pwsh $PACKAGER -Manifest package.manifest.json -Command validate -Backend appimage -RunSmoke
```

or the whole sequence with
`pwsh ~/git/gnustep/gnustep-packager/scripts/run-packaging-pipeline.ps1 -Manifest package.manifest.json -Backend appimage -RunSmoke`.

`GlobalDefaults.plist` also carries what the Adwaita theme needs from settings
a GNOME user's GNUstep does not have yet, with the same `ifUnset` semantics:
`GSX11HandlesWindowDecorations = NO`, so the theme draws the header bar with
the title, window buttons and toolbar (the theme asks for this itself only
with a patched libs-gui; the bundled one is stock), and the key mapping that
makes Ctrl GNUstep's Command key (`GSFirstCommandKey = Control_L`, Control on
Alt, Alternate on Super), so shortcuts are Ctrl+… as in GNOME apps. Without
them the first AppImage build had no title, window buttons or Zoom In.

The AppImage lands at `dist/packages/LinDirStat-0.1.0-x86_64.AppImage` (about
29 MB), with
`.metadata.json` and `.diagnostics.txt` sidecars; logs go to `dist/logs` and
`dist/validation`. `dist/` is gitignored.

The `-RunSmoke` step launches the AppImage on `$DISPLAY`. Run it on a private
X server (`Xvfb :N`, `DISPLAY=:N`), not on a desktop someone is using.

`build` runs `scripts/package-build.sh` (the normal `gnustep-cli-new` build).
`stage` runs `scripts/package-stage.sh dist/stage`, which can also be run on
its own to inspect the payload.

### Payload

`scripts/package-stage.sh` produces the packager's stage layout:

| Path | Contents |
| --- | --- |
| `app/LinDirStat.app` | The app bundle, including `Resources/Info-gnustep.plist` and the toolbar icons |
| `runtime/lib` | Every shared library the app, the back bundle, the theme and the tools need, except host libraries (below) |
| `runtime/System/Library` | GNUstep resources (`Libraries/gnustep-base`, `Libraries/gnustep-gui`), `Bundles` (including `libgnustep-back-032.bundle`), `ColorPickers`, `Fonts`, `Images`, `KeyBindings`, `PostScript`, `Services`, `Sounds`, and `Themes/Adwaita.theme` |
| `runtime/bin` | `defaults`, `gpbs`, `gdnc` |
| `runtime/etc/GNUstep` | `GNUstep.conf` and `GlobalDefaults.plist` |
| `metadata/icons/lindirstat.png` | The 256x256 app icon (`packaging/linux/lindirstat.png`, drawn by `scripts/make-linux-icon.py`) |
| `metadata/licenses` | Notices for LinDirStat and each bundled component, `host-libraries.txt` and the Debian copyright files of bundled distribution libraries |

`scripts/stage-linux-runtime.py` builds `runtime/lib` by walking the `NEEDED`
entries of every ELF file in the payload, resolving each library first in the
`libs-OpenSave` build and the GNUstep install, then in the host linker cache.
It strips the staged copies and rewrites any `RUNPATH` that points outside the
payload (the app's link-time `libs-OpenSave` path) to `$ORIGIN/../../runtime/lib`.

Host libraries are not bundled: glibc, `libstdc++`/`libgcc_s`, X11/xcb/GL/
Vulkan/Wayland, fontconfig/freetype/harfbuzz/cairo/pango, GTK 4 and GLib
(used by `libs-OpenSave` and the Adwaita theme), and a few ubiquitous
compression and system libraries (`libz`, `libzstd`, `liblzma`, `libffi`,
`libdbus-1`, ...). The list is `HOST_LIBRARIES` in
`scripts/stage-linux-runtime.py`. The AppImage therefore needs a desktop with
GTK 4 and a glibc at least as new as the build host's (Debian 13 builds
need glibc 2.41).

### Launch environment

The packager renders `launch.env` into the AppImage's `AppRun`:

- `GNUSTEP_CONFIG_FILE={@runtimeRoot}/etc/GNUstep/GNUstep.conf`. The staged
  `GNUstep.conf` uses paths relative to itself (gnustep-base resolves `./`
  and `../` against the config file's directory), so every GNUstep domain
  except the user's resolves inside the AppImage mount. The user domain stays
  `~/GNUstep` and the defaults stay in `~/GNUstep/Defaults`.
- `LD_LIBRARY_PATH={@runtimeRoot}/lib`. Most toolchain libraries have no
  `RUNPATH` to rewrite, so the loader needs the path. It is inherited by
  processes LinDirStat starts (open, terminal, cleanups); the bundled
  libraries are the same sonames the host would load.
- `GSTheme=Adwaita` with `ifUnset`, as AGENTS.md asks.

GNUstep reads `GSTheme` only from defaults, never from the environment, so
the theme default that takes effect is `runtime/etc/GNUstep/GlobalDefaults.plist`
(`GSTheme = Adwaita`). gnustep-base ranks it below the user's own
`NSGlobalDomain` and app defaults, which keeps the `ifUnset` semantics: a theme
the user chose still wins. The manifest does not use
`packagedDefaults.defaultTheme`; that seeds `GSTheme` into the
`package.id` defaults domain, which is not the domain GNUstep reads (see
`docs/gnustep-packager-upstream-requests.md`).

A theme in the user's `~/GNUstep/Library/Themes` with the same name takes
precedence over the bundled one, as in any GNUstep install.

### Validation

`validation.smoke.requiredPaths` covers the app, the `Info-gnustep.plist`,
icon, notices, tools, `GNUstep.conf`, `GlobalDefaults.plist`,
`libOpenSave.so.0`, the back bundle and the Adwaita theme. The package and
installed-result contracts require the bundled Adwaita theme and the notice
report. `backends.appimage.validation.runtimeClosure` is `strict`: every ELF
in the extracted AppImage must resolve its libraries and carry no `RUNPATH`
outside the AppImage.

Checks run on the staged payload on 2026-10-09 (Debian 13, private Xvfb):

- every ELF under `dist/stage` resolves with `LD_LIBRARY_PATH=dist/stage/runtime/lib`;
  nothing resolves into `~/.local/share/gnustep-cli`, `~/git/gnustep` or
  `~/GNUstep`, and no `RUNPATH` points outside the payload;
- launched with the `AppRun` environment and an empty GNUstep home
  (`GNUSTEP_HOME`), the app starts, loads
  `runtime/System/Library/Themes/Adwaita.theme` (Adwaita header bar and menu),
  scans `LINDIRSTAT_SCAN_PATH`, and maps no library from the build machine.

The `package -Backend appimage` and `validate -Backend appimage` steps have
not been run yet: the session that set this up could not run `pwsh`. Record
the artifact size and the strict runtime-closure result here after the first
run.

Note for screenshot runs: gnustep-base does not read
`GNUSTEP_USER_DEFAULTS_DIR` from the environment, only from `GNUstep.conf`.
To keep test runs out of the real `~/GNUstep/Defaults`, set `GNUSTEP_HOME` to
a scratch directory.

## macOS Packaging Direction

The intended macOS distribution shape is a native macOS `.dmg` installer or disk image built around Apple's frameworks and app bundle conventions.

Do not add ad hoc macOS DMG scripts directly to LinDirStat. The packaging path should mature in `gnustep-packager` first, then LinDirStat should enable the macOS backend in its manifest once that backend exists.

Expected future `gnustep-packager` capabilities:

- a macOS backend, likely named `dmg` or `macos-dmg`
- native `.app` bundle staging rules
- DMG layout configuration
- code signing and notarization hooks
- validation for bundle metadata, launch behavior, signing state, and packaged defaults

Until that exists, keep macOS packaging requirements documented here and keep the manifest valid against the currently supported packager schema.
