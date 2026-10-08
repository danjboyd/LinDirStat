#import "LDExtensionColor.h"

static const LDRGBColor LDDefaultCushionColors[] = {
  LDRGB(0, 0, 255),     // Blue
  LDRGB(255, 0, 0),     // Red
  LDRGB(0, 255, 0),     // Green
  LDRGB(255, 255, 0),   // Yellow
  LDRGB(0, 255, 255),   // Cyan
  LDRGB(255, 0, 255),   // Magenta
  LDRGB(255, 170, 0),   // Orange
  LDRGB(0, 85, 255),    // Dodger Blue
  LDRGB(255, 0, 85),    // Hot Pink
  LDRGB(85, 255, 0),    // Lime Green
  LDRGB(170, 0, 255),   // Violet
  LDRGB(0, 255, 85),    // Spring Green
  LDRGB(255, 0, 170),   // Deep Pink
  LDRGB(0, 170, 255),   // Sky Blue
  LDRGB(255, 85, 0),    // Orange Red
  LDRGB(0, 255, 170),   // Aquamarine
  LDRGB(85, 0, 255),    // Indigo
  LDRGB(255, 255, 255), // White
};

#define LDPaletteCount (sizeof(LDDefaultCushionColors) / sizeof(LDDefaultCushionColors[0]))

static void LDDistributeFirst(int *first, int *second, int *third)
{
  int h = (*first - 255) / 2;
  *first = 255;
  *second += h;
  *third += h;

  if (*second > 255) {
    int j = *second - 255;
    *second = 255;
    *third += j;
  } else if (*third > 255) {
    int j = *third - 255;
    *third = 255;
    *second += j;
  }
}

@implementation LDExtensionColor

+ (NSUInteger)paletteCount
{
  return LDPaletteCount;
}

+ (void)normalizeRed:(int *)red green:(int *)green blue:(int *)blue
{
  if (*red > 255) {
    LDDistributeFirst(red, green, blue);
  } else if (*green > 255) {
    LDDistributeFirst(green, red, blue);
  } else if (*blue > 255) {
    LDDistributeFirst(blue, red, green);
  }
}

+ (LDRGBColor)makeBrightColor:(LDRGBColor)color brightness:(double)brightness
{
  double red = LDRGBRed(color) / 255.0;
  double green = LDRGBGreen(color) / 255.0;
  double blue = LDRGBBlue(color) / 255.0;
  double sum = red + green + blue;
  if (sum <= 0.0) {
    return color;
  }

  double f = 3.0 * brightness / sum;
  int r = (int)(red * f * 255);
  int g = (int)(green * f * 255);
  int b = (int)(blue * f * 255);
  [self normalizeRed:&r green:&g blue:&b];
  return LDRGB(r, g, b);
}

+ (LDRGBColor)paletteColorAtIndex:(NSUInteger)index
{
  static LDRGBColor palette[LDPaletteCount];
  static BOOL initialized = NO;
  if (!initialized) {
    NSUInteger i = 0;
    for (i = 0; i < LDPaletteCount; i++) {
      palette[i] = [self makeBrightColor:LDDefaultCushionColors[i] brightness:0.6];
    }
    initialized = YES;
  }
  return palette[MIN(index, LDPaletteCount - 1)];
}

+ (NSUInteger)paletteIndexForRank:(NSUInteger)rank
{
  return MIN(rank, LDPaletteCount - 1);
}

@end
