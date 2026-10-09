#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDDuplicateFinder.h"
#import "LDFileNode.h"
#import "LDScanOptions.h"
#import "LDScanner.h"
#import "LDScanSession.h"

#include <fcntl.h>
#include <unistd.h>

@interface LDDuplicateCollectorTests : XCTestCase
{
  NSString *_temporaryRoot;
  // Nodes must not outlive their root, so tests keep it here.
  LDFileNode *_root;
}
@end

@implementation LDDuplicateCollectorTests

- (NSString *)temporaryRoot
{
  if (!_temporaryRoot) {
    NSString *name = [NSString stringWithFormat:@"lindirstat-collector-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
    _temporaryRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:_temporaryRoot withIntermediateDirectories:YES attributes:nil error:NULL];
  }
  return _temporaryRoot;
}

- (void)tearDown
{
  _root = nil;
  if (_temporaryRoot) {
    [[NSFileManager defaultManager] removeItemAtPath:_temporaryRoot error:NULL];
    _temporaryRoot = nil;
  }
  [super tearDown];
}

- (void)write:(NSData *)contents to:(NSString *)relativePath
{
  NSString *path = [[self temporaryRoot] stringByAppendingPathComponent:relativePath];
  [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  [contents writeToFile:path atomically:NO];
}

// length bytes of fill, with the byte at marker replaced by tail.
- (NSData *)bytes:(NSUInteger)length fill:(uint8_t)fill marker:(NSUInteger)marker tail:(uint8_t)tail
{
  NSMutableData *data = [NSMutableData dataWithLength:length];
  memset([data mutableBytes], fill, length);
  if (marker < length) {
    ((uint8_t *)[data mutableBytes])[marker] = tail;
  }
  return data;
}

// Many folders of files whose sizes collide often, with equal and unequal
// contents at every tier: files that differ only after 4 KiB or after
// 1 MiB, empty files, and sizes seen once.
- (void)writeMixedTree
{
  NSUInteger sizes[] = { 0, 1, 7, 100, 4096, 5000, 70000, 1024 * 1024, 1024 * 1024 + 300 };
  NSUInteger sizeCount = sizeof(sizes) / sizeof(sizes[0]);
  unsigned int seed = 7;
  for (NSUInteger folder = 0; folder < 12; folder++) {
    for (NSUInteger file = 0; file < 9; file++) {
      seed = seed * 1103515245u + 12345u;
      NSUInteger length = sizes[(seed >> 8) % sizeCount];
      uint8_t fill = (uint8_t)('a' + (seed >> 16) % 2);
      // The marker sits past 4 KiB or past 1 MiB for some files.
      NSUInteger marker = ((seed >> 20) % 3 == 0) ? length - 1 : length;
      uint8_t tail = (uint8_t)('0' + (seed >> 24) % 2);
      NSString *name = [NSString stringWithFormat:@"d%lu/sub%lu/f%lu.%@", (unsigned long)folder, (unsigned long)(file % 3),
                        (unsigned long)file, file % 2 ? @"bin" : @"txt"];
      [self write:[self bytes:length fill:fill marker:marker tail:tail] to:name];
    }
  }
  [self write:[self bytes:333 fill:'u' marker:0 tail:'u'] to:@"unique-size"];
}

- (NSString *)describeGroups:(NSArray *)groups
{
  NSMutableArray *lines = [NSMutableArray array];
  for (LDDuplicateGroup *group in groups) {
    NSMutableArray *paths = [NSMutableArray array];
    for (LDFileNode *node in [group nodes]) {
      [paths addObject:[node path]];
    }
    [lines addObject:[NSString stringWithFormat:@"%@ %llu %llu %@", [group hashString], [group logicalSize],
                      [group totalPhysicalSize], [paths componentsJoinedByString:@"|"]]];
  }
  return [lines componentsJoinedByString:@"\n"];
}

- (LDScanner *)scannerFindingDuplicates:(BOOL)finds threads:(NSUInteger)threads
{
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setFindsDuplicates:finds];
  [options setThreadCount:threads];
  LDScanner *scanner = [[LDScanner alloc] init];
  [scanner setScanOptions:options];
  return scanner;
}

