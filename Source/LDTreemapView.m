#import "LDTreemapView.h"
#import "LDExtensionColor.h"
#import "LDFileNode.h"
#import "LDTreemapItem.h"
#import "LDTreemapLayout.h"

@implementation LDTreemapView

- (BOOL)isFlipped
{
  return YES;
}

- (void)setItems:(NSArray *)items
{
  if (_items != items) {
    [_items release];
    _items = [items copy];
    [_selectedItem release];
    _selectedItem = nil;
    [self setNeedsDisplay:YES];
  }
}

- (NSArray *)items { return _items; }
- (LDTreemapItem *)selectedItem { return _selectedItem; }

- (void)drawRect:(NSRect)dirtyRect
{
  (void)dirtyRect;
  [[NSColor blackColor] set];
  NSRectFill([self bounds]);

  NSEnumerator *enumerator = [_items objectEnumerator];
  LDTreemapItem *item = nil;
  while ((item = [enumerator nextObject])) {
    NSRect rect = NSInsetRect([item rect], 0.7, 0.7);
    if (rect.size.width <= 0.0 || rect.size.height <= 0.0) {
      continue;
    }
    NSColor *baseColor = [LDExtensionColor colorForExtensionKey:[item extensionKey]];
    [baseColor set];
    NSRectFill(rect);

    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.22] set];
    NSRectFill(NSMakeRect(rect.origin.x, rect.origin.y, rect.size.width, MAX(1.0, rect.size.height * 0.10)));
    NSRectFill(NSMakeRect(rect.origin.x, rect.origin.y, MAX(1.0, rect.size.width * 0.08), rect.size.height));

    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.24] set];
    NSRectFill(NSMakeRect(rect.origin.x, NSMaxY(rect) - MAX(1.0, rect.size.height * 0.10), rect.size.width, MAX(1.0, rect.size.height * 0.10)));
    NSRectFill(NSMakeRect(NSMaxX(rect) - MAX(1.0, rect.size.width * 0.08), rect.origin.y, MAX(1.0, rect.size.width * 0.08), rect.size.height));

    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.72] set];
    NSFrameRect(rect);
    if (rect.size.width > 10.0 && rect.size.height > 10.0) {
      [[NSColor colorWithCalibratedWhite:1.0 alpha:0.18] set];
      NSFrameRect(NSInsetRect(rect, 2.0, 2.0));
    }
  }

  if (_selectedItem) {
    [[NSColor selectedControlColor] set];
    NSFrameRectWithWidth([_selectedItem rect], 3.0);
  }
}

- (void)mouseDown:(NSEvent *)event
{
  NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
  LDTreemapItem *item = [LDTreemapLayout itemAtPoint:point inItems:_items];
  if (_selectedItem != item) {
    [_selectedItem release];
    _selectedItem = [item retain];
    [self setNeedsDisplay:YES];
  }
}

- (void)dealloc
{
  [_items release];
  [_selectedItem release];
  [super dealloc];
}

@end
