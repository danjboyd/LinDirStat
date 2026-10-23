#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDPreferences.h"
#import "LDScanOptions.h"

#include <locale.h>
#include <string.h>

@interface LDScanOptionsTests : XCTestCase
@end

@implementation LDScanOptionsTests

- (LDPathFilter *)globs:(NSArray *)patterns
{
  return [[LDPathFilter alloc] initWithPatterns:patterns usesRegex:NO];
}

- (void)testDefaultsMatchWinDirStat
{
  LDScanOptions *options = [[LDScanOptions alloc] init];
  XCTAssertEqual((NSUInteger)0, [[options excludedFolderPatterns] count]);
  XCTAssertEqual((NSUInteger)0, [[options excludedFilePatterns] count]);
  XCTAssertFalse([options usesRegex]);
  XCTAssertEqual((unsigned long long)0, [options minimumFileSize]);
  XCTAssertFalse([options excludeHidden]);
  XCTAssertTrue([options excludeSymbolicLinks]);
  XCTAssertTrue([options excludeMountPoints]);
  XCTAssertTrue([options processHardLinks]);
  XCTAssertEqual((NSUInteger)4, [options threadCount]);
  XCTAssertTrue([options validateWithError:NULL]);
}

- (void)testPatternsAreSplitPerLineAndTrimmed
{
  NSArray *patterns = [LDScanOptions patternsFromString:@"/tmp/cache/\r\n\n*.log\r\n  \n/var//\r"];
  NSArray *expected = [NSArray arrayWithObjects:@"/tmp/cache", @"*.log", @"/var", nil];
  XCTAssertEqualObjects(expected, patterns);
  XCTAssertEqual((NSUInteger)0, [[LDScanOptions patternsFromString:nil] count]);
  XCTAssertEqual((NSUInteger)0, [[LDScanOptions patternsFromString:@"\r\n/\n"] count]);
}

- (void)testOptionsFromPreferences
{
  LDPreferences *preferences = [[LDPreferences alloc] initWithUserDefaults:[NSUserDefaults standardUserDefaults]];
  [preferences resetAll];
  [preferences setExcludedFolderPatterns:@"/proc\n/sys/"];
  [preferences setExcludedFilePatterns:@"*.o"];
  [preferences setFilterUsesRegex:YES];
  [preferences setMinimumFileSize:2];
  [preferences setMinimumFileSizeUnit:LDSizeUnitKiB];
  [preferences setIncludedFolderPatterns:@"/home/*\n"];
  [preferences setIncludedFilePatterns:@"*.c\n*.h"];
  [preferences setFilterExcludesLargerFiles:YES];
  [preferences setFilterMaximumAgeDays:30];
  [preferences setFilterExcludesNewerFiles:YES];
  [preferences setExcludeHiddenEntries:YES];
  [preferences setExcludeSymbolicLinks:NO];
  [preferences setExcludeMountPoints:NO];
  [preferences setScanningThreads:7];
  XCTAssertTrue([preferences processHardLinks]);
  [preferences setProcessHardLinks:NO];

  LDScanOptions *options = [LDScanOptions optionsFromPreferences:preferences];
  [preferences resetAll];

  XCTAssertEqualObjects(([NSArray arrayWithObjects:@"/proc", @"/sys", nil]), [options excludedFolderPatterns]);
  XCTAssertEqualObjects([NSArray arrayWithObject:@"*.o"], [options excludedFilePatterns]);
  XCTAssertTrue([options usesRegex]);
  XCTAssertEqual((unsigned long long)2048, [options minimumFileSize]);
  XCTAssertEqualObjects(@[@"/home/*"], [options includedFolderPatterns]);
  XCTAssertEqualObjects((@[@"*.c", @"*.h"]), [options includedFilePatterns]);
  XCTAssertTrue([options excludesLargerFiles]);
  XCTAssertEqual((NSUInteger)30, [options maximumAgeDays]);
  XCTAssertTrue([options excludesNewerFiles]);
  XCTAssertEqualObjects(@[@"/home/*"], [[options copy] includedFolderPatterns]);
  XCTAssertEqual((NSUInteger)30, [[options copy] maximumAgeDays]);
  XCTAssertTrue([options excludeHidden]);
  XCTAssertFalse([options excludeSymbolicLinks]);
  XCTAssertFalse([options excludeMountPoints]);
  XCTAssertFalse([options processHardLinks]);
  XCTAssertFalse([[options copy] processHardLinks]);
  XCTAssertEqual((NSUInteger)7, [options threadCount]);
}