- (void)assertInScanGroupsMatchBatchForPaths:(NSArray *)paths threads:(NSUInteger)threads
{
  LDScanSession *session = [[LDScanSession alloc] init];
  _root = [[self scannerFindingDuplicates:YES threads:threads] scanPaths:paths session:session];
  LDDuplicateCollector *collector = [session duplicateCollector];
  XCTAssertNotNil(collector);
  [collector waitUntilFinished];
  XCTAssertTrue([collector isFinished]);
  XCTAssertFalse([collector isCancelled]);

  NSArray *batch = [[[LDDuplicateFinder alloc] initWithRootNode:_root] findGroups];
  XCTAssertTrue([batch count] > 3);
  XCTAssertEqualObjects([self describeGroups:batch], [self describeGroups:[collector groups]]);
}

- (void)testInScanGroupsMatchTheBatchFinder
{
  [self writeMixedTree];
  [self assertInScanGroupsMatchBatchForPaths:@[[self temporaryRoot]] threads:4];
}

- (void)testInScanGroupsMatchTheBatchFinderWithOneThread
{
  [self writeMixedTree];
  [self assertInScanGroupsMatchBatchForPaths:@[[self temporaryRoot]] threads:1];
}

- (void)testInScanGroupsMatchTheBatchFinderAcrossRoots
{
  [self writeMixedTree];
  NSString *root = [self temporaryRoot];
  NSArray *paths = @[[root stringByAppendingPathComponent:@"d0"], [root stringByAppendingPathComponent:@"d1"],
                     [root stringByAppendingPathComponent:@"d2"], [root stringByAppendingPathComponent:@"unique-size"]];
  [self assertInScanGroupsMatchBatchForPaths:paths threads:4];
}

- (void)testCollectorIgnoresWhatIsNotARegularFile
{
  LDDuplicateCollector *collector = [[LDDuplicateCollector alloc] init];
  LDFileNode *root = [LDFileNode nodeWithPath:[self temporaryRoot] kind:LDFileNodeKindDirectory size:0];
  LDFileNode *directory = [LDFileNode nodeWithName:@"dir" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  LDFileNode *link = [LDFileNode nodeWithName:@"link" kind:LDFileNodeKindSymlink size:0 allocatedSize:0];
  LDFileNode *failed = [LDFileNode nodeWithName:@"failed" kind:LDFileNodeKindFile size:0 allocatedSize:0];
  [failed setError:LDFileNodeErrorStatFailed errorNumber:2];
  [(LDDirectoryNode *)root publishChildren:@[directory, link, failed]];

  [collector addNodes:@[directory, link, failed]];
  [collector finishAdding];
  [collector waitUntilFinished];

  XCTAssertEqual((NSUInteger)0, [[collector groups] count]);
}

- (void)testAsyncScanReportsLiveGroupsOnTheMainQueue
{
  [self writeMixedTree];
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setFindsDuplicates:YES];
  LDScanSession *session = [[LDScanSession alloc] init];
  [session setScanOptions:options];
  [session startAsyncScanPaths:@[[self temporaryRoot]] completion:nil];
  LDDuplicateCollector *collector = [session duplicateCollector];
  // The collector exists as soon as the scan starts, so it can be watched.
  XCTAssertNotNil(collector);

  __block NSArray *finalGroups = nil;
  __block BOOL onMain = YES;
  __block NSUInteger updates = 0;
  [collector setUpdateHandler:^(NSArray *groups, BOOL finished) {
    onMain = onMain && [NSThread isMainThread];
    updates++;
    if (finished) {
      finalGroups = groups;
    }
  }];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20.0];
  while (!finalGroups && [[NSDate date] compare:deadline] == NSOrderedAscending) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  }
  [session waitUntilFinishedBeforeDate:deadline];
  _root = [session rootNode];

  XCTAssertNotNil(finalGroups);
  XCTAssertTrue(onMain);
  XCTAssertTrue(updates >= 1);
  NSArray *batch = [[[LDDuplicateFinder alloc] initWithRootNode:_root] findGroups];
  XCTAssertEqualObjects([self describeGroups:batch], [self describeGroups:finalGroups]);
}

// Sparse files hash quickly to the 1 MiB tier and then take seconds for the
// whole-file tier.
- (void)writeSparseFiles:(NSUInteger)count length:(off_t)length
{
  for (NSUInteger index = 0; index < count; index++) {
    NSString *path = [[self temporaryRoot] stringByAppendingPathComponent:[NSString stringWithFormat:@"sparse-%lu", (unsigned long)index]];
    int fd = open([path fileSystemRepresentation], O_CREAT | O_WRONLY | O_TRUNC, 0644);
    XCTAssertTrue(fd >= 0);
    XCTAssertEqual(0, ftruncate(fd, length));
    close(fd);
  }
}

