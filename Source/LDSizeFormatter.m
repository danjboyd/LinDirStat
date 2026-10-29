#import "LDSizeFormatter.h"
#import "LDLocalization.h"

#include <math.h>

static BOOL LDHumanReadable = YES;

@implementation LDSizeFormatter

+ (void)setHumanReadable:(BOOL)humanReadable
{
  LDHumanReadable = humanReadable;
}

+ (NSString *)stringForBytes:(unsigned long long)bytes
{
  if (!LDHumanReadable) {
    static NSNumberFormatter *grouped = nil;
    if (!grouped) {
      grouped = [[NSNumberFormatter alloc] init];
      [grouped setNumberStyle:NSNumberFormatterDecimalStyle];
      [grouped setUsesGroupingSeparator:YES];
    }
    return [NSString stringWithFormat:LDLocalized(@"%@ bytes"), [grouped stringFromNumber:[NSNumber numberWithUnsignedLongLong:bytes]]];
  }
  // WinDirStat's FormatSizeSuffixes and FormatDouble (HelpersInterface.cpp):
  // a unit starts half a step below its size, so rounding never shows
  // "1024.00 KB", and the value always has two decimals (322ee29b).
  static const struct {
    unsigned long long bytes;
    unsigned long long threshold;
    __unsafe_unretained NSString *unit;
  } units[] = {
    {1ULL << 40, (1ULL << 40) - (1ULL << 29), @"TB"},
    {1ULL << 30, (1ULL << 30) - (1ULL << 19), @"GB"},
    {1ULL << 20, (1ULL << 20) - (1ULL << 9), @"MB"},
    {1ULL << 10, 1ULL << 10, @"KB"},
  };
  NSUInteger i = 0;
  for (i = 0; i < sizeof(units) / sizeof(units[0]); i++) {
    if (bytes < units[i].threshold) {
      continue;
    }
    long long hundredths = llround((double)bytes / (double)units[i].bytes * 100.0);
    return [NSString stringWithFormat:@"%lld.%02lld %@", hundredths / 100, hundredths % 100, units[i].unit];
  }
  return [NSString stringWithFormat:@"%llu B", bytes];
}

@end
