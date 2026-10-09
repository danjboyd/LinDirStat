#import "LDTreemapPreview.h"
#import "LDExtensionColor.h"
#import "LDFileNode.h"

@implementation LDTreemapPreview

+ (LDTreemapPreview *)sharedPreview
{
  static LDTreemapPreview *shared = nil;
  if (!shared) {
    shared = [[LDTreemapPreview alloc] init];
  }
  return shared;
}

// Leaves of one colour share an extension key, "c<palette index>".
- (LDFileNode *)leafWithSize:(unsigned long long)size color:(NSUInteger)color
{
  LDFileNode *leaf = [LDFileNode nodeWithName:[NSString stringWithFormat:@"demo.c%lu", (unsigned long)color]
                                         kind:LDFileNodeKindFile
                                         size:size
                                allocatedSize:size];
  return leaf;
}

- (LDFileNode *)containerWithChildren:(NSArray *)children
{
  LDFileNode *container = [LDFileNode nodeWithName:@"demo" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  for (LDFileNode *child in children) {
    [container addChild:child];
  }
  return container;
}

// GetNextColor: walks the default palette.
- (NSUInteger)nextColor:(NSUInteger *)cursor
{
  NSUInteger color = *cursor % [LDExtensionColor paletteCount];
  *cursor += 1;
  return color;
}

- (id)init
{
  self = [super init];
  if (self) {
    NSUInteger cursor = 0;
    NSMutableArray *c4 = [NSMutableArray array];
    NSUInteger color = [self nextColor:&cursor];
    for (NSUInteger i = 0; i < 30; i++) {
      [c4 addObject:[self leafWithSize:1 + 100 * i color:color]];
    }
    NSMutableArray *c0 = [NSMutableArray array];
    for (NSUInteger i = 0; i < 8; i++) {
      [c0 addObject:[self leafWithSize:500 + 600 * i color:[self nextColor:&cursor]]];
    }
    NSMutableArray *c1 = [NSMutableArray array];
    color = [self nextColor:&cursor];
    for (NSUInteger i = 0; i < 10; i++) {
      [c1 addObject:[self leafWithSize:1 + 200 * i color:color]];
    }
    [c0 addObject:[self containerWithChildren:c1]];
    NSMutableArray *c2 = [NSMutableArray array];
    color = [self nextColor:&cursor];
    for (NSUInteger i = 0; i < 160; i++) {
      [c2 addObject:[self leafWithSize:1 + i color:color]];
    }
    NSMutableArray *c3 = [NSMutableArray array];
    [c3 addObject:[self leafWithSize:10000 color:[self nextColor:&cursor]]];
    [c3 addObject:[self containerWithChildren:c4]];
    [c3 addObject:[self containerWithChildren:c2]];
    [c3 addObject:[self leafWithSize:6000 color:[self nextColor:&cursor]]];
    [c3 addObject:[self leafWithSize:1500 color:[self nextColor:&cursor]]];
    _rootNode = [self containerWithChildren:@[[self containerWithChildren:c0], [self containerWithChildren:c3]]];
    [_rootNode recalculateAggregateSize];
    [_rootNode sortChildrenByMetric:LDSizeMetricPhysical];

    NSMutableDictionary *indexes = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < [LDExtensionColor paletteCount]; i++) {
      [indexes setObject:@(i) forKey:[NSString stringWithFormat:@"c%lu", (unsigned long)i]];
    }
    _colorIndexes = indexes;
  }
  return self;
}

- (LDFileNode *)rootNode { return _rootNode; }
- (NSDictionary *)colorIndexes { return _colorIndexes; }

- (NSData *)renderRGBAWithWidth:(int)width height:(int)height options:(LDTreemapOptions)options
{
  LDTreemap *treemap = [[LDTreemap alloc] initWithRootNode:_rootNode
                                                    metric:LDSizeMetricPhysical
                                                     width:width
                                                    height:height
                                                   options:options];
  return [treemap renderRGBAWithColorIndexes:_colorIndexes];
}

@end
