#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDExtensionStats.h"
#import "LDScanner.h"
#import "LDScanSession.h"
#import "LDScanOptions.h"

#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

@interface LDScannerTests : XCTestCase
{
  NSString *_temporaryRoot;
}
@end

@implementation LDScannerTests

- (NSString *)fixturePath
{
  return [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Tests/Fixtures/basic-tree"];
}

- (NSString *)temporaryRoot
{
  if (!_temporaryRoot) {
    NSString *name = [NSString stringWithFormat:@"lindirstat-tests-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
    _temporaryRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:_temporaryRoot withIntermediateDirectories:YES attributes:nil error:NULL];
  }
  return _temporaryRoot;
}

- (void)tearDown
{
  if (_temporaryRoot) {
    [[NSFileManager defaultManager] removeItemAtPath:_temporaryRoot error:NULL];
    _temporaryRoot = nil;
  }
  [super tearDown];
}

- (NSString *)writeFile:(NSString *)name bytes:(NSUInteger)bytes
{
  NSString *path = [[self temporaryRoot] stringByAppendingPathComponent:name];
  [[NSMutableData dataWithLength:bytes] writeToFile:path atomically:NO];
  return path;
}

- (LDFileNode *)childNamed:(NSString *)name of:(LDFileNode *)node
{
  NSEnumerator *enumerator = [[node children] objectEnumerator];
  LDFileNode *child = nil;
  while ((child = [enumerator nextObject])) {
    if ([[child displayName] isEqualToString:name]) {
      return child;
    }
  }
  return nil;
}

- (void)testScansFixtureTreeDeterministically
{
  LDScanner *scanner = [[LDScanner alloc] init];
  LDScanSession *session = [[LDScanSession alloc] init];

  LDFileNode *root = [scanner scanPath:[self fixturePath] session:session];

  XCTAssertNotNil(root);
  XCTAssertEqual(LDScanSessionStateComplete, [session state]);
  XCTAssertEqual((unsigned long long)40, [root aggregateSize]);
  XCTAssertEqual((NSUInteger)4, [root fileCount]);
  XCTAssertEqual((NSUInteger)2, [root directoryCount]);
  XCTAssertEqual((NSUInteger)0, [session errorCount]);
  XCTAssertEqual((NSUInteger)4, [session filesScanned]);
  XCTAssertEqual((NSUInteger)2, [session directoriesScanned]);
}

- (void)testScannedTreeProducesExtensionStats
{
  LDScanner *scanner = [[LDScanner alloc] init];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *root = [scanner scanPath:[self fixturePath] session:session];

  NSArray *stats = [LDExtensionStats sortedStatsForRootNode:root];
  LDExtensionStats *largest = [stats objectAtIndex:0];

  XCTAssertEqualObjects(@"txt", [largest extensionKey]);
  XCTAssertEqual((NSUInteger)2, [largest fileCount]);
  XCTAssertEqual((unsigned long long)22, [largest bytes]);
}

- (void)testMissingPathProducesFailedSession
{
  LDScanner *scanner = [[LDScanner alloc] init];
  LDScanSession *session = [[LDScanSession alloc] init];
  NSString *missing = [[self fixturePath] stringByAppendingPathComponent:@"does-not-exist"];

  LDFileNode *root = [scanner scanPath:missing session:session];

  XCTAssertNotNil(root);
  XCTAssertEqual(LDScanSessionStateComplete, [session state]);
  XCTAssertEqual((NSUInteger)1, [session errorCount]);
  XCTAssertTrue([[root errorCode] hasPrefix:@"stat_failed:"]);
}

- (void)testHardLinksAreCountedOnce
{
  NSString *original = [self writeFile:@"original.bin" bytes:50000];
  NSString *linked = [[self temporaryRoot] stringByAppendingPathComponent:@"linked.bin"];
  XCTAssertEqual(0, link([original fileSystemRepresentation], [linked fileSystemRepresentation]));

  LDScanner *scanner = [[LDScanner alloc] init];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *root = [scanner scanPath:[self temporaryRoot] session:session];

  XCTAssertEqual((unsigned long long)50000, [root aggregateSize]);
  XCTAssertEqual((NSUInteger)2, [root fileCount]);
  NSUInteger duplicates = 0;
  NSEnumerator *enumerator = [[root children] objectEnumerator];
  LDFileNode *child = nil;
  while ((child = [enumerator nextObject])) {
    if ([child isHardLinkDuplicate]) {
      duplicates++;
      XCTAssertEqual((unsigned long long)0, [child allocatedSize]);
    }
  }
  XCTAssertEqual((NSUInteger)1, duplicates);
}

- (void)testSparseFilesReportPhysicalSize
{
  NSString *path = [[self temporaryRoot] stringByAppendingPathComponent:@"sparse.img"];
  int fd = open([path fileSystemRepresentation], O_CREAT | O_WRONLY, 0644);
  XCTAssertTrue(fd >= 0);
  XCTAssertEqual(0, ftruncate(fd, 64 * 1024 * 1024));
  close(fd);
  [self writeFile:@"dense.bin" bytes:200000];

  LDScanner *scanner = [[LDScanner alloc] init];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *root = [scanner scanPath:[self temporaryRoot] session:session];
  LDFileNode *sparse = [self childNamed:@"sparse.img" of:root];

  XCTAssertEqual((unsigned long long)(64 * 1024 * 1024), [sparse size]);
  XCTAssertTrue([sparse allocatedSize] < 1024 * 1024);
  // Children are sorted by physical size, so the dense file comes first.
  XCTAssertEqualObjects(@"dense.bin", [[[root children] objectAtIndex:0] displayName]);
}

- (void)testRecordsModificationTimeAndMode
{
  NSString *path = [self writeFile:@"stamped.txt" bytes:10];
  chmod([path fileSystemRepresentation], 0640);

  LDScanner *scanner = [[LDScanner alloc] init];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *root = [scanner scanPath:[self temporaryRoot] session:session];
  LDFileNode *file = [self childNamed:@"stamped.txt" of:root];

  XCTAssertTrue(fabs([file modificationTime] - [[NSDate date] timeIntervalSince1970]) < 60.0);
  XCTAssertEqual((unsigned int)0640, [file mode] & 0777);
  XCTAssertTrue(S_ISREG([file mode]));
}

- (void)testStaysOnRootFilesystemByDefault
{
  LDScanner *scanner = [[LDScanner alloc] init];
  LDScanSession *session = [[LDScanSession alloc] init];
  [scanner scanPath:[self fixturePath] session:session];

  struct stat info;
  stat([[self fixturePath] fileSystemRepresentation], &info);
  XCTAssertFalse([scanner crossesFilesystems]);
  XCTAssertTrue([[scanner scanOptions] excludeMountPoints]);
  XCTAssertTrue([scanner shouldDescendIntoDevice:info.st_dev rootDevice:info.st_dev]);
  XCTAssertFalse([scanner shouldDescendIntoDevice:info.st_dev + 1 rootDevice:info.st_dev]);

  [scanner setCrossesFilesystems:YES];
  XCTAssertFalse([[scanner scanOptions] excludeMountPoints]);
  XCTAssertTrue([scanner shouldDescendIntoDevice:info.st_dev + 1 rootDevice:info.st_dev]);
}

- (void)testMountedSubdirectoryIsNotDescended
{
  // On systemd hosts /run/user/<uid> is its own tmpfs mounted inside /run.
  NSString *parent = @"/run/user";
  NSString *mounted = [parent stringByAppendingPathComponent:[NSString stringWithFormat:@"%u", getuid()]];
  struct stat parentInfo;
  struct stat mountedInfo;
  if (stat([parent fileSystemRepresentation], &parentInfo) != 0
      || stat([mounted fileSystemRepresentation], &mountedInfo) != 0
      || parentInfo.st_dev == mountedInfo.st_dev) {
    return;
  }

  LDScanner *scanner = [[LDScanner alloc] init];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *root = [scanner scanPath:parent session:session];
  LDFileNode *child = [self childNamed:[mounted lastPathComponent] of:root];

  XCTAssertTrue([child isMountPoint]);
  XCTAssertEqual((NSUInteger)0, [[child children] count]);
}

- (void)buildWideTreeAt:(NSString *)root depth:(int)depth seed:(unsigned int *)seed
{
  NSFileManager *manager = [NSFileManager defaultManager];
  int i = 0;
  for (i = 0; i < 6; i++) {
    *seed = *seed * 1103515245u + 12345u;
    NSString *file = [root stringByAppendingPathComponent:[NSString stringWithFormat:@"f%d.%@", i, (i % 3 == 0) ? @"log" : @"dat"]];
    [[NSMutableData dataWithLength:(*seed >> 8) % 20000] writeToFile:file atomically:NO];
  }
  if (depth == 0) {
    return;
  }
  for (i = 0; i < 4; i++) {
    NSString *directory = [root stringByAppendingPathComponent:[NSString stringWithFormat:@"d%d", i]];
    [manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    [self buildWideTreeAt:directory depth:depth - 1 seed:seed];
  }
}

- (void)testParallelScanMatchesSerialScan
{
  unsigned int seed = 7;
  [self buildWideTreeAt:[self temporaryRoot] depth:4 seed:&seed];

  LDScanner *serial = [[LDScanner alloc] init];
  [serial setThreadCount:1];
  LDFileNode *serialRoot = [serial scanPath:[self temporaryRoot] session:[[LDScanSession alloc] init]];

  LDScanner *parallel = [[LDScanner alloc] init];
  [parallel setThreadCount:8];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *parallelRoot = [parallel scanPath:[self temporaryRoot] session:session];

  XCTAssertEqual((NSUInteger)341, [parallelRoot directoryCount]);
  XCTAssertEqual((NSUInteger)2046, [parallelRoot fileCount]);
  XCTAssertEqual((NSUInteger)2046, [session filesScanned]);
  XCTAssertEqual([serialRoot aggregateSize], [parallelRoot aggregateSize]);
  XCTAssertEqualObjects([serialRoot snapshotDictionary], [parallelRoot snapshotDictionary]);
}

- (void)testParallelScanCountsHardLinksOnce
{
  NSString *original = [self writeFile:@"original.bin" bytes:30000];
  int i = 0;
  for (i = 0; i < 20; i++) {
    NSString *directory = [[self temporaryRoot] stringByAppendingPathComponent:[NSString stringWithFormat:@"links%d", i]];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *linked = [directory stringByAppendingPathComponent:@"linked.bin"];
    XCTAssertEqual(0, link([original fileSystemRepresentation], [linked fileSystemRepresentation]));
  }

  LDScanner *scanner = [[LDScanner alloc] init];
  [scanner setThreadCount:8];
  LDFileNode *root = [scanner scanPath:[self temporaryRoot] session:[[LDScanSession alloc] init]];

  XCTAssertEqual((unsigned long long)30000, [root aggregateSize]);
  XCTAssertEqual((NSUInteger)21, [root fileCount]);
}

#if !defined(__APPLE__)
// APFS and HFS+ refuse names that are not UTF-8 (EILSEQ).
- (void)testNamesThatAreNotUTF8AreScannedAndDescended
{
  // "caf\xe9" is Latin-1, not valid UTF-8; Linux allows any bytes in names.
  NSString *root = [self temporaryRoot];
  NSMutableData *directoryPath = [NSMutableData dataWithBytes:[root fileSystemRepresentation] length:strlen([root fileSystemRepresentation])];
  [directoryPath appendBytes:"/caf\xe9\0" length:6];
  XCTAssertEqual(0, mkdir([directoryPath bytes], 0755));
  NSMutableData *filePath = [NSMutableData dataWithData:directoryPath];
  [filePath setLength:[filePath length] - 1];
  [filePath appendBytes:"/menu\xe9.txt\0" length:11];
  int fd = open([filePath bytes], O_CREAT | O_WRONLY, 0644);
  XCTAssertTrue(fd >= 0);
  XCTAssertEqual((ssize_t)5000, write(fd, [[NSMutableData dataWithLength:5000] bytes], 5000));
  close(fd);

  LDScanner *scanner = [[LDScanner alloc] init];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *scanned = [scanner scanPath:root session:session];
  LDFileNode *directory = [[scanned children] objectAtIndex:0];

  XCTAssertEqual(0, strcmp("caf\xe9", [directory nameBytes]));
  XCTAssertEqualObjects(@"caf\u00e9", [directory displayName]);
  XCTAssertEqual((NSUInteger)1, [[directory children] count]);
  XCTAssertEqual((unsigned long long)5000, [scanned aggregateSize]);
  XCTAssertEqualObjects(@"txt", [[[directory children] objectAtIndex:0] extensionKey]);
  XCTAssertEqual((NSUInteger)0, [session errorCount]);
}
#endif

- (void)testScannedNamesLiveInTheRootsArenas
{
  [self writeFile:@"a.txt" bytes:10];
  LDScanner *scanner = [[LDScanner alloc] init];
  LDFileNode *root = nil;
  @autoreleasepool {
    root = [scanner scanPath:[self temporaryRoot] session:[[LDScanSession alloc] init]];
    scanner = nil;
  }
  // The scanner is gone; names must still be readable through the root.
  XCTAssertEqualObjects(@"a.txt", [[[root children] objectAtIndex:0] displayName]);
}

- (void)testFinishedScanHasNothingPendingAndNoRetiredArraysLeak
{
  [self writeFile:@"a.txt" bytes:10];
  [[NSFileManager defaultManager] createDirectoryAtPath:[[self temporaryRoot] stringByAppendingPathComponent:@"sub/deeper"]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
  [self writeFile:@"sub/deeper/b.txt" bytes:20];
  LDScanner *scanner = [[LDScanner alloc] init];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *root = [scanner scanPath:[self temporaryRoot] session:session];

  XCTAssertFalse([root isScanPending]);
  XCTAssertFalse([[self childNamed:@"sub" of:root] isScanPending]);
  XCTAssertEqual(root, [session rootNode]);
  // The final sort replaced the published children arrays.
  XCTAssertTrue([[scanner takeRetiredArrays] count] >= 3);
  XCTAssertNil([scanner takeRetiredArrays]);
}

- (void)testCanceledScanLeavesNothingPending
{
  for (NSUInteger i = 0; i < 50; i++) {
    NSString *directory = [NSString stringWithFormat:@"d%lu/e", (unsigned long)i];
    [[NSFileManager defaultManager] createDirectoryAtPath:[[self temporaryRoot] stringByAppendingPathComponent:directory]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
  }
  LDScanSession *session = [[LDScanSession alloc] init];
  [session cancel];
  LDFileNode *root = [[[LDScanner alloc] init] scanPath:[self temporaryRoot] session:session];
  XCTAssertFalse([root isScanPending]);
}

- (void)testEntryRescanReplacesSubtree
{
  [[NSFileManager defaultManager] createDirectoryAtPath:[[self temporaryRoot] stringByAppendingPathComponent:@"sub"]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
  [self writeFile:@"sub/a.txt" bytes:5000];
  LDFileNode *root = [[[LDScanner alloc] init] scanPath:[self temporaryRoot] session:[[LDScanSession alloc] init]];
  LDFileNode *sub = [self childNamed:@"sub" of:root];
  [self writeFile:@"sub/b.txt" bytes:7000];

  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *fresh = [[[LDScanner alloc] init] scanEntryAtPathData:[sub pathData] session:session];
  XCTAssertEqualObjects(@"sub", [fresh displayName]);
  XCTAssertEqual((NSUInteger)2, [fresh fileCount]);
  XCTAssertEqual((unsigned long long)12000, [fresh aggregateSize]);

  [(LDDirectoryNode *)root replaceChild:sub withNode:fresh];
  [root updateTotalsUpwardSortedByMetric:LDSizeMetricPhysical];
  XCTAssertEqual((unsigned long long)12000, [root aggregateSize]);
  XCTAssertEqualObjects([[self temporaryRoot] stringByAppendingPathComponent:@"sub/b.txt"],
                        [[self childNamed:@"b.txt" of:fresh] path]);
}

- (void)testEntryRescanOfMissingEntryReturnsNil
{
  [self writeFile:@"gone.txt" bytes:10];
  LDFileNode *root = [[[LDScanner alloc] init] scanPath:[self temporaryRoot] session:[[LDScanSession alloc] init]];
  LDFileNode *gone = [self childNamed:@"gone.txt" of:root];
  [[NSFileManager defaultManager] removeItemAtPath:[gone path] error:NULL];

  XCTAssertNil([[[LDScanner alloc] init] scanEntryAtPathData:[gone pathData] session:[[LDScanSession alloc] init]]);
}

// After Add to Exclusion Filter: refreshing an excluded entry drops it, as a
// scan of its folder would.
- (void)testEntryRescanOfExcludedEntryReturnsNil
{
  NSString *root = [self makeDirectory:@"root"];
  [self makeDirectory:@"root/cache"];
  [self writeFile:@"root/cache/a.bin" bytes:1000];
  [self writeFile:@"root/b.log" bytes:200];
  [self writeFile:@"root/c.txt" bytes:300];
  NSData *(^pathData)(NSString *) = ^NSData *(NSString *name) {
    const char *bytes = [[root stringByAppendingPathComponent:name] fileSystemRepresentation];
    return [NSData dataWithBytes:bytes length:strlen(bytes)];
  };

  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludedFolderPatterns:[NSArray arrayWithObject:[root stringByAppendingPathComponent:@"cache"]]];
  [options setExcludedFilePatterns:[NSArray arrayWithObject:@"*.log"]];
  LDScanner *scanner = [[LDScanner alloc] init];
  [scanner setScanOptions:options];

  XCTAssertNil([scanner scanEntryAtPathData:pathData(@"cache") session:[[LDScanSession alloc] init]]);
  XCTAssertNil([scanner scanEntryAtPathData:pathData(@"b.log") session:[[LDScanSession alloc] init]]);
  LDFileNode *kept = [scanner scanEntryAtPathData:pathData(@"c.txt") session:[[LDScanSession alloc] init]];
  XCTAssertEqualObjects(@"c.txt", [kept displayName]);
}

#if defined(__APPLE__)
// The Data volume shares st_dev with the System volume it is mounted under;
// it must still be a mount point so the firmlinks (/Users...) own its data.
- (void)testAPFSDataVolumeIsAMountPoint
{
  NSData *data = [NSData dataWithBytes:"/System/Volumes/Data" length:20];
  struct stat dataInfo, systemInfo;
  if (stat("/System/Volumes/Data", &dataInfo) != 0 || stat("/", &systemInfo) != 0) {
    return;
  }
  LDFileNode *node = [[[LDScanner alloc] init] scanEntryAtPathData:data session:[[LDScanSession alloc] init]];
  XCTAssertEqual(LDFileNodeErrorMountPoint, [node error]);
  XCTAssertEqual((NSUInteger)0, [node fileCount]);
}

#endif
#pragma mark - Filters and exclusions

- (NSString *)makeDirectory:(NSString *)relativePath
{
  NSString *path = [[self temporaryRoot] stringByAppendingPathComponent:relativePath];
  [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
  return path;
}

- (void)link:(NSString *)relativeLink to:(NSString *)target
{
  NSString *path = [[self temporaryRoot] stringByAppendingPathComponent:relativeLink];
  XCTAssertEqual(0, symlink([target fileSystemRepresentation], [path fileSystemRepresentation]));
}

- (LDFileNode *)scan:(NSString *)path options:(LDScanOptions *)options session:(LDScanSession *)session
{
  LDScanner *scanner = [[LDScanner alloc] init];
  [scanner setScanOptions:options];
  return [scanner scanPath:path session:session ? session : [[LDScanSession alloc] init]];
}

- (void)testExcludedFolderPatternsMatchTheFullPath
{
  NSString *root = [self makeDirectory:@"root"];
  [self makeDirectory:@"root/Cache"];
  [self makeDirectory:@"root/sub/cache"];
  [self makeDirectory:@"root/sub/keep"];
  [self writeFile:@"root/Cache/a.bin" bytes:1000];
  [self writeFile:@"root/sub/cache/b.bin" bytes:2000];
  [self writeFile:@"root/sub/keep/c.bin" bytes:4000];

  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludedFolderPatterns:[NSArray arrayWithObject:[root stringByAppendingPathComponent:@"cache"]]];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *scanned = [self scan:root options:options session:session];

  XCTAssertNil([self childNamed:@"Cache" of:scanned]);
  XCTAssertNotNil([self childNamed:@"cache" of:[self childNamed:@"sub" of:scanned]]);
  XCTAssertEqual((unsigned long long)6000, [scanned aggregateSize]);
  XCTAssertEqual((NSUInteger)2, [session filesScanned]);
  XCTAssertEqual((NSUInteger)0, [session skippedCount]);

  // "*" never crosses "/", so the nested folder needs its own level.
  [options setExcludedFolderPatterns:[NSArray arrayWithObject:[root stringByAppendingPathComponent:@"*/cache"]]];
  scanned = [self scan:root options:options session:nil];
  XCTAssertNotNil([self childNamed:@"Cache" of:scanned]);
  XCTAssertNil([self childNamed:@"cache" of:[self childNamed:@"sub" of:scanned]]);
  XCTAssertEqual((unsigned long long)5000, [scanned aggregateSize]);
}

- (void)testExcludedFilePatternsMatchTheNameOnly
{
  NSString *root = [self makeDirectory:@"root"];
  [self makeDirectory:@"root/logs.d"];
  [self writeFile:@"root/a.log" bytes:100];
  [self writeFile:@"root/b.txt" bytes:200];
  [self writeFile:@"root/logs.d/C.LOG" bytes:400];
  [self writeFile:@"root/logs.d/d.txt" bytes:800];

  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludedFilePatterns:[NSArray arrayWithObjects:@"*.log", @"logs.d", nil]];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *scanned = [self scan:root options:options session:session];

  // "logs.d" is a folder, so the file pattern does not apply to it.
  XCTAssertNotNil([self childNamed:@"logs.d" of:scanned]);
  XCTAssertEqual((unsigned long long)1000, [scanned aggregateSize]);
  XCTAssertEqual((NSUInteger)2, [scanned fileCount]);
  XCTAssertEqual((NSUInteger)2, [session filesScanned]);
}

- (void)testRegexFiltersAndInvalidPatternsAreSkipped
{
  NSString *root = [self makeDirectory:@"root"];
  [self writeFile:@"root/a.log" bytes:100];
  [self writeFile:@"root/b.txt" bytes:200];

  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setUsesRegex:YES];
  [options setExcludedFilePatterns:[NSArray arrayWithObjects:@"(bad", @".*\\.LOG", nil]];
  XCTAssertFalse([options validateWithError:NULL]);
  LDFileNode *scanned = [self scan:root options:options session:nil];
  XCTAssertEqual((unsigned long long)200, [scanned aggregateSize]);
}

#if !defined(__APPLE__)
// APFS and HFS+ refuse names that are not UTF-8 (EILSEQ).
- (void)testFiltersMatchNamesThatAreNotUTF8
{
  NSString *root = [self makeDirectory:@"root"];
  const char *rootBytes = [root fileSystemRepresentation];
  char path[PATH_MAX];
  snprintf(path, sizeof(path), "%s/caf\xe9", rootBytes);
  XCTAssertEqual(0, mkdir(path, 0755));
  snprintf(path, sizeof(path), "%s/caf\xe9/inner.bin", rootBytes);
  XCTAssertEqual(0, close(open(path, O_CREAT | O_WRONLY, 0644)));
  snprintf(path, sizeof(path), "%s/menu\xe9.tmp", rootBytes);
  int fd = open(path, O_CREAT | O_WRONLY, 0644);
  XCTAssertEqual((ssize_t)300, write(fd, [[NSMutableData dataWithLength:300] bytes], 300));
  close(fd);
  [self writeFile:@"root/kept.bin" bytes:50];

  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludedFolderPatterns:[NSArray arrayWithObject:[root stringByAppendingPathComponent:@"CAF?"]]];
  [options setExcludedFilePatterns:[NSArray arrayWithObject:@"menu?.TMP"]];
  LDFileNode *scanned = [self scan:root options:options session:nil];

  XCTAssertEqual((NSUInteger)1, [[scanned children] count]);
  XCTAssertEqualObjects(@"kept.bin", [[[scanned children] objectAtIndex:0] displayName]);
}
#endif

- (void)testMinimumFileSizeUsesTheLogicalSize
{
  NSString *root = [self makeDirectory:@"root"];
  [self writeFile:@"root/small.bin" bytes:999];
  [self writeFile:@"root/exact.bin" bytes:1000];
  NSString *sparse = [root stringByAppendingPathComponent:@"sparse.img"];
  int fd = open([sparse fileSystemRepresentation], O_CREAT | O_WRONLY, 0644);
  XCTAssertEqual(0, ftruncate(fd, 8 * 1024 * 1024));
  close(fd);

  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setMinimumFileSize:1000];
  LDFileNode *scanned = [self scan:root options:options session:nil];

  XCTAssertNil([self childNamed:@"small.bin" of:scanned]);
  XCTAssertNotNil([self childNamed:@"exact.bin" of:scanned]);
  XCTAssertNotNil([self childNamed:@"sparse.img" of:scanned]);
  XCTAssertEqual((NSUInteger)2, [scanned fileCount]);
}

