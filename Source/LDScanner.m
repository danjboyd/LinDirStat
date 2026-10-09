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
    _arenas = [[NSMutableArray alloc] init];
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
- (NSString *)internedExtensionKeyForNode:(LDFileNode *)node cache:(NSMutableDictionary *)cache
{
  const char *rawName = [node nameBytes];
  const char *dot = strrchr(rawName, '.');
  if (dot == NULL || dot == rawName || dot[1] == '\0') {
    return @"<none>";
  }

  char buffer[32];
  size_t length = 0;
  const char *cursor = dot + 1;
  while (*cursor) {
    unsigned char c = (unsigned char)*cursor++;
    if (c >= 0x80 || length >= sizeof(buffer)) {
      return [self internKey:[LDExtensionStats extensionKeyForFilename:[node displayName]] cache:cache];
    }
    buffer[length++] = (char)((c >= 'A' && c <= 'Z') ? c + ('a' - 'A') : c);
  }
  NSString *probe = [[NSString alloc] initWithBytesNoCopy:buffer
                                                   length:length
                                                 encoding:NSASCIIStringEncoding
                                             freeWhenDone:NO];
  return [self internKey:probe cache:cache];
}

// Fills in a node from stat data. Hard-link duplicates and special files keep
// their identity in the tree but contribute no bytes, so totals match `du`.
- (void)applyStat:(const struct stat *)info toNode:(LDFileNode *)node session:(LDScanSession *)session cache:(NSMutableDictionary *)cache
{
  LDFileNodeKind kind = [node kind];
  if (kind == LDFileNodeKindFile && info->st_nlink > 1) {
    if (![self insertKey:[self identityKeyForStat:info] intoSet:_visitedHardLinks]) {
      [node setSize:0 allocatedSize:0];
      [node setError:LDFileNodeErrorHardLinkDuplicate errorNumber:0];
      [session incrementSkippedCount];
    }
  } else if (kind == LDFileNodeKindSpecial) {
    [node setError:LDFileNodeErrorSpecialFile errorNumber:0];
    [session incrementSkippedCount];
  }
  [node setModificationTime:(NSTimeInterval)info->st_mtime];
  [node setMode:(unsigned int)info->st_mode];
  if (kind == LDFileNodeKindFile || kind == LDFileNodeKindSymlink) {
    [node setExtensionKey:[self internedExtensionKeyForNode:node cache:cache]];
  }
}

- (void)sizesForStat:(const struct stat *)info kind:(LDFileNodeKind)kind size:(unsigned long long *)size allocated:(unsigned long long *)allocated
{
  *size = 0;
  *allocated = 0;
  if (kind == LDFileNodeKindFile || kind == LDFileNodeKindSymlink) {
    *size = (unsigned long long)info->st_size;
    *allocated = (unsigned long long)info->st_blocks * 512ULL;
  }
}

#pragma mark - Scanning

- (void)resetForScan
{
  [_visitedHardLinks removeAllObjects];
  [_visitedDirectories removeAllObjects];
  [_pendingDirectories removeAllObjects];
  [_arenas removeAllObjects];
  _retiredArrays = [[NSMutableArray alloc] init];
  _activeWorkers = 0;
}

- (LDFileNode *)scanPath:(NSString *)path session:(LDScanSession *)session
{
  [self resetForScan];
  [session markScanning];
  [session setCurrentPath:path];

  // The root follows symlinks so scanning a linked folder scans its target.
  struct stat info;
  const char *rootPath = [path fileSystemRepresentation];
  if (stat(rootPath, &info) != 0) {
    LDFileNode *missing = [LDFileNode nodeWithPath:path kind:LDFileNodeKindSpecial size:0];
    [missing setError:LDFileNodeErrorStatFailed errorNumber:errno];
    [session incrementErrorCount];
    [session incrementSkippedCount];
    [session setRootNode:missing];
    [session markComplete];
    return missing;
  }

  _rootDevice = info.st_dev;
  LDFileNodeKind kind = [self kindForMode:info.st_mode];
  unsigned long long size = 0;
  unsigned long long allocated = 0;
  [self sizesForStat:&info kind:kind size:&size allocated:&allocated];
  LDFileNode *root = [LDFileNode nodeWithPath:path kind:kind size:size];
  [root setAllocatedSize:allocated];
  [self applyStat:&info toNode:root session:session cache:nil];
  [self scanEntry:root stat:&info pathBytes:[NSData dataWithBytes:rootPath length:strlen(rootPath)] session:session];
  [session markComplete];
  return root;
}

