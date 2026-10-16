#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDCSV.h"
#import "LDCommandRules.h"
#import "LDExtensionStats.h"
#import "LDFileNode.h"
#import "LDHardLinks.h"
#import "LDLargestFiles.h"
#import "LDNodeRanking.h"
#import "LDScanOptions.h"
#import "LDScanSession.h"
#import "LDScanner.h"
#import "LDSearch.h"
#import "LDTreemapLayout.h"

#include <sys/stat.h>
#include <unistd.h>

@interface LDHardLinksTests : XCTestCase
{
  NSString *_temporaryRoot;
}
@end

@implementation LDHardLinksTests

- (void)setUp
{
  [super setUp];
  NSString *name = [NSString stringWithFormat:@"lindirstat-links-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
  _temporaryRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
  [[NSFileManager defaultManager] createDirectoryAtPath:_temporaryRoot withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
  [[NSFileManager defaultManager] removeItemAtPath:_temporaryRoot error:NULL];
  _temporaryRoot = nil;
  [super tearDown];
}

- (NSString *)pathFor:(NSString *)name
{
  return [_temporaryRoot stringByAppendingPathComponent:name];
}

- (void)writeFile:(NSString *)name bytes:(NSUInteger)bytes
{
  NSString *path = [self pathFor:name];
  [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
  [[NSMutableData dataWithLength:bytes] writeToFile:path atomically:NO];
}

- (void)link:(NSString *)existing as:(NSString *)name
{
  NSString *path = [self pathFor:name];
  [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
  XCTAssertEqual(0, link([[self pathFor:existing] fileSystemRepresentation], [path fileSystemRepresentation]));
}

- (unsigned long long)allocatedSizeOf:(NSString *)name
{
  struct stat info;
  XCTAssertEqual(0, lstat([[self pathFor:name] fileSystemRepresentation], &info));
  return (unsigned long long)info.st_blocks * 512ULL;
}

- (unsigned long long)inodeOf:(NSString *)name
{
  struct stat info;
  XCTAssertEqual(0, lstat([[self pathFor:name] fileSystemRepresentation], &info));
  return (unsigned long long)info.st_ino;
}

// tree/a/shared.bin and tree/b/link.bin are one 8000-byte file; tree/b/own.bin
// and tree/c/solo.bin are plain.
- (NSString *)makeLinkedTree
{
  [self writeFile:@"tree/a/shared.bin" bytes:8000];
  [self link:@"tree/a/shared.bin" as:@"tree/b/link.bin"];
  [self writeFile:@"tree/b/own.bin" bytes:3000];
  [self writeFile:@"tree/c/solo.bin" bytes:1000];
  return [self pathFor:@"tree"];
}

- (LDFileNode *)scan:(NSString *)path processHardLinks:(BOOL)process
{
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setProcessHardLinks:process];
  LDScanner *scanner = [[LDScanner alloc] init];
  [scanner setScanOptions:options];
  return [scanner scanPath:path session:[[LDScanSession alloc] init]];
}

- (LDFileNode *)child:(NSString *)name of:(LDFileNode *)node
{
  for (LDFileNode *child in [node children]) {
    if ([[child displayName] isEqualToString:name]) {
      return child;
    }
  }
  return nil;
}

- (LDFileNode *)node:(NSString *)relativePath under:(LDFileNode *)root
{
  LDFileNode *cursor = root;
  for (NSString *component in [relativePath pathComponents]) {
    cursor = [self child:component of:cursor];
  }
  return cursor;
}

// Rescans relativePath below root with the tree's table, as Refresh Selected
// does, and puts the result in place.
- (LDFileNode *)refresh:(NSString *)relativePath under:(LDFileNode *)root
{
  LDFileNode *old = [self node:relativePath under:root];
  LDHardLinkTable *table = [LDHardLinkTable tableForRoot:root];
  LDScanner *scanner = [[LDScanner alloc] init];
  [scanner setHardLinkTable:table replacing:old];
  LDFileNode *replacement = [scanner scanEntryAtPathData:[old pathData] session:[[LDScanSession alloc] init]];
  LDDirectoryNode *parent = (LDDirectoryNode *)[old parent];
  if (replacement) {
    [parent replaceChild:old withNode:replacement];
  } else {
    [parent removeChild:old];
  }
  [parent updateTotalsUpwardSortedByMetric:LDSizeMetricPhysical];
  NSMutableArray *folders = [NSMutableArray array];
  for (LDFileNode *heir in [table removeLinksUnder:old]) {
    [folders addObject:[heir parent]];
  }
  [folders addObjectsFromArray:[LDHardLinks updateTree:root table:table metric:LDSizeMetricPhysical retiring:nil]];
  for (LDFileNode *folder in folders) {
    [folder updateTotalsUpwardSortedByMetric:LDSizeMetricPhysical];
  }
  return replacement;
}

#pragma mark - Scanning

- (void)testLinkSetsAreShownUnderHardlinks
{
  NSString *path = [self makeLinkedTree];
  unsigned long long shared = [self allocatedSizeOf:@"tree/a/shared.bin"];
  unsigned long long own = [self allocatedSizeOf:@"tree/b/own.bin"];
  unsigned long long solo = [self allocatedSizeOf:@"tree/c/solo.bin"];
  LDFileNode *root = [self scan:path processHardLinks:YES];

  LDFileNode *first = [self node:@"a/shared.bin" under:root];
  LDFileNode *second = [self node:@"b/link.bin" under:root];
  XCTAssertTrue([first isHardLink]);
  XCTAssertTrue([second isHardLink]);
  XCTAssertFalse([[self node:@"b/own.bin" under:root] isHardLink]);
  // Links add nothing to their folders; "<Hardlinks>" counts the file once.
  XCTAssertEqual((unsigned long long)0, [[self child:@"a" of:root] aggregateAllocatedSize]);
  XCTAssertEqual(own, [[self child:@"b" of:root] aggregateAllocatedSize]);
  XCTAssertEqual((unsigned long long)3000, [[self child:@"b" of:root] aggregateSize]);
  XCTAssertEqual(shared + own + solo, [root aggregateAllocatedSize]);
  XCTAssertEqual((unsigned long long)12000, [root aggregateSize]);
  XCTAssertEqual((NSUInteger)4, [root fileCount]);
  XCTAssertEqual((NSUInteger)4, [root directoryCount]);

  LDFileNode *container = [self child:@"<Hardlinks>" of:root];
  XCTAssertNotNil(container);
  XCTAssertEqual(container, [LDHardLinks containerForNode:second]);
  XCTAssertEqual(LDHardLinkItemContainer, LDHardLinkItemTypeOfNode(container));
  XCTAssertEqual(shared, [container aggregateAllocatedSize]);
  XCTAssertEqual((NSUInteger)0, [container fileCount]);
  XCTAssertEqual((NSUInteger)1, [[container children] count]);

  unsigned long long inode = [self inodeOf:@"tree/a/shared.bin"];
  LDFileNode *indexSet = [[container children] objectAtIndex:0];
  XCTAssertEqual(LDHardLinkItemIndexSet, LDHardLinkItemTypeOfNode(indexSet));
  XCTAssertEqualObjects(([NSString stringWithFormat:@"Index ≡ 0x%02X", (unsigned)(inode % 20) + 1]), [indexSet displayName]);
  LDFileNode *index = [[indexSet children] objectAtIndex:0];
  XCTAssertEqual(LDHardLinkItemIndex, LDHardLinkItemTypeOfNode(index));
  XCTAssertEqualObjects(([NSString stringWithFormat:@"Index 0x%016llX", inode]), [index displayName]);
  XCTAssertTrue([index isLeaf]);
  XCTAssertEqual(shared, [index aggregateAllocatedSize]);
  XCTAssertEqual((unsigned long long)8000, [index aggregateSize]);
  XCTAssertEqual(index, [LDHardLinks indexNodeForLink:first]);
  XCTAssertEqual(index, [LDHardLinks indexNodeForLink:second]);

  NSArray *references = [index children];
  XCTAssertEqual((NSUInteger)2, [references count]);
  NSMutableSet *names = [NSMutableSet set];
  for (LDFileNode *reference in references) {
    XCTAssertEqual(LDHardLinkItemReference, LDHardLinkItemTypeOfNode(reference));
    XCTAssertEqual(shared, [reference allocatedSize]);
    [names addObject:[reference displayName]];
    LDFileNode *link = [LDHardLinks linkForReference:reference];
    XCTAssertEqualObjects([link path], [reference displayName]);
  }
  XCTAssertEqualObjects(([NSSet setWithObjects:[path stringByAppendingPathComponent:@"a/shared.bin"],
                          [path stringByAppendingPathComponent:@"b/link.bin"], nil]), names);

  LDHardLinkSet *set = [[LDHardLinkTable tableForRoot:root] setForNode:first];
  XCTAssertEqual(set, [[LDHardLinkTable tableForRoot:root] setForNode:second]);
  XCTAssertEqual(inode, [set inode]);
  XCTAssertEqual(shared, [set allocatedSize]);
  XCTAssertNil([[LDHardLinkTable tableForRoot:root] setForNode:[self node:@"b/own.bin" under:root]]);
}

- (void)testWithoutTheOptionLinksAreCountedOnceAsBefore
{
  NSString *path = [self makeLinkedTree];
  unsigned long long shared = [self allocatedSizeOf:@"tree/a/shared.bin"];
  LDFileNode *root = [self scan:path processHardLinks:NO];

  XCTAssertNil([self child:@"<Hardlinks>" of:root]);
  LDFileNode *first = [self node:@"a/shared.bin" under:root];
  LDFileNode *second = [self node:@"b/link.bin" under:root];
  XCTAssertFalse([first isHardLink]);
  XCTAssertFalse([second isHardLink]);
  XCTAssertTrue([first isHardLinkDuplicate] != [second isHardLinkDuplicate]);
  XCTAssertEqual(shared, [first aggregateAllocatedSize] + [second aggregateAllocatedSize]);
  XCTAssertEqual((unsigned long long)12000, [root aggregateSize]);
  // The table is kept either way, for Refresh Selected.
  XCTAssertNotNil([[LDHardLinkTable tableForRoot:root] setForNode:first]);
}

- (void)testLinkWhoseOtherLinkIsOutsideTheScanIsAPlainFile
{
  [self makeLinkedTree];
  LDFileNode *root = [self scan:[self pathFor:@"tree/b"] processHardLinks:YES];

  XCTAssertNil([self child:@"<Hardlinks>" of:root]);
  LDFileNode *link = [self child:@"link.bin" of:root];
  XCTAssertFalse([link isHardLink]);
  XCTAssertFalse([link isHardLinkDuplicate]);
  XCTAssertEqual((unsigned long long)11000, [root aggregateSize]);
}

- (void)testSeveralRootsGetTheirOwnHardlinks
{
  [self makeLinkedTree];
  [self link:@"tree/c/solo.bin" as:@"tree/c/solo-again.bin"];
  LDScanner *scanner = [[LDScanner alloc] init];
  LDFileNode *computer = [scanner scanPaths:@[[self pathFor:@"tree/a"], [self pathFor:@"tree/b"], [self pathFor:@"tree/c"]]
                                    session:[[LDScanSession alloc] init]];

  XCTAssertNil([self child:@"<Hardlinks>" of:computer]);
  LDFileNode *a = [self child:@"a" of:computer];
  LDFileNode *c = [self child:@"c" of:computer];
  // The set spanning a and b goes under the root of its first link.
  XCTAssertNotNil([self child:@"<Hardlinks>" of:a]);
  XCTAssertNil([self child:@"<Hardlinks>" of:[self child:@"b" of:computer]]);
  XCTAssertNotNil([self child:@"<Hardlinks>" of:c]);
  XCTAssertEqual((unsigned long long)12000, [computer aggregateSize]);
  XCTAssertEqual((NSUInteger)5, [computer fileCount]);
}

#pragma mark - Refresh and deletion

- (void)testRefreshKeepsTheScanHardLinkSet
{
  NSString *path = [self makeLinkedTree];
  for (NSNumber *process in @[@NO, @YES]) {
    LDFileNode *root = [self scan:path processHardLinks:[process boolValue]];
    unsigned long long total = [root aggregateAllocatedSize];

    // b holds one link; the other is outside it, so the rescan does not
    // count the file again.
    LDFileNode *b = [self refresh:@"b" under:root];
    XCTAssertNotNil(b);
    XCTAssertEqual(total, [root aggregateAllocatedSize], @"process %@", process);
    XCTAssertEqual((unsigned long long)12000, [root aggregateSize], @"process %@", process);
    XCTAssertEqual([process boolValue], [[self child:@"link.bin" of:b] isHardLink]);

    // a may hold the counted link; its rescan keeps the file counted once.
    [self refresh:@"a" under:root];
    XCTAssertEqual(total, [root aggregateAllocatedSize], @"process %@", process);
    XCTAssertEqual((unsigned long long)12000, [root aggregateSize], @"process %@", process);
    LDHardLinkSet *set = [[LDHardLinkTable tableForRoot:root] setForNode:[self node:@"b/link.bin" under:root]];
    XCTAssertEqual((NSUInteger)2, [[set members] count]);
    XCTAssertEqual([process boolValue], [self child:@"<Hardlinks>" of:root] != nil);
  }
}

- (void)testDeletingALinkMovesTheBytesToTheOtherLink
{
  NSString *path = [self makeLinkedTree];
  for (NSNumber *process in @[@NO, @YES]) {
    LDFileNode *root = [self scan:path processHardLinks:[process boolValue]];
    unsigned long long total = [root aggregateAllocatedSize];
    unsigned long long shared = [self allocatedSizeOf:@"tree/a/shared.bin"];

    // Leave the file on disk (it is scanned again in the next round) but
    // take a out of the tree, as a deletion does.
    LDFileNode *a = [self child:@"a" of:root];
    LDHardLinkTable *table = [LDHardLinkTable tableForRoot:root];
    [(LDDirectoryNode *)root removeChild:a];
    [root updateTotalsUpwardSortedByMetric:LDSizeMetricPhysical];
    for (LDFileNode *heir in [table removeLinksUnder:a]) {
      [[heir parent] updateTotalsUpwardSortedByMetric:LDSizeMetricPhysical];
    }
    for (LDFileNode *folder in [LDHardLinks updateTree:root table:table metric:LDSizeMetricPhysical retiring:nil]) {
      [folder updateTotalsUpwardSortedByMetric:LDSizeMetricPhysical];
    }

    LDFileNode *link = [self node:@"b/link.bin" under:root];
    XCTAssertFalse([link isHardLink]);
    XCTAssertFalse([link isHardLinkDuplicate]);
    XCTAssertEqual(shared, [link aggregateAllocatedSize]);
    XCTAssertNil([self child:@"<Hardlinks>" of:root]);
    XCTAssertEqual(total, [root aggregateAllocatedSize], @"process %@", process);
    XCTAssertEqual((unsigned long long)12000, [root aggregateSize]);
  }
}

#pragma mark - CSV

- (NSArray *)rowsOfCSV:(NSString *)path
{
  NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
  NSMutableArray *rows = [NSMutableArray array];
  for (NSString *line in [text componentsSeparatedByString:@"\r\n"]) {
    if ([line length] > 0) {
      [rows addObject:line];
    }
  }
  return rows;
}

- (NSArray *)fieldsOfRowNamed:(NSString *)path inRows:(NSArray *)rows
{
  NSString *prefix = [NSString stringWithFormat:@"\"%@\",", path];
  for (NSString *row in rows) {
    if ([row hasPrefix:prefix]) {
      return [[row substringFromIndex:[prefix length]] componentsSeparatedByString:@","];
    }
  }
  return nil;
}

- (void)testCSVUndoesTheDeduplicationAndWritesIndexes
{
  NSString *path = [self makeLinkedTree];
  unsigned long long shared = [self allocatedSizeOf:@"tree/a/shared.bin"];
  unsigned long long own = [self allocatedSizeOf:@"tree/b/own.bin"];
  unsigned long long solo = [self allocatedSizeOf:@"tree/c/solo.bin"];
  for (NSNumber *process in @[@NO, @YES]) {
    LDFileNode *root = [self scan:path processHardLinks:[process boolValue]];
    NSString *csv = [self pathFor:@"out.csv"];
    NSError *error = nil;
    XCTAssertTrue([LDCSV writeTree:root toPath:csv includeOwner:NO error:&error], @"%@", error);
    NSArray *rows = [self rowsOfCSV:csv];

    // Header, tree, a, a/shared.bin, b, b/link.bin, b/own.bin, c, c/solo.bin;
    // no "<Hardlinks>" rows.
    XCTAssertEqual((NSUInteger)9, [rows count], @"process %@", process);
    for (NSString *row in rows) {
      XCTAssertEqual(NSNotFound, [row rangeOfString:@"Hardlinks"].location);
    }
    // Fields after the name: Files, Folders, Logical, Physical, Attributes,
    // Last Change, WinDirStat Attributes, Index.
    NSArray *link = [self fieldsOfRowNamed:[path stringByAppendingPathComponent:@"b/link.bin"] inRows:rows];
    NSArray *first = [self fieldsOfRowNamed:[path stringByAppendingPathComponent:@"a/shared.bin"] inRows:rows];
    XCTAssertEqualObjects(@"8000", [link objectAtIndex:2]);
    XCTAssertEqualObjects(@"8000", [first objectAtIndex:2]);
    XCTAssertEqual(shared, strtoull([[link objectAtIndex:3] UTF8String], NULL, 10));
    XCTAssertEqual(shared, strtoull([[first objectAtIndex:3] UTF8String], NULL, 10));
    NSString *inode = [NSString stringWithFormat:@"0x%016llX", [self inodeOf:@"tree/a/shared.bin"]];
    XCTAssertEqualObjects(inode, [link objectAtIndex:7]);
    XCTAssertEqualObjects(inode, [first objectAtIndex:7]);
    XCTAssertEqualObjects(([NSString stringWithFormat:@"0x%016llX", [self inodeOf:@"tree/c/solo.bin"]]),
                          [[self fieldsOfRowNamed:[path stringByAppendingPathComponent:@"c/solo.bin"] inRows:rows] objectAtIndex:7]);
    XCTAssertEqualObjects(([NSString stringWithFormat:@"0x%016llX", [self inodeOf:@"tree"]]),
                          [[self fieldsOfRowNamed:path inRows:rows] objectAtIndex:7]);

    NSArray *a = [self fieldsOfRowNamed:[path stringByAppendingPathComponent:@"a"] inRows:rows];
    NSArray *b = [self fieldsOfRowNamed:[path stringByAppendingPathComponent:@"b"] inRows:rows];
    NSArray *top = [self fieldsOfRowNamed:path inRows:rows];
    XCTAssertEqual(shared, strtoull([[a objectAtIndex:3] UTF8String], NULL, 10));
    XCTAssertEqual(shared + own, strtoull([[b objectAtIndex:3] UTF8String], NULL, 10));
    XCTAssertEqualObjects(@"11000", [b objectAtIndex:2]);
    XCTAssertEqual(2 * shared + own + solo, strtoull([[top objectAtIndex:3] UTF8String], NULL, 10));
    XCTAssertEqualObjects(@"20000", [top objectAtIndex:2]);

    // Reading it back counts the links once again.
    LDFileNode *loaded = [LDCSV readTreeFromPath:csv processHardLinks:[process boolValue] error:&error];
    XCTAssertNotNil(loaded, @"%@", error);
    XCTAssertEqual([root aggregateAllocatedSize], [loaded aggregateAllocatedSize]);
    XCTAssertEqual((unsigned long long)12000, [loaded aggregateSize]);
    XCTAssertEqual([process boolValue], [self child:@"<Hardlinks>" of:loaded] != nil);
    XCTAssertEqual([process boolValue], [[self node:@"b/link.bin" under:loaded] isHardLink]);

    // Links scanned again later match the loaded ones by inode.
    [self refresh:@"b" under:loaded];
    XCTAssertEqual([root aggregateAllocatedSize], [loaded aggregateAllocatedSize]);
    XCTAssertEqual((unsigned long long)12000, [loaded aggregateSize]);
  }
}

- (void)testCSVWithoutIndexesIsTakenAsWritten
{
  NSString *csv = [self pathFor:@"old.csv"];
  NSString *text = @"\"Name\",\"Files\",\"Folders\",\"Logical Size\",\"Physical Size\",\"Attributes\",\"Last Change\",\"WinDirStat Attributes\",\"Index\""
    @"\r\n\"/d\",2,0,10,8192,\"\",1970-01-01T00:00:00Z,0x30000004,0x0000000000000000"
    @"\r\n\"/d/x\",0,0,10,8192,\"\",1970-01-01T00:00:00Z,0x20000008,0x0000000000000000"
    @"\r\n\"/d/y\",0,0,0,0,\"\",1970-01-01T00:00:00Z,0x20000008,0x0000000000000000";
  [[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:csv atomically:NO];
  LDFileNode *loaded = [LDCSV readTreeFromPath:csv error:NULL];
  XCTAssertEqual((unsigned long long)8192, [loaded aggregateAllocatedSize]);
  XCTAssertNil([self child:@"<Hardlinks>" of:loaded]);
}

#pragma mark - Exclusions

- (void)testPseudoItemsAreLeftOutOfListsStatsAndCommands
{
  NSString *path = [self makeLinkedTree];
  LDFileNode *root = [self scan:path processHardLinks:YES];
  LDFileNode *container = [self child:@"<Hardlinks>" of:root];
  LDFileNode *index = [[(LDFileNode *)[[container children] objectAtIndex:0] children] objectAtIndex:0];
  LDFileNode *reference = [[index children] objectAtIndex:0];

  __block NSUInteger visited = 0;
  LDVisitNodes(root, ^(LDFileNode *node) {
    XCTAssertFalse(LDIsHardLinkItem(node));
    visited++;
  });
  XCTAssertEqual((NSUInteger)8, visited);

  NSArray *largest = [LDLargestFiles largestFilesUnderNode:root count:10];
  XCTAssertEqual((NSUInteger)3, [largest count]);
  for (LDFileNode *node in largest) {
    XCTAssertFalse(LDIsHardLinkItem(node));
  }
  LDSearchResult *found = [LDSearch searchNode:root options:[LDSearchOptions optionsWithTerm:@"bin"] maxResults:0];
  for (LDFileNode *node in [found nodes]) {
    XCTAssertFalse(LDIsHardLinkItem(node));
  }

  NSArray *stats = [LDExtensionStats sortedStatsForRootNode:root metric:LDSizeMetricLogical];
  XCTAssertEqual((NSUInteger)1, [stats count]);
  XCTAssertEqual((NSUInteger)4, [[stats objectAtIndex:0] fileCount]);
  XCTAssertEqual((unsigned long long)12000, [[stats objectAtIndex:0] bytesForMetric:LDSizeMetricLogical]);

  for (LDFileNode *item in @[container, index, reference]) {
    for (int command = LDCommandOpen; command <= LDCommandCustomCleanup; command++) {
      XCTAssertFalse([LDCommandRules isCommand:(LDCommand)command enabledForNodes:@[item] rootNode:root busy:NO]);
    }
  }
  LDFileNode *link = [self node:@"b/link.bin" under:root];
  XCTAssertTrue([LDCommandRules isCommand:LDCommandMoveToTrash enabledForNodes:@[link] rootNode:root busy:NO]);
}

- (void)testTreemapDrawsIndexFoldersInWinDirStatsColour
{
  NSString *path = [self makeLinkedTree];
  LDFileNode *root = [self scan:path processHardLinks:YES];
  LDFileNode *container = [self child:@"<Hardlinks>" of:root];
  LDFileNode *index = [[(LDFileNode *)[[container children] objectAtIndex:0] children] objectAtIndex:0];

  XCTAssertEqual((LDRGBColor)(LDRGB(200, 150, 100) | LDTreemapColorFlagLighter),
                 [LDTreemap colorForNode:index colorIndexes:@{}]);

  LDTreemap *treemap = [[LDTreemap alloc] initWithRootNode:root metric:LDSizeMetricPhysical
                                                      width:200 height:100 options:LDTreemapDefaultOptions()];
  // The Index folder is a painted leaf; links have no area of their own.
  NSInteger cell = [treemap cellIndexForNode:index];
  XCTAssertTrue(cell >= 0);
  XCTAssertEqual(index, [treemap nodeOfCell:(NSUInteger)cell]);
  XCTAssertTrue([treemap isCellRendered:(NSUInteger)cell]);
  NSInteger linkCell = [treemap cellIndexForNode:[self node:@"a/shared.bin" under:root]];
  XCTAssertTrue(linkCell < 0 || [treemap nodeOfCell:(NSUInteger)linkCell] != [self node:@"a/shared.bin" under:root]);
}

@end