- (void)testCopyIsIndependent
{
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludedFilePatterns:[NSArray arrayWithObject:@"*.tmp"]];
  LDScanOptions *copy = [options copy];
  [options setExcludeHidden:YES];
  [options setExcludedFilePatterns:nil];
  XCTAssertFalse([copy excludeHidden]);
  XCTAssertEqualObjects([NSArray arrayWithObject:@"*.tmp"], [copy excludedFilePatterns]);
  XCTAssertEqual((NSUInteger)0, [[options excludedFilePatterns] count]);
}

- (void)testGlobIsAnchoredCaseInsensitiveAndStaysInOneComponent
{
  LDPathFilter *filter = [self globs:[NSArray arrayWithObject:@"*.log"]];
  XCTAssertTrue([filter matchesBytes:"error.log"]);
  XCTAssertTrue([filter matchesBytes:"ERROR.LOG"]);
  XCTAssertTrue([filter matchesBytes:".log"]);
  XCTAssertFalse([filter matchesBytes:"error.log.1"]);
  XCTAssertFalse([filter matchesBytes:"logs/error.log"]);

  LDPathFilter *folders = [self globs:[NSArray arrayWithObject:@"/home/*/Cache"]];
  XCTAssertTrue([folders matchesBytes:"/home/dan/cache"]);
  XCTAssertFalse([folders matchesBytes:"/home/dan/x/cache"]);
  XCTAssertFalse([folders matchesBytes:"/home/dan/cache/inner"]);
}

- (void)testGlobQuestionMarkIsOneCharacter
{
  LDPathFilter *filter = [self globs:[NSArray arrayWithObject:@"caf?.txt"]];
  XCTAssertTrue([filter matchesBytes:"cafe.txt"]);
  XCTAssertTrue([filter matchesBytes:"caf\xc3\xa9.txt"]);   // UTF-8 "é", two bytes
  XCTAssertTrue([filter matchesBytes:"caf\xe9.txt"]);       // Latin-1 byte
  XCTAssertFalse([filter matchesBytes:"caf.txt"]);
  XCTAssertFalse([filter matchesBytes:"cafee.txt"]);
  XCTAssertFalse([filter matchesBytes:"caf/.txt"]);
}

- (void)testGlobTreatsRegexCharactersLiterally
{
  NSString *pattern = @"a+b(1).[x]{y}|z^$\\";
  LDPathFilter *filter = [self globs:[NSArray arrayWithObject:pattern]];
  XCTAssertEqual((NSUInteger)1, [filter count]);
  XCTAssertTrue([filter matchesBytes:[pattern UTF8String]]);
  XCTAssertFalse([filter matchesBytes:"aab(1)x[x]{y}|z^$\\"]);
}

- (void)testRegexPatternsAreAnchoredAndCaseInsensitive
{
  LDPathFilter *filter = [[LDPathFilter alloc] initWithPatterns:[NSArray arrayWithObjects:@".*\\.exe", @"foo|bar", nil]
                                                      usesRegex:YES];
  XCTAssertTrue([filter matchesBytes:"SETUP.EXE"]);
  XCTAssertFalse([filter matchesBytes:"setup.exe.bak"]);
  XCTAssertTrue([filter matchesBytes:"bar"]);
  XCTAssertFalse([filter matchesBytes:"foobar"]);
}