- (void)testExcludeHiddenSkipsDotEntriesButNotTheRoot
{
  NSString *root = [self makeDirectory:@".root"];
  [self makeDirectory:@".root/.git/objects"];
  [self writeFile:@".root/.git/objects/blob" bytes:5000];
  [self writeFile:@".root/.profile" bytes:100];
  [self writeFile:@".root/visible.txt" bytes:10];

  LDScanOptions *options = [[LDScanOptions alloc] init];
  LDFileNode *all = [self scan:root options:options session:nil];
  XCTAssertEqual((NSUInteger)3, [all fileCount]);

  [options setExcludeHidden:YES];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *visible = [self scan:root options:options session:session];
  XCTAssertEqual((NSUInteger)1, [[visible children] count]);
  XCTAssertEqual((unsigned long long)10, [visible aggregateSize]);
  XCTAssertEqual((NSUInteger)1, [visible directoryCount]);
  XCTAssertEqual((NSUInteger)1, [session directoriesScanned]);
}

- (void)buildLinkTree
{
  [self makeDirectory:@"root/data"];
  [self makeDirectory:@"outside/folder"];
  [self writeFile:@"root/data/inside.bin" bytes:1000];
  [self writeFile:@"outside/folder/big.bin" bytes:7000];
  NSString *target = [self writeFile:@"outside/target.bin" bytes:4000];
  XCTAssertEqual(0, link([target fileSystemRepresentation],
                         [[[self temporaryRoot] stringByAppendingPathComponent:@"outside/hardlink.bin"] fileSystemRepresentation]));
  NSString *outside = [[self temporaryRoot] stringByAppendingPathComponent:@"outside"];
  [self link:@"root/folderlink" to:[outside stringByAppendingPathComponent:@"folder"]];
  [self link:@"root/filelink" to:target];
  [self link:@"root/filelink2" to:target];
  [self link:@"root/broken" to:@"/nonexistent/lindirstat"];
  [self link:@"root/loop" to:@"."];
}

