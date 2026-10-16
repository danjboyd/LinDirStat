# Updates

The Linux AppImage updates itself with gnustep-packager's updater
(`vendor/gnustep-packager-updater`). Other copies of the app do not: a build
run from the tree (`gnustep run`, `scripts/run-isolated.sh`, the tests) has
no update configuration, so it never checks, never offers updates and has no
**Check for Updates…** item; the macOS build has no updater.

## What the user sees

- About 15 seconds after the AppImage starts, and at most once a day, it reads
  the update feed. When the feed offers a newer version it asks:
  **Install Update**, **Later** or **Skip This Version**. When the AppImage is
  current it says nothing.
- **Help › Check for Updates…** checks now and always reports, up to date or
  not.
- **Install Update** downloads the new AppImage and checks its SHA-256 and its
  Ed25519 signature, then offers **Restart and Install**. That quits
  LinDirStat, puts the new AppImage in place of the old one (same path, so
  menu entries and symlinks keep working) and starts it.
- When the AppImage's folder is not writable, the download is kept and the
  user is told to replace the AppImage themselves.

The dialogs are the updater's own and are in English only.

## How it works

- `package.manifest.json` `updates` enables updates for the AppImage:
  channel `stable`, checks at most every 24 hours, 15 seconds after launch,
  payloads signed with the key `updates.publicEDKey`, releases in the public
  repository `danjboyd/LinDirStat-releases`.
  `backends.appimage.updates` gives the feed URL,
  `https://danjboyd.github.io/LinDirStat-releases/updates/linux/stable.json`,
  and embeds AppImage update information
  (`gh-releases-zsync|danjboyd|LinDirStat-releases|latest|…`), so
  AppImageUpdate, AppImageLauncher and Gear can update the AppImage too.
  `platformOverrides.macos` turns updates off for the DMG, and
  `platformOverrides.linux` turns the DMG backend off on Linux, where it can't
  be built (the packager wants a feed URL for every enabled backend when
  updates are on).
- Packaging writes the update configuration into the AppImage
  (`usr/metadata/updates/gnustep-packager-update.json`) and, next to the
  AppImage, its `.zsync` file and `.update-feed.json`, the feed for that
  release.
- `LDUpdates` (`Source/LDUpdates.m`) starts the updater when it finds that
  configuration and adds the menu item. The build links the updater's two
  static libraries into the app and copies `gp-update-helper` next to the
  executable, where the updater looks for it.
- The helper does the work outside the app: it downloads and checks the
  payload, then writes a `/bin/sh` script that waits for LinDirStat to quit,
  swaps the AppImage and starts it again. The helper's state is in GNUstep's
  temporary folder (`$TMP`, else `/tmp/GNUstepSecure<uid>`), under
  `gnustep-packager-updater/org.lindirstat.LinDirStat`.

The source repository is private, and the updater downloads anonymously, so
the AppImages and the feed are published in the public
`danjboyd/LinDirStat-releases`: AppImages as GitHub release assets, the feed
on its GitHub Pages site (`gh-pages` branch).

## The signing key

Each release's feed carries an Ed25519 signature of the AppImage
(`edSignature`); an AppImage whose signature does not verify with the public
key built into the installed copy is refused.

- Public key: `updates.publicEDKey` in `package.manifest.json`.
- Private key: `~/.config/lindirstat/update-ed25519.key` (mode 600), base64 of
  the 32-byte Ed25519 seed. It is not in any repository. Keep a backup
  somewhere safe: without it no release can be signed for copies already
  installed, and replacing the key means every installed copy has to be
  replaced by hand once.
- `scripts/sign-update-feed.py` signs a feed with `openssl`; it checks that
  the private key matches `UPDATE_ED_PUBLIC_KEY` first.

## Releasing

Releases are built on GitHub's runners and signed and published here, after
Dan approves. The update key never goes to GitHub, and the workflow has no
secrets.

1. Set `package.version` in `package.manifest.json` to the new version, add
   `packaging/linux/release-notes/<version>.md`, and merge that to `main`. The
   release is tag `v<version>`.
