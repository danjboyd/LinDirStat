#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDSelectTargetRules.h"
#import "LDVolumes.h"

@interface LDSelectTargetRulesTests : XCTestCase
@end

@implementation LDSelectTargetRulesTests

- (LDVolume *)volumeAt:(NSString *)mountPoint label:(NSString *)label total:(unsigned long long)total free:(unsigned long long)free
{
  LDVolume *volume = [[LDVolume alloc] initWithMountPointData:[mountPoint dataUsingEncoding:NSUTF8StringEncoding]
                                                       device:0
                                               fileSystemType:@"ext4"
                                                       source:@"/dev/test"
                                                        label:label];
  if (total > 0) {
    [volume setTotalBytes:total freeBytes:free];
  }
  return volume;
}

- (NSString *)temporaryDirectory
{
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"LDSelectTargetRulesTests-%d", getpid()]];
  [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
  return path;
}

- (void)testAllLocalDrivesTitleListsMountPoints
{
  XCTAssertEqualObjects(@"All local drives", [LDSelectTargetRules allLocalDrivesTitleForMountPoints:@[]]);
  XCTAssertEqualObjects(@"All local drives (/)", [LDSelectTargetRules allLocalDrivesTitleForMountPoints:@[@"/"]]);
  XCTAssertEqualObjects(@"All local drives (/ /boot/efi /home)",
                        ([LDSelectTargetRules allLocalDrivesTitleForMountPoints:@[@"/", @"/boot/efi", @"/home"]]));
}

- (void)testAllLocalDrivesTitleElidesLongLists
{
  NSArray *mountPoints = @[@"/", @"/boot/efi", @"/home", @"/media/dan/Backup Disk", @"/srv/data", @"/var/lib/big"];
  NSString *title = [LDSelectTargetRules allLocalDrivesTitleForMountPoints:mountPoints];
  XCTAssertEqualObjects(@"All local drives (/ /boot/efi /home /media/dan/Backup Disk …)", title);
  // A single long mount point is still shown whole.
  NSString *longPath = [@"/" stringByPaddingToLength:80 withString:@"x" startingAtIndex:0];
  XCTAssertEqualObjects(([NSString stringWithFormat:@"All local drives (%@)", longPath]),
                        [LDSelectTargetRules allLocalDrivesTitleForMountPoints:@[longPath]]);
}

- (void)testFolderPathExpandsTildeAndDropsTrailingSlashes
{
  XCTAssertEqualObjects(@"", [LDSelectTargetRules folderPathFromText:nil]);
  XCTAssertEqualObjects(@"", [LDSelectTargetRules folderPathFromText:@"  "]);
  XCTAssertEqualObjects(NSHomeDirectory(), [LDSelectTargetRules folderPathFromText:@"~"]);
  XCTAssertEqualObjects([NSHomeDirectory() stringByAppendingPathComponent:@"Music"],
                        [LDSelectTargetRules folderPathFromText:@"~/Music/"]);
  XCTAssertEqualObjects(@"/", [LDSelectTargetRules folderPathFromText:@"/"]);
  XCTAssertEqualObjects(@"/usr", [LDSelectTargetRules folderPathFromText:@"/usr//"]);
}

