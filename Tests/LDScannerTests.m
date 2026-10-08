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

@end
