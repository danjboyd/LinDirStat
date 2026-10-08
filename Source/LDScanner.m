#import "LDScanner.h"
#import "LDFileNode.h"
#import "LDScanSession.h"
#import "LDExtensionStats.h"

#include <dirent.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>

static const NSUInteger LDDefaultScanThreads = 4;

@implementation LDScanner

- (id)init
{
  self = [super init];
  if (self) {
    _visitedHardLinks = [[NSMutableSet alloc] init];
    _visitedDirectories = [[NSMutableSet alloc] init];
    _internedExtensionKeys = [[NSMutableDictionary alloc] init];
    pthread_mutex_init(&_sharedStateLock, NULL);
    _workCondition = [[NSCondition alloc] init];
    _pendingDirectories = [[NSMutableArray alloc] init];
    _sortMetric = LDSizeMetricPhysical;
    _threadCount = LDDefaultScanThreads;
  }
  return self;
}

- (void)dealloc
{
  pthread_mutex_destroy(&_sharedStateLock);
}

- (BOOL)crossesFilesystems { return _crossesFilesystems; }
- (void)setCrossesFilesystems:(BOOL)crossesFilesystems { _crossesFilesystems = crossesFilesystems; }
- (LDSizeMetric)sortMetric { return _sortMetric; }
- (void)setSortMetric:(LDSizeMetric)sortMetric { _sortMetric = sortMetric; }
+ (NSUInteger)defaultThreadCount { return LDDefaultScanThreads; }
- (NSUInteger)threadCount { return _threadCount; }
- (void)setThreadCount:(NSUInteger)threadCount { _threadCount = MAX((NSUInteger)1, threadCount); }

- (BOOL)shouldDescendIntoDevice:(dev_t)device
{
  return _crossesFilesystems || device == _rootDevice;
}

- (LDFileNodeKind)kindForMode:(mode_t)mode
{
  if (S_ISDIR(mode)) {
    return LDFileNodeKindDirectory;
  }
  if (S_ISLNK(mode)) {
    return LDFileNodeKindSymlink;
  }
  if (S_ISREG(mode)) {
    return LDFileNodeKindFile;
  }
  return LDFileNodeKindSpecial;
}

- (NSString *)identityKeyForStat:(const struct stat *)info
{
  return [NSString stringWithFormat:@"%llu:%llu",
          (unsigned long long)info->st_dev,
          (unsigned long long)info->st_ino];
}

#pragma mark - Shared state (called from workers)

// Adds key to set; returns NO if it was already there.
- (BOOL)insertKey:(NSString *)key intoSet:(NSMutableSet *)set
{
  pthread_mutex_lock(&_sharedStateLock);
  BOOL inserted = ![set containsObject:key];
  if (inserted) {
    [set addObject:key];
  }
  pthread_mutex_unlock(&_sharedStateLock);
  return inserted;
}

// Interns through the worker's own cache first, so the shared lock is taken
// only the first time a worker meets an extension.
- (NSString *)internKey:(NSString *)candidate cache:(NSMutableDictionary *)cache
{
  NSString *cached = [cache objectForKey:candidate];
  if (cached) {
    return cached;
  }
  pthread_mutex_lock(&_sharedStateLock);
  NSString *key = [_internedExtensionKeys objectForKey:candidate];
  if (!key) {
    key = [candidate copy];
    [_internedExtensionKeys setObject:key forKey:key];
  }
  pthread_mutex_unlock(&_sharedStateLock);
  [cache setObject:key forKey:key];
  return key;
}

