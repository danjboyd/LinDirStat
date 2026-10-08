#import <AppKit/AppKit.h>

// The directory tree's "Subtree Percentage" graph: a bar showing a node's
// share of its parent, indented by depth and coloured by depth as in
// WinDirStat. The depth colours use GNOME's palette (blue, red, green,
// yellow, dark then light) in WinDirStat's order; the trough follows the
// theme's text colour.
@interface LDPercentageBarCell : NSCell
{
  double _fraction;
  NSUInteger _depth;
}

- (void)setFraction:(double)fraction depth:(NSUInteger)depth;
+ (NSColor *)colorForDepth:(NSUInteger)depth;

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
