#import <Foundation/Foundation.h>

@interface LDSizeFormatter : NSObject

+ (NSString *)stringForBytes:(unsigned long long)bytes;
// NO shows exact byte counts with digit grouping ("1,234,567 bytes"), as
// WinDirStat does when its human-readable format is off. Default YES.
+ (void)setHumanReadable:(BOOL)humanReadable;

@end
