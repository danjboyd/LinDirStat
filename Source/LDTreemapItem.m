#import "LDTreemapItem.h"
#import "LDFileNode.h"

@implementation LDTreemapItem

+ (id)itemWithNode:(LDFileNode *)node rect:(NSRect)rect extensionKey:(NSString *)extensionKey depth:(NSUInteger)depth
{
  return [[[self alloc] initWithNode:node rect:rect extensionKey:extensionKey depth:depth] autorelease];
}

- (id)initWithNode:(LDFileNode *)node rect:(NSRect)rect extensionKey:(NSString *)extensionKey depth:(NSUInteger)depth
{
  self = [super init];
  if (self) {
    _node = [node retain];
    _rect = rect;
    _extensionKey = [extensionKey copy];
    _depth = depth;
  }
  return self;
}

- (LDFileNode *)node { return _node; }
- (NSRect)rect { return _rect; }
- (NSString *)extensionKey { return _extensionKey; }
- (NSUInteger)depth { return _depth; }

- (NSDictionary *)snapshotDictionary
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
          [[_node path] copy], @"path",
          [NSNumber numberWithDouble:_rect.origin.x], @"x",
          [NSNumber numberWithDouble:_rect.origin.y], @"y",
          [NSNumber numberWithDouble:_rect.size.width], @"width",
          [NSNumber numberWithDouble:_rect.size.height], @"height",
          _extensionKey ? _extensionKey : @"<none>", @"extension",
          [NSNumber numberWithUnsignedInteger:_depth], @"depth",
          nil];
}

- (void)dealloc
{
  [_node release];
  [_extensionKey release];
  [super dealloc];
}

@end
