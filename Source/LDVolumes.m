#import "LDVolumes.h"

#include <ctype.h>
#include <dispatch/dispatch.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/statvfs.h>
#if defined(__APPLE__)
#include <sys/mount.h>
#include <sys/stat.h>
#else
#include <sys/sysmacros.h>
#endif

static NSString *LDStringFromBytes(NSData *bytes)
{
  NSString *string = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
  return string ? string : [[NSString alloc] initWithData:bytes encoding:NSISOLatin1StringEncoding];
}

@implementation LDVolume

- (id)initWithMountPointData:(NSData *)mountPointData
                      device:(dev_t)device
              fileSystemType:(NSString *)fileSystemType
                      source:(NSString *)source
                       label:(NSString *)label
{
  self = [super init];
  if (self) {
    _mountPointData = [mountPointData copy];
    _mountPoint = LDStringFromBytes(_mountPointData);
    _device = device;
    _fileSystemType = [fileSystemType copy];
    _source = [source copy];
    _label = [label length] > 0 ? [label copy] : nil;
  }
  return self;
}

- (NSString *)mountPoint { return _mountPoint; }
- (NSData *)mountPointData { return _mountPointData; }
- (dev_t)device { return _device; }
- (NSString *)fileSystemType { return _fileSystemType; }
- (NSString *)source { return _source; }
- (NSString *)label { return _label; }
- (unsigned long long)totalBytes { return _totalBytes; }
- (unsigned long long)freeBytes { return _freeBytes; }
- (BOOL)isQueried { return _queried; }
- (BOOL)queryFailed { return _queryFailed; }

- (NSString *)displayName
{
  return _label ? [NSString stringWithFormat:@"%@ (%@)", _label, _mountPoint] : _mountPoint;
}

- (double)usedFraction
{
  if (_totalBytes == 0 || _freeBytes >= _totalBytes) {
    return 0.0;
  }
  return (double)(_totalBytes - _freeBytes) / (double)_totalBytes;
}

- (void)setTotalBytes:(unsigned long long)totalBytes freeBytes:(unsigned long long)freeBytes
{
  _totalBytes = totalBytes;
  _freeBytes = freeBytes;
  _queried = YES;
  _queryFailed = NO;
}

- (void)markQueryFailed
{
  _queried = NO;
  _queryFailed = YES;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"<LDVolume %@ %@ %@>", _mountPoint, _fileSystemType, _source];
}

@end

@implementation LDVolumes

+ (NSSet *)excludedFileSystemTypes
{
  static NSSet *types = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    types = [NSSet setWithObjects:
      // Pseudo filesystems.
      @"proc", @"sysfs", @"devtmpfs", @"devpts", @"tmpfs", @"ramfs", @"cgroup", @"cgroup2",
      @"securityfs", @"pstore", @"bpf", @"debugfs", @"tracefs", @"configfs", @"fusectl",
      @"mqueue", @"hugetlbfs", @"autofs", @"binfmt_misc", @"efivarfs", @"nsfs", @"squashfs",
      @"overlay", @"rpc_pipefs", @"nfsd", @"selinuxfs", @"fuse",
      // Network filesystems.
      @"nfs", @"nfs4", @"cifs", @"smb3", @"smbfs", @"sshfs", @"9p", @"afs", @"ceph",
      @"glusterfs", nil];
  });
  return types;
}

// fuseblk is a local block device (NTFS, exFAT); other FUSE mounts are not.
+ (BOOL)includesFileSystemType:(NSString *)type mountPoint:(NSData *)mountPoint
{
  if ([type isEqualToString:@"overlay"] && [mountPoint isEqualToData:[NSData dataWithBytes:"/" length:1]]) {
    return YES;
  }
  if ([type hasPrefix:@"fuse."]) {
    return NO;
  }
  return ![[self excludedFileSystemTypes] containsObject:type];
}

+ (NSData *)decodeMountInfoField:(NSData *)field
{
  const unsigned char *bytes = [field bytes];
  NSUInteger length = [field length];
  NSMutableData *decoded = [NSMutableData dataWithCapacity:length];
  NSUInteger i = 0;
  while (i < length) {
    unsigned char c = bytes[i];
    if (c == '\\' && i + 3 < length
        && bytes[i + 1] >= '0' && bytes[i + 1] <= '3'
        && bytes[i + 2] >= '0' && bytes[i + 2] <= '7'
        && bytes[i + 3] >= '0' && bytes[i + 3] <= '7') {
      c = (unsigned char)(((bytes[i + 1] - '0') << 6) | ((bytes[i + 2] - '0') << 3) | (bytes[i + 3] - '0'));
      i += 4;
    } else {
      i++;
    }
    [decoded appendBytes:&c length:1];
  }
  return decoded;
}

