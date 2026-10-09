#import <Foundation/Foundation.h>

// Colors are 0xRRGGBB values so the palette stays usable from non-GUI code.
typedef uint32_t LDRGBColor;

#define LDRGB(r, g, b) ((LDRGBColor)((((r) & 0xFF) << 16) | (((g) & 0xFF) << 8) | ((b) & 0xFF)))
#define LDRGBRed(c) (((c) >> 16) & 0xFF)
#define LDRGBGreen(c) (((c) >> 8) & 0xFF)
#define LDRGBBlue(c) ((c) & 0xFF)

// CTreeMap::COLORFLAG_DARKER/LIGHTER in the unused top byte: the color is
// equalized to the palette brightness and drawn darker or lighter.
#define LDRGBColorFlagDarker ((LDRGBColor)0x01000000)
#define LDRGBColorFlagLighter ((LDRGBColor)0x02000000)
#define LDRGBColorFlagMask ((LDRGBColor)0x03000000)

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