- (LDFileNode *)scanEntryAtPathData:(NSData *)pathData session:(LDScanSession *)session
{
  [self resetForScan];
  [session markScanning];
  NSString *displayPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:[pathData bytes]
                                                                                       length:[pathData length]];
  [session setCurrentPath:displayPath];

  NSMutableData *terminated = [pathData mutableCopy];
  [terminated appendBytes:"\0" length:1];
  const char *path = [terminated bytes];
  const char *slash = strrchr(path, '/');
  const char *name = slash ? slash + 1 : path;

  // Mount points stay unentered relative to the containing folder.
  struct stat parentInfo;
  NSData *parentPath = slash && slash != path ? [NSData dataWithBytes:path length:(NSUInteger)(slash - path)] : [NSData dataWithBytes:"/" length:1];
  NSMutableData *parentTerminated = [parentPath mutableCopy];
  [parentTerminated appendBytes:"\0" length:1];

  struct stat info;
  if (lstat(path, &info) != 0 || stat([parentTerminated bytes], &parentInfo) != 0) {
    [session markComplete];
    return nil;
  }
  _rootDevice = parentInfo.st_dev;

  LDFileNodeKind kind = [self kindForMode:info.st_mode];
  unsigned long long size = 0;
  unsigned long long allocated = 0;
  [self sizesForStat:&info kind:kind size:&size allocated:&allocated];
  LDFileNode *node = [LDFileNode nodeWithNameBytes:name length:strlen(name) arena:nil
                                              kind:kind size:size allocatedSize:allocated];
  [self applyStat:&info toNode:node session:session cache:nil];
  if (kind == LDFileNodeKindDirectory && ![self shouldDescendIntoDevice:info.st_dev]) {
    [node setError:LDFileNodeErrorMountPoint errorNumber:0];
    [session incrementSkippedCount];
    [session setRootNode:node];
    [session markComplete];
    return node;
  }
  [self scanEntry:node stat:&info pathBytes:pathData session:session];
  [session markComplete];
  return node;
}

// Reads root's subtree (if it is a directory), then totals and sorts it.
// The root is published to the session first, so the tree can be shown
// while it grows.
- (void)scanEntry:(LDFileNode *)root stat:(const struct stat *)info pathBytes:(NSData *)pathBytes session:(LDScanSession *)session
{
  if ([root kind] == LDFileNodeKindDirectory) {
    LDDirectoryNode *directory = (LDDirectoryNode *)root;
    [directory beginPendingScans:1];
    [session setRootNode:root];
    [session recordDirectory];
    [_visitedDirectories addObject:[self identityKeyForStat:info]];
    [_pendingDirectories addObject:@[root, pathBytes]];
    [self runWorkersWithSession:session];
    [directory setOwnedStorage:[_arenas copy]];
    [_arenas removeAllObjects];
  } else {
    [session recordFileWithBytes:[root allocatedSize]];
  }

  [root recalculateAggregateSize];
  [root sortChildrenByMetric:_sortMetric retiring:_retiredArrays];
  [session setRootNode:root];
}

- (NSArray *)takeRetiredArrays
{
  NSArray *retired = _retiredArrays;
  _retiredArrays = nil;
  return retired;
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
    LDNameArena *arena = [[LDNameArena alloc] init];
    [_workCondition lock];
    [_arenas addObject:arena];
    [_workCondition unlock];
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
        subdirectories = [self readDirectoryNode:[job objectAtIndex:0]
                                       pathBytes:[job objectAtIndex:1]
                                         session:session
                                           arena:arena
                                           cache:keyCache];
      }

      [_workCondition lock];
      [_pendingDirectories addObjectsFromArray:subdirectories];
      _activeWorkers--;
      [_workCondition broadcast];
      [_workCondition unlock];
    }
  });
}

