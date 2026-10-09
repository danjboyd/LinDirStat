#import <Foundation/Foundation.h>

// User-visible text. The key is the English text; translations live in
// Resources/<language>.lproj/Localizable.strings (generated from WinDirStat's
// language files by scripts/generate-translations.py). Text with no
// translation is shown in English.
#define LDLocalized(text) NSLocalizedString(text, nil)
