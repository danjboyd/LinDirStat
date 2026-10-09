#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDExtensionStats.h"
#import "LDScanner.h"
#import "LDScanSession.h"

#include <fcntl.h>
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
  XCTAssertTrue([scanner shouldDescendIntoDevice:info.st_dev]);
  XCTAssertFalse([scanner shouldDescendIntoDevice:info.st_dev + 1]);

  [scanner setCrossesFilesystems:YES];
  XCTAssertTrue([scanner shouldDescendIntoDevice:info.st_dev + 1]);
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

@end