2. Build a release candidate: run the **Release** workflow
   (`.github/workflows/release.yml`) on `main` by hand with a version such as
   `0.1.4-rc1` (`gh workflow run release.yml --ref main -f version=0.1.4-rc1`).
   It packages the AppImage on Debian 13 (`scripts/ci-release-linux.sh`) and
   the universal DMG on macOS 15 (`scripts/ci-release-macos.sh`) from the
   inputs pinned in `packaging/release-inputs.json`, runs the release checks
   that can run there, and uploads one artifact, `release`: the AppImage, its
   `.zsync`, the unsigned feed, a provenance file (the commit, every pin, the
   build IDs of the bundled Adwaita theme, libs-back and GNUstep libraries,
   and each check's result), the DMG and its `.sha256`, and `SHA256SUMS`.
   Every release check runs there, Alt+F4 under GNOME Shell included, and
   the DMG must be built with the macOS 26 SDK.
3. `scripts/release-linux.sh --from-ci <run id>` (a dry run, from a clean
   checkout at the run's commit) downloads that artifact and checks it:
   `SHA256SUMS`; that the provenance names this commit and this checkout's
   pins; that the build IDs of the Adwaita theme and libs-back inside the
   AppImage are the provenance's and those of builds of the pins made here;
   then it runs the first-launch, open-folder and Alt+F4 checks on the CI
   AppImage here, checks that the feed's URL, sha256 and size describe the
   files, signs the feed, and runs `scripts/test-appimage-update.sh` from the
   current release.
4. With Dan's go, `scripts/release-linux.sh --from-ci <run id> --publish`
   does the same, then creates the release in `danjboyd/LinDirStat-releases`
   with the AppImage, `.zsync`, feed, DMG and `.sha256`, attaches
   `SHA256SUMS`, and pushes tag `v<version>`. A release candidate is a
   GitHub pre-release and stays out of the feed.
5. The final release is the same with the version `package.version`: a
   manual run without a version, or pushing tag `v<version>` (the workflow
   checks the tag matches `package.version`; `--publish` then finds the tag
   already there). A final release also pushes the signed feed to
   `gh-pages` as `updates/linux/stable.json`.

`scripts/release-linux.sh` without `--from-ci` still builds the AppImage on
this machine (`scripts/package-linux.sh`, the script the workflow runs) and
publishes it the same way, without a DMG. It builds with gnustep-packager,
the Adwaita theme and appimagetool at their pins (`docs/packaging.md`,
"Pinned inputs"), checked out in `out/`; `GNUSTEP_PACKAGER`, `ADWAITA_THEME`
and `LIBS_BACK_BUNDLE` can point a dry run at local trees, and `--publish`
refuses any that is not at its pin.

Every release carries one `SHA256SUMS` covering every platform's payloads:
each asset except `SHA256SUMS` itself, the per-file `.sha256` files and the
signed `.update-feed.json`. `scripts/release-sha256sums.sh v<version>`
writes it from the assets on the release, uploads it with `--clobber` and
checks it against a fresh download, so run it after attaching any asset by
hand. `--check` only verifies, and fails if a payload is missing from the
file; `--dir` and `--check-dir` do the same for a local folder (the
workflow's artifact). Users check a download with
`sha256sum -c --ignore-missing SHA256SUMS`.

A version with a `-` (`0.2.0-rc1`) is published as a GitHub pre-release and
is not put in the feed, so installed copies are not offered it, and GitHub's
latest release (which the AppImage update information follows) stays the
last real one.

## Testing

- `Tests/LDUpdatesTests.m`: a build without packaged configuration has no
  updater; the manifest's update settings; reading the packaged
  configuration, and which feed versions count as an update.
- `Tests/UI/LDAppControllerUITests.m`: the unpackaged app has no
  **Check for Updates…** item.
- `scripts/test-appimage-update.sh OLD.AppImage NEW.AppImage NEW.update-feed.json`:
  the whole update on a private Xvfb. OLD finds NEW in a local signed feed
  (`GP_UPDATER_FEED_URL`), installs it, and NEW starts in its place; then a
  payload signed with another key is refused and OLD stays. NEW comes from
  `package -Backend appimage -PackageVersion <higher version>`. It answers the
  dialogs with xdotool, and needs the private key to sign the test feed.

A copy can be pointed at another feed for testing with `GP_UPDATER_FEED_URL`
(environment) or the `GPUpdaterFeedURL` default.
