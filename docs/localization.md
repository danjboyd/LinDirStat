# Localization

LinDirStat shows its own text in the language chosen in Preferences ›
General › Language (WinDirStat's Language setting), or the system's
languages by default. A change takes effect when LinDirStat is opened again.
On macOS the choice is stored as `AppleLanguages`, under GNUstep as
`NSLanguages`, in LinDirStat's own defaults (`LDLanguages`).

## How text is translated

- User-visible text is written in English and wrapped in `LDLocalized(@"…")`
  (`Source/LDLocalization.h`, `NSLocalizedString`): the English text is the
  key. Data stays English: CSV column names, defaults keys, identifiers, the
  names of `<Free Space>`, `<Unknown>` and "This Computer" (they are paths).
- `Source/Resources/<language>.lproj/Localizable.strings` hold the
  translations. Both builds bundle them (`Source/GNUmakefile`,
  `macos/GNUmakefile`).
- The tables are generated, not edited: `scripts/generate-translations.py`
  collects every `LDLocalized` key and takes its translation from
  WinDirStat's language files (`references/WinDirStat/windirstat/res/langs`,
  the pinned submodule) when the English text matches one of WinDirStat's,
  ignoring Windows accelerators and mnemonics, `...`/`…`, a trailing colon
  and case, or when the script's `MANUAL` table names the WinDirStat string.
  WinDirStat's `{}` placeholders become the key's format specifiers in order.
  Text with no WinDirStat counterpart is shown in English.

After adding or changing UI text:

```sh
git submodule update --init references/WinDirStat
python3 scripts/generate-translations.py --report   # lists untranslated keys
```

Write new text as whole sentences with format specifiers, never by joining
pieces ("About %@", not "About " + name), so that translations can reorder
words.

Not mapped on purpose: Show in Finder/Files and Open Terminal Here (WinDirStat
says Explorer and Command Prompt).

## Languages

The 22 of WinDirStat 2.x: Czech, Danish, German, Spanish, Estonian, Finnish,
French, Hungarian, Italian, Japanese, Korean, Norwegian Bokmål, Dutch,
Polish, Portuguese, Russian, Slovenian, Swedish, Turkish, Ukrainian,
Simplified Chinese (`zh-Hans`) and Traditional Chinese (Hong Kong, `zh-HK`),
plus English. About half of LinDirStat's text has a WinDirStat counterpart
(menus, columns, most of Preferences); the rest is English until translated.

## License

WinDirStat's translations are GPL-2.0-or-later, and so is LinDirStat (see
`COPYING`).
