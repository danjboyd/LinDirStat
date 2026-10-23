#import <AppKit/AppKit.h>

// 0xRRGGBB colours as stored in LDPreferences.
FOUNDATION_EXPORT NSColor *LDColorFromRGB(uint32_t rgb);
FOUNDATION_EXPORT uint32_t LDRGBFromColor(NSColor *color);

// The directory tree's "Size Proportion" graph: a bar showing a node's
// share of its parent and, inside it, its share of the whole scan, indented
// by depth and coloured by depth as in WinDirStat (Preferences › Folder
// List; GNOME's palette by default). The trough follows the theme's text
// colour.
//
// While a folder is still being read the cell shows WinDirStat's pacman
// instead, running across the cell (PacMan.cpp); a pacman whose folder made
// no progress for a while stops and sleeps ("zzz").
@interface LDPercentageBarCell : NSCell
{
  double _fraction;
  double _absoluteFraction;
  NSUInteger _depth;
  BOOL _showsPacman;
  BOOL _pacmanAsleep;
  NSTimeInterval _pacmanTime;
  NSUInteger _readJobs;
}

- (void)setFraction:(double)fraction depth:(NSUInteger)depth;
// WinDirStat 2.6's Size Proportion bar (5be7353c): the share of the parent
// as a light bar, and inside it the share of the whole scan in the level's
// colour; indented SizeProportionIndent points per level.
- (void)setFraction:(double)fraction absoluteFraction:(double)absolute depth:(NSUInteger)depth;
- (double)fraction;
- (double)absoluteFraction;
// Where the bar is drawn in a cell, or an empty rect when there is no room.
+ (NSRect)barRectForCellFrame:(NSRect)cellFrame depth:(NSUInteger)depth;
// time is seconds since the scan started; it sets the pacman's position and
// mouth. NO shows the bar.
- (void)setShowsPacman:(BOOL)showsPacman time:(NSTimeInterval)time;
// As above; asleep draws three "z"s over a stopped pacman.
- (void)setShowsPacman:(BOOL)showsPacman time:(NSTimeInterval)time asleep:(BOOL)asleep;
// With the pacman animation off, WinDirStat writes "[N Read Jobs]" instead.
// 0 shows the bar.
- (void)setReadJobs:(NSUInteger)readJobs;
+ (NSColor *)colorForDepth:(NSUInteger)depth;
// Position (0 left ... 1 right), mouth aperture (0...1) and direction after
// elapsed seconds in a cell of the given width, as WinDirStat animates them.
+ (void)pacmanStateAtTime:(NSTimeInterval)time
                    width:(CGFloat)width
                 position:(CGFloat *)position
                 aperture:(CGFloat *)aperture
               movesRight:(BOOL *)movesRight;

@end

// A text cell with a leading symbolic icon, tinted with the cell's text
// colour the way the Adwaita theme tints symbolic images in its controls.
@interface LDIconTextCell : NSTextFieldCell
{
  NSImage *_icon;
}

- (void)setIcon:(NSImage *)icon;

// A copy of image filled with color through its alpha.
+ (NSImage *)image:(NSImage *)image tintedWithColor:(NSColor *)color;

@end
