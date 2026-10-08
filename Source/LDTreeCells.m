#import "LDTreeCells.h"

// Bar geometry: thin and rounded like GTK's level bars.
static const CGFloat LDBarHeight = 8.0;
static const CGFloat LDBarHorizontalInset = 6.0;
// WinDirStat indents the graph by a tenth of its width per level.
static const NSUInteger LDMaxIndentLevels = 8;

@implementation LDPercentageBarCell

+ (NSColor *)colorForDepth:(NSUInteger)depth
{
  static NSArray *colors = nil;
  if (!colors) {
    colors = @[
      [NSColor colorWithCalibratedRed:0x1a / 255.0 green:0x5f / 255.0 blue:0xb4 / 255.0 alpha:1.0], // blue 5
      [NSColor colorWithCalibratedRed:0xa5 / 255.0 green:0x1d / 255.0 blue:0x2d / 255.0 alpha:1.0], // red 5
      [NSColor colorWithCalibratedRed:0x26 / 255.0 green:0xa2 / 255.0 blue:0x69 / 255.0 alpha:1.0], // green 5
      [NSColor colorWithCalibratedRed:0xe5 / 255.0 green:0xa5 / 255.0 blue:0x0a / 255.0 alpha:1.0], // yellow 5
      [NSColor colorWithCalibratedRed:0x35 / 255.0 green:0x84 / 255.0 blue:0xe4 / 255.0 alpha:1.0], // blue 3
      [NSColor colorWithCalibratedRed:0xe0 / 255.0 green:0x1b / 255.0 blue:0x24 / 255.0 alpha:1.0], // red 3
      [NSColor colorWithCalibratedRed:0x33 / 255.0 green:0xd1 / 255.0 blue:0x7a / 255.0 alpha:1.0], // green 3
      [NSColor colorWithCalibratedRed:0xf6 / 255.0 green:0xd3 / 255.0 blue:0x2d / 255.0 alpha:1.0], // yellow 3
    ];
  }
  return [colors objectAtIndex:depth % [colors count]];
}

- (void)setFraction:(double)fraction depth:(NSUInteger)depth
{
  _fraction = MAX(0.0, MIN(1.0, fraction));
  _depth = depth;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
  (void)controlView;
  NSRect track = NSInsetRect(cellFrame, LDBarHorizontalInset, 0.0);
  CGFloat indent = floor(track.size.width * MIN(_depth, LDMaxIndentLevels) / 10.0);
  track.origin.x += indent;
  track.size.width -= indent;
  track.origin.y = floor(NSMidY(cellFrame) - LDBarHeight / 2.0);
  track.size.height = LDBarHeight;
  if (track.size.width <= LDBarHeight) {
    return;
  }

  CGFloat radius = LDBarHeight / 2.0;
  // Catalog colours ignore alpha, so go through RGB first.
  NSColor *text = [[NSColor controlTextColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  [[text colorWithAlphaComponent:0.15] set];
  [[NSBezierPath bezierPathWithRoundedRect:track xRadius:radius yRadius:radius] fill];

  CGFloat filled = floor(track.size.width * _fraction);
  if (filled < 1.0) {
    return;
  }
  NSRect fill = track;
  fill.size.width = MAX(filled, LDBarHeight);
  [[LDPercentageBarCell colorForDepth:_depth] set];
  [[NSBezierPath bezierPathWithRoundedRect:fill xRadius:radius yRadius:radius] fill];
}

@end

@implementation LDIconTextCell

- (id)copyWithZone:(NSZone *)zone
{
  LDIconTextCell *copy = [super copyWithZone:zone];
  copy->_icon = _icon;
  return copy;
}

- (void)setIcon:(NSImage *)icon
{
  _icon = icon;
}

+ (NSImage *)image:(NSImage *)image tintedWithColor:(NSColor *)color
{
  NSSize size = [image size];
  NSImage *tinted = [[NSImage alloc] initWithSize:size];
  [tinted lockFocus];
  NSRect bounds = NSMakeRect(0.0, 0.0, size.width, size.height);
  [image drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
  [color set];
  NSRectFillUsingOperation(bounds, NSCompositeSourceIn);
  [tinted unlockFocus];
  return tinted;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
  if (_icon) {
    NSSize size = [_icon size];
    NSRect iconFrame = NSZeroRect;
    NSDivideRect(cellFrame, &iconFrame, &cellFrame, size.width + 6.0, NSMinXEdge);
    NSRect target = NSMakeRect(NSMinX(iconFrame),
                               floor(NSMidY(iconFrame) - size.height / 2.0),
                               size.width,
                               size.height);
    [_icon drawInRect:target
             fromRect:NSZeroRect
            operation:NSCompositeSourceOver
             fraction:[self isEnabled] ? 1.0 : 0.5
       respectFlipped:YES
                hints:nil];
  }
  [super drawWithFrame:cellFrame inView:controlView];
}

@end
