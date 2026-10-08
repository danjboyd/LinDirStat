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
    _temporaryRoot = [[NSTemporaryDirectory() stringByAppendingPathComponent:name] retain];
    [[NSFileManager defaultManager] createDirectoryAtPath:_temporaryRoot withIntermediateDirectories:YES attributes:nil error:NULL];
  }
  return _temporaryRoot;
}

- (void)tearDown
{
  if (_temporaryRoot) {
    [[NSFileManager defaultManager] removeItemAtPath:_temporaryRoot error:NULL];
    [_temporaryRoot release];
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
  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  LDScanSession *session = [[[LDScanSession alloc] init] autorelease];

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
  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  LDScanSession *session = [[[LDScanSession alloc] init] autorelease];
  LDFileNode *root = [scanner scanPath:[self fixturePath] session:session];

  NSArray *stats = [LDExtensionStats sortedStatsForRootNode:root];
  LDExtensionStats *largest = [stats objectAtIndex:0];

  XCTAssertEqualObjects(@"txt", [largest extensionKey]);
  XCTAssertEqual((NSUInteger)2, [largest fileCount]);
  XCTAssertEqual((unsigned long long)22, [largest bytes]);
}

- (void)testMissingPathProducesFailedSession
{
  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  LDScanSession *session = [[[LDScanSession alloc] init] autorelease];
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

  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  LDScanSession *session = [[[LDScanSession alloc] init] autorelease];
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

  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  LDScanSession *session = [[[LDScanSession alloc] init] autorelease];
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

  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  LDScanSession *session = [[[LDScanSession alloc] init] autorelease];
  LDFileNode *root = [scanner scanPath:[self temporaryRoot] session:session];
  LDFileNode *file = [self childNamed:@"stamped.txt" of:root];

  XCTAssertTrue(fabs([file modificationTime] - [[NSDate date] timeIntervalSince1970]) < 60.0);
  XCTAssertEqual((unsigned int)0640, [file mode] & 0777);
  XCTAssertTrue(S_ISREG([file mode]));
}

- (void)testStaysOnRootFilesystemByDefault
{
  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  LDScanSession *session = [[[LDScanSession alloc] init] autorelease];
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

  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  LDScanSession *session = [[[LDScanSession alloc] init] autorelease];
  LDFileNode *root = [scanner scanPath:parent session:session];
  LDFileNode *child = [self childNamed:[mounted lastPathComponent] of:root];

  XCTAssertTrue([child isMountPoint]);
  XCTAssertEqual((NSUInteger)0, [[child children] count]);
}

@end
