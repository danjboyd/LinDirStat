#import <Foundation/Foundation.h>

// WinDirStat's Language setting: the language LinDirStat's own text is shown
// in, from the localizations it ships. It takes effect at the next launch.
@interface LDLanguages : NSObject

// Language codes of the shipped localizations ("de", "zh-Hans"), English
// first, then by display name.
+ (NSArray *)availableLanguages;
// The chosen language code, or nil to follow the system's languages.
+ (NSString *)chosenLanguage;
// Chooses a language (nil: follow the system) for the next launch, through
// AppleLanguages (macOS) and NSLanguages (GNUstep) in the app's defaults.
+ (void)setChosenLanguage:(NSString *)code;
// The language's name in that language ("Deutsch"), capitalized.
+ (NSString *)nativeNameOfLanguage:(NSString *)code;

@end
