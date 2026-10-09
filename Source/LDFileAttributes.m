#import "LDFileAttributes.h"
#import "LDFileNode.h"

#include <errno.h>
#include <pthread.h>
#include <pwd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

@implementation LDFileAttributes

+ (NSString *)attributeStringForNode:(LDFileNode *)node
{
  unsigned int mode = [node mode];
  if (mode == 0) {
    return @"";
  }
  // Of WinDirStat's RHSACEOZ only R and H have Linux counterparts: System and
  // Archive are DOS flags, and Compressed, Encrypted, Offline and Sparse are
  // NTFS attributes that stat() does not report.
  char letters[3];
  size_t count = 0;
  LDFileNodeKind kind = [node kind];
  if ((kind == LDFileNodeKindFile || kind == LDFileNodeKindDirectory) && (mode & S_IWUSR) == 0) {
    letters[count++] = 'R';
  }
  if ([node nameBytes][0] == '.') {
    letters[count++] = 'H';
  }
  return [[NSString alloc] initWithBytes:letters length:count encoding:NSASCIIStringEncoding];
}

static pthread_mutex_t LDOwnerCacheLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary *LDOwnerCache = nil;

static NSString *LDOwnerNameForUID(uid_t uid)
{
  NSNumber *key = [NSNumber numberWithUnsignedLong:(unsigned long)uid];
  pthread_mutex_lock(&LDOwnerCacheLock);
  NSString *cached = [LDOwnerCache objectForKey:key];
  pthread_mutex_unlock(&LDOwnerCacheLock);
  if (cached) {
    return cached;
  }

  NSString *name = nil;
  long suggested = sysconf(_SC_GETPW_R_SIZE_MAX);
  size_t bufferSize = suggested > 0 ? (size_t)suggested : 1024;
  while (YES) {
    char *buffer = malloc(bufferSize);
    if (!buffer) {
      break;
    }
    struct passwd entry;
    struct passwd *result = NULL;
    int status = getpwuid_r(uid, &entry, buffer, bufferSize, &result);
    if (status == 0 && result && result->pw_name) {
      name = [NSString stringWithUTF8String:result->pw_name];
    }
    free(buffer);
    if (status != ERANGE || bufferSize >= 1024 * 1024) {
      break;
    }
    bufferSize *= 2;
  }
  if (!name) {
    name = [NSString stringWithFormat:@"%lu", (unsigned long)uid];
  }

  pthread_mutex_lock(&LDOwnerCacheLock);
  if (!LDOwnerCache) {
    LDOwnerCache = [[NSMutableDictionary alloc] init];
  }
  [LDOwnerCache setObject:name forKey:key];
  pthread_mutex_unlock(&LDOwnerCacheLock);
  return name;
}

+ (NSString *)ownerOfPath:(NSData *)pathData
{
  NSMutableData *terminated = [pathData mutableCopy];
  [terminated appendBytes:"\0" length:1];
  struct stat info;
  if (lstat([terminated bytes], &info) != 0) {
    return nil;
  }
  return LDOwnerNameForUID(info.st_uid);
}

@end
