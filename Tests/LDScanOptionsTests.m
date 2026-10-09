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

@end
