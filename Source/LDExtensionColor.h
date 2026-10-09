#import <Foundation/Foundation.h>

// Colors are 0xRRGGBB values so the palette stays usable from non-GUI code.
typedef uint32_t LDRGBColor;

#define LDRGB(r, g, b) ((LDRGBColor)((((r) & 0xFF) << 16) | (((g) & 0xFF) << 8) | ((b) & 0xFF)))
#define LDRGBRed(c) (((c) >> 16) & 0xFF)
#define LDRGBGreen(c) (((c) >> 8) & 0xFF)
#define LDRGBBlue(c) ((c) & 0xFF)

// WinDirStat's CTreeMap::COLORFLAG_DARKER / COLORFLAG_LIGHTER: pseudo-items
// are drawn with the colour made palette-bright and the brightness scaled
// (x0.66 darker, x1.2 capped at 1 lighter).
#define LDTreemapColorFlagDarker 0x01000000u
#define LDTreemapColorFlagLighter 0x02000000u
#define LDTreemapColorFlagMask 0x03000000u

// WinDirStat's treemap palette and color math (references/WinDirStat
// windirstat/Controls/TreeMap.h).
@interface LDExtensionColor : NSObject

// Number of palette entries (18). The last entry is used for every extension
// ranked below the colored ones.
+ (NSUInteger)paletteCount;
// The default palette, equalized to brightness 0.6 like WinDirStat.
+ (LDRGBColor)paletteColorAtIndex:(NSUInteger)index;
+ (NSUInteger)paletteIndexForRank:(NSUInteger)rank;

// Port of CColorSpace::MakeBrightColor.
+ (LDRGBColor)makeBrightColor:(LDRGBColor)color brightness:(double)brightness;
// Port of CColorSpace::NormalizeColor; spills channels above 255 into the others.
+ (void)normalizeRed:(int *)red green:(int *)green blue:(int *)blue;

@end
