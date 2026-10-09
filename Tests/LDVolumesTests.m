#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDVolumes.h"

#if !defined(__APPLE__)
#include <sys/sysmacros.h>
#endif

@interface LDVolumesTests : XCTestCase
@end

@implementation LDVolumesTests

- (NSString *)fixtureMountInfo
{
  return [@[
    @"22 1 259:2 / / rw,relatime shared:1 - ext4 /dev/nvme0n1p2 rw",
    @"23 22 0:21 / /proc rw,nosuid shared:5 - proc proc rw",
    @"24 22 0:22 / /sys rw,nosuid shared:6 - sysfs sysfs rw",
    @"25 22 0:5 / /dev rw,nosuid shared:2 - devtmpfs udev rw,size=8000000k",
    @"26 25 0:23 / /dev/pts rw,nosuid shared:3 - devpts devpts rw",
    @"27 22 0:24 / /run rw,nosuid shared:7 - tmpfs tmpfs rw",
    @"28 24 0:25 / /sys/fs/cgroup rw shared:8 - cgroup2 cgroup2 rw",
    @"29 22 259:1 / /boot/efi rw,relatime shared:9 - vfat /dev/nvme0n1p1 rw",
    @"30 22 259:3 / /home rw,relatime shared:10 - ext4 /dev/nvme0n1p3 rw",
    @"31 22 259:3 /dan/shared /srv/shared\\040home rw,relatime shared:10 - ext4 /dev/nvme0n1p3 rw",
    @"32 22 0:30 / /var/lib/docker/overlay2/abc/merged rw - overlay overlay rw",
    @"33 22 7:0 / /snap/core/123 ro shared:11 - squashfs /dev/loop0 ro",
    @"34 22 0:40 / /mnt/nas rw shared:12 - nfs4 nas:/export rw",
    @"35 22 0:41 / /mnt/remote rw shared:13 - fuse.sshfs dan@host: rw",
    @"36 22 8:17 / /media/dan/My\\040Disk rw shared:14 - fuseblk /dev/sdb1 rw",
    @"37 22 0:42 / /run/user/1000/doc rw - fuse.portal portal rw",
    @"38 22 0:43 / /mnt/share rw - cifs //server/share rw",
    @"39 22 8:33 / /mnt/back\\134slash rw - xfs /dev/lindirstat-test-disk rw",
    @"malformed line without separator",
    @""
  ] componentsJoinedByString:@"\n"];
}

- (NSArray *)mountPointsOf:(NSArray *)volumes
{
  NSMutableArray *mountPoints = [NSMutableArray array];
  for (LDVolume *volume in volumes) {
    [mountPoints addObject:[volume mountPoint]];
  }
  return mountPoints;
}

- (void)testParsesLocalDisksAndSkipsPseudoNetworkAndFuse
{
  NSArray *volumes = [LDVolumes volumesFromMountInfo:[self fixtureMountInfo]];
  NSArray *expected = @[@"/", @"/boot/efi", @"/home", @"/media/dan/My Disk", @"/mnt/back\\slash"];
  XCTAssertEqualObjects(expected, [self mountPointsOf:volumes]);

  LDVolume *root = [volumes objectAtIndex:0];
  XCTAssertEqual(makedev(259, 2), [root device]);
  XCTAssertEqualObjects(@"ext4", [root fileSystemType]);
  XCTAssertEqualObjects(@"/dev/nvme0n1p2", [root source]);
  XCTAssertEqualObjects(@"/", [root displayName]);
  XCTAssertFalse([root isQueried]);

  LDVolume *usb = [volumes objectAtIndex:3];
  XCTAssertEqualObjects(@"fuseblk", [usb fileSystemType]);
  XCTAssertEqualObjects([NSData dataWithBytes:"/media/dan/My Disk" length:18], [usb mountPointData]);
}

