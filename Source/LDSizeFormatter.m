#import "LDSizeFormatter.h"
#import "LDLocalization.h"

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
  double value = (double)bytes;
  NSArray *units = [NSArray arrayWithObjects:@"B", @"KB", @"MB", @"GB", @"TB", nil];
  NSUInteger unitIndex = 0;
  while (value >= 1024.0 && unitIndex + 1 < [units count]) {
    value = value / 1024.0;
    unitIndex++;
  }

  if (unitIndex == 0) {
    return [NSString stringWithFormat:@"%llu B", bytes];
  }
  if (value >= 10.0) {
    return [NSString stringWithFormat:@"%.0f %@", value, [units objectAtIndex:unitIndex]];
  }
  return [NSString stringWithFormat:@"%.1f %@", value, [units objectAtIndex:unitIndex]];
}

@end