- (void)testSymbolicLinksAreExcludedByDefault
{
  [self buildLinkTree];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *root = [self scan:[[self temporaryRoot] stringByAppendingPathComponent:@"root"]
                        options:[[LDScanOptions alloc] init] session:session];

  XCTAssertNil([self childNamed:@"filelink" of:root]);
  XCTAssertNil([self childNamed:@"filelink2" of:root]);
  XCTAssertNil([self childNamed:@"broken" of:root]);
  LDFileNode *folderLink = [self childNamed:@"folderlink" of:root];
  LDFileNode *loop = [self childNamed:@"loop" of:root];
  XCTAssertEqual(LDFileNodeKindSymlink, [folderLink kind]);
  XCTAssertEqual(LDFileNodeKindSymlink, [loop kind]);
  XCTAssertEqual((NSUInteger)0, [[folderLink children] count]);
  XCTAssertEqual((NSUInteger)3, [[root children] count]);
  XCTAssertEqual((unsigned long long)1000 + [folderLink size] + [loop size], [root aggregateSize]);
}

- (void)testSymbolicLinksAreFollowedWhenNotExcluded
{
  [self buildLinkTree];
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludeSymbolicLinks:NO];
  LDFileNode *root = [self scan:[[self temporaryRoot] stringByAppendingPathComponent:@"root"] options:options session:nil];

  LDFileNode *folderLink = [self childNamed:@"folderlink" of:root];
  XCTAssertEqual(LDFileNodeKindDirectory, [folderLink kind]);
  XCTAssertEqual((NSUInteger)1, [[folderLink children] count]);
  XCTAssertEqualObjects([[[self temporaryRoot] stringByAppendingPathComponent:@"root/folderlink"] stringByAppendingPathComponent:@"big.bin"],
                        [[[folderLink children] objectAtIndex:0] path]);

  // Both links lead to one inode with two hard links: counted once.
  LDFileNode *fileLink = [self childNamed:@"filelink" of:root];
  LDFileNode *fileLink2 = [self childNamed:@"filelink2" of:root];
  XCTAssertEqual(LDFileNodeKindFile, [fileLink kind]);
  XCTAssertEqual(LDFileNodeKindFile, [fileLink2 kind]);
  XCTAssertTrue([fileLink isHardLinkDuplicate] != [fileLink2 isHardLinkDuplicate]);
  XCTAssertEqualObjects(@"filelink", [fileLink displayName]);
  XCTAssertEqual((unsigned long long)4000, [fileLink size] + [fileLink2 size]);

  // A dangling link stays a link; a link back to the root is a cycle.
  XCTAssertEqual(LDFileNodeKindSymlink, [[self childNamed:@"broken" of:root] kind]);
  LDFileNode *loop = [self childNamed:@"loop" of:root];
  XCTAssertEqual(LDFileNodeKindDirectory, [loop kind]);
  XCTAssertEqual(LDFileNodeErrorDirectoryCycle, [loop error]);

  unsigned long long brokenSize = [[self childNamed:@"broken" of:root] size];
  XCTAssertEqual((unsigned long long)(1000 + 7000 + 4000) + brokenSize, [root aggregateSize]);
}

