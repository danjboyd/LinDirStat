#import "LDScanner.h"
#import "LDFileNode.h"
#import "LDScanSession.h"

#include <dirent.h>
#include <errno.h>
#include <string.h>
#include <sys/stat.h>

@implementation LDScanner

- (id)init
{
  self = [super init];
  if (self) {
    _visitedHardLinks = [[NSMutableSet alloc] init];
    _visitedDirectories = [[NSMutableSet alloc] init];
  }
  return self;
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

- (NSString *)hardLinkKeyForStat:(struct stat *)info
{
  if (!S_ISREG(info->st_mode) || info->st_nlink < 2) {
    return nil;
  }
  return [NSString stringWithFormat:@"%llu:%llu",
          (unsigned long long)info->st_dev,
          (unsigned long long)info->st_ino];
}

- (NSString *)directoryKeyForStat:(struct stat *)info
{
  if (!S_ISDIR(info->st_mode)) {
    return nil;
  }
  return [NSString stringWithFormat:@"%llu:%llu",
          (unsigned long long)info->st_dev,
          (unsigned long long)info->st_ino];
}

- (LDFileNode *)scanPath:(NSString *)path session:(LDScanSession *)session
{
  [_visitedHardLinks removeAllObjects];
  [_visitedDirectories removeAllObjects];
  [session markScanning];
  LDFileNode *root = [self scanPath:path parentSession:session];
  if (root) {
    [root recalculateAggregateSize];
    [session setRootNode:root];
    [session markComplete];
  } else {
    [session markFailed];
  }
  return root;
}

- (LDFileNode *)scanPath:(NSString *)path parentSession:(LDScanSession *)session
{
  if ([session isCanceled]) {
    return nil;
  }

  [session setCurrentPath:path];

  struct stat info;
  if (lstat([path fileSystemRepresentation], &info) != 0) {
    LDFileNode *missing = [LDFileNode nodeWithPath:path kind:LDFileNodeKindSpecial size:0];
    [missing setErrorCode:[NSString stringWithFormat:@"stat_failed:%s", strerror(errno)]];
    [session incrementErrorCount];
    [session incrementSkippedCount];
    return missing;
  }

  LDFileNodeKind kind = [self kindForMode:info.st_mode];
  unsigned long long size = S_ISREG(info.st_mode) || S_ISLNK(info.st_mode) ? (unsigned long long)info.st_size : 0;
  LDFileNode *node = [LDFileNode nodeWithPath:path kind:kind size:size];
  [node setAllocatedSize:(unsigned long long)info.st_blocks * 512ULL];

  NSString *hardLinkKey = [self hardLinkKeyForStat:&info];
  if (hardLinkKey) {
    if ([_visitedHardLinks containsObject:hardLinkKey]) {
      [node setErrorCode:@"hard_link_duplicate"];
      [session incrementSkippedCount];
      return node;
    }
    [_visitedHardLinks addObject:hardLinkKey];
  }

  if (kind != LDFileNodeKindDirectory) {
    if (kind == LDFileNodeKindSpecial) {
      [node setErrorCode:@"special_file"];
      [session incrementSkippedCount];
    }
    return node;
  }

  NSString *directoryKey = [self directoryKeyForStat:&info];
  if (directoryKey) {
    if ([_visitedDirectories containsObject:directoryKey]) {
      [node setErrorCode:@"directory_cycle"];
      [session incrementSkippedCount];
      return node;
    }
    [_visitedDirectories addObject:directoryKey];
  }

  DIR *directory = opendir([path fileSystemRepresentation]);
  if (directory == NULL) {
    [node setErrorCode:@"directory_unreadable"];
    [session incrementErrorCount];
    [session incrementSkippedCount];
    return node;
  }

  NSMutableArray *names = [NSMutableArray array];
  struct dirent *entry = NULL;
  while ((entry = readdir(directory)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }

    NSString *name = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:entry->d_name
                                                                                 length:strlen(entry->d_name)];
    if (name == nil) {
      [session incrementSkippedCount];
      continue;
    }
    [names addObject:name];
  }
  closedir(directory);

  NSArray *sortedNames = [names sortedArrayUsingSelector:@selector(compare:)];
  NSEnumerator *enumerator = [sortedNames objectEnumerator];
  NSString *name = nil;
  while ((name = [enumerator nextObject])) {
    NSAutoreleasePool *childPool = [[NSAutoreleasePool alloc] init];
    if ([session isCanceled]) {
      [childPool release];
      break;
    }
    NSString *childPath = [path stringByAppendingPathComponent:name];
    LDFileNode *child = [self scanPath:childPath parentSession:session];
    if (child) {
      [node addChild:child];
    }
    [childPool release];
  }

  return node;
}

- (void)dealloc
{
  [_visitedHardLinks release];
  [_visitedDirectories release];
  [super dealloc];
}

@end