- (void)testNonUTF8NamesMatchUnderAUTF8Locale
{
  // glibc does not match invalid UTF-8 under a UTF-8 locale; the filter
  // compiles in the C locale so raw names still match.
  char *saved = strdup(setlocale(LC_ALL, NULL));
  if (setlocale(LC_ALL, "C.UTF-8") == NULL) {
    setlocale(LC_ALL, "en_US.UTF-8");
  }
  LDPathFilter *filter = [self globs:[NSArray arrayWithObjects:@"*.TMP", @"/data/caf*", nil]];
  BOOL fileMatches = [filter matchesBytes:"menu\xe9.tmp"];
  BOOL folderMatches = [filter matchesBytes:"/data/caf\xe9"];
  setlocale(LC_ALL, saved);
  free(saved);

  XCTAssertTrue(fileMatches);
  XCTAssertTrue(folderMatches);
}

- (void)testInvalidRegexIsReported
{
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setUsesRegex:YES];
  [options setExcludedFolderPatterns:[NSArray arrayWithObject:@"/ok/.*"]];
  [options setExcludedFilePatterns:[NSArray arrayWithObjects:@".*\\.log", @"(unclosed", @"[z-a]", nil]];

  NSError *error = nil;
  XCTAssertFalse([options validateWithError:&error]);
  XCTAssertEqualObjects(@"Invalid filter: (unclosed", [error localizedDescription]);
  XCTAssertEqualObjects(LDScanOptionsErrorDomain, [error domain]);

  LDPathFilter *filter = [[LDPathFilter alloc] initWithPatterns:[options excludedFilePatterns] usesRegex:YES];
  XCTAssertEqual((NSUInteger)1, [filter count]);
  XCTAssertEqualObjects(@"(unclosed", [filter invalidPattern]);
  XCTAssertTrue([filter matchesBytes:"x.log"]);
}

- (void)testGlobsAreAlwaysValid
{
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludedFilePatterns:[NSArray arrayWithObjects:@"(unclosed", @"[z-a]", @"a{2", nil]];
  XCTAssertTrue([options validateWithError:NULL]);
}

#pragma mark - WinDirStat 2.6 filtering

- (void)testFolderPatternsMatchTheFolderAndBelow
{
  LDPathFilter *globs = [[LDPathFilter alloc] initWithPatterns:@[@"/data/cache"] usesRegex:NO descendants:YES];
  XCTAssertTrue([globs matchesBytes:"/data/cache"]);
  XCTAssertTrue([globs matchesBytes:"/data/CACHE/x/y.bin"]);
  XCTAssertTrue([globs matchesBytes:"/data/cache/line\nbreak"]);
  XCTAssertFalse([globs matchesBytes:"/data/cached"]);
  XCTAssertFalse([globs matchesBytes:"/data"]);
  // A regex's own "$" no longer stops it at the folder.
  LDPathFilter *regex = [[LDPathFilter alloc] initWithPatterns:@[@"/data/c.che$"] usesRegex:YES descendants:YES];
  XCTAssertTrue([regex matchesBytes:"/data/cache/x"]);
  LDPathFilter *escaped = [[LDPathFilter alloc] initWithPatterns:@[@"/data/cost\\$"] usesRegex:YES descendants:YES];
  XCTAssertTrue([escaped matchesBytes:"/data/cost$"]);
  XCTAssertTrue([escaped matchesBytes:"/data/cost$/x"]);
}

- (void)testIncludeAnchorsAreTheFixedLeadingFolder
{
  XCTAssertEqualObjects(@"/data", [LDScanFilter anchorForIncludePattern:@"/data/proj*" usesRegex:NO]);
  XCTAssertEqualObjects(@"/data/proj", [LDScanFilter anchorForIncludePattern:@"/data/proj" usesRegex:NO]);
  XCTAssertEqualObjects(@"", [LDScanFilter anchorForIncludePattern:@"*/src" usesRegex:NO]);
  XCTAssertEqualObjects(@"/", [LDScanFilter anchorForIncludePattern:@"/*" usesRegex:NO]);
  XCTAssertEqualObjects(@"/data/a.b", [LDScanFilter anchorForIncludePattern:@"^/data/a\\.b$" usesRegex:YES]);
  XCTAssertEqualObjects(@"/data", [LDScanFilter anchorForIncludePattern:@"/data/(x|y)" usesRegex:YES]);
}

- (LDScanFilter *)filterWith:(void (^)(LDScanOptions *options))configure
{
  LDScanOptions *options = [[LDScanOptions alloc] init];
  configure(options);
  return [[LDScanFilter alloc] initWithOptions:options now:1000000000];
}

