#import "LDLanguages.h"

static NSString *const LDLanguageKey = @"Language";

@implementation LDLanguages

+ (NSArray *)availableLanguages
{
  NSMutableArray *codes = [NSMutableArray array];
  for (NSString *code in [[NSBundle mainBundle] localizations]) {
    if (![code isEqualToString:@"Base"] && ![codes containsObject:code]) {
      [codes addObject:code];
    }
  }
  [codes sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
    if ([a isEqualToString:@"en"] != [b isEqualToString:@"en"]) {
      return [a isEqualToString:@"en"] ? NSOrderedAscending : NSOrderedDescending;
    }
    return [[self nativeNameOfLanguage:a] localizedCaseInsensitiveCompare:[self nativeNameOfLanguage:b]];
  }];
  return codes;
}

+ (NSString *)chosenLanguage
{
  NSString *code = [[NSUserDefaults standardUserDefaults] stringForKey:LDLanguageKey];
  return [code length] > 0 ? code : nil;
}

+ (void)setChosenLanguage:(NSString *)code
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([code length] > 0) {
    [defaults setObject:code forKey:LDLanguageKey];
    [defaults setObject:@[code] forKey:@"AppleLanguages"];
    [defaults setObject:@[code] forKey:@"NSLanguages"];
  } else {
    [defaults removeObjectForKey:LDLanguageKey];
    [defaults removeObjectForKey:@"AppleLanguages"];
    [defaults removeObjectForKey:@"NSLanguages"];
  }
  [defaults synchronize];
}

+ (NSString *)nativeNameOfLanguage:(NSString *)code
{
  NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:code];
  NSString *name = [locale displayNameForKey:NSLocaleIdentifier value:code];
  if ([name length] == 0) {
    return code;
  }
  return [[[name substringToIndex:1] uppercaseStringWithLocale:locale] stringByAppendingString:[name substringFromIndex:1]];
}

@end
