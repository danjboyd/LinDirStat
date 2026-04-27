#import <Foundation/Foundation.h>

typedef enum {
  LDFileNodeKindFile = 0,
  LDFileNodeKindDirectory = 1,
  LDFileNodeKindSymlink = 2,
  LDFileNodeKindSpecial = 3
} LDFileNodeKind;

@interface LDFileNode : NSObject
{
  NSString *_path;
  NSString *_displayName;
  LDFileNodeKind _kind;
  unsigned long long _size;
  unsigned long long _allocatedSize;
  unsigned long long _aggregateSize;
  NSUInteger _fileCount;
  NSUInteger _directoryCount;
  NSString *_errorCode;
  NSMutableArray *_children;
  LDFileNode *_parent;
}

+ (id)nodeWithPath:(NSString *)path kind:(LDFileNodeKind)kind size:(unsigned long long)size;
- (id)initWithPath:(NSString *)path kind:(LDFileNodeKind)kind size:(unsigned long long)size;

- (NSString *)path;
- (NSString *)displayName;
- (LDFileNodeKind)kind;
- (unsigned long long)size;
- (unsigned long long)allocatedSize;
- (void)setAllocatedSize:(unsigned long long)allocatedSize;
- (unsigned long long)aggregateSize;
- (NSUInteger)fileCount;
- (NSUInteger)directoryCount;
- (NSString *)errorCode;
- (void)setErrorCode:(NSString *)errorCode;
- (LDFileNode *)parent;
- (NSArray *)children;
- (void)addChild:(LDFileNode *)child;
- (void)recalculateAggregateSize;
- (NSComparisonResult)compareByAggregateSizeThenName:(LDFileNode *)other;
- (NSDictionary *)snapshotDictionary;

@end
