#import <Foundation/Foundation.h>

@class LDFileNode;

@interface LDTreemapItem : NSObject
{
  LDFileNode *_node;
  NSRect _rect;
  NSString *_extensionKey;
  NSUInteger _depth;
}

+ (id)itemWithNode:(LDFileNode *)node rect:(NSRect)rect extensionKey:(NSString *)extensionKey depth:(NSUInteger)depth;
- (id)initWithNode:(LDFileNode *)node rect:(NSRect)rect extensionKey:(NSString *)extensionKey depth:(NSUInteger)depth;
- (LDFileNode *)node;
- (NSRect)rect;
- (NSString *)extensionKey;
- (NSUInteger)depth;
- (NSDictionary *)snapshotDictionary;

@end
