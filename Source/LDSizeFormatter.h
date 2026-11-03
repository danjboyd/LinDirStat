#import <Foundation/Foundation.h>

@interface LDSizeFormatter : NSObject

+ (NSString *)stringForBytes:(unsigned long long)bytes;
// A percentage as WinDirStat writes one (FormatDouble plus "%"): two
// decimals and the locale's separator, "89.60%" or "89,60%".
+ (NSString *)stringForPercent:(double)percent;
// The number alone (WinDirStat's FormatDouble), for text that adds its own
// "%".
+ (NSString *)stringForDouble:(double)value;
// NO shows exact byte counts with digit grouping ("1,234,567 bytes"), as
// WinDirStat does when its human-readable format is off. Default YES.
+ (void)setHumanReadable:(BOOL)humanReadable;
// The locale whose decimal separator sizes and percentages use; nil (the
// default) is the user's current locale.
+ (void)setLocaleForTesting:(NSLocale *)locale;

@end