- (void)testUsableFolderNeedsAnExistingAbsoluteDirectory
{
  NSString *directory = [self temporaryDirectory];
  NSString *file = [directory stringByAppendingPathComponent:@"file.txt"];
  [@"x" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];

  XCTAssertTrue([LDSelectTargetRules isUsableFolderText:directory]);
  XCTAssertTrue([LDSelectTargetRules isUsableFolderText:[directory stringByAppendingString:@"/"]]);
  XCTAssertTrue([LDSelectTargetRules isUsableFolderText:@"~"]);
  XCTAssertFalse([LDSelectTargetRules isUsableFolderText:@""]);
  XCTAssertFalse([LDSelectTargetRules isUsableFolderText:file]);
  XCTAssertFalse([LDSelectTargetRules isUsableFolderText:[directory stringByAppendingPathComponent:@"missing"]]);
  XCTAssertFalse([LDSelectTargetRules isUsableFolderText:@"relative/path"]);
  [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

- (void)testOKEnablementPerMode
{
  NSString *directory = [self temporaryDirectory];
  XCTAssertTrue([LDSelectTargetRules canConfirmMode:LDSelectTargetAllLocalDrives volumeCount:1 selectedCount:0 folderText:@""]);
  XCTAssertFalse([LDSelectTargetRules canConfirmMode:LDSelectTargetAllLocalDrives volumeCount:0 selectedCount:0 folderText:directory]);
  XCTAssertTrue([LDSelectTargetRules canConfirmMode:LDSelectTargetIndividualDrives volumeCount:3 selectedCount:1 folderText:@""]);
  XCTAssertFalse([LDSelectTargetRules canConfirmMode:LDSelectTargetIndividualDrives volumeCount:3 selectedCount:0 folderText:directory]);
  XCTAssertTrue([LDSelectTargetRules canConfirmMode:LDSelectTargetFolder volumeCount:0 selectedCount:0 folderText:directory]);
  XCTAssertFalse([LDSelectTargetRules canConfirmMode:LDSelectTargetFolder volumeCount:3 selectedCount:2 folderText:@""]);
  XCTAssertFalse([LDSelectTargetRules canConfirmMode:LDSelectTargetFolder volumeCount:3 selectedCount:2
                                          folderText:[directory stringByAppendingPathComponent:@"missing"]]);
  [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

- (void)testPathsForEachMode
{
  NSArray *mountPoints = @[@"/", @"/boot/efi", @"/home"];
  NSMutableIndexSet *selected = [NSMutableIndexSet indexSetWithIndex:2];
  [selected addIndex:0];
  [selected addIndex:7]; // stale index past the list is ignored

  XCTAssertEqualObjects(mountPoints, ([LDSelectTargetRules pathsForMode:LDSelectTargetAllLocalDrives
                                                            mountPoints:mountPoints
                                                        selectedIndexes:selected
                                                             folderText:@"/tmp"]));
  XCTAssertEqualObjects((@[@"/", @"/home"]), ([LDSelectTargetRules pathsForMode:LDSelectTargetIndividualDrives
                                                                     mountPoints:mountPoints
                                                                 selectedIndexes:selected
                                                                      folderText:@"/tmp"]));
  XCTAssertEqualObjects(@[NSHomeDirectory()], ([LDSelectTargetRules pathsForMode:LDSelectTargetFolder
                                                                      mountPoints:mountPoints
                                                                  selectedIndexes:selected
                                                                       folderText:@"~/"]));
  XCTAssertNil([LDSelectTargetRules pathsForMode:LDSelectTargetIndividualDrives
                                     mountPoints:mountPoints
                                 selectedIndexes:[NSIndexSet indexSet]
                                      folderText:@"/tmp"]);
  XCTAssertNil([LDSelectTargetRules pathsForMode:LDSelectTargetAllLocalDrives
                                     mountPoints:@[]
                                 selectedIndexes:nil
                                      folderText:@"/tmp"]);
  XCTAssertNil([LDSelectTargetRules pathsForMode:LDSelectTargetFolder
                                     mountPoints:mountPoints
                                 selectedIndexes:nil
                                      folderText:@"/no/such/folder/for/lindirstat"]);
}

- (void)testPercentString
{
  XCTAssertEqualObjects(@"", [LDSelectTargetRules percentStringForVolume:[self volumeAt:@"/" label:nil total:0 free:0]]);
  XCTAssertEqualObjects(@"25.0%", [LDSelectTargetRules percentStringForVolume:[self volumeAt:@"/" label:nil total:400 free:300]]);
  XCTAssertEqualObjects(@"33.3%", [LDSelectTargetRules percentStringForVolume:[self volumeAt:@"/" label:nil total:3 free:2]]);
  XCTAssertEqualObjects(@"0.0%", [LDSelectTargetRules percentStringForVolume:[self volumeAt:@"/" label:nil total:100 free:200]]);
  LDVolume *failed = [self volumeAt:@"/" label:nil total:0 free:0];
  [failed markQueryFailed];
  XCTAssertEqualObjects(@"", [LDSelectTargetRules percentStringForVolume:failed]);
}

- (NSArray *)mountPointsOf:(NSArray *)volumes
{
  return [volumes valueForKey:@"mountPoint"];
}

- (void)testSortingByColumns
{
  LDVolume *root = [self volumeAt:@"/" label:nil total:1000 free:100];      // 90% used
  LDVolume *home = [self volumeAt:@"/home" label:@"Home" total:4000 free:2000]; // 50%
  LDVolume *efi = [self volumeAt:@"/boot/efi" label:nil total:500 free:450];   // 10%
  LDVolume *pending = [self volumeAt:@"/srv" label:nil total:0 free:0];
  NSArray *volumes = @[root, home, efi, pending];

  XCTAssertEqualObjects((@[@"/", @"/boot/efi", @"/srv", @"/home"]),
                        [self mountPointsOf:[LDSelectTargetRules volumes:volumes sortedByKey:LDSelectTargetColumnName ascending:YES]]);
  XCTAssertEqualObjects((@[@"/home", @"/", @"/boot/efi", @"/srv"]),
                        [self mountPointsOf:[LDSelectTargetRules volumes:volumes sortedByKey:LDSelectTargetColumnTotal ascending:NO]]);
  XCTAssertEqualObjects((@[@"/srv", @"/", @"/boot/efi", @"/home"]),
                        [self mountPointsOf:[LDSelectTargetRules volumes:volumes sortedByKey:LDSelectTargetColumnFree ascending:YES]]);
  XCTAssertEqualObjects((@[@"/", @"/home", @"/boot/efi", @"/srv"]),
                        [self mountPointsOf:[LDSelectTargetRules volumes:volumes sortedByKey:LDSelectTargetColumnUsed ascending:NO]]);
  XCTAssertEqualObjects((@[@"/srv", @"/boot/efi", @"/home", @"/"]),
                        [self mountPointsOf:[LDSelectTargetRules volumes:volumes sortedByKey:LDSelectTargetColumnPercent ascending:YES]]);
}

- (void)testSortTiesFallBackToMountPoint
{
  LDVolume *b = [self volumeAt:@"/b" label:nil total:0 free:0];
  LDVolume *a = [self volumeAt:@"/a" label:nil total:0 free:0];
  XCTAssertEqualObjects((@[@"/a", @"/b"]),
                        ([self mountPointsOf:[LDSelectTargetRules volumes:@[b, a] sortedByKey:LDSelectTargetColumnTotal ascending:NO]]));
}

- (void)testIndexesOfMountPoints
{
  NSArray *volumes = @[[self volumeAt:@"/" label:nil total:0 free:0],
                       [self volumeAt:@"/boot/efi" label:nil total:0 free:0],
                       [self volumeAt:@"/home" label:nil total:0 free:0]];
  NSMutableIndexSet *expected = [NSMutableIndexSet indexSetWithIndex:0];
  [expected addIndex:2];
  XCTAssertEqualObjects(expected, ([LDSelectTargetRules indexesOfMountPoints:@[@"/home", @"/gone", @"/"] inVolumes:volumes]));
  XCTAssertEqual((NSUInteger)0, [[LDSelectTargetRules indexesOfMountPoints:nil inVolumes:volumes] count]);
}

- (void)testInitialFolder
{
  XCTAssertEqualObjects(@"/srv", ([LDSelectTargetRules initialFolderForRequested:@"/srv" history:@[@"/home"]]));
  XCTAssertEqualObjects(@"/home", ([LDSelectTargetRules initialFolderForRequested:nil history:@[@"/home", @"/tmp"]]));
  XCTAssertEqualObjects(@"/home", ([LDSelectTargetRules initialFolderForRequested:@"" history:@[@"/home"]]));
  XCTAssertEqualObjects(@"", [LDSelectTargetRules initialFolderForRequested:nil history:@[]]);
}

@end