// Splits one line on spaces (mountinfo escapes spaces inside fields).
+ (NSArray *)fieldsOfLine:(const char *)line length:(NSUInteger)length
{
  NSMutableArray *fields = [NSMutableArray array];
  NSUInteger start = 0;
  for (NSUInteger i = 0; i <= length; i++) {
    if (i == length || line[i] == ' ') {
      if (i > start) {
        [fields addObject:[NSData dataWithBytes:line + start length:i - start]];
      }
      start = i + 1;
    }
  }
  return fields;
}

+ (BOOL)parseDevice:(NSData *)field into:(dev_t *)device
{
  NSString *text = LDStringFromBytes(field);
  NSArray *parts = [text componentsSeparatedByString:@":"];
  if ([parts count] != 2) {
    return NO;
  }
  *device = makedev((unsigned int)[[parts objectAtIndex:0] longLongValue],
                    (unsigned int)[[parts objectAtIndex:1] longLongValue]);
  return YES;
}

// A volume for one mountinfo line, or nil if the line is malformed or the
// filesystem is not a local disk.
+ (LDVolume *)volumeFromFields:(NSArray *)fields labels:(NSDictionary *)labels
{
  NSUInteger separator = [fields indexOfObject:[NSData dataWithBytes:"-" length:1]];
  dev_t device = 0;
  if (separator == NSNotFound || separator < 6 || separator + 2 >= [fields count]
      || ![self parseDevice:[fields objectAtIndex:2] into:&device]) {
    return nil;
  }
  NSData *mountPoint = [self decodeMountInfoField:[fields objectAtIndex:4]];
  NSString *type = LDStringFromBytes([self decodeMountInfoField:[fields objectAtIndex:separator + 1]]);
  if (![self includesFileSystemType:type mountPoint:mountPoint]) {
    return nil;
  }
  NSString *source = LDStringFromBytes([self decodeMountInfoField:[fields objectAtIndex:separator + 2]]);
  NSString *label = [labels objectForKey:[self resolvedDevicePath:source]];
  return [[LDVolume alloc] initWithMountPointData:mountPoint device:device fileSystemType:type source:source label:label];
}

+ (NSArray *)volumesFromMountInfoData:(NSData *)data labels:(NSDictionary *)labels
{
  NSMutableDictionary *byDevice = [NSMutableDictionary dictionary];
  const char *bytes = [data bytes];
  NSUInteger length = [data length];
  NSUInteger start = 0;
  for (NSUInteger i = 0; i <= length; i++) {
    if (i < length && bytes[i] != '\n') {
      continue;
    }
    LDVolume *volume = [self volumeFromFields:[self fieldsOfLine:bytes + start length:i - start] labels:labels];
    start = i + 1;
    if (!volume) {
      continue;
    }
    // Bind mounts share a device; list it once, where it is shortest.
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)[volume device]];
    LDVolume *existing = [byDevice objectForKey:key];
    if (!existing || [[volume mountPointData] length] < [[existing mountPointData] length]) {
      [byDevice setObject:volume forKey:key];
    }
  }
  return [[byDevice allValues] sortedArrayUsingComparator:^NSComparisonResult(LDVolume *left, LDVolume *right) {
    NSData *a = [left mountPointData];
    NSData *b = [right mountPointData];
    int order = memcmp([a bytes], [b bytes], MIN([a length], [b length]));
    if (order == 0) {
      return [a length] < [b length] ? NSOrderedAscending : ([a length] > [b length] ? NSOrderedDescending : NSOrderedSame);
    }
    return order < 0 ? NSOrderedAscending : NSOrderedDescending;
  }];
}

+ (NSArray *)volumesFromMountInfo:(NSString *)text
{
  return [self volumesFromMountInfoData:[text dataUsingEncoding:NSUTF8StringEncoding] labels:nil];
}

#if defined(__APPLE__)