- (void)testCancellingTheSessionStopsHashing
{
  [self writeSparseFiles:4 length:(off_t)512 * 1024 * 1024];
  LDScanSession *session = [[LDScanSession alloc] init];
  _root = [[self scannerFindingDuplicates:YES threads:2] scanPaths:@[[self temporaryRoot]] session:session];
  LDDuplicateCollector *collector = [session duplicateCollector];
  [NSThread sleepForTimeInterval:0.05];

  NSDate *start = [NSDate date];
  [session cancel];
  [collector waitUntilFinished];
  NSTimeInterval stopTime = -[start timeIntervalSinceNow];

  XCTAssertTrue([collector isCancelled]);
  XCTAssertTrue([collector isFinished]);
  // Hashing 2 GiB takes seconds; cancelling stops between reads.
  XCTAssertTrue(stopTime < 1.0, @"took %.2f s to stop", stopTime);
  XCTAssertEqual((NSUInteger)0, [[collector groups] count]);
}

- (void)testCancelBeforeAnythingIsAddedFinishesAtOnce
{
  LDDuplicateCollector *collector = [[LDDuplicateCollector alloc] init];
  [collector cancel];
  [collector waitUntilFinished];
  XCTAssertTrue([collector isFinished]);

  LDFileNode *root = [LDFileNode nodeWithPath:[self temporaryRoot] kind:LDFileNodeKindDirectory size:0];
  LDFileNode *one = [LDFileNode nodeWithName:@"one" kind:LDFileNodeKindFile size:5 allocatedSize:8];
  LDFileNode *two = [LDFileNode nodeWithName:@"two" kind:LDFileNodeKindFile size:5 allocatedSize:8];
  [(LDDirectoryNode *)root publishChildren:@[one, two]];
  [collector addNodes:@[one, two]];
  XCTAssertEqual((NSUInteger)0, [[collector groups] count]);
}

- (void)testScansWithoutDuplicateDetectionMakeNoCollector
{
  [self write:[NSData dataWithBytes:"same" length:4] to:@"one"];
  [self write:[NSData dataWithBytes:"same" length:4] to:@"two"];

  LDScanSession *session = [[LDScanSession alloc] init];
  _root = [[self scannerFindingDuplicates:NO threads:4] scanPaths:@[[self temporaryRoot]] session:session];
  XCTAssertNil([session duplicateCollector]);

  LDScanSession *asyncSession = [[LDScanSession alloc] init];
  [asyncSession setScanOptions:[[LDScanOptions alloc] init]];
  [asyncSession startAsyncScanPaths:@[[self temporaryRoot]] completion:nil];
  XCTAssertNil([asyncSession duplicateCollector]);
  [asyncSession waitUntilFinishedBeforeDate:[NSDate dateWithTimeIntervalSinceNow:10.0]];
  XCTAssertNil([asyncSession duplicateCollector]);
}

- (void)testRefreshesNeverLookForDuplicates
{
  [self write:[NSData dataWithBytes:"same" length:4] to:@"dir/one"];
  [self write:[NSData dataWithBytes:"same" length:4] to:@"dir/two"];
  NSString *directory = [[self temporaryRoot] stringByAppendingPathComponent:@"dir"];
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setFindsDuplicates:YES];

  LDScanSession *refresh = [[LDScanSession alloc] init];
  [refresh setScanOptions:options];
  [refresh startAsyncRefreshOfPathData:[NSData dataWithBytes:[directory fileSystemRepresentation]
                                                      length:strlen([directory fileSystemRepresentation])]
                            completion:nil];
  [refresh waitUntilFinishedBeforeDate:[NSDate dateWithTimeIntervalSinceNow:10.0]];
  XCTAssertNil([refresh duplicateCollector]);

  LDScanSession *rescan = [[LDScanSession alloc] init];
  [rescan setScanOptions:options];
  [rescan startAsyncRescanOfRootPath:directory completion:nil];
  [rescan waitUntilFinishedBeforeDate:[NSDate dateWithTimeIntervalSinceNow:10.0]];
  XCTAssertNil([rescan duplicateCollector]);
}

- (void)testOptionsCopyKeepsFindsDuplicates
{
  LDScanOptions *options = [[LDScanOptions alloc] init];
  XCTAssertFalse([options findsDuplicates]);
  [options setFindsDuplicates:YES];
  XCTAssertTrue([[options copy] findsDuplicates]);
}

@end
