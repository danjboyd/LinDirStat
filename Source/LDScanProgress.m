#import "LDScanProgress.h"
#import "LDScanOptions.h"

#include <string.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#if defined(__APPLE__)
#include <sys/mount.h>
#endif

@implementation LDScanProgress

+ (BOOL)isVolumeRootPath:(NSString *)path
{
  const char *bytes = [path fileSystemRepresentation];
  if (!bytes) {
    return NO;
  }
#if defined(__APPLE__)
  // APFS volumes of one group share a device number.
  struct statfs volume;
  if (statfs(bytes, &volume) == 0) {
    char resolved[PATH_MAX];
    return realpath(bytes, resolved) && strcmp(volume.f_mntonname, resolved) == 0;
  }
  return NO;
#else
  struct stat info;
  struct stat parentInfo;
  NSString *parent = [[path stringByStandardizingPath] stringByAppendingPathComponent:@".."];
  if (stat(bytes, &info) != 0 || !S_ISDIR(info.st_mode) || stat([parent fileSystemRepresentation], &parentInfo) != 0) {
    return NO;
  }
  // "/" is its own parent.
  return info.st_dev != parentInfo.st_dev || info.st_ino == parentInfo.st_ino;
#endif
}

+ (unsigned long long)usedBytesOfVolumeAtPath:(NSString *)path
{
  struct statvfs volume;
  const char *bytes = [path fileSystemRepresentation];
  if (!bytes || statvfs(bytes, &volume) != 0 || volume.f_blocks < volume.f_bfree) {
    return 0;
  }
  unsigned long long unit = volume.f_frsize ? volume.f_frsize : volume.f_bsize;
  return (unsigned long long)(volume.f_blocks - volume.f_bfree) * unit;
}

+ (unsigned long long)rangeForScanPaths:(NSArray *)paths options:(LDScanOptions *)options
{
  if (!options) {
    options = [[LDScanOptions alloc] init];
  }
  if (![options excludeMountPoints] || ![options excludeSymbolicLinks]) {
    return 0;
  }
  NSMutableArray *used = [NSMutableArray array];
  for (NSString *path in paths) {
    BOOL volume = [self isVolumeRootPath:path];
    [used addObject:@(volume ? [self usedBytesOfVolumeAtPath:path] : 0ULL)];
    if (!volume) {
      break;
    }
  }
  return [self rangeForUsedBytes:used excludeMountPoints:YES excludeSymbolicLinks:YES];
}

+ (unsigned long long)rangeForUsedBytes:(NSArray *)usedBytes
                     excludeMountPoints:(BOOL)excludeMountPoints
                   excludeSymbolicLinks:(BOOL)excludeSymbolicLinks
{
  if (!excludeMountPoints || !excludeSymbolicLinks || [usedBytes count] == 0) {
    return 0;
  }
  unsigned long long range = 0;
  for (NSNumber *used in usedBytes) {
    if ([used unsignedLongLongValue] == 0) {
      return 0;
    }
    range += [used unsignedLongLongValue];
  }
  return range;
}

+ (NSInteger)percentForPosition:(unsigned long long)position range:(unsigned long long)range
{
  if (range == 0) {
    return 0;
  }
  if (position >= range) {
    return 100;
  }
  // Avoid overflowing position * 100 on huge volumes.
  return (NSInteger)((double)position * 100.0 / (double)range);
}

+ (NSString *)titlePrefixForPosition:(unsigned long long)position
                               range:(unsigned long long)range
                           suspended:(BOOL)suspended
{
  NSString *prefix = range > 0
    ? [NSString stringWithFormat:@"%ld%%", (long)[self percentForPosition:position range:range]]
    : @"Scanning";
  return suspended ? [prefix stringByAppendingString:@" (Suspended)"] : prefix;
}

@end