- (void)testFollowedLinkToFileInTheTreeIsCountedOnce
{
  NSString *root = [[self temporaryRoot] stringByAppendingPathComponent:@"single"];
  [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];
  [self writeFile:@"single/target.bin" bytes:6000];
  XCTAssertEqual(0, symlink("target.bin", [[root stringByAppendingPathComponent:@"alias"] fileSystemRepresentation]));
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludeSymbolicLinks:NO];
  LDFileNode *scanned = [self scan:root options:options session:nil];

  XCTAssertEqual((unsigned long long)6000, [scanned aggregateSize]);
  XCTAssertTrue([[self childNamed:@"alias" of:scanned] isHardLinkDuplicate]
                != [[self childNamed:@"target.bin" of:scanned] isHardLinkDuplicate]);
}

- (void)testFollowedFolderLinkStillRespectsMountPoints
{
  NSString *mounted = [NSString stringWithFormat:@"/run/user/%u", getuid()];
  struct stat mountedInfo;
  struct stat temporaryInfo;
  if (stat([mounted fileSystemRepresentation], &mountedInfo) != 0
      || stat([[self temporaryRoot] fileSystemRepresentation], &temporaryInfo) != 0
      || mountedInfo.st_dev == temporaryInfo.st_dev) {
    return;
  }
  [self makeDirectory:@"root"];
  [self link:@"root/runlink" to:mounted];

  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludeSymbolicLinks:NO];
  LDFileNode *root = [self scan:[[self temporaryRoot] stringByAppendingPathComponent:@"root"] options:options session:nil];
  LDFileNode *runLink = [self childNamed:@"runlink" of:root];
  XCTAssertTrue([runLink isMountPoint]);
  XCTAssertEqual((NSUInteger)0, [[runLink children] count]);
}