// The browsable local mounts from getmntinfo, as Finder lists them: APFS
// system volumes (Preboot, VM, Data...) are marked MNT_DONTBROWSE.
+ (NSArray *)localVolumes
{
  struct statfs *mounts = NULL;
  int count = getmntinfo(&mounts, MNT_NOWAIT);
  NSMutableDictionary *byDevice = [NSMutableDictionary dictionary];
  for (int i = 0; i < count; i++) {
    struct statfs *mount = &mounts[i];
    if (!(mount->f_flags & MNT_LOCAL) || (mount->f_flags & MNT_DONTBROWSE)) {
      continue;
    }
    struct stat info;
    if (stat(mount->f_mntonname, &info) != 0) {
      continue;
    }
    NSData *mountPoint = [NSData dataWithBytes:mount->f_mntonname length:strlen(mount->f_mntonname)];
    NSURL *url = [NSURL fileURLWithFileSystemRepresentation:mount->f_mntonname isDirectory:YES relativeToURL:nil];
    NSString *label = nil;
    [url getResourceValue:&label forKey:NSURLVolumeLocalizedNameKey error:NULL];
    LDVolume *volume = [[LDVolume alloc] initWithMountPointData:mountPoint
                                                         device:info.st_dev
                                                 fileSystemType:[NSString stringWithUTF8String:mount->f_fstypename]
                                                         source:[NSString stringWithUTF8String:mount->f_mntfromname]
                                                          label:[label length] > 0 ? label : nil];
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)info.st_dev];
    LDVolume *existing = [byDevice objectForKey:key];
    if (!existing || [mountPoint length] < [[existing mountPointData] length]) {
      [byDevice setObject:volume forKey:key];
    }
  }
  return [[byDevice allValues] sortedArrayUsingComparator:^NSComparisonResult(LDVolume *left, LDVolume *right) {
    NSData *a = [left mountPointData];
    NSData *b = [right mountPointData];
    int order = memcmp([a bytes], [b bytes], MIN([a length], [b length]));
    if (order == 0) {
      return [a length] < [b length] ? NSOrderedAscending : ([a length] > [b length] ? NSOrderedDescending : NSOrderedSame);
    }
    return order < 0 ? NSOrderedAscending : NSOrderedDescending;
  }];
}

#else

+ (NSArray *)localVolumes
{
  NSData *data = [NSData dataWithContentsOfFile:@"/proc/self/mountinfo"];
  return data ? [self volumesFromMountInfoData:data labels:[self deviceLabels]] : [NSArray array];
}

#endif

+ (NSString *)resolvedDevicePath:(NSString *)path
{
  char resolved[PATH_MAX];
  if (![path hasPrefix:@"/"] || realpath([path fileSystemRepresentation], resolved) == NULL) {
    return path;
  }
  return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:resolved length:strlen(resolved)];
}

// udev escapes label characters as "\xHH" in the link names.
+ (NSString *)decodeLabel:(NSString *)name
{
  const char *bytes = [name UTF8String];
  NSMutableData *decoded = [NSMutableData data];
  size_t length = strlen(bytes);
  size_t i = 0;
  while (i < length) {
    char hex[3] = { 0, 0, 0 };
    if (bytes[i] == '\\' && i + 3 < length && bytes[i + 1] == 'x'
        && isxdigit((unsigned char)bytes[i + 2]) && isxdigit((unsigned char)bytes[i + 3])) {
      hex[0] = bytes[i + 2];
      hex[1] = bytes[i + 3];
      unsigned char c = (unsigned char)strtoul(hex, NULL, 16);
      [decoded appendBytes:&c length:1];
      i += 4;
    } else {
      [decoded appendBytes:bytes + i length:1];
      i++;
    }
  }
  return LDStringFromBytes(decoded);
}

+ (NSDictionary *)deviceLabels
{
  NSString *directory = @"/dev/disk/by-label";
  NSMutableDictionary *labels = [NSMutableDictionary dictionary];
  for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL]) {
    NSString *device = [self resolvedDevicePath:[directory stringByAppendingPathComponent:name]];
    [labels setObject:[self decodeLabel:name] forKey:device];
  }
  return labels;
}

+ (BOOL)queryUsageForVolume:(LDVolume *)volume
{
  NSMutableData *path = [[volume mountPointData] mutableCopy];
  [path appendBytes:"\0" length:1];
  struct statvfs info;
  if (statvfs([path bytes], &info) != 0) {
    [volume markQueryFailed];
    return NO;
  }
  [volume setTotalBytes:(unsigned long long)info.f_blocks * info.f_frsize
              freeBytes:(unsigned long long)info.f_bavail * info.f_frsize];
  return YES;
}

@end