// Returns the shared key instance for a file name's extension. Short ASCII
// extensions are parsed straight from the dirent bytes, so the common case
// allocates nothing that outlives the lookup.
- (NSString *)internedExtensionKeyForName:(NSString *)name rawName:(const char *)rawName cache:(NSMutableDictionary *)cache
{
  char buffer[32];
  size_t length = 0;
  BOOL simple = NO;
  if (rawName) {
    const char *dot = strrchr(rawName, '.');
    if (dot == NULL || dot == rawName || dot[1] == '\0') {
      return @"<none>";
    }
    simple = YES;
    const char *cursor = dot + 1;
    while (*cursor && simple) {
      unsigned char c = (unsigned char)*cursor++;
      if (c >= 0x80 || length >= sizeof(buffer)) {
        simple = NO;
      } else {
        buffer[length++] = (char)((c >= 'A' && c <= 'Z') ? c + ('a' - 'A') : c);
      }
    }
  }

  if (simple) {
    NSString *probe = [[NSString alloc] initWithBytesNoCopy:buffer
                                                     length:length
                                                   encoding:NSASCIIStringEncoding
                                               freeWhenDone:NO];
    return [self internKey:probe cache:cache];
  }
  return [self internKey:[LDExtensionStats extensionKeyForFilename:name] cache:cache];
}

// Builds a node from stat data. Hard-link duplicates and special files keep
// their identity in the tree but contribute no bytes, so totals match `du`.
- (LDFileNode *)nodeNamed:(NSString *)name rawName:(const char *)rawName path:(NSString *)path info:(const struct stat *)info session:(LDScanSession *)session cache:(NSMutableDictionary *)cache
{
  LDFileNodeKind kind = [self kindForMode:info->st_mode];
  unsigned long long size = 0;
  unsigned long long allocated = 0;
  if (kind == LDFileNodeKindFile || kind == LDFileNodeKindSymlink) {
    size = (unsigned long long)info->st_size;
    allocated = (unsigned long long)info->st_blocks * 512ULL;
  }

  NSString *errorCode = nil;
  if (kind == LDFileNodeKindFile && info->st_nlink > 1) {
    if (![self insertKey:[self identityKeyForStat:info] intoSet:_visitedHardLinks]) {
      errorCode = @"hard_link_duplicate";
      size = 0;
      allocated = 0;
      [session incrementSkippedCount];
    }
  } else if (kind == LDFileNodeKindSpecial) {
    errorCode = @"special_file";
    [session incrementSkippedCount];
  }

  LDFileNode *node = nil;
  if (path) {
    node = [LDFileNode nodeWithPath:path kind:kind size:size];
    [node setAllocatedSize:allocated];
  } else {
    node = [LDFileNode nodeWithName:name kind:kind size:size allocatedSize:allocated];
  }
  [node setModificationTime:(NSTimeInterval)info->st_mtime];
  [node setMode:(unsigned int)info->st_mode];
  if (errorCode) {
    [node setErrorCode:errorCode];
  }
  if (kind == LDFileNodeKindFile || kind == LDFileNodeKindSymlink) {
    [node setExtensionKey:[self internedExtensionKeyForName:name rawName:rawName cache:cache]];
  }

  return node;
}

#pragma mark - Scanning

- (LDFileNode *)scanPath:(NSString *)path session:(LDScanSession *)session
{
  [_visitedHardLinks removeAllObjects];
  [_visitedDirectories removeAllObjects];
  [_pendingDirectories removeAllObjects];
  _activeWorkers = 0;
  [session markScanning];
  [session setCurrentPath:path];

  // The root follows symlinks so scanning a linked folder scans its target.
  struct stat info;
  if (stat([path fileSystemRepresentation], &info) != 0) {
    LDFileNode *missing = [LDFileNode nodeWithPath:path kind:LDFileNodeKindSpecial size:0];
    [missing setErrorCode:[NSString stringWithFormat:@"stat_failed:%s", strerror(errno)]];
    [session incrementErrorCount];
    [session incrementSkippedCount];
    [session setRootNode:missing];
    [session markComplete];
    return missing;
  }

  _rootDevice = info.st_dev;
  LDFileNode *root = [self nodeNamed:[path lastPathComponent] rawName:NULL path:path info:&info session:session cache:nil];
  if ([root kind] == LDFileNodeKindDirectory) {
    [session recordDirectory];
  } else {
    [session recordFileWithBytes:[root allocatedSize]];
  }
  if ([root kind] == LDFileNodeKindDirectory) {
    [_visitedDirectories addObject:[self identityKeyForStat:&info]];
    [_pendingDirectories addObject:@[root, path]];
    [self runWorkersWithSession:session];
  }

  [root recalculateAggregateSize];
  [root sortChildrenByMetric:_sortMetric];
  [session setRootNode:root];
  [session markComplete];
  return root;
}