#pragma mark - Multi-root scans

- (void)testScanningOnePathIsAPlainScan
{
  NSString *root = [self makeDirectory:@"a"];
  [self writeFile:@"a/x.bin" bytes:100];
  LDFileNode *scanned = [[[LDScanner alloc] init] scanPaths:[NSArray arrayWithObject:root] session:[[LDScanSession alloc] init]];
  XCTAssertFalse([scanned isComputer]);
  XCTAssertEqualObjects(root, [scanned path]);
  XCTAssertEqual((unsigned long long)100, [scanned aggregateSize]);
}

- (void)testScanningSeveralPathsBuildsAComputerNode
{
  NSString *a = [self makeDirectory:@"a"];
  NSString *b = [[self makeDirectory:@"b/inner"] stringByDeletingLastPathComponent];
  [self writeFile:@"a/one.bin" bytes:1000];
  [self writeFile:@"a/two.bin" bytes:2000];
  [self writeFile:@"b/inner/three.bin" bytes:3000];
  XCTAssertEqual(0, link([[a stringByAppendingPathComponent:@"one.bin"] fileSystemRepresentation],
                         [[b stringByAppendingPathComponent:@"one-again.bin"] fileSystemRepresentation]));
  NSString *missing = [[self temporaryRoot] stringByAppendingPathComponent:@"missing"];

  LDScanSession *session = [[LDScanSession alloc] init];
  LDScanner *scanner = [[LDScanner alloc] init];
  LDFileNode *computer = [scanner scanPaths:[NSArray arrayWithObjects:a, b, missing, nil] session:session];

  XCTAssertTrue([computer isComputer]);
  XCTAssertTrue([computer isKindOfClass:[LDComputerNode class]]);
  XCTAssertEqualObjects(@"This Computer", [computer displayName]);
  XCTAssertEqualObjects(@"This Computer", [computer path]);
  XCTAssertEqual((NSUInteger)0, [[computer pathData] length]);
  XCTAssertEqual(computer, [session rootNode]);
  XCTAssertEqual(LDScanSessionStateComplete, [session state]);
  XCTAssertFalse([computer isScanPending]);

  XCTAssertEqual((NSUInteger)3, [[computer children] count]);
  LDFileNode *aNode = [self childNamed:@"a" of:computer];
  LDFileNode *bNode = [self childNamed:@"b" of:computer];
  XCTAssertFalse([aNode isComputer]);
  XCTAssertEqualObjects(a, [aNode path]);
  XCTAssertEqualObjects([NSData dataWithBytes:[a fileSystemRepresentation] length:strlen([a fileSystemRepresentation])], [aNode pathData]);
  LDFileNode *three = [self childNamed:@"three.bin" of:[self childNamed:@"inner" of:bNode]];
  XCTAssertEqualObjects([b stringByAppendingPathComponent:@"inner/three.bin"], [three path]);
  XCTAssertTrue([[[self childNamed:@"missing" of:computer] errorCode] hasPrefix:@"stat_failed:"]);

  // The hard link across roots is counted once.
  XCTAssertEqual((unsigned long long)6000, [computer aggregateSize]);
  XCTAssertEqual((NSUInteger)5, [computer fileCount]);
  XCTAssertEqual((NSUInteger)1, [session errorCount]);
}

