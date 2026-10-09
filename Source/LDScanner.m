#import "LDScanner.h"
#import "LDFileNode.h"
#import "LDScanSession.h"
#import "LDExtensionStats.h"
#import "LDScanOptions.h"
#import "LDScanClock.h"
#import "LDDuplicateFinder.h"
#import "LDHardLinks.h"

#include <dirent.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <string.h>
#include <sys/stat.h>
#if defined(__APPLE__)
#include <sys/mount.h>
#endif

// YES if path is where a volume is mounted. The APFS volumes of one group
// (System and Data) report the same st_dev, so the device test misses the
// Data volume at /System/Volumes/Data; entering it would race the firmlinks
// (/Users, /Applications...) for the same directories.
static BOOL LDIsVolumeMountPoint(const char *path)
{
#if defined(__APPLE__)
  struct statfs info;
  return statfs(path, &info) == 0 && strcmp(info.f_mntonname, path) == 0;
#else
  (void)path;
  return NO;
#endif
}

typedef enum {
  LDLinkSkip = 0,
  LDLinkLeaf,
  LDLinkFollow
} LDLinkDisposition;

// One directory waiting to be read. rootDevice is the filesystem of the scan
// root it belongs to, for the mount-point rule.
@interface LDScanJob : NSObject
{
@public
  LDDirectoryNode *_node;
  NSData *_path;
  dev_t _rootDevice;
}
@end

@implementation LDScanJob
@end

static LDScanJob *LDMakeScanJob(LDFileNode *node, NSData *path, dev_t rootDevice)
{
  LDScanJob *job = [[LDScanJob alloc] init];
  job->_node = (LDDirectoryNode *)node;
  job->_path = path;
  job->_rootDevice = rootDevice;
  return job;
}

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
    _options = [[LDScanOptions alloc] init];
    _threadCount = [_options threadCount];
  }
  return self;
}

- (void)dealloc
{
  pthread_mutex_destroy(&_sharedStateLock);
}

- (LDScanOptions *)scanOptions { return _options; }

- (void)setScanOptions:(LDScanOptions *)options
{
  _options = options ? [options copy] : [[LDScanOptions alloc] init];
  _threadCount = [_options threadCount];
}

- (BOOL)crossesFilesystems { return ![_options excludeMountPoints]; }

- (void)setCrossesFilesystems:(BOOL)crossesFilesystems
{
  LDScanOptions *options = [_options copy];
  [options setExcludeMountPoints:!crossesFilesystems];
  _options = options;
}

- (BOOL)findsDuplicates { return [_options findsDuplicates]; }

- (void)setFindsDuplicates:(BOOL)findsDuplicates
{
  LDScanOptions *options = [_options copy];
  [options setFindsDuplicates:findsDuplicates];
  _options = options;
}

- (void)setHardLinkTable:(LDHardLinkTable *)table replacing:(LDFileNode *)node
{
  _hardLinks = table;
  _replacedNode = node;
  _usesGivenHardLinks = (table != nil);
}

- (LDHardLinkTable *)hardLinkTable { return _hardLinks; }

- (LDSizeMetric)sortMetric { return _sortMetric; }
- (void)setSortMetric:(LDSizeMetric)sortMetric { _sortMetric = sortMetric; }
+ (NSUInteger)defaultThreadCount { return [[[LDScanOptions alloc] init] threadCount]; }
- (NSUInteger)threadCount { return _threadCount; }
- (void)setThreadCount:(NSUInteger)threadCount { _threadCount = MAX((NSUInteger)1, threadCount); }