// Drains _pendingDirectories with _threadCount workers. A worker waits while
// the stack is empty but another worker may still add subdirectories, and
// all workers exit once nothing is pending and nobody is busy.
- (void)runWorkersWithSession:(LDScanSession *)session
{
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  dispatch_apply(_threadCount, queue, ^(size_t worker) {
    (void)worker;
    NSMutableDictionary *keyCache = [NSMutableDictionary dictionary];
    while (YES) {
      NSArray *job = nil;
      [_workCondition lock];
      while ([_pendingDirectories count] == 0 && _activeWorkers > 0 && ![session isCanceled]) {
        [_workCondition wait];
      }
      if ([_pendingDirectories count] == 0 || [session isCanceled]) {
        [_workCondition broadcast];
        [_workCondition unlock];
        return;
      }
      job = [_pendingDirectories lastObject];
      [_pendingDirectories removeLastObject];
      _activeWorkers++;
      [_workCondition unlock];

      NSArray *subdirectories = nil;
      @autoreleasepool {
        LDFileNode *node = [job objectAtIndex:0];
        NSString *path = [job objectAtIndex:1];
        [session setCurrentPath:path];
        subdirectories = [self readDirectoryNode:node path:path session:session cache:keyCache];
      }

      [_workCondition lock];
      [_pendingDirectories addObjectsFromArray:subdirectories];
      _activeWorkers--;
      [_workCondition broadcast];
      [_workCondition unlock];
    }
  });
}

// Reads one directory, adding its entries as children of node. Returns the
// subdirectories still to scan as [node, path] pairs.
- (NSArray *)readDirectoryNode:(LDFileNode *)node path:(NSString *)path session:(LDScanSession *)session cache:(NSMutableDictionary *)cache
{
  DIR *directory = opendir([path fileSystemRepresentation]);
  if (directory == NULL) {
    [node setErrorCode:@"directory_unreadable"];
    [session incrementErrorCount];
    [session incrementSkippedCount];
    return nil;
  }

  int directoryFD = dirfd(directory);
  NSMutableArray *subdirectories = [NSMutableArray array];
  NSUInteger files = 0;
  NSUInteger directories = 0;
  unsigned long long bytes = 0;
  struct dirent *entry = NULL;
  while ((entry = readdir(directory)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    if ([session isCanceled]) {
      break;
    }

    size_t nameLength = strlen(entry->d_name);
    NSString *name = [[NSString alloc] initWithBytes:entry->d_name
                                              length:nameLength
                                            encoding:NSUTF8StringEncoding];
    if (name == nil) {
      // Not valid UTF-8; fall back to the locale's filesystem encoding.
      name = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:entry->d_name length:nameLength];
    }
    if (name == nil) {
      [session incrementSkippedCount];
      continue;
    }

    struct stat info;
    LDFileNode *child = nil;
    if (fstatat(directoryFD, entry->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0) {
      child = [LDFileNode nodeWithName:name kind:LDFileNodeKindSpecial size:0 allocatedSize:0];
      [child setErrorCode:[NSString stringWithFormat:@"stat_failed:%s", strerror(errno)]];
      [session incrementErrorCount];
      [session incrementSkippedCount];
    } else {
      child = [self nodeNamed:name rawName:entry->d_name path:nil info:&info session:session cache:cache];
      if ([child kind] == LDFileNodeKindDirectory) {
        directories++;
      } else {
        files++;
        bytes += [child allocatedSize];
      }
      if ([child kind] == LDFileNodeKindDirectory) {
        if (![self shouldDescendIntoDevice:info.st_dev]) {
          [child setErrorCode:@"mount_point"];
          [session incrementSkippedCount];
        } else if (![self insertKey:[self identityKeyForStat:&info] intoSet:_visitedDirectories]) {
          [child setErrorCode:@"directory_cycle"];
          [session incrementSkippedCount];
        } else {
          [subdirectories addObject:@[child, [path stringByAppendingPathComponent:name]]];
        }
      }
    }
    [node addChild:child];
  }
  closedir(directory);
  [session recordFiles:files directories:directories bytes:bytes];
  return subdirectories;
}

@end
