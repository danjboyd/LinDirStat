#import <Foundation/Foundation.h>

@class LDFileNode;

@interface LDTreemapLayout : NSObject

+ (NSArray *)layoutItemsForRootNode:(LDFileNode *)rootNode inRect:(NSRect)rect;
+ (id)itemAtPoint:(NSPoint)point inItems:(NSArray *)items;

@end
