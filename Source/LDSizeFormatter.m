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
  // "1024.00 KiB", and the value always has two decimals (322ee29b).
  static const struct {
    unsigned long long bytes;
    unsigned long long threshold;
  } units[] = {
    {1ULL << 40, (1ULL << 40) - (1ULL << 29)},
    {1ULL << 30, (1ULL << 30) - (1ULL << 19)},
    {1ULL << 20, (1ULL << 20) - (1ULL << 9)},
    {1ULL << 10, 1ULL << 10},
  };
  // WinDirStat's IDS_SPEC_TiB … IDS_SPEC_KiB.
  // Once, whichever thread asks first: scans format sizes off the main thread.
  static NSArray *names = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    names = @[LDLocalized(@"TiB"), LDLocalized(@"GiB"), LDLocalized(@"MiB"), LDLocalized(@"KiB")];
  });
  NSUInteger i = 0;
  for (i = 0; i < sizeof(units) / sizeof(units[0]); i++) {
    if (bytes < units[i].threshold) {
      continue;
    }
    long long hundredths = llround((double)bytes / (double)units[i].bytes * 100.0);
    return [NSString stringWithFormat:@"%lld.%02lld %@", hundredths / 100, hundredths % 100, [names objectAtIndex:i]];
  }
  return [NSString stringWithFormat:@"%llu B", bytes];
}

@end