- (void)testBindMountsAreListedOnceAtTheShortestMountPoint
{
  NSString *text = [@[
    @"31 22 259:3 /dan/shared /srv/shared rw - ext4 /dev/nvme0n1p3 rw",
    @"30 22 259:3 / /home rw - ext4 /dev/nvme0n1p3 rw"
  ] componentsJoinedByString:@"\n"];
  NSArray *volumes = [LDVolumes volumesFromMountInfo:text];
  XCTAssertEqualObjects(@[@"/home"], [self mountPointsOf:volumes]);
}

- (void)testOverlayIsKeptOnlyAsTheRootFilesystem
{
  NSString *text = [@[
    @"1 0 0:50 / / rw - overlay overlay rw,lowerdir=/a",
    @"2 1 0:51 / /merged rw - overlay overlay rw"
  ] componentsJoinedByString:@"\n"];
  XCTAssertEqualObjects(@[@"/"], [self mountPointsOf:[LDVolumes volumesFromMountInfo:text]]);
}

- (void)testDecodesOctalEscapes
{
  NSData *field = [@"/a\\040b\\011c\\134d\\012e\\9" dataUsingEncoding:NSUTF8StringEncoding];
  NSData *decoded = [LDVolumes decodeMountInfoField:field];
  XCTAssertEqualObjects([NSData dataWithBytes:"/a b\tc\\d\ne\\9" length:12], decoded);
}

- (void)testDisplayNameUsesTheLabel
{
  NSData *text = [@"39 22 8:33 / /mnt/data rw - xfs /dev/lindirstat-test-disk rw\n" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *labels = @{@"/dev/lindirstat-test-disk": @"Backups"};
  LDVolume *volume = [[LDVolumes volumesFromMountInfoData:text labels:labels] objectAtIndex:0];
  XCTAssertEqualObjects(@"Backups", [volume label]);
  XCTAssertEqualObjects(@"Backups (/mnt/data)", [volume displayName]);
}

- (void)testUsedFractionIsClamped
{
  LDVolume *volume = [[LDVolume alloc] initWithMountPointData:[NSData dataWithBytes:"/" length:1]
                                                       device:1 fileSystemType:@"ext4" source:@"/dev/x" label:nil];
  XCTAssertEqual(0.0, [volume usedFraction]);
  [volume setTotalBytes:400 freeBytes:100];
  XCTAssertTrue([volume isQueried]);
  XCTAssertEqualWithAccuracy(0.75, [volume usedFraction], 1e-9);
  [volume setTotalBytes:100 freeBytes:400];
  XCTAssertEqual(0.0, [volume usedFraction]);
  [volume setTotalBytes:0 freeBytes:0];
  XCTAssertEqual(0.0, [volume usedFraction]);
}

- (void)testQueriesTheRealRootVolume
{
  NSArray *volumes = [LDVolumes localVolumes];
  XCTAssertTrue([volumes count] > 0);
  for (LDVolume *volume in volumes) {
    XCTAssertFalse([[volume fileSystemType] isEqualToString:@"proc"]);
    XCTAssertFalse([[volume fileSystemType] isEqualToString:@"tmpfs"]);
  }
  LDVolume *root = [volumes objectAtIndex:0];
  if (![[root mountPoint] isEqualToString:@"/"]) {
    return;
  }
  XCTAssertTrue([LDVolumes queryUsageForVolume:root]);
  XCTAssertTrue([root isQueried]);
  XCTAssertTrue([root totalBytes] > 0);
  XCTAssertTrue([root freeBytes] <= [root totalBytes]);
  XCTAssertTrue([root usedFraction] > 0.0 && [root usedFraction] <= 1.0);
}

- (void)testQueryOfAMissingMountPointFails
{
  LDVolume *volume = [[LDVolume alloc] initWithMountPointData:[NSData dataWithBytes:"/no/such/mount" length:14]
                                                       device:1 fileSystemType:@"ext4" source:@"/dev/x" label:nil];
  XCTAssertFalse([LDVolumes queryUsageForVolume:volume]);
  XCTAssertFalse([volume isQueried]);
  XCTAssertTrue([volume queryFailed]);
}

@end