- (void)testFolderIncludesEnterOnlyIncludedFoldersAndTheWayThere
{
  LDScanFilter *filter = [self filterWith:^(LDScanOptions *options) {
    [options setIncludedFolderPatterns:@[@"/data/proj*"]];
  }];
  XCTAssertTrue([filter isActive]);
  XCTAssertFalse([filter excludesFolderAtPath:"/"]);
  XCTAssertFalse([filter excludesFolderAtPath:"/data"]);
  XCTAssertFalse([filter excludesFolderAtPath:"/data/project1"]);
  XCTAssertFalse([filter excludesFolderAtPath:"/data/project1/src"]);
  XCTAssertTrue([filter excludesFolderAtPath:"/data/other"]);
  XCTAssertTrue([filter excludesFolderAtPath:"/home"]);
  XCTAssertTrue([filter excludesFolderAtPath:"/database"]);
  // Files: only below an included folder.
  XCTAssertFalse([filter includesFilesInFolderAtPath:"/data"]);
  XCTAssertTrue([filter includesFilesInFolderAtPath:"/data/project1"]);
  XCTAssertTrue([filter excludesFileNamed:"a.txt" atPath:"/data/a.txt" folderIncluded:NO size:1 mtime:0 checkSizeAndAge:YES]);
  XCTAssertFalse([filter excludesFileNamed:"a.txt" atPath:"/data/project1/a.txt" folderIncluded:YES size:1 mtime:0 checkSizeAndAge:YES]);
  // A pattern can match a file's own path.
  XCTAssertFalse([filter excludesFileNamed:"proj.txt" atPath:"/data/proj.txt" folderIncluded:NO size:1 mtime:0 checkSizeAndAge:YES]);
}

// Upstream prunes everything below an include's fixed leading folder; a
// glob here is followed component by component, so "/data/*/src" works.
- (void)testGlobIncludesAreFollowedComponentByComponent
{
  LDScanFilter *filter = [self filterWith:^(LDScanOptions *options) {
    [options setIncludedFolderPatterns:@[@"/data/*/src"]];
  }];
  XCTAssertEqualObjects((@[@"/", @"/data", @"/data/*"]), [LDScanFilter prefixesOfIncludeGlob:@"/data/*/src"]);
  XCTAssertFalse([filter excludesFolderAtPath:"/data"]);
  XCTAssertFalse([filter excludesFolderAtPath:"/data/app"]);
  XCTAssertFalse([filter excludesFolderAtPath:"/data/app/src"]);
  XCTAssertFalse([filter excludesFolderAtPath:"/data/app/src/deep"]);
  XCTAssertTrue([filter excludesFolderAtPath:"/data/app/docs"]);
  XCTAssertTrue([filter excludesFolderAtPath:"/home"]);
  XCTAssertTrue([filter excludesFileNamed:"a.c" atPath:"/data/app/a.c" folderIncluded:NO size:1 mtime:0 checkSizeAndAge:YES]);
  XCTAssertTrue([filter includesFilesInFolderAtPath:"/data/app/src"]);
}

// A regex include cannot be split into components: below its fixed leading
// folder nothing is pruned, and one starting with a wildcard prunes nothing.
- (void)testRegexIncludesPruneOnlyOffTheirLeadingFolder
{
  LDScanFilter *anchored = [self filterWith:^(LDScanOptions *options) {
    [options setUsesRegex:YES];
    [options setIncludedFolderPatterns:@[@"/data/.*/src"]];
  }];
  XCTAssertFalse([anchored excludesFolderAtPath:"/data/app/docs"]);
  XCTAssertTrue([anchored excludesFolderAtPath:"/home"]);
  XCTAssertTrue([anchored excludesFileNamed:"a.c" atPath:"/data/app/docs/a.c" folderIncluded:NO size:1 mtime:0 checkSizeAndAge:YES]);
  LDScanFilter *anywhere = [self filterWith:^(LDScanOptions *options) {
    [options setUsesRegex:YES];
    [options setIncludedFolderPatterns:@[@".*/src"]];
  }];
  XCTAssertFalse([anywhere excludesFolderAtPath:"/home"]);
  XCTAssertTrue([anywhere includesFilesInFolderAtPath:"/home/x/src"]);
}