// Reads one directory, adding its entries as children of node. Paths stay
// raw bytes so names that are not valid UTF-8 still open. Returns the
// subdirectories still to scan as [node, path bytes] pairs.
- (NSArray *)readDirectoryNode:(LDFileNode *)node
                     pathBytes:(NSData *)pathBytes
                       session:(LDScanSession *)session
                         arena:(LDNameArena *)arena
                         cache:(NSMutableDictionary *)cache
{
  size_t pathLength = [pathBytes length];
  char *path = malloc(pathLength + 1);
  memcpy(path, [pathBytes bytes], pathLength);
  path[pathLength] = '\0';
  [session setCurrentPath:[[NSFileManager defaultManager] stringWithFileSystemRepresentation:path length:pathLength]];

  LDDirectoryNode *directoryNode = (LDDirectoryNode *)node;
  DIR *directory = opendir(path);
  if (directory == NULL) {
    free(path);
    [node setError:LDFileNodeErrorDirectoryUnreadable errorNumber:errno];
    [session incrementErrorCount];
    [session incrementSkippedCount];
    [directoryNode finishPendingScan];
    return nil;
  }

  int directoryFD = dirfd(directory);
  BOOL rootIsSlash = (pathLength == 1 && path[0] == '/');
  NSMutableArray *subdirectories = [NSMutableArray array];
  NSMutableArray *children = [NSMutableArray array];
  NSUInteger files = 0;
  NSUInteger directories = 0;
  unsigned long long bytes = 0;
  unsigned long long logicalBytes = 0;
  int64_t newest = (int64_t)[node modificationTime];
  struct dirent *entry = NULL;
  while ((entry = readdir(directory)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    if ([session isCanceled]) {
      break;
    }

    size_t nameLength = strlen(entry->d_name);
    struct stat info;
    if (fstatat(directoryFD, entry->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0) {
      LDFileNode *failed = [LDFileNode nodeWithNameBytes:entry->d_name length:nameLength arena:arena
                                                    kind:LDFileNodeKindSpecial size:0 allocatedSize:0];
      [failed setError:LDFileNodeErrorStatFailed errorNumber:errno];
      [session incrementErrorCount];
      [session incrementSkippedCount];
      [children addObject:failed];
      files++;
      continue;
    }

    LDFileNodeKind kind = [self kindForMode:info.st_mode];
    unsigned long long size = 0;
    unsigned long long allocated = 0;
    [self sizesForStat:&info kind:kind size:&size allocated:&allocated];
    LDFileNode *child = [LDFileNode nodeWithNameBytes:entry->d_name length:nameLength arena:arena
                                                 kind:kind size:size allocatedSize:allocated];
    [self applyStat:&info toNode:child session:session cache:cache];
    [children addObject:child];
    newest = MAX(newest, (int64_t)info.st_mtime);

    if (kind != LDFileNodeKindDirectory) {
      files++;
      bytes += [child allocatedSize];
      logicalBytes += [child size];
      continue;
    }
    directories++;
    if (![self shouldDescendIntoDevice:info.st_dev]) {
      [child setError:LDFileNodeErrorMountPoint errorNumber:0];
      [session incrementSkippedCount];
    } else if (![self insertKey:[self identityKeyForStat:&info] intoSet:_visitedDirectories]) {
      [child setError:LDFileNodeErrorDirectoryCycle errorNumber:0];
      [session incrementSkippedCount];
    } else {
      NSMutableData *childPath = [NSMutableData dataWithCapacity:pathLength + nameLength + 1];
      [childPath appendBytes:path length:pathLength];
      if (!rootIsSlash) {
        [childPath appendBytes:"/" length:1];
      }
      [childPath appendBytes:entry->d_name length:nameLength];
      [subdirectories addObject:@[child, childPath]];
    }
  }
  closedir(directory);
  free(path);

  // Publish before queueing the subdirectories, which are read as children
  // of this node. Each queued subdirectory holds one pending read here.
  [directoryNode publishChildren:children];
  [directoryNode addLiveFiles:files directories:directories size:logicalBytes allocatedSize:bytes modificationTime:newest];
  for (NSArray *job in subdirectories) {
    [(LDDirectoryNode *)[job objectAtIndex:0] beginPendingScans:1];
  }
  [directoryNode beginPendingScans:[subdirectories count]];
  [directoryNode finishPendingScan];
  [session recordFiles:files directories:directories bytes:bytes];
  return subdirectories;
}

@end
