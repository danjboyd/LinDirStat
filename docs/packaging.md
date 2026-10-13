# Packaging

LinDirStat uses `~/git/gnustep/gnustep-packager` for packaging and distribution.

The downstream package contract lives in:

`package.manifest.json`

Current packaging scope:

- Linux packaging uses the `appimage` backend.
- Windows MSI is disabled for this project unless explicitly revisited.
- macOS packaging uses the `dmg` backend (native AppKit build, see "macOS DMG" below).

## Linux AppImage

### Requirements

- `pwsh` (PowerShell 7) for the packager, plus `readelf`, `ldd`, `strip`,
  `dpkg` and `python3` (the stage script uses them).
- `gnustep-packager` `main` (AppImage support for apps without file
  associations landed in #8; see `docs/gnustep-packager-upstream-requests.md`).
- The build inputs the stage script copies from, each overridable by an
  environment variable:
  - `LINDIRSTAT_GNUSTEP_ROOT`: the GNUstep install (default `/usr/GNUstep`,
    the gnustep-clang apt packages; see `docs/development.md`): GNUstep base,
    gui, back and their resources, `libobjc2`, `libdispatch`, and the
    `defaults`, `gpbs`, `gdnc` and `make_services` tools.
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
74 MB with the gnustep-clang packages, whose libgnustep-gui links FFmpeg,
ImageMagick, libsndfile, libao and aspell, all bundled; 29 MB with
gnustep-cli-new's leaner libs-gui), with
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
GTK 4 and a glibc new enough for the newest symbol versions the payload uses,
which is not the build host's glibc version: v0.1.0, built on Debian 13
(glibc 2.41), needs glibc 2.38 or newer (`GLIBC_2.38` from the app and from
staged Debian libraries such as `libxml2`). Check a new build with
`objdump -T` over the extracted AppImage's ELF files.

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
  nothing resolves into the GNUstep install, `~/git/gnustep` or
  `~/GNUstep`, and no `RUNPATH` points outside the payload;
- launched with the `AppRun` environment and an empty GNUstep home
  (`GNUSTEP_HOME`), the app starts, loads
  `runtime/System/Library/Themes/Adwaita.theme` (Adwaita header bar and menu),
  scans `LINDIRSTAT_SCAN_PATH`, and maps no library from the build machine.

`package -Backend appimage` and `validate -Backend appimage -RunSmoke`
(strict runtime closure) pass with gnustep-packager `3e487ab` (checked
2026-10-12, Debian 13, private Xvfb); the AppImage is about 29 MB.

### Updates

The AppImage updates itself: the manifest's `updates` settings, the update
configuration and feed packaging writes, the signing key and the release
script are described in [updates.md](updates.md).

Note for screenshot runs: gnustep-base does not read
`GNUSTEP_USER_DEFAULTS_DIR` from the environment, only from `GNUstep.conf`.
To keep test runs out of the real `~/GNUstep/Defaults`, set `GNUSTEP_HOME` to
a scratch directory.

## macOS DMG

The macOS app is the native AppKit build (`make -C macos`, see
[macos.md](macos.md)), not a GNUstep runtime payload. `package.manifest.json`
describes it in `platformOverrides.macos`, which gnustep-packager merges over
the manifest whenever the target platform is macOS (on a Mac, or with
`-Backend dmg`): it swaps the pipeline commands, entry path, validation paths
and notices, drops the `gnustep-gui` profile, and removes the GNUstep launch
environment, which a native bundle does not use. The Linux view of the
manifest is unchanged.

There is no DMG script in this repository: the image is built by
gnustep-packager's `dmg` backend from the staged bundle.

### Requirements

- macOS 13 or later with Xcode or the Command Line Tools, and `pwsh`.
- gnustep-packager `main` (the `dmg` backend landed in #10).
- For the Finder window layout (app on the left, Applications on the right):
  a logged-in desktop session where the terminal may control Finder (System
  Settings › Privacy & Security › Automation). Without it the layout is
  skipped with a log line and the DMG opens in Finder's default window.

### Commands

From the repository root on a Mac:

```sh
PACKAGER=~/git/gnustep/gnustep-packager/scripts/gnustep-packager.ps1
pwsh $PACKAGER -Manifest package.manifest.json -Command manifest-check
pwsh $PACKAGER -Manifest package.manifest.json -Command build      # make -C macos
pwsh $PACKAGER -Manifest package.manifest.json -Command stage      # scripts/package-stage-macos.sh dist/stage
pwsh $PACKAGER -Manifest package.manifest.json -Command validate
pwsh $PACKAGER -Manifest package.manifest.json -Command package -Backend dmg
pwsh $PACKAGER -Manifest package.manifest.json -Command validate -Backend dmg -RunSmoke
```

or the whole sequence:
`pwsh ~/git/gnustep/gnustep-packager/scripts/run-packaging-pipeline.ps1 -Manifest package.manifest.json -Backend dmg -RunSmoke`.

To check the Linux view of the manifest from a Mac:
`pwsh $PACKAGER -Manifest package.manifest.json -Command manifest-check -Platform linux`.

### Payload and image

`scripts/package-stage-macos.sh dist/stage` builds the app if needed,
verifies its signature, and stages:

| Path | Contents |
| --- | --- |
| `app/LinDirStat.app` | The universal (arm64 + x86_64), ad-hoc signed bundle from `macos/build`, copied with `ditto` |
| `runtime/` | Empty: the bundle links only Apple frameworks |
| `metadata/licenses` | `LinDirStat.txt` (with `COPYING` when present) and `WinDirStat-reference.txt` |

The package step writes `dist/packages/LinDirStat-0.1.0-macos-universal.dmg`
(about 1.9 MB) with `.metadata.json` and `.diagnostics.txt` sidecars. The
volume `LinDirStat` holds `LinDirStat.app`, an `Applications` link and
`THIRD-PARTY-NOTICES.txt` (both notices, with their text).

`backends.dmg` settings:

- `signing.identity` is `-` (ad-hoc) and `signing.resign` is `false`: the
  image keeps the signature `make -C macos` gave the app (hardened runtime,
  `macos/LinDirStat.entitlements`). `signing.entitlementsPath` already points
  at that file for a later re-sign with a real identity.
- `notarization.enabled` is `false`. The keychain profile would come from the
  `LINDIRSTAT_NOTARY_PROFILE` environment variable; the manifest never holds
  credentials.
- The launch smoke (`-RunSmoke`) starts the app from the mounted image for
  8 seconds with `LINDIRSTAT_SCAN_PATH=/usr/share/zoneinfo`, then kills it.
  The window appears on screen while it runs.

### Validation

`validate -Backend dmg` runs `hdiutil verify`, mounts the image read-only
and hidden from Finder, checks the bundle, the `Applications` link and the
notice report, runs `codesign --verify --deep --strict` on the mounted app,
records the Gatekeeper assessment, runs the smoke launch, and detaches.
Gatekeeper rejects an ad-hoc signed app (`spctl` "rejected"); that is
recorded, not a failure. Downloaded copies need the first-launch steps in
[macos.md](macos.md#signing-without-a-developer-id).

Run on 2026-10-09 (macOS 26.5, Apple Silicon, Xcode 26.4): every check
passed; Finder layout applied; Gatekeeper rejected (ad-hoc, expected); the app
stayed running through the smoke window from the mounted image.

### With a Developer ID later

Set `backends.dmg.signing.identity` to the Developer ID Application identity
and `signing.resign` to `true` (or pass `SIGN_ID` to the build), store notary
credentials with `xcrun notarytool store-credentials <profile>`, export
`LINDIRSTAT_NOTARY_PROFILE=<profile>`, and set `notarization.enabled` to
`true`. See gnustep-packager's `docs/dmg-backend.md`.
