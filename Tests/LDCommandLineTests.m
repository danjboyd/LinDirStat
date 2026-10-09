#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDCommandLine.h"
#import "LDCSV.h"
#import "LDFileNode.h"
#import "LDScanOptions.h"

#include <unistd.h>

@interface LDCommandLineTests : XCTestCase
{
  NSString *_temporaryRoot;
}
@end

@implementation LDCommandLineTests

- (NSString *)temporaryRoot
{
  if (!_temporaryRoot) {
    NSString *name = [NSString stringWithFormat:@"lindirstat-cli-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
    _temporaryRoot = [[NSTemporaryDirectory() stringByAppendingPathComponent:name] stringByStandardizingPath];
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

- (NSString *)makeFolder:(NSString *)relativePath
{
  NSString *path = [[self temporaryRoot] stringByAppendingPathComponent:relativePath];
  [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
  return path;
}

- (void)write:(NSString *)text to:(NSString *)relativePath
{
  NSString *path = [[self temporaryRoot] stringByAppendingPathComponent:relativePath];
  [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  [[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:NO];
}

- (LDCommandLine *)parse:(NSArray *)arguments
{
  NSMutableArray *all = [NSMutableArray arrayWithObject:@"LinDirStat"];
  [all addObjectsFromArray:arguments];
  return [LDCommandLine commandLineWithArguments:all currentDirectory:[self temporaryRoot]];
}

#pragma mark - Parsing

- (void)testNoArgumentsMeansAnInteractiveScanOfNothing
{
  LDCommandLine *commandLine = [self parse:@[]];
  XCTAssertEqual((NSUInteger)0, [[commandLine scanPaths] count]);
  XCTAssertFalse([commandLine isHeadless]);
  XCTAssertNil([commandLine saveToCSVPath]);
  XCTAssertNil([commandLine loadFromCSVPath]);
  XCTAssertNil([commandLine errorMessage]);
}

- (void)testFoldersAreMadeAbsoluteAndKeptInOrder
{
  NSString *b = [self makeFolder:@"b"];
  NSString *a = [self makeFolder:@"a"];
  LDCommandLine *commandLine = [self parse:@[@"b", [a stringByAppendingString:@"/"], @"./a/../b"]];
  NSArray *expected = @[b, a, b];
  XCTAssertEqualObjects(expected, [commandLine scanPaths]);
}

- (void)testMissingFoldersAndFilesAreIgnored
{
  NSString *folder = [self makeFolder:@"folder"];
  [self write:@"x" to:@"file.txt"];
  LDCommandLine *commandLine = [self parse:@[@"missing", @"file.txt", @"folder"]];
  XCTAssertEqualObjects(@[folder], [commandLine scanPaths]);
  NSArray *ignored = @[@"missing", @"file.txt"];
  XCTAssertEqualObjects(ignored, [commandLine ignoredPaths]);
}

- (void)testSaveFlagsInEverySpelling
{
  NSString *folder = [self makeFolder:@"folder"];
  NSArray *spellings = @[@"--savetocsv", @"-savetocsv", @"/savetocsv", @"/SaveToCSV", @"--SAVETOCSV"];
  for (NSString *spelling in spellings) {
    LDCommandLine *commandLine = [self parse:@[spelling, @"out.csv", @"folder"]];
    XCTAssertTrue([commandLine isHeadless], @"%@", spelling);
    XCTAssertEqualObjects([[self temporaryRoot] stringByAppendingPathComponent:@"out.csv"], [commandLine saveToCSVPath], @"%@", spelling);
    XCTAssertEqualObjects(@[folder], [commandLine scanPaths], @"%@", spelling);
  }
}

- (void)testDuplicatesAndLoadFlags
{
  LDCommandLine *commandLine = [self parse:@[@"/SaveDupesToCsv", @"/abs/dupes.csv"]];
  XCTAssertTrue([commandLine isHeadless]);
  XCTAssertEqualObjects(@"/abs/dupes.csv", [commandLine saveDuplicatesToCSVPath]);
  XCTAssertNil([commandLine saveToCSVPath]);

  commandLine = [self parse:@[@"--loadfromcsv", @"saved.csv"]];
  XCTAssertFalse([commandLine isHeadless]);
  XCTAssertEqualObjects([[self temporaryRoot] stringByAppendingPathComponent:@"saved.csv"], [commandLine loadFromCSVPath]);
}

- (void)testFlagWithoutFileNameIsAnError
{
  LDCommandLine *commandLine = [self parse:@[@"--savetocsv"]];
  XCTAssertTrue([commandLine isHeadless]);
  XCTAssertNil([commandLine saveToCSVPath]);
  XCTAssertEqualObjects(@"--savetocsv needs a file name", [commandLine errorMessage]);
}

- (void)testDefaultsArgumentsAreSkipped
{
  NSString *folder = [self makeFolder:@"folder"];
  LDCommandLine *commandLine = [self parse:@[@"-NSDocumentRevisionsDebugMode", @"YES", @"folder",
                                             @"-GSTheme", @"Adwaita", @"--GNU-Debug=dflt"]];
  XCTAssertEqualObjects(@[folder], [commandLine scanPaths]);
  XCTAssertEqual((NSUInteger)0, [[commandLine ignoredPaths] count]);
}

#pragma mark - Headless export

- (int)run:(NSArray *)arguments messages:(NSMutableArray *)messages
{
  return [LDCommandLineExport runCommandLine:[self parse:arguments]
                                 scanOptions:[[LDScanOptions alloc] init]
                                includeOwner:NO
                                    messages:messages];
}

- (NSString *)contentsOf:(NSString *)relativePath
{
  return [NSString stringWithContentsOfFile:[[self temporaryRoot] stringByAppendingPathComponent:relativePath]
                                   encoding:NSUTF8StringEncoding
                                      error:NULL];
}

- (void)testSaveToCSVWritesTheScannedTree
{
  [self write:@"hello" to:@"tree/a.txt"];
  [self write:@"world!" to:@"tree/sub/b.txt"];
  NSMutableArray *messages = [NSMutableArray array];

  int status = [self run:@[@"--savetocsv", @"out.csv", @"tree"] messages:messages];

  XCTAssertEqual(0, status);
  XCTAssertEqual((NSUInteger)0, [messages count]);
  NSString *csv = [self contentsOf:@"out.csv"];
  XCTAssertTrue([csv hasPrefix:@"\"Name\",\"Files\",\"Folders\",\"Logical Size\""]);
  NSString *tree = [[self temporaryRoot] stringByAppendingPathComponent:@"tree"];
  NSString *rootRow = [NSString stringWithFormat:@"\r\n\"%@\",2,1,11,", tree];
  NSString *fileRow = [NSString stringWithFormat:@"\r\n\"%@/sub/b.txt\",0,0,6,", tree];
  XCTAssertTrue([csv rangeOfString:rootRow].location != NSNotFound, @"%@", csv);
  XCTAssertTrue([csv rangeOfString:fileRow].location != NSNotFound, @"%@", csv);
  XCTAssertNil([self contentsOf:@"dupes.csv"]);
}

- (void)testSaveDuplicatesToCSVFindsDuplicates
{
  [self write:@"same" to:@"tree/one"];
  [self write:@"same" to:@"tree/sub/two"];
  [self write:@"diff" to:@"tree/three"];
  NSMutableArray *messages = [NSMutableArray array];

  int status = [self run:@[@"/savedupestocsv", @"dupes.csv", @"tree"] messages:messages];

  XCTAssertEqual(0, status);
  NSArray *lines = [[self contentsOf:@"dupes.csv"] componentsSeparatedByString:@"\r\n"];
  XCTAssertEqualObjects(@"\"Hash Prefix\",\"Name\",\"Logical Size\",\"Physical Size\",\"Last Change\",\"Attributes\"",
                        [lines objectAtIndex:0]);
  NSString *tree = [[self temporaryRoot] stringByAppendingPathComponent:@"tree"];
  XCTAssertTrue([[lines objectAtIndex:1] rangeOfString:[tree stringByAppendingString:@"/one\",4,"]].location != NSNotFound);
  XCTAssertTrue([[lines objectAtIndex:2] rangeOfString:[tree stringByAppendingString:@"/sub/two\",4,"]].location != NSNotFound);
  XCTAssertEqualObjects(@"", [lines lastObject]);
  XCTAssertEqual((NSUInteger)4, [lines count]);
}

- (void)testSeveralFoldersAreSavedUnderThisComputer
{
  [self write:@"1" to:@"one/a"];
  [self write:@"22" to:@"two/b"];

  int status = [self run:@[@"--savetocsv", @"out.csv", @"one", @"two"] messages:[NSMutableArray array]];

  XCTAssertEqual(0, status);
  NSArray *lines = [[self contentsOf:@"out.csv"] componentsSeparatedByString:@"\r\n"];
  XCTAssertEqual((NSUInteger)6, [lines count]);
  // WinDirStat's MyComputer row, then each root as a drive with its full path.
  XCTAssertTrue([[lines objectAtIndex:1] hasPrefix:@"\"This Computer\",2,2,3,"], @"%@", [lines objectAtIndex:1]);
  XCTAssertTrue([[lines objectAtIndex:1] hasSuffix:@",0x30000001,0x0000000000000000"], @"%@", [lines objectAtIndex:1]);
  NSString *one = [NSString stringWithFormat:@"\"%@\",1,0,1,", [[self temporaryRoot] stringByAppendingPathComponent:@"one"]];
  XCTAssertTrue([[lines objectAtIndex:2] hasPrefix:one], @"%@", [lines objectAtIndex:2]);
  // A drive row (0x2, done); Index is the folder's inode.
  XCTAssertTrue([[lines objectAtIndex:2] rangeOfString:@",0x20000002,0x"].location != NSNotFound, @"%@", [lines objectAtIndex:2]);

  // Loading it back gives a "This Computer" tree with full-path roots.
  NSError *error = nil;
  LDFileNode *root = [LDCSV readTreeFromPath:[[self temporaryRoot] stringByAppendingPathComponent:@"out.csv"] error:&error];
  XCTAssertNotNil(root, @"%@", error);
  XCTAssertTrue([root isComputer]);
  XCTAssertEqual((NSUInteger)2, [[root children] count]);
  XCTAssertEqual((unsigned long long)3, [root aggregateSize]);
  NSMutableArray *paths = [NSMutableArray array];
  for (LDFileNode *child in [root children]) {
    for (LDFileNode *file in [child children]) {
      [paths addObject:[file path]];
    }
  }
  [paths sortUsingSelector:@selector(compare:)];
  NSArray *expected = @[[[self temporaryRoot] stringByAppendingPathComponent:@"one/a"],
                        [[self temporaryRoot] stringByAppendingPathComponent:@"two/b"]];
  XCTAssertEqualObjects(expected, paths);
}

- (void)testFailuresExitWithOne
{
  [self makeFolder:@"tree"];
  NSMutableArray *messages = [NSMutableArray array];
  int status = [self run:@[@"--savetocsv", @"no-such-dir/out.csv", @"tree"] messages:messages];
  XCTAssertEqual(1, status);
  XCTAssertEqual((NSUInteger)1, [messages count]);

  [messages removeAllObjects];
  status = [self run:@[@"--savetocsv", @"out.csv", @"missing"] messages:messages];
  XCTAssertEqual(1, status);
  NSArray *expected = @[@"Not a folder, ignored: missing", @"No folder to scan"];
  XCTAssertEqualObjects(expected, messages);

  [messages removeAllObjects];
  status = [self run:@[@"tree", @"--savedupestocsv"] messages:messages];
  XCTAssertEqual(1, status);
  XCTAssertEqualObjects(@[@"--savedupestocsv needs a file name"], messages);
}

- (void)testInvalidFilterFailsBeforeScanning
{
  [self makeFolder:@"tree"];
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setUsesRegex:YES];
  [options setExcludedFilePatterns:@[@"("]];
  NSMutableArray *messages = [NSMutableArray array];
  int status = [LDCommandLineExport runCommandLine:[self parse:@[@"--savetocsv", @"out.csv", @"tree"]]
                                       scanOptions:options
                                      includeOwner:NO
                                          messages:messages];
  XCTAssertEqual(1, status);
  XCTAssertEqualObjects(@[@"Invalid filter: ("], messages);
  XCTAssertNil([self contentsOf:@"out.csv"]);
}

@end
