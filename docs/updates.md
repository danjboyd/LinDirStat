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

`scripts/release-linux.sh` makes a release from a clean checkout of `main`:

1. Set `package.version` in `package.manifest.json` to the new version and
   merge that to `main`. The release is tag `v<version>`.
2. `scripts/release-linux.sh` (a dry run) packages the AppImage and validates
   it (the smoke launch runs on a private Xvfb), signs the feed, and, when a
   release already exists, runs `scripts/test-appimage-update.sh` from the
   current release to the new one.
3. `scripts/release-linux.sh --publish` does the same, then creates the
   GitHub release in `danjboyd/LinDirStat-releases` (AppImage, `.zsync`,
   and feed; the `.metadata.json` and `.diagnostics.txt` sidecars hold the
   build machine's paths and stay local), attaches `SHA256SUMS`, pushes the
   feed to `gh-pages` as `updates/linux/stable.json`, and pushes tag
   `v<version>` to this repository.
4. The macOS session builds the DMG from the tag (`docs/packaging.md`,
   "macOS DMG") and attaches it and its `.sha256` to the same release, then
   runs `scripts/release-sha256sums.sh v<version>` so `SHA256SUMS` lists it
   too.

Every release carries one `SHA256SUMS` covering every platform's payloads:
each asset except `SHA256SUMS` itself, the per-file `.sha256` files and the
signed `.update-feed.json`. `scripts/release-sha256sums.sh v<version>`
writes it from the assets on the release, uploads it with `--clobber` and
checks it against a fresh download, so run it after attaching any asset.
`--check` only verifies, and fails if a payload is missing from the file.
Users check a download with `sha256sum -c --ignore-missing SHA256SUMS`.

A version with a `-` (`0.2.0-rc1`) is published as a GitHub pre-release and
is not put in the feed, so installed copies are not offered it, and GitHub's
latest release (which the AppImage update information follows) stays the
last real one.

It builds with gnustep-packager and the Adwaita theme at their pins in
`packaging/release-inputs.json` (`docs/packaging.md`, "Pinned inputs"),
checked out in `out/`. `GNUSTEP_PACKAGER` and `ADWAITA_THEME` can point a dry
run at local trees; `--publish` refuses any that is not at its pin.

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
