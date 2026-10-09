#import <AppKit/AppKit.h>

// The directory tree's "Subtree Percentage" graph: a bar showing a node's
// share of its parent, indented by depth and coloured by depth as in
// WinDirStat. The depth colours use GNOME's palette (blue, red, green,
// yellow, dark then light) in WinDirStat's order; the trough follows the
// theme's text colour.
//
// While a folder is still being read the cell shows WinDirStat's pacman
// instead, running across the cell (PacMan.cpp).
@interface LDPercentageBarCell : NSCell
{
  double _fraction;
  NSUInteger _depth;
  BOOL _showsPacman;
  NSTimeInterval _pacmanTime;
}

- (void)setFraction:(double)fraction depth:(NSUInteger)depth;
// time is seconds since the scan started; it sets the pacman's position and
// mouth. NO shows the bar.
- (void)setShowsPacman:(BOOL)showsPacman time:(NSTimeInterval)time;
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
