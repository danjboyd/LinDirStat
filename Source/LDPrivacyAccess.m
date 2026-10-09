#import "LDPrivacyAccess.h"
#import "LDFileNode.h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

@implementation LDPrivacyAccess

+ (BOOL)hasFullDiskAccess
{
#if defined(__APPLE__)
  // The user's privacy database is readable only with Full Disk Access.
  NSString *database = [NSHomeDirectory() stringByAppendingPathComponent:
                        @"Library/Application Support/com.apple.TCC/TCC.db"];
  int fd = open([database fileSystemRepresentation], O_RDONLY);
  if (fd >= 0) {
    close(fd);
    return YES;
  }
  return errno != EPERM && errno != EACCES;
#else
  return YES;
#endif
}

+ (NSArray *)directoriesDeniedByPrivacyUnder:(LDFileNode *)root limit:(NSUInteger)limit
{
  NSMutableArray *denied = [NSMutableArray array];
  NSMutableArray *stack = root ? [NSMutableArray arrayWithObject:root] : [NSMutableArray array];
  while ([stack count] > 0 && [denied count] < limit) {
    LDFileNode *node = [stack lastObject];
    [stack removeLastObject];
    if ([node error] == LDFileNodeErrorDirectoryUnreadable && [node errorNumber] == EPERM) {
      [denied addObject:node];
      continue;
    }
    NSArray *children = [node children];
    // Reversed so that children come off the stack in tree order.
    for (NSUInteger i = [children count]; i > 0; i--) {
      LDFileNode *child = [children objectAtIndex:i - 1];
      if ([child kind] == LDFileNodeKindDirectory) {
        [stack addObject:child];
      }
    }
  }
  return denied;
}

@end
