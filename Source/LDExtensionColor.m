#import "LDExtensionColor.h"

@implementation LDExtensionColor

+ (NSArray *)palette
{
  static NSArray *palette = nil;
  if (!palette) {
    palette = [[NSArray alloc] initWithObjects:
               [NSColor colorWithCalibratedRed:0.18 green:0.18 blue:1.00 alpha:1.0],
               [NSColor colorWithCalibratedRed:1.00 green:0.18 blue:0.18 alpha:1.0],
               [NSColor colorWithCalibratedRed:0.16 green:0.86 blue:0.16 alpha:1.0],
               [NSColor colorWithCalibratedRed:1.00 green:0.88 blue:0.12 alpha:1.0],
               [NSColor colorWithCalibratedRed:0.08 green:0.88 blue:0.88 alpha:1.0],
               [NSColor colorWithCalibratedRed:0.95 green:0.08 blue:0.95 alpha:1.0],
               [NSColor colorWithCalibratedRed:1.00 green:0.55 blue:0.00 alpha:1.0],
               [NSColor colorWithCalibratedRed:0.00 green:0.34 blue:1.00 alpha:1.0],
               [NSColor colorWithCalibratedRed:1.00 green:0.00 blue:0.34 alpha:1.0],
               [NSColor colorWithCalibratedRed:0.42 green:1.00 blue:0.00 alpha:1.0],
               [NSColor colorWithCalibratedRed:0.66 green:0.00 blue:1.00 alpha:1.0],
               [NSColor colorWithCalibratedRed:0.00 green:1.00 blue:0.34 alpha:1.0],
               [NSColor colorWithCalibratedRed:1.00 green:0.00 blue:0.66 alpha:1.0],
               [NSColor colorWithCalibratedRed:0.00 green:0.66 blue:1.00 alpha:1.0],
               [NSColor colorWithCalibratedRed:1.00 green:0.34 blue:0.00 alpha:1.0],
               [NSColor colorWithCalibratedRed:0.00 green:1.00 blue:0.66 alpha:1.0],
               [NSColor colorWithCalibratedRed:0.34 green:0.00 blue:1.00 alpha:1.0],
               [NSColor colorWithCalibratedRed:0.42 green:0.42 blue:0.42 alpha:1.0],
               nil];
  }
  return palette;
}

+ (NSUInteger)paletteIndexForExtensionKey:(NSString *)extensionKey
{
  NSString *key = extensionKey ? extensionKey : @"<none>";
  NSUInteger hash = 5381;
  NSUInteger i = 0;
  for (i = 0; i < [key length]; i++) {
    hash = ((hash << 5) + hash) + [key characterAtIndex:i];
  }
  return hash % [[self palette] count];
}

+ (NSColor *)colorForExtensionKey:(NSString *)extensionKey
{
  return [[self palette] objectAtIndex:[self paletteIndexForExtensionKey:extensionKey]];
}

@end
