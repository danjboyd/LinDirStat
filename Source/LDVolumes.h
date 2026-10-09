#import <Foundation/Foundation.h>

#include <sys/types.h>

// One mounted local filesystem, as listed by the Select Drives dialog.
@interface LDVolume : NSObject
{
  NSString *_mountPoint;
  NSData *_mountPointData;
  dev_t _device;
  NSString *_fileSystemType;
  NSString *_source;
  NSString *_label;
  unsigned long long _totalBytes;
  unsigned long long _freeBytes;
  BOOL _queried;
  BOOL _queryFailed;
}

- (id)initWithMountPointData:(NSData *)mountPointData
                      device:(dev_t)device
              fileSystemType:(NSString *)fileSystemType
                      source:(NSString *)source
                       label:(NSString *)label;

- (NSString *)mountPoint;
// The exact mount point bytes (no NUL); use these to touch the filesystem.
- (NSData *)mountPointData;
- (dev_t)device;
- (NSString *)fileSystemType;
// The mounted device or source ("/dev/nvme0n1p2").
- (NSString *)source;
// The filesystem label from /dev/disk/by-label, or nil.
- (NSString *)label;
// "<label> (<mount point>)" when the label is known, else the mount point.
- (NSString *)displayName;

// Sizes, valid once -isQueried (see +[LDVolumes queryUsageForVolume:]).
// Free space is what an unprivileged user can use (f_bavail).
- (unsigned long long)totalBytes;
- (unsigned long long)freeBytes;
// (total - free) / total, clamped to 0..1; 0 when total is 0.
- (double)usedFraction;
- (BOOL)isQueried;
// YES once a query was attempted and statvfs failed ("(unavailable)").
- (BOOL)queryFailed;
- (void)setTotalBytes:(unsigned long long)totalBytes freeBytes:(unsigned long long)freeBytes;
- (void)markQueryFailed;

@end

// Lists local volumes, the Linux counterpart of WinDirStat's drive list.
@interface LDVolumes : NSObject

// The local volumes from /proc/self/mountinfo, sizes not yet queried.
+ (NSArray *)localVolumes;

// Parses mountinfo text. Pseudo, network and FUSE filesystems (except
// fuseblk) are left out, and bind mounts of one device are listed once, at
// the shortest mount point. Sorted by mount point. No labels are looked up.
+ (NSArray *)volumesFromMountInfo:(NSString *)text;
// As above, with labels mapping a resolved device path to its label.
+ (NSArray *)volumesFromMountInfoData:(NSData *)data labels:(NSDictionary *)labels;

// Resolved device path -> label, from the /dev/disk/by-label symlinks.
+ (NSDictionary *)deviceLabels;

// Fills in the volume's sizes with statvfs. Blocking; returns NO on failure.
+ (BOOL)queryUsageForVolume:(LDVolume *)volume;

// Decodes mountinfo's octal escapes ("\040" is a space).
+ (NSData *)decodeMountInfoField:(NSData *)field;

@end