- (void)testEntryRescanWorksUnderAComputerRoot
{
  NSString *a = [self makeDirectory:@"a/sub"];
  NSString *b = [self makeDirectory:@"b"];
  [self writeFile:@"a/sub/x.bin" bytes:1000];
  [self writeFile:@"b/y.bin" bytes:500];
  LDFileNode *computer = [[[LDScanner alloc] init] scanPaths:[NSArray arrayWithObjects:[a stringByDeletingLastPathComponent], b, nil]
                                                      session:[[LDScanSession alloc] init]];
  LDFileNode *sub = [self childNamed:@"sub" of:[self childNamed:@"a" of:computer]];
  [self writeFile:@"a/sub/z.bin" bytes:2000];

  LDFileNode *fresh = [[[LDScanner alloc] init] scanEntryAtPathData:[sub pathData] session:[[LDScanSession alloc] init]];
  XCTAssertEqual((unsigned long long)3000, [fresh aggregateSize]);
  [(LDDirectoryNode *)[sub parent] replaceChild:sub withNode:fresh];
  [[fresh parent] updateTotalsUpwardSortedByMetric:LDSizeMetricPhysical];
  XCTAssertEqual((unsigned long long)3500, [computer aggregateSize]);
  XCTAssertEqualObjects([a stringByAppendingPathComponent:@"z.bin"], [[self childNamed:@"z.bin" of:fresh] path]);
}

@end
