# The gnustep-packager updater

`GPUpdaterCore/`, `GPUpdaterUI/` and `gp-update-helper/` are copies of
`updater/objc/` in [danjboyd/gnustep-packager](https://github.com/danjboyd/gnustep-packager):
the in-app updater for LinDirStat's AppImage (see `docs/updates.md`).

- Source: gnustep-packager `updater/objc` at `3e487ab` (its main after #8, #10
  and #12), the packager LinDirStat packages with.
- Copied: `Headers/` and `Source/` of each, unchanged. The helper's
  `Source/monocypher/` is Monocypher 4.0.2 (CC0), which checks the update
  payloads' Ed25519 signatures.
- Ours: the `GNUmakefile`s, which build the two libraries as static archives
  (linked into the app, so the AppImage carries no extra shared libraries)
  and the helper as a tool, with gnustep-make, as part of this tree. The
  packager's own `Makefile`s are not copied. Like the packager's, this code
  uses manual reference counting; it is built without `-fobjc-arc`.
- Not built on macOS: the native build (`macos/`) leaves the updater out.

Change the updater in gnustep-packager first, then copy the files here and
update the source commit above.