- (BOOL)shouldDescendIntoDevice:(dev_t)device rootDevice:(dev_t)rootDevice
{
  return ![_options excludeMountPoints] || device == rootDevice;
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
    if (![_hardLinks addLink:node device:info->st_dev inode:(unsigned long long)info->st_ino
                        size:[node size] allocatedSize:[node allocatedSize] ignoringLinksUnder:_replacedNode]) {
      [session incrementSkippedCount];
    }
  } else if (kind == LDFileNodeKindFile && ![_options excludeSymbolicLinks]) {
    // When links are followed, a file can also be reached through a link, so
    // every file is counted once by identity, not only multiply linked ones.
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

#pragma mark - Filters

- (LDPathFilter *)compiledFilterForPatterns:(NSArray *)patterns
{
  if ([patterns count] == 0) {
    return nil;
  }
  LDPathFilter *filter = [[LDPathFilter alloc] initWithPatterns:patterns usesRegex:[_options usesRegex]];
  return [filter count] > 0 ? filter : nil;
}

// Decides what a symlink entry becomes. A link is followed by replacing info
// with its target's; a dangling link counts as a link to a file.
- (LDLinkDisposition)dispositionForLinkAt:(int)directoryFD
                                     name:(const char *)name
                                     stat:(struct stat *)info
                              isDirectory:(BOOL *)isDirectory
{
  struct stat target;
  BOOL resolved = fstatat(directoryFD, name, &target, 0) == 0;
  *isDirectory = resolved && S_ISDIR(target.st_mode);
  if ([_options excludeSymbolicLinks]) {
    return *isDirectory ? LDLinkLeaf : LDLinkSkip;
  }
  if (!resolved) {
    return LDLinkLeaf;
  }
  *info = target;
  return LDLinkFollow;
}

#pragma mark - Scanning

- (void)resetForScan
{
  [_visitedHardLinks removeAllObjects];
  if (!_usesGivenHardLinks) {
    _hardLinks = [[LDHardLinkTable alloc] init];
    [_hardLinks setShowsHardLinks:[_options processHardLinks]];
  }
  _attachesHardLinks = NO;
  [_visitedDirectories removeAllObjects];
  [_pendingDirectories removeAllObjects];
  [_arenas removeAllObjects];
  _retiredArrays = [[NSMutableArray alloc] init];
  _duplicateCollector = nil;
  _activeWorkers = 0;
  _readDuration = 0;
  _finishDuration = 0;
  _folderFilter = [self compiledFilterForPatterns:[_options excludedFolderPatterns]];
  _fileFilter = [self compiledFilterForPatterns:[_options excludedFilePatterns]];
}

// The node for a scan root, following a symlink at the root. The root is
// never filtered. If it cannot be read the result carries the stat error.
- (LDFileNode *)nodeForRootPath:(NSString *)path stat:(struct stat *)info session:(LDScanSession *)session
{
  if (stat([path fileSystemRepresentation], info) != 0) {
    LDFileNode *missing = [LDFileNode nodeWithPath:path kind:LDFileNodeKindSpecial size:0];
    [missing setError:LDFileNodeErrorStatFailed errorNumber:errno];
    [session incrementErrorCount];
    [session incrementSkippedCount];
    return missing;
  }
  LDFileNodeKind kind = [self kindForMode:info->st_mode];
  unsigned long long size = 0;
  unsigned long long allocated = 0;
  [self sizesForStat:info kind:kind size:&size allocated:&allocated];
  LDFileNode *root = [LDFileNode nodeWithPath:path kind:kind size:size];
  [root setAllocatedSize:allocated];
  [self applyStat:info toNode:root session:session cache:nil];
  return root;
}

- (NSData *)pathBytesForPath:(NSString *)path
{
  const char *bytes = [path fileSystemRepresentation];
  return [NSData dataWithBytes:bytes length:strlen(bytes)];
}

- (LDFileNode *)scanPath:(NSString *)path session:(LDScanSession *)session
{
  [self resetForScan];
  [self beginDuplicateCollectionForSession:session];
  _attachesHardLinks = !_usesGivenHardLinks;
  [session markScanning];
  [session setCurrentPath:path];

  struct stat info;
  LDFileNode *root = [self nodeForRootPath:path stat:&info session:session];
  if ([root error] == LDFileNodeErrorStatFailed) {
    [session setRootNode:root];
  } else {
    [self scanEntry:root stat:&info pathBytes:[self pathBytesForPath:path] rootDevice:info.st_dev session:session];
  }
  [self finishDuplicateCollection];
  [session markComplete];
  return root;
}

- (void)beginDuplicateCollectionForSession:(LDScanSession *)session
{
  _duplicateCollector = nil;
  if (![_options findsDuplicates]) {
    return;
  }
  LDDuplicateCollector *collector = [session duplicateCollector];
  if (!collector) {
    collector = [[LDDuplicateCollector alloc] init];
    [session setDuplicateCollector:collector];
  }
  _duplicateCollector = collector;
}

- (void)finishDuplicateCollection
{
  [_duplicateCollector finishAdding];
  _duplicateCollector = nil;
}

- (LDFileNode *)scanPaths:(NSArray *)paths session:(LDScanSession *)session
{
  if ([paths count] == 1) {
    return [self scanPath:[paths objectAtIndex:0] session:session];
  }
  [self resetForScan];
  [self beginDuplicateCollectionForSession:session];
  _attachesHardLinks = !_usesGivenHardLinks;
  [session markScanning];
  [session setCurrentPath:[paths firstObject]];

  LDComputerNode *computer = [LDComputerNode computerNode];
  NSMutableArray *roots = [NSMutableArray array];
  NSUInteger queued = 0;
  for (NSString *path in paths) {
    struct stat info;
    LDFileNode *root = [self nodeForRootPath:path stat:&info session:session];
    [roots addObject:root];
    if ([root error] != LDFileNodeErrorStatFailed
        && [self queueRoot:root stat:&info pathBytes:[self pathBytesForPath:path] rootDevice:info.st_dev session:session]) {
      queued++;
    }
  }
  // Each queued root holds one pending read on the computer node, so it
  // stays pending until the last root is done.
  [computer publishChildren:roots];
  [_duplicateCollector addNodes:roots];
  [computer beginPendingScans:queued];
  [session setRootNode:computer];
  if (queued > 0) {
    [self runWorkersWithSession:session];
  }
  [self giveArenasToDirectory:computer];
  [self finishTree:computer session:session];
  [self finishDuplicateCollection];
  [session markComplete];
  return computer;
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

  LDFileNodeKind kind = [self kindForMode:info.st_mode];
  if (kind == LDFileNodeKindSymlink) {
    BOOL isDirectory = NO;
    LDLinkDisposition disposition = [self dispositionForLinkAt:AT_FDCWD name:path stat:&info isDirectory:&isDirectory];
    if (disposition == LDLinkSkip) {
      [session markComplete];
      return nil;
    }
    if (disposition == LDLinkFollow) {
      kind = [self kindForMode:info.st_mode];
    }
  }
  unsigned long long size = 0;
  unsigned long long allocated = 0;
  [self sizesForStat:&info kind:kind size:&size allocated:&allocated];
  LDFileNode *node = [LDFileNode nodeWithNameBytes:name length:strlen(name) arena:nil
                                              kind:kind size:size allocatedSize:allocated];
  [self applyStat:&info toNode:node session:session cache:nil];
  if (kind == LDFileNodeKindDirectory && (![self shouldDescendIntoDevice:info.st_dev rootDevice:parentInfo.st_dev]
                                          || ([_options excludeMountPoints] && LDIsVolumeMountPoint(path)))) {
    [node setError:LDFileNodeErrorMountPoint errorNumber:0];
    [session incrementSkippedCount];
    [session setRootNode:node];
    [session markComplete];
    return node;
  }
  [self scanEntry:node stat:&info pathBytes:pathData rootDevice:parentInfo.st_dev session:session];
  [session markComplete];
  return node;
}

// Queues a root directory for the workers; a file root is only counted.
// Returns NO if nothing was queued (a file, or a directory already queued
// through another root).
- (BOOL)queueRoot:(LDFileNode *)root
             stat:(const struct stat *)info
        pathBytes:(NSData *)pathBytes
       rootDevice:(dev_t)rootDevice
          session:(LDScanSession *)session
{
  if ([root kind] != LDFileNodeKindDirectory) {
    [session recordFileWithBytes:[root allocatedSize]];
    return NO;
  }
  if (![self insertKey:[self identityKeyForStat:info] intoSet:_visitedDirectories]) {
    [root setError:LDFileNodeErrorDirectoryCycle errorNumber:0];
    [session incrementSkippedCount];
    return NO;
  }
  [(LDDirectoryNode *)root beginPendingScans:1];
  [session recordDirectory];
  [_pendingDirectories addObject:LDMakeScanJob(root, pathBytes, rootDevice)];
  return YES;
}

- (void)giveArenasToDirectory:(LDDirectoryNode *)directory
{
  [directory setOwnedStorage:_attachesHardLinks ? [_arenas arrayByAddingObject:_hardLinks] : [_arenas copy]];
  [_arenas removeAllObjects];
}

- (void)finishTree:(LDFileNode *)root session:(LDScanSession *)session
{
  NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
  if (_attachesHardLinks) {
    [LDHardLinks updateTree:root table:_hardLinks metric:_sortMetric retiring:_retiredArrays];
  }
  [root finishTreeSortedByMetric:_sortMetric retiring:_retiredArrays];
  [session setRootNode:root];
  _finishDuration = [NSDate timeIntervalSinceReferenceDate] - started;
}

// Reads root's subtree (if it is a directory), then totals and sorts it.
// The root is published to the session first, so the tree can be shown
// while it grows.
- (void)scanEntry:(LDFileNode *)root
             stat:(const struct stat *)info
        pathBytes:(NSData *)pathBytes
       rootDevice:(dev_t)rootDevice
          session:(LDScanSession *)session
{
  if ([self queueRoot:root stat:info pathBytes:pathBytes rootDevice:rootDevice session:session]) {
    [session setRootNode:root];
    [self runWorkersWithSession:session];
    [self giveArenasToDirectory:(LDDirectoryNode *)root];
  }
  [self finishTree:root session:session];
}

- (NSTimeInterval)readDuration { return _readDuration; }
- (NSTimeInterval)finishDuration { return _finishDuration; }

- (NSArray *)takeRetiredArrays
{
  NSArray *retired = _retiredArrays;
  _retiredArrays = nil;
  return retired;
}

// Drains _pendingDirectories with _threadCount workers. A worker waits while
// the stack is empty but another worker may still add subdirectories, and
// all workers exit once nothing is pending and nobody is busy. While the
// session is suspended, workers block between directory reads.
- (void)runWorkersWithSession:(LDScanSession *)session
{
  NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  dispatch_apply(_threadCount, queue, ^(size_t worker) {
    (void)worker;
    NSMutableDictionary *keyCache = [NSMutableDictionary dictionary];
    LDNameArena *arena = [[LDNameArena alloc] init];
    [_workCondition lock];
    [_arenas addObject:arena];
    [_workCondition unlock];
    while (YES) {
      [session waitWhileSuspended];
      LDScanJob *job = nil;
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
        subdirectories = [self readDirectoryJob:job session:session arena:arena cache:keyCache];
      }

      [_workCondition lock];
      [_pendingDirectories addObjectsFromArray:subdirectories];
      _activeWorkers--;
      [_workCondition broadcast];
      [_workCondition unlock];
    }
  });
  _readDuration = [NSDate timeIntervalSinceReferenceDate] - started;
}

