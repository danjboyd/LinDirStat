#import <AppKit/AppKit.h>

@class LDTreemapItem;

@interface LDTreemapView : NSView
{
  NSArray *_items;
  LDTreemapItem *_selectedItem;
}

- (void)setItems:(NSArray *)items;
- (NSArray *)items;
- (LDTreemapItem *)selectedItem;

@end
