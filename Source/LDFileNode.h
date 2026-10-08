#import <Foundation/Foundation.h>

typedef enum {
  LDFileNodeKindFile = 0,
  LDFileNodeKindDirectory = 1,
  LDFileNodeKindSymlink = 2,
  LDFileNodeKindSpecial = 3
} LDFileNodeKind;

// WinDirStat defaults to physical (allocated) sizes and offers logical sizes
// as an option ("Use Logical Size").
typedef enum {
  LDSizeMetricPhysical = 0,
  LDSizeMetricLogical = 1
} LDSizeMetric;

@interface LDFileNode : NSObject
{
  NSString *_name;
  NSString *_storedPath;
  LDFileNodeKind _kind;
  unsigned long long _size;
  unsigned long long _allocatedSize;
  unsigned long long _aggregateSize;
  unsigned long long _aggregateAllocatedSize;
  NSUInteger _fileCount;
  NSUInteger _directoryCount;
  NSTimeInterval _modificationTime;
  NSTimeInterval _aggregateModificationTime;
  unsigned int _mode;
  NSString *_errorCode;
  NSString *_extensionKey;
  NSMutableArray *_children;
  LDFileNode *_parent;
}

// Creates a node that remembers its full path. Used for scan roots and tests.
+ (id)nodeWithPath:(NSString *)path kind:(LDFileNodeKind)kind size:(unsigned long long)size;
- (id)initWithPath:(NSString *)path kind:(LDFileNodeKind)kind size:(unsigned long long)size;

// Creates a node that stores only its name; its path is derived from its parent.
+ (id)nodeWithName:(NSString *)name kind:(LDFileNodeKind)kind size:(unsigned long long)size allocatedSize:(unsigned long long)allocatedSize;

- (NSString *)path;
- (NSString *)displayName;
- (LDFileNodeKind)kind;
- (BOOL)isLeaf;

// Logical size (st_size) of this node alone.
- (unsigned long long)size;
// Physical size (st_blocks * 512) of this node alone.
- (unsigned long long)allocatedSize;
- (void)setAllocatedSize:(unsigned long long)allocatedSize;
- (void)setSize:(unsigned long long)size allocatedSize:(unsigned long long)allocatedSize;
- (unsigned long long)sizeForMetric:(LDSizeMetric)metric;

// Logical subtree size.
- (unsigned long long)aggregateSize;
// Physical subtree size.
- (unsigned long long)aggregateAllocatedSize;
- (unsigned long long)aggregateSizeForMetric:(LDSizeMetric)metric;

- (NSUInteger)fileCount;
- (NSUInteger)directoryCount;

// Seconds since 1970. For directories, aggregateModificationTime is the newest
// time in the subtree, matching WinDirStat's "Last Change" column.
- (NSTimeInterval)modificationTime;
- (NSTimeInterval)aggregateModificationTime;
- (void)setModificationTime:(NSTimeInterval)modificationTime;
- (unsigned int)mode;
- (void)setMode:(unsigned int)mode;

// Lowercased extension used for grouping and colors ("<none>" if absent).
// Cached; the scanner sets interned instances so equal keys share storage.
- (NSString *)extensionKey;
- (void)setExtensionKey:(NSString *)extensionKey;

- (NSString *)errorCode;
- (void)setErrorCode:(NSString *)errorCode;
- (BOOL)isHardLinkDuplicate;
- (BOOL)isMountPoint;

- (LDFileNode *)parent;
- (NSArray *)children;
- (void)addChild:(LDFileNode *)child;
- (BOOL)isAncestorOf:(LDFileNode *)node;
- (NSUInteger)depth;

- (void)recalculateAggregateSize;
// Sorts children (recursively) by descending size for the metric, then name.
// Views read -children directly, so this must run once after a scan and again
// when the size metric changes.
- (void)sortChildrenByMetric:(LDSizeMetric)metric;

- (NSComparisonResult)compareByAggregateSizeThenName:(LDFileNode *)other;
- (NSDictionary *)snapshotDictionary;

@end