// Reads one directory, adding its entries as children of the job's node.
// Paths stay raw bytes so names that are not valid UTF-8 still open. Entries
// the options exclude are not added and count toward nothing. Returns the
// subdirectories still to scan as jobs.
- (NSArray *)readDirectoryJob:(LDScanJob *)job
                      session:(LDScanSession *)session
                        arena:(LDNameArena *)arena
                        cache:(NSMutableDictionary *)cache
{
  LDDirectoryNode *directoryNode = job->_node;
  NSData *pathBytes = job->_path;
  size_t pathLength = [pathBytes length];
  BOOL rootIsSlash = (pathLength == 1 && ((const char *)[pathBytes bytes])[0] == '/');
  // path holds "<directory>/" followed by the current entry's name.
  size_t prefixLength = rootIsSlash ? pathLength : pathLength + 1;
  char *path = malloc(prefixLength + NAME_MAX + 1);
  memcpy(path, [pathBytes bytes], pathLength);
  path[pathLength] = '\0';
  [session setCurrentPath:[[NSFileManager defaultManager] stringWithFileSystemRepresentation:path length:pathLength]];

  DIR *directory = opendir(path);
  if (directory == NULL) {
    free(path);
    [directoryNode setError:LDFileNodeErrorDirectoryUnreadable errorNumber:errno];
    [session incrementErrorCount];
    [session incrementSkippedCount];
    [directoryNode noteScanActivityAt:LDScanClockMilliseconds()];
    [directoryNode finishPendingScan];
    return nil;
  }
  path[prefixLength - 1] = '/';
  char *nameSlot = path + prefixLength;

  BOOL excludeHidden = [_options excludeHidden];
  BOOL crossesFilesystems = ![_options excludeMountPoints];
  unsigned long long minimumFileSize = [_options minimumFileSize];
  int directoryFD = dirfd(directory);
  NSMutableArray *subdirectories = [NSMutableArray array];
  NSMutableArray *children = [NSMutableArray array];
  NSUInteger files = 0;
  NSUInteger directories = 0;
  unsigned long long bytes = 0;
  unsigned long long logicalBytes = 0;
  int64_t newest = (int64_t)[directoryNode modificationTime];
  NSUInteger entriesRead = 0;
  struct dirent *entry = NULL;
  while ((entry = readdir(directory)) != NULL) {
    const char *name = entry->d_name;
    if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) {
      continue;
    }
    if ([session isCanceled]) {
      break;
    }
    // A large folder keeps its pacmen awake while it is read (WinDirStat
    // drives them per entry).
    if (++entriesRead % 4096 == 0) {
      [directoryNode noteScanActivityAt:LDScanClockMilliseconds()];
    }
    if (excludeHidden && name[0] == '.') {
      continue;
    }

    size_t nameLength = strlen(name);
    struct stat info;
    if (fstatat(directoryFD, name, &info, AT_SYMLINK_NOFOLLOW) != 0) {
      if (_fileFilter && [_fileFilter matchesBytes:name]) {
        continue;
      }
      LDFileNode *failed = [LDFileNode nodeWithNameBytes:name length:nameLength arena:arena
                                                    kind:LDFileNodeKindSpecial size:0 allocatedSize:0];
      [failed setError:LDFileNodeErrorStatFailed errorNumber:errno];
      [session incrementErrorCount];
      [session incrementSkippedCount];
      [children addObject:failed];
      files++;
      continue;
    }

    LDFileNodeKind kind = [self kindForMode:info.st_mode];
    BOOL directoryLike = (kind == LDFileNodeKindDirectory);
    if (kind == LDFileNodeKindSymlink) {
      LDLinkDisposition disposition = [self dispositionForLinkAt:directoryFD name:name stat:&info isDirectory:&directoryLike];
      if (disposition == LDLinkSkip) {
        continue;
      }
      if (disposition == LDLinkFollow) {
        kind = [self kindForMode:info.st_mode];
      }
    }
    if (directoryLike) {
      memcpy(nameSlot, name, nameLength + 1);
      if (_folderFilter && [_folderFilter matchesBytes:path]) {
        continue;
      }
    } else if ((_fileFilter && [_fileFilter matchesBytes:name])
               || (kind == LDFileNodeKindFile && (unsigned long long)info.st_size < minimumFileSize)) {
      continue;
    }

    unsigned long long size = 0;
    unsigned long long allocated = 0;
    [self sizesForStat:&info kind:kind size:&size allocated:&allocated];
    LDFileNode *child = [LDFileNode nodeWithNameBytes:name length:nameLength arena:arena
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
    if (!crossesFilesystems && (info.st_dev != job->_rootDevice || LDIsVolumeMountPoint(path))) {
      [child setError:LDFileNodeErrorMountPoint errorNumber:0];
      [session incrementSkippedCount];
    } else if (![self insertKey:[self identityKeyForStat:&info] intoSet:_visitedDirectories]) {
      [child setError:LDFileNodeErrorDirectoryCycle errorNumber:0];
      [session incrementSkippedCount];
    } else {
      NSData *childPath = [NSData dataWithBytes:path length:prefixLength + nameLength];
      [subdirectories addObject:LDMakeScanJob(child, childPath, job->_rootDevice)];
    }
  }
  closedir(directory);
  free(path);

  // Publish before queueing the subdirectories, which are read as children
  // of this node. Each queued subdirectory holds one pending read here.
  [directoryNode publishChildren:children];
  if (_duplicateCollector) {
    [_duplicateCollector addNodes:children];
  }
  [directoryNode addLiveFiles:files directories:directories size:logicalBytes allocatedSize:bytes modificationTime:newest];
  [directoryNode noteScanActivityAt:LDScanClockMilliseconds()];
  for (LDScanJob *subdirectory in subdirectories) {
    [subdirectory->_node beginPendingScans:1];
  }
  [directoryNode beginPendingScans:[subdirectories count]];
  [directoryNode finishPendingScan];
  [session recordFiles:files directories:directories bytes:bytes];
  return subdirectories;
}

@end
