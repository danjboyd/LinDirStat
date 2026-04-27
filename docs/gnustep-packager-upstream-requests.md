# GNUstep Packager Upstream Requests

LinDirStat depends on `~/git/gnustep/gnustep-packager` for packaging.

## AppImage: Apps Without File Associations

Current blocker:

`gnustep-packager` AppImage packaging fails for LinDirStat because the app has no MIME/file associations and the backend passes an empty `MimeEntries` array into a mandatory parameter.

Expected behavior:

- apps with no document types should package successfully
- the generated desktop entry should omit MIME declarations when no file associations are present
- consumers should not need to declare fake extensions or MIME types

## macOS: DMG Backend

Current gap:

`gnustep-packager` does not currently have a macOS target.

Expected future capability:

- a native macOS DMG-style backend
- `.app` bundle staging support
- DMG layout configuration
- code signing and notarization hooks
- validation for bundle metadata, launch behavior, signing/notarization state, and packaged defaults

LinDirStat should enable this backend in `package.manifest.json` once the backend exists.
