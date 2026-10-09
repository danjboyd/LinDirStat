#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDScanner.h"
#import "LDScanSession.h"
#import "LDDuplicateFinder.h"
#import "LDHasher.h"

#include <sys/stat.h>
#include <unistd.h>

@interface LDDuplicateFinderTests : XCTestCase
{
  NSString *_temporaryRoot;
  // Nodes must not outlive their root, so tests keep it here.
  LDFileNode *_root;
}
@end

@implementation LDDuplicateFinderTests

- (NSString *)temporaryRoot
{
  if (!_temporaryRoot) {
    NSString *name = [NSString stringWithFormat:@"lindirstat-dupes-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
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

- (NSString *)write:(NSData *)contents to:(NSString *)relativePath
{
  NSString *path = [[self temporaryRoot] stringByAppendingPathComponent:relativePath];
  [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  [contents writeToFile:path atomically:NO];
  return path;
}

// length bytes of fill, with the last byte replaced by tail.
- (NSData *)bytes:(NSUInteger)length fill:(uint8_t)fill tail:(uint8_t)tail
{
  NSMutableData *data = [NSMutableData dataWithLength:length];
  memset([data mutableBytes], fill, length);
  if (length > 0) {
    ((uint8_t *)[data mutableBytes])[length - 1] = tail;
  }
  return data;
}

- (LDFileNode *)scan
{
  LDScanner *scanner = [[LDScanner alloc] init];
  _root = [scanner scanPath:[self temporaryRoot] session:[[LDScanSession alloc] init]];
  return _root;
}

- (NSArray *)namesOf:(LDDuplicateGroup *)group
{
  NSMutableArray *names = [NSMutableArray array];
  for (LDFileNode *node in [group nodes]) {
    [names addObject:[node displayName]];
  }
  return names;
}

- (LDDuplicateGroup *)groupContaining:(NSString *)name in:(NSArray *)groups
{
  for (LDDuplicateGroup *group in groups) {
    if ([[self namesOf:group] containsObject:name]) {
      return group;
    }
  }
  return nil;
}

- (LDFileNode *)nodeNamed:(NSString *)name under:(LDFileNode *)node
{
  if ([[node displayName] isEqualToString:name]) {
    return node;
  }
  for (LDFileNode *child in [node children]) {
    LDFileNode *found = [self nodeNamed:name under:child];
    if (found) {
      return found;
    }
  }
  return nil;
}

- (void)testIdenticalSmallFilesFormAGroupSortedByPath
{
  NSData *contents = [@"same bytes" dataUsingEncoding:NSASCIIStringEncoding];
  [self write:contents to:@"b/copy.txt"];
  [self write:contents to:@"a/original.txt"];
  [self write:[@"diff bytes" dataUsingEncoding:NSASCIIStringEncoding] to:@"other.txt"];
  [self write:[@"unique size" dataUsingEncoding:NSASCIIStringEncoding] to:@"lonely.txt"];

  NSArray *groups = [[[LDDuplicateFinder alloc] initWithRootNode:[self scan]] findGroups];

  XCTAssertEqual((NSUInteger)1, [groups count]);
  LDDuplicateGroup *group = [groups objectAtIndex:0];
  NSArray *expected = [NSArray arrayWithObjects:@"original.txt", @"copy.txt", nil];
  XCTAssertEqualObjects(expected, [self namesOf:group]);
  XCTAssertEqual((NSUInteger)2, [group count]);
  XCTAssertEqual((unsigned long long)10, [group logicalSize]);
  XCTAssertEqual((unsigned long long)20, [group totalLogicalSize]);
  NSData *digest = [LDHasher duplicateDigestForFileAtPath:[[[group nodes] objectAtIndex:0] pathData]
                                                byteLimit:ULLONG_MAX
                                                    error:NULL];
  XCTAssertEqualObjects([LDHasher hexStringForData:digest], [group hashString]);
  XCTAssertEqual((NSUInteger)32, [[group hashString] length]);
}

- (void)testTotalPhysicalSizeSumsAllocatedSizes
{
  NSData *contents = [self bytes:10000 fill:'x' tail:'x'];
  [self write:contents to:@"one.bin"];
  [self write:contents to:@"two.bin"];
  LDFileNode *root = [self scan];

  LDDuplicateGroup *group = [[[[LDDuplicateFinder alloc] initWithRootNode:root] findGroups] objectAtIndex:0];
  unsigned long long expected = [[self nodeNamed:@"one.bin" under:root] allocatedSize]
                              + [[self nodeNamed:@"two.bin" under:root] allocatedSize];
  XCTAssertEqual(expected, [group totalPhysicalSize]);
}

- (void)testFilesSharingFirstFourKiBButDifferingLaterAreNotDuplicates
{
  [self write:[self bytes:8192 fill:'a' tail:'1'] to:@"first.bin"];
  [self write:[self bytes:8192 fill:'a' tail:'2'] to:@"second.bin"];
  [self write:[self bytes:8192 fill:'a' tail:'1'] to:@"third.bin"];

  NSArray *groups = [[[LDDuplicateFinder alloc] initWithRootNode:[self scan]] findGroups];

  XCTAssertEqual((NSUInteger)1, [groups count]);
  NSArray *expected = [NSArray arrayWithObjects:@"first.bin", @"third.bin", nil];
  XCTAssertEqualObjects(expected, [self namesOf:[groups objectAtIndex:0]]);
}

- (void)testFilesSharingFirstMiBButDifferingLaterAreNotDuplicates
{
  NSUInteger length = 2 * 1024 * 1024 + 17;
  [self write:[self bytes:length fill:'m' tail:'1'] to:@"big-1.bin"];
  [self write:[self bytes:length fill:'m' tail:'2'] to:@"big-2.bin"];
  [self write:[self bytes:length fill:'m' tail:'2'] to:@"big-3.bin"];

  NSArray *groups = [[[LDDuplicateFinder alloc] initWithRootNode:[self scan]] findGroups];

  XCTAssertEqual((NSUInteger)1, [groups count]);
  LDDuplicateGroup *group = [groups objectAtIndex:0];
  NSArray *expected = [NSArray arrayWithObjects:@"big-2.bin", @"big-3.bin", nil];
  XCTAssertEqualObjects(expected, [self namesOf:group]);
  // The reported hash is the whole-file tier's.
  NSData *whole = [LDHasher duplicateDigestForFileAtPath:[[[group nodes] objectAtIndex:0] pathData]
                                               byteLimit:ULLONG_MAX
                                                   error:NULL];
  XCTAssertEqualObjects([LDHasher hexStringForData:whole], [group hashString]);
}

- (void)testZeroByteFilesAreGrouped
{
  [self write:[NSData data] to:@"empty-a"];
  [self write:[NSData data] to:@"empty-b"];

  NSArray *groups = [[[LDDuplicateFinder alloc] initWithRootNode:[self scan]] findGroups];

  XCTAssertEqual((NSUInteger)1, [groups count]);
  XCTAssertEqual((NSUInteger)2, [[groups objectAtIndex:0] count]);
  XCTAssertEqual((unsigned long long)0, [[groups objectAtIndex:0] logicalSize]);
}

- (void)testHardLinkDuplicatesAreExcluded
{
  NSData *contents = [@"linked contents" dataUsingEncoding:NSASCIIStringEncoding];
  NSString *original = [self write:contents to:@"original"];
  NSString *linked = [[self temporaryRoot] stringByAppendingPathComponent:@"linked"];
  XCTAssertEqual(0, link([original fileSystemRepresentation], [linked fileSystemRepresentation]));
  [self write:contents to:@"copy"];

  NSArray *groups = [[[LDDuplicateFinder alloc] initWithRootNode:[self scan]] findGroups];

  XCTAssertEqual((NSUInteger)1, [groups count]);
  XCTAssertEqual((NSUInteger)2, [[groups objectAtIndex:0] count]);
  for (LDFileNode *node in [[groups objectAtIndex:0] nodes]) {
    XCTAssertFalse([node isHardLinkDuplicate]);
  }
}

- (void)testUnreadableFilesAreDropped
{
  if (geteuid() == 0) {
    return; // root reads mode-000 files.
  }
  NSData *contents = [@"readable?" dataUsingEncoding:NSASCIIStringEncoding];
  [self write:contents to:@"one"];
  [self write:contents to:@"two"];
  NSString *locked = [self write:contents to:@"locked"];
  [self write:[@"secret!!!" dataUsingEncoding:NSASCIIStringEncoding] to:@"locked-pair"];
  NSString *lockedPairCopy = [self write:[@"secret!!!" dataUsingEncoding:NSASCIIStringEncoding] to:@"locked-pair-copy"];
  chmod([locked fileSystemRepresentation], 0);
  chmod([lockedPairCopy fileSystemRepresentation], 0);

  NSArray *groups = [[[LDDuplicateFinder alloc] initWithRootNode:[self scan]] findGroups];

  chmod([locked fileSystemRepresentation], 0644);
  chmod([lockedPairCopy fileSystemRepresentation], 0644);
  XCTAssertEqual((NSUInteger)1, [groups count]);
  NSArray *expected = [NSArray arrayWithObjects:@"one", @"two", nil];
  XCTAssertEqualObjects(expected, [self namesOf:[groups objectAtIndex:0]]);
}

- (void)testGroupsAreSortedByTotalPhysicalSize
{
  [self write:[self bytes:100 fill:'s' tail:'s'] to:@"small-1"];
  [self write:[self bytes:100 fill:'s' tail:'s'] to:@"small-2"];
  [self write:[self bytes:100000 fill:'l' tail:'l'] to:@"large-1"];
  [self write:[self bytes:100000 fill:'l' tail:'l'] to:@"large-2"];

  NSArray *groups = [[[LDDuplicateFinder alloc] initWithRootNode:[self scan]] findGroups];

  XCTAssertEqual((NSUInteger)2, [groups count]);
  XCTAssertEqual((unsigned long long)100000, [[groups objectAtIndex:0] logicalSize]);
  XCTAssertEqual((unsigned long long)100, [[groups objectAtIndex:1] logicalSize]);
}

- (void)testExtensionsLabel
{
  NSData *contents = [@"label" dataUsingEncoding:NSASCIIStringEncoding];
  [self write:contents to:@"a.JPG"];
  [self write:contents to:@"b.png"];
  [self write:contents to:@"c.jpg"];
  [self write:contents to:@"d"];

  NSArray *groups = [[[LDDuplicateFinder alloc] initWithRootNode:[self scan]] findGroups];

  XCTAssertEqualObjects(@"(.jpg, .png, .?\?\?)", [[groups objectAtIndex:0] extensionsLabel]);
}

- (void)testLongExtensionsLabelIsTruncated
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/x" kind:LDFileNodeKindDirectory size:0];
  NSMutableArray *nodes = [NSMutableArray array];
  for (NSUInteger index = 0; index < 40; index++) {
    LDFileNode *node = [LDFileNode nodeWithName:[NSString stringWithFormat:@"f.ext%lu", (unsigned long)index]
                                           kind:LDFileNodeKindFile
                                           size:1
                                  allocatedSize:1];
    [root addChild:node];
    [nodes addObject:node];
  }
  LDDuplicateGroup *group = [[LDDuplicateGroup alloc] initWithHashString:@"00" logicalSize:1 nodes:nodes totalPhysicalSize:40];
  NSString *label = [group extensionsLabel];
  XCTAssertTrue([label hasPrefix:@"(.ext0, .ext1, "]);
  XCTAssertTrue([label hasSuffix:@"…)"]);
  XCTAssertEqual((NSUInteger)131, [label length]);
}

- (void)testRemovingNodesUnderDropsFilesAndSmallGroups
{
  NSData *pair = [@"pair" dataUsingEncoding:NSASCIIStringEncoding];
  NSData *trio = [@"trio!" dataUsingEncoding:NSASCIIStringEncoding];
  [self write:pair to:@"keep/pair-1"];
  [self write:pair to:@"gone/pair-2"];
  [self write:trio to:@"keep/trio-1"];
  [self write:trio to:@"keep/trio-2"];
  [self write:trio to:@"gone/trio-3"];
  LDFileNode *root = [self scan];
  NSArray *groups = [[[LDDuplicateFinder alloc] initWithRootNode:root] findGroups];
  XCTAssertEqual((NSUInteger)2, [groups count]);

  NSArray *removed = [NSArray arrayWithObject:[self nodeNamed:@"gone" under:root]];
  NSArray *remaining = [LDDuplicateFinder groups:groups removingNodesUnder:removed];

  XCTAssertEqual((NSUInteger)1, [remaining count]);
  NSArray *expected = [NSArray arrayWithObjects:@"trio-1", @"trio-2", nil];
  XCTAssertEqualObjects(expected, [self namesOf:[remaining objectAtIndex:0]]);
  XCTAssertEqual((unsigned long long)10, [[remaining objectAtIndex:0] totalLogicalSize]);

  NSArray *byFile = [NSArray arrayWithObject:[self nodeNamed:@"trio-1" under:root]];
  remaining = [LDDuplicateFinder groups:remaining removingNodesUnder:byFile];
  XCTAssertEqual((NSUInteger)0, [remaining count]);
}

- (void)testAsynchronousRunReportsOnMainThread
{
  NSData *contents = [@"async" dataUsingEncoding:NSASCIIStringEncoding];
  [self write:contents to:@"one"];
  [self write:contents to:@"two"];
  [self write:contents to:@"three"];
  LDDuplicateFinder *finder = [[LDDuplicateFinder alloc] initWithRootNode:[self scan]];

  __block NSArray *result = nil;
  __block BOOL completionOnMain = NO;
  __block BOOL progressOnMain = YES;
  __block NSUInteger lastHashed = 0;
  __block NSUInteger lastCandidates = 0;
  [finder startWithProgress:^(NSUInteger hashedFiles, NSUInteger candidateFiles) {
    progressOnMain = progressOnMain && [NSThread isMainThread];
    lastHashed = hashedFiles;
    lastCandidates = candidateFiles;
  } completion:^(NSArray *groups) {
    completionOnMain = [NSThread isMainThread];
    result = groups;
  }];

  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
  while (!result && [[NSDate date] compare:deadline] == NSOrderedAscending) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }

  XCTAssertNotNil(result);
  XCTAssertTrue(completionOnMain);
  XCTAssertTrue(progressOnMain);
  XCTAssertEqual((NSUInteger)3, lastCandidates);
  XCTAssertEqual((NSUInteger)3, lastHashed);
  XCTAssertEqual((NSUInteger)1, [result count]);
  XCTAssertEqual((NSUInteger)3, [[result objectAtIndex:0] count]);
}

- (void)testCancelSuppressesCompletion
{
  NSData *contents = [@"cancel me" dataUsingEncoding:NSASCIIStringEncoding];
  [self write:contents to:@"one"];
  [self write:contents to:@"two"];
  LDDuplicateFinder *finder = [[LDDuplicateFinder alloc] initWithRootNode:[self scan]];

  __block BOOL called = NO;
  [finder startWithProgress:nil completion:^(NSArray *groups) {
    (void)groups;
    called = YES;
  }];
  [finder cancel];
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

  XCTAssertTrue([finder isCancelled]);
  XCTAssertFalse(called);
}

@end
