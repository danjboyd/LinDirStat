#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDCSV.h"
#import "LDFileAttributes.h"
#import "LDFileNode.h"
#import "LDScanner.h"
#import "LDScanSession.h"

#include <pwd.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static NSString *const LDCSVTestHeader =
  @"\"Name\",\"Files\",\"Folders\",\"Logical Size\",\"Physical Size\",\"Attributes\",\"Last Change\",\"WinDirStat Attributes\",\"Index\"";

@interface LDCSVTests : XCTestCase
{
  NSString *_temporaryRoot;
}
@end

@implementation LDCSVTests

- (void)setUp
{
  [super setUp];
  NSString *name = [NSString stringWithFormat:@"lindirstat-csv-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
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

- (NSString *)writeCSV:(NSString *)contents named:(NSString *)name
{
  NSString *path = [self pathFor:name];
  [[contents dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:NO];
  return path;
}

- (NSString *)contentsOf:(NSString *)path
{
  NSData *data = [NSData dataWithContentsOfFile:path];
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (LDFileNode *)childNamed:(NSString *)name of:(LDFileNode *)node
{
  for (LDFileNode *child in [node children]) {
    if ([[child displayName] isEqualToString:name]) {
      return child;
    }
  }
  return nil;
}

- (LDFileNode *)fileNamed:(NSString *)name size:(unsigned long long)size allocated:(unsigned long long)allocated mode:(unsigned int)mode time:(NSTimeInterval)time
{
  LDFileNode *node = [LDFileNode nodeWithName:name kind:LDFileNodeKindFile size:size allocatedSize:allocated];
  [node setMode:S_IFREG | mode];
  [node setModificationTime:time];
  return node;
}

// /data { A (read-only) { say "hi" (read-only) }, b.txt }
- (LDFileNode *)handBuiltTree
{
  LDDirectoryNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  [root setMode:S_IFDIR | 0755];
  LDDirectoryNode *folder = [LDFileNode nodeWithName:@"A" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [folder setMode:S_IFDIR | 0555];
  [folder setModificationTime:500];
  [folder addChild:[self fileNamed:@"say \"hi\"" size:5 allocated:0 mode:0444 time:2000]];
  [root addChild:[self fileNamed:@"b.txt" size:10 allocated:4096 mode:0644 time:1000]];
  [root addChild:folder];
  [root recalculateAggregateSize];
  [root sortChildrenByMetric:LDSizeMetricPhysical];
  return root;
}

#pragma mark - Attributes

- (void)testAttributeLettersMapReadOnlyAndHidden
{
  LDFileNode *plain = [self fileNamed:@"a.txt" size:1 allocated:1 mode:0644 time:0];
  LDFileNode *readOnlyHidden = [self fileNamed:@".profile" size:1 allocated:1 mode:0444 time:0];
  LDFileNode *unknown = [LDFileNode nodeWithName:@".x" kind:LDFileNodeKindFile size:0 allocatedSize:0];
  LDFileNode *link = [LDFileNode nodeWithName:@"link" kind:LDFileNodeKindSymlink size:0 allocatedSize:0];
  [link setMode:S_IFLNK | 0444];
  LDFileNode *folder = [LDFileNode nodeWithName:@"dir" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [folder setMode:S_IFDIR | 0555];

  XCTAssertEqualObjects(@"", [LDFileAttributes attributeStringForNode:plain]);
  XCTAssertEqualObjects(@"RH", [LDFileAttributes attributeStringForNode:readOnlyHidden]);
  XCTAssertEqualObjects(@"", [LDFileAttributes attributeStringForNode:unknown]);
  XCTAssertEqualObjects(@"", [LDFileAttributes attributeStringForNode:link]);
  XCTAssertEqualObjects(@"R", [LDFileAttributes attributeStringForNode:folder]);
}

- (void)testOwnerOfPathUsesUserNameOrUID
{
  NSString *path = [self pathFor:@"owned"];
  [[NSData data] writeToFile:path atomically:NO];
  struct passwd *entry = getpwuid(getuid());
  NSString *expected = entry ? [NSString stringWithUTF8String:entry->pw_name]
                             : [NSString stringWithFormat:@"%lu", (unsigned long)getuid()];
  const char *bytes = [path fileSystemRepresentation];
  NSData *pathData = [NSData dataWithBytes:bytes length:strlen(bytes)];

  XCTAssertEqualObjects(expected, [LDFileAttributes ownerOfPath:pathData]);
  XCTAssertEqualObjects(expected, [LDFileAttributes ownerOfPath:pathData]);
  NSData *missing = [@"/nonexistent/lindirstat/owner" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertNil([LDFileAttributes ownerOfPath:missing]);
}

#pragma mark - Writing

- (void)testWritesWinDirStatRowsExactly
{
  NSString *path = [self pathFor:@"tree.csv"];
  NSError *error = nil;
  XCTAssertTrue([LDCSV writeTree:[self handBuiltTree] toPath:path includeOwner:NO error:&error], @"%@", error);

  NSString *expected = [NSString stringWithFormat:@"%@%@%@%@%@", LDCSVTestHeader,
    @"\r\n\"/data\",2,1,15,4096,\"\",1970-01-01T00:33:20Z,0x30000004,0x0000000000000000",
    @"\r\n\"/data/A\",1,0,5,0,\"R\",1970-01-01T00:33:20Z,0x20000004,0x0000000000000000",
    @"\r\n\"/data/A/say \"\"hi\"\"\",0,0,5,0,\"R\",1970-01-01T00:33:20Z,0x20000008,0x0000000000000000",
    @"\r\n\"/data/b.txt\",0,0,10,4096,\"\",1970-01-01T00:16:40Z,0x20000008,0x0000000000000000"];
  XCTAssertEqualObjects(expected, [self contentsOf:path]);
}

- (void)testNamesThatAreNotUTF8AreWrittenAsLatin1
{
  LDDirectoryNode *root = [LDFileNode nodeWithPath:@"/r" kind:LDFileNodeKindDirectory size:0];
  [root addChild:[LDFileNode nodeWithNameBytes:"caf\xe9" length:4 arena:nil kind:LDFileNodeKindFile size:1 allocatedSize:1]];
  [root recalculateAggregateSize];
  NSString *path = [self pathFor:@"latin1.csv"];
  XCTAssertTrue([LDCSV writeTree:root toPath:path includeOwner:NO error:NULL]);

  NSString *contents = [self contentsOf:path];
  XCTAssertNotNil(contents);
  XCTAssertTrue([contents rangeOfString:@"\"/r/caf\u00e9\""].location != NSNotFound);
}

- (void)testOwnerColumnIsAppendedWhenRequested
{
  NSString *folder = [self pathFor:@"owned-tree"];
  [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
  [[NSData dataWithBytes:"x" length:1] writeToFile:[folder stringByAppendingPathComponent:@"f"] atomically:NO];
  LDFileNode *root = [[[LDScanner alloc] init] scanPath:folder session:[[LDScanSession alloc] init]];
  NSString *owner = [LDFileAttributes ownerOfPath:[root pathData]];

  NSString *path = [self pathFor:@"owner.csv"];
  NSError *error = nil;
  XCTAssertTrue([LDCSV writeTree:root toPath:path includeOwner:YES error:&error], @"%@", error);

  NSArray *lines = [[self contentsOf:path] componentsSeparatedByString:@"\r\n"];
  XCTAssertEqual((NSUInteger)3, [lines count]);
  XCTAssertEqualObjects([LDCSVTestHeader stringByAppendingString:@",\"Owner\""], [lines objectAtIndex:0]);
  NSString *ownerField = [NSString stringWithFormat:@",\"%@\"", owner];
  XCTAssertTrue([[lines objectAtIndex:1] hasSuffix:ownerField]);
  XCTAssertTrue([[lines objectAtIndex:2] hasSuffix:ownerField]);

  LDFileNode *loaded = [LDCSV readTreeFromPath:path error:&error];
  XCTAssertNotNil(loaded, @"%@", error);
  XCTAssertEqual((NSUInteger)1, [loaded fileCount]);
}

#pragma mark - Reading

- (void)assertNode:(LDFileNode *)loaded matches:(LDFileNode *)scanned
{
  XCTAssertEqualObjects([scanned displayName], [loaded displayName]);
  XCTAssertEqual([scanned kind] == LDFileNodeKindDirectory, [loaded kind] == LDFileNodeKindDirectory, @"%@", [scanned path]);
  XCTAssertEqual([scanned aggregateSize], [loaded aggregateSize], @"%@", [scanned path]);
  XCTAssertEqual([scanned aggregateAllocatedSize], [loaded aggregateAllocatedSize], @"%@", [scanned path]);
  XCTAssertEqual([scanned fileCount], [loaded fileCount], @"%@", [scanned path]);
  XCTAssertEqual([scanned directoryCount], [loaded directoryCount], @"%@", [scanned path]);
  XCTAssertEqual([scanned aggregateModificationTime], [loaded aggregateModificationTime], @"%@", [scanned path]);
  XCTAssertEqualObjects([LDFileAttributes attributeStringForNode:scanned],
                        [LDFileAttributes attributeStringForNode:loaded], @"%@", [scanned path]);
  XCTAssertEqual([[scanned children] count], [[loaded children] count], @"%@", [scanned path]);
  for (LDFileNode *child in [scanned children]) {
    LDFileNode *match = [self childNamed:[child displayName] of:loaded];
    XCTAssertNotNil(match, @"%@", [child path]);
    if (match) {
      [self assertNode:match matches:child];
    }
  }
}

- (void)testScannedTreeRoundTrips
{
  NSFileManager *manager = [NSFileManager defaultManager];
  NSString *folder = [self pathFor:@"scan"];
  [manager createDirectoryAtPath:[folder stringByAppendingPathComponent:@"nested/deeper"] withIntermediateDirectories:YES attributes:nil error:NULL];
  [[NSMutableData dataWithLength:3000] writeToFile:[folder stringByAppendingPathComponent:@"nested/deeper/data.bin"] atomically:NO];
  [[NSMutableData dataWithLength:10] writeToFile:[folder stringByAppendingPathComponent:@"nested/Note.txt"] atomically:NO];
  [[NSMutableData dataWithLength:20] writeToFile:[folder stringByAppendingPathComponent:@".hidden"] atomically:NO];
  NSString *readOnly = [folder stringByAppendingPathComponent:@"readonly.txt"];
  [[NSMutableData dataWithLength:70000] writeToFile:readOnly atomically:NO];
  chmod([readOnly fileSystemRepresentation], 0444);

  LDFileNode *scanned = [[[LDScanner alloc] init] scanPath:folder session:[[LDScanSession alloc] init]];
  NSString *path = [self pathFor:@"scan.csv"];
  NSError *error = nil;
  XCTAssertTrue([LDCSV writeTree:scanned toPath:path includeOwner:NO error:&error], @"%@", error);

  LDFileNode *loaded = [LDCSV readTreeFromPath:path error:&error];
  XCTAssertNotNil(loaded, @"%@", error);
  XCTAssertEqualObjects([scanned path], [loaded path]);
  [self assertNode:loaded matches:scanned];
  XCTAssertEqualObjects(@"R", [LDFileAttributes attributeStringForNode:[self childNamed:@"readonly.txt" of:loaded]]);
  XCTAssertEqualObjects(@"H", [LDFileAttributes attributeStringForNode:[self childNamed:@".hidden" of:loaded]]);
  XCTAssertEqualObjects([folder stringByAppendingPathComponent:@"nested/deeper/data.bin"],
                        [[self childNamed:@"data.bin" of:[self childNamed:@"deeper" of:[self childNamed:@"nested" of:loaded]]] path]);
  // Children come back sorted by physical size.
  XCTAssertEqualObjects(@"readonly.txt", [[[loaded children] objectAtIndex:0] displayName]);
}

- (void)testQuotedNamesWithCommasQuotesAndNewlinesRoundTrip
{
  NSString *odd = @"a,\"b\"\r\nc";
  LDDirectoryNode *root = [LDFileNode nodeWithPath:@"/odd \"root\"" kind:LDFileNodeKindDirectory size:0];
  [root addChild:[self fileNamed:odd size:3 allocated:4096 mode:0644 time:1700000000]];
  [root recalculateAggregateSize];
  NSString *path = [self pathFor:@"odd.csv"];
  XCTAssertTrue([LDCSV writeTree:root toPath:path includeOwner:NO error:NULL]);

  NSError *error = nil;
  LDFileNode *loaded = [LDCSV readTreeFromPath:path error:&error];
  XCTAssertNotNil(loaded, @"%@", error);
  XCTAssertEqualObjects(@"/odd \"root\"", [loaded path]);
  LDFileNode *child = [[loaded children] firstObject];
  XCTAssertEqualObjects(odd, [child displayName]);
  XCTAssertEqual((unsigned long long)3, [child size]);
  XCTAssertEqual((NSTimeInterval)1700000000, [child modificationTime]);
}

- (void)testMissingColumnIsReported
{
  NSString *path = [self writeCSV:@"\"Name\",\"Files\",\"Folders\",\"Logical Size\",\"Physical Size\",\"Attributes\",\"Last Change\",\"WinDirStat Attributes\""
                                  @"\r\n\"/x\",0,0,0,0,\"\",2024-01-01T00:00:00Z,0x30000004"
                            named:@"missing.csv"];
  NSError *error = nil;
  XCTAssertNil([LDCSV readTreeFromPath:path error:&error]);
  XCTAssertEqualObjects(LDCSVErrorDomain, [error domain]);
  XCTAssertEqual((NSInteger)LDCSVErrorMissingColumn, [error code]);
  XCTAssertTrue([[error localizedDescription] rangeOfString:@"\"Index\""].location != NSNotFound, @"%@", error);
}

- (void)testColumnsAreMatchedByNameInAnyOrder
{
  NSString *path = [self writeCSV:@"\"Index\",\"Owner\",\"WinDirStat Attributes\",\"Last Change\",\"Attributes\",\"Physical Size\",\"Logical Size\",\"Folders\",\"Files\",\"Name\"\n"
                                  @"0x0,\"me\",0x30000004,2024-01-01T00:00:00Z,\"\",8192,300,1,2,\"/top\"\n"
                                  @"0x0,\"me\",0x20000004,2024-01-01T00:00:00Z,\"R\",4096,100,0,1,\"/top/sub\"\n"
                                  @"0x0,\"me\",0x20000008,2024-01-01T00:00:00Z,\"\",4096,100,0,0,\"/top/sub/one\"\n"
                                  @"0x0,\"me\",0x20000008,2024-02-01T00:00:00Z,\"RH\",4096,200,0,0,\"/top/.two\"\n"
                            named:@"reordered.csv"];
  NSError *error = nil;
  LDFileNode *root = [LDCSV readTreeFromPath:path error:&error];
  XCTAssertNotNil(root, @"%@", error);
  XCTAssertEqualObjects(@"/top", [root path]);
  XCTAssertEqual((unsigned long long)300, [root aggregateSize]);
  XCTAssertEqual((unsigned long long)8192, [root aggregateAllocatedSize]);
  XCTAssertEqual((NSUInteger)2, [root fileCount]);
  XCTAssertEqual((NSUInteger)2, [root directoryCount]);
  XCTAssertEqual((NSTimeInterval)1706745600, [root aggregateModificationTime]);
  LDFileNode *two = [self childNamed:@".two" of:root];
  XCTAssertEqualObjects(@"RH", [LDFileAttributes attributeStringForNode:two]);
  XCTAssertEqualObjects(@"R", [LDFileAttributes attributeStringForNode:[self childNamed:@"sub" of:root]]);
  XCTAssertEqualObjects(@"/top/sub/one", [[self childNamed:@"one" of:[self childNamed:@"sub" of:root]] path]);
}

- (void)testRowWithoutParentIsAnError
{
  NSString *path = [self writeCSV:[LDCSVTestHeader stringByAppendingString:
                                   @"\r\n\"/top\",0,0,0,0,\"\",2024-01-01T00:00:00Z,0x30000004,0x0"
                                   @"\r\n\"/elsewhere/file\",0,0,1,1,\"\",2024-01-01T00:00:00Z,0x20000008,0x0"]
                            named:@"orphan.csv"];
  NSError *error = nil;
  XCTAssertNil([LDCSV readTreeFromPath:path error:&error]);
  XCTAssertEqual((NSInteger)LDCSVErrorMissingParent, [error code]);
}

- (void)testReadsWinDirStatDriveExport
{
  NSString *fixture = [[[NSFileManager defaultManager] currentDirectoryPath]
                        stringByAppendingPathComponent:@"Tests/Fixtures/csv/windirstat-drive.csv"];
  NSError *error = nil;
  LDFileNode *root = [LDCSV readTreeFromPath:fixture error:&error];
  XCTAssertNotNil(root, @"%@", error);
  XCTAssertEqualObjects(@"C:\\", [root path]);
  XCTAssertEqual(LDFileNodeKindDirectory, [root kind]);
  XCTAssertEqual((unsigned long long)1610612836, [root aggregateSize]);
  XCTAssertEqual((unsigned long long)1610620928, [root aggregateAllocatedSize]);
  XCTAssertEqual((NSUInteger)3, [root fileCount]);
  XCTAssertEqual((NSUInteger)3, [root directoryCount]);
  XCTAssertEqual((NSUInteger)2, [[root children] count]);
  XCTAssertEqualObjects(@"pagefile.sys", [[[root children] objectAtIndex:0] displayName]);

  LDFileNode *users = [self childNamed:@"Users" of:root];
  LDFileNode *dan = [self childNamed:@"dan" of:users];
  XCTAssertEqualObjects(@"R", [LDFileAttributes attributeStringForNode:users]);
  XCTAssertEqual((NSUInteger)2, [[dan children] count]);
  LDFileNode *notes = [self childNamed:@"notes, final.txt" of:dan];
  LDFileNode *unicode = [self childNamed:@"\u00dcn\u00efcode.md" of:dan];
  XCTAssertEqual((unsigned long long)60, [notes size]);
  XCTAssertEqual((unsigned long long)4096, [notes allocatedSize]);
  XCTAssertEqualObjects(@"R", [LDFileAttributes attributeStringForNode:unicode]);
  XCTAssertEqual((NSTimeInterval)1704067199, [unicode modificationTime]);
  XCTAssertEqual((NSTimeInterval)1714552200, [root aggregateModificationTime]);
}

- (NSString *)fixture:(NSString *)name
{
  return [[[NSFileManager defaultManager] currentDirectoryPath]
           stringByAppendingPathComponent:[@"Tests/Fixtures/csv" stringByAppendingPathComponent:name]];
}

// A results file as WinDirStat 2.9.3 writes it (CsvLoader.cpp
// SaveResultsCsv): rows preceded by CRLF, hex type and index, no Owner.
- (void)testReadsWinDirStat293Export
{
  NSError *error = nil;
  LDFileNode *root = [LDCSV readTreeFromPath:[self fixture:@"windirstat-2.9.3.csv"] error:&error];
  XCTAssertNotNil(root, @"%@", error);
  XCTAssertEqualObjects(@"D:\\Projects", [root path]);
  XCTAssertEqual((unsigned long long)7340, [root aggregateSize]);
  XCTAssertEqual((unsigned long long)12288, [root aggregateAllocatedSize]);
  XCTAssertEqual((NSUInteger)3, [root fileCount]);
  // The root folder counts itself.
  XCTAssertEqual((NSUInteger)3, [root directoryCount]);
  // Sorted by physical size, as WinDirStat does after loading.
  XCTAssertEqualObjects(@"app", [[[root children] objectAtIndex:0] displayName]);
  LDFileNode *app = [self childNamed:@"app" of:root];
  LDFileNode *icon = [self childNamed:@"icon.ico" of:[self childNamed:@"res" of:app]];
  XCTAssertEqual((unsigned long long)3000, [icon size]);
  XCTAssertEqual((unsigned long long)4096, [icon allocatedSize]);
  // Only the read-only and hidden letters have a counterpart on Linux.
  XCTAssertEqualObjects(@"R", [LDFileAttributes attributeStringForNode:[self childNamed:@"README.md" of:root]]);
  XCTAssertEqual((NSTimeInterval)1790777100, [app aggregateModificationTime]);
}

// Upstream after 2.9.3 (51f123b2, 589e83c5) appends ScanOutcome and
// ScanError and leaves Physical Size blank when it is unknown (a cloud file
// not stored locally). Columns are matched by name, so the extra ones are
// ignored; a blank size reads as 0 bytes on disk.
- (void)testReadsScanOutcomeColumnsAndBlankPhysicalSize
{
  NSError *error = nil;
  LDFileNode *root = [LDCSV readTreeFromPath:[self fixture:@"windirstat-master-scan-outcome.csv"] error:&error];
  XCTAssertNotNil(root, @"%@", error);
  LDFileNode *cloud = [self childNamed:@"cloud" of:root];
  LDFileNode *video = [self childNamed:@"video.mp4" of:cloud];
  XCTAssertEqual((unsigned long long)1048576, [video size]);
  XCTAssertEqual((unsigned long long)0, [video allocatedSize]);
  XCTAssertEqual((unsigned long long)1048916, [root aggregateSize]);
  XCTAssertEqual((unsigned long long)4096, [root aggregateAllocatedSize]);
  // The folder that could not be read is there, empty; its quoted error
  // (with a comma) does not shift the columns.
  LDFileNode *locked = [self childNamed:@"locked" of:root];
  XCTAssertNotNil(locked);
  XCTAssertEqual((NSUInteger)0, [[locked children] count]);
  XCTAssertEqual((NSUInteger)2, [root fileCount]);
  XCTAssertEqual((NSUInteger)3, [root directoryCount]);
}

// The duplicates export has WinDirStat 2.9's columns, Sampled hash last.
- (void)testDuplicatesHeaderMatchesWinDirStat293
{
  NSString *path = [self pathFor:@"dupes.csv"];
  NSError *error = nil;
  XCTAssertTrue([LDCSV writeDuplicateGroups:@[] toPath:path error:&error], @"%@", error);
  NSString *ours = [[[self contentsOf:path] componentsSeparatedByString:@"\r\n"] firstObject];
  NSString *theirs = [[[self contentsOf:[self fixture:@"windirstat-2.9.3-duplicates.csv"]]
                       componentsSeparatedByString:@"\r\n"] firstObject];
  XCTAssertEqualObjects(theirs, ours);
  XCTAssertTrue([ours hasSuffix:@",\"Sampled hash\""]);
}

@end
