#import "LDScanner.h"
#import "LDFileNode.h"
#import "LDScanSession.h"
#import "LDExtensionStats.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>

@implementation LDScanner

- (id)init
{
  self = [super init];
  if (self) {
    _visitedHardLinks = [[NSMutableSet alloc] init];
    _visitedDirectories = [[NSMutableSet alloc] init];
    _internedExtensionKeys = [[NSMutableDictionary alloc] init];
    _sortMetric = LDSizeMetricPhysical;
  }
  return self;
}

- (BOOL)crossesFilesystems { return _crossesFilesystems; }
- (void)setCrossesFilesystems:(BOOL)crossesFilesystems { _crossesFilesystems = crossesFilesystems; }
- (LDSizeMetric)sortMetric { return _sortMetric; }
- (void)setSortMetric:(LDSizeMetric)sortMetric { _sortMetric = sortMetric; }

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

// Builds a node from stat data. Hard-link duplicates and special files keep
// their identity in the tree but contribute no bytes, so totals match `du`.
// Returns the shared key instance for a file name's extension. Short ASCII
// extensions are parsed straight from the dirent bytes, so the common case
// allocates nothing that outlives the lookup.
- (NSString *)internedExtensionKeyForName:(NSString *)name rawName:(const char *)rawName
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

  NSString *key = nil;
  if (simple) {
    NSString *probe = [[NSString alloc] initWithBytesNoCopy:buffer
                                                     length:length
                                                   encoding:NSASCIIStringEncoding
                                               freeWhenDone:NO];
    key = [_internedExtensionKeys objectForKey:probe];
    if (!key) {
      key = [probe copy];
      [_internedExtensionKeys setObject:key forKey:key];
    }
    return key;
  }

  NSString *computed = [LDExtensionStats extensionKeyForFilename:name];
  key = [_internedExtensionKeys objectForKey:computed];
  if (!key) {
    [_internedExtensionKeys setObject:computed forKey:computed];
    key = computed;
  }
  return key;
}

- (LDFileNode *)nodeNamed:(NSString *)name rawName:(const char *)rawName path:(NSString *)path info:(const struct stat *)info session:(LDScanSession *)session
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
    NSString *key = [self identityKeyForStat:info];
    if ([_visitedHardLinks containsObject:key]) {
      errorCode = @"hard_link_duplicate";
      size = 0;
      allocated = 0;
      [session incrementSkippedCount];
    } else {
      [_visitedHardLinks addObject:key];
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
    [node setExtensionKey:[self internedExtensionKeyForName:name rawName:rawName]];
  }

  if (kind == LDFileNodeKindDirectory) {
    [session recordDirectory];
  } else {
    [session recordFileWithBytes:allocated];
  }
  return node;
}

- (LDFileNode *)scanPath:(NSString *)path session:(LDScanSession *)session
{
  [_visitedHardLinks removeAllObjects];
  [_visitedDirectories removeAllObjects];
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
  LDFileNode *root = [self nodeNamed:[path lastPathComponent] rawName:NULL path:path info:&info session:session];
  if ([root kind] == LDFileNodeKindDirectory) {
    [_visitedDirectories addObject:[self identityKeyForStat:&info]];
    [self scanDirectoryNode:root path:path session:session];
  }

  [root recalculateAggregateSize];
  [root sortChildrenByMetric:_sortMetric];
  [session setRootNode:root];
  [session markComplete];
  return root;
}

- (void)scanDirectoryNode:(LDFileNode *)node path:(NSString *)path session:(LDScanSession *)session
{
  DIR *directory = opendir([path fileSystemRepresentation]);
  if (directory == NULL) {
    [node setErrorCode:@"directory_unreadable"];
    [session incrementErrorCount];
    [session incrementSkippedCount];
    return;
  }

  int directoryFD = dirfd(directory);
  NSMutableArray *subdirectories = [NSMutableArray array];
  // One pool per directory: under ARC few objects are autoreleased, and a
  // pool per entry costs more than it saves.
  @autoreleasepool {
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
        child = [self nodeNamed:name rawName:entry->d_name path:nil info:&info session:session];
        if ([child kind] == LDFileNodeKindDirectory) {
          NSString *key = [self identityKeyForStat:&info];
          if (![self shouldDescendIntoDevice:info.st_dev]) {
            [child setErrorCode:@"mount_point"];
            [session incrementSkippedCount];
          } else if ([_visitedDirectories containsObject:key]) {
            [child setErrorCode:@"directory_cycle"];
            [session incrementSkippedCount];
          } else {
            [_visitedDirectories addObject:key];
            [subdirectories addObject:child];
          }
        }
      }
      [node addChild:child];
    }
  }
  closedir(directory);

  NSEnumerator *enumerator = [subdirectories objectEnumerator];
  LDFileNode *subdirectory = nil;
  while ((subdirectory = [enumerator nextObject])) {
    if ([session isCanceled]) {
      break;
    }
    @autoreleasepool {
      NSString *childPath = [path stringByAppendingPathComponent:[subdirectory displayName]];
      [session setCurrentPath:childPath];
      [self scanDirectoryNode:subdirectory path:childPath session:session];
    }
  }
}


@end