- (void)testExclusionsWinOverInclusions
{
  LDScanFilter *filter = [self filterWith:^(LDScanOptions *options) {
    [options setIncludedFolderPatterns:@[@"/data"]];
    [options setExcludedFolderPatterns:@[@"/data/tmp"]];
    [options setIncludedFilePatterns:@[@"*.c"]];
    [options setExcludedFilePatterns:@[@"skip*"]];
  }];
  XCTAssertFalse([filter excludesFolderAtPath:"/data/src"]);
  XCTAssertTrue([filter excludesFolderAtPath:"/data/tmp/x"]);
  XCTAssertFalse([filter excludesFileNamed:"main.c" atPath:"/data/main.c" folderIncluded:YES size:1 mtime:0 checkSizeAndAge:YES]);
  XCTAssertTrue([filter excludesFileNamed:"main.h" atPath:"/data/main.h" folderIncluded:YES size:1 mtime:0 checkSizeAndAge:YES]);
  XCTAssertTrue([filter excludesFileNamed:"skip.c" atPath:"/data/skip.c" folderIncluded:YES size:1 mtime:0 checkSizeAndAge:YES]);
}

- (void)testSizeAndAgeComparisons
{
  time_t now = 1000000000;
  LDScanFilter *smaller = [self filterWith:^(LDScanOptions *options) {
    [options setMinimumFileSize:100];
  }];
  XCTAssertTrue([smaller excludesFileNamed:"a" atPath:"/a" folderIncluded:YES size:99 mtime:now checkSizeAndAge:YES]);
  XCTAssertFalse([smaller excludesFileNamed:"a" atPath:"/a" folderIncluded:YES size:100 mtime:now checkSizeAndAge:YES]);
  // Not stat'ed, not a regular file: no size or age to judge.
  XCTAssertFalse([smaller excludesFileNamed:"a" atPath:"/a" folderIncluded:YES size:0 mtime:0 checkSizeAndAge:NO]);
  LDScanFilter *larger = [self filterWith:^(LDScanOptions *options) {
    [options setMinimumFileSize:100];
    [options setExcludesLargerFiles:YES];
  }];
  XCTAssertTrue([larger excludesFileNamed:"a" atPath:"/a" folderIncluded:YES size:101 mtime:now checkSizeAndAge:YES]);
  XCTAssertFalse([larger excludesFileNamed:"a" atPath:"/a" folderIncluded:YES size:99 mtime:now checkSizeAndAge:YES]);

  LDScanFilter *older = [self filterWith:^(LDScanOptions *options) {
    [options setMaximumAgeDays:10];
  }];
  XCTAssertTrue([older excludesFileNamed:"a" atPath:"/a" folderIncluded:YES size:1 mtime:now - 11 * 86400 checkSizeAndAge:YES]);
  XCTAssertFalse([older excludesFileNamed:"a" atPath:"/a" folderIncluded:YES size:1 mtime:now - 9 * 86400 checkSizeAndAge:YES]);
  LDScanFilter *newer = [self filterWith:^(LDScanOptions *options) {
    [options setMaximumAgeDays:10];
    [options setExcludesNewerFiles:YES];
  }];
  XCTAssertTrue([newer excludesFileNamed:"a" atPath:"/a" folderIncluded:YES size:1 mtime:now - 9 * 86400 checkSizeAndAge:YES]);
  XCTAssertFalse([newer excludesFileNamed:"a" atPath:"/a" folderIncluded:YES size:1 mtime:now - 11 * 86400 checkSizeAndAge:YES]);
  XCTAssertFalse([[self filterWith:^(LDScanOptions *options) { (void)options; }] isActive]);
}

- (void)testInvalidIncludePatternIsReported
{
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setUsesRegex:YES];
  [options setIncludedFilePatterns:@[@"(bad"]];
  NSError *error = nil;
  XCTAssertFalse([options validateWithError:&error]);
  XCTAssertTrue([[error localizedDescription] hasSuffix:@"(bad"]);
}

@end
