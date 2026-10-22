#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFilterPatterns.h"
#import "LDScanOptions.h"

@interface LDFilterPatternsTests : XCTestCase
@end

@implementation LDFilterPatternsTests

- (void)testPatternsAreNonBlankLinesWithCarriageReturnsTrimmed
{
  NSArray *patterns = [LDFilterPatterns patternsFromString:@"*.o\r\n\n/tmp/*\n\r\n"];
  XCTAssertEqualObjects((@[@"*.o", @"/tmp/*"]), patterns);
  XCTAssertEqual((NSUInteger)0, [[LDFilterPatterns patternsFromString:nil] count]);
  XCTAssertEqual((NSUInteger)0, [[LDFilterPatterns patternsFromString:@""] count]);
}

- (void)testRegularExpressionValidation
{
  XCTAssertTrue([LDFilterPatterns isValidRegularExpression:@".*\\.exe"]);
  XCTAssertTrue([LDFilterPatterns isValidRegularExpression:@"^/home/[^/]+/\\.cache$"]);
  XCTAssertFalse([LDFilterPatterns isValidRegularExpression:@"foo("]);
  XCTAssertFalse([LDFilterPatterns isValidRegularExpression:@"[a-"]);
}

- (void)testGlobPatternsAreAlwaysValid
{
  XCTAssertNil([LDFilterPatterns firstInvalidPatternInString:@"foo(\n[a-" usesRegex:NO]);
}

- (void)testFirstInvalidRegexIsReported
{
  XCTAssertNil([LDFilterPatterns firstInvalidPatternInString:@".*\\.o\n\nnode_modules" usesRegex:YES]);
  XCTAssertEqualObjects(@"bad(", [LDFilterPatterns firstInvalidPatternInString:@".*\\.o\r\nbad(\nworse[" usesRegex:YES]);
}

- (void)testLiteralPatternsEscapeRegexOnly
{
  XCTAssertEqualObjects(@"/home/a (1)/x.y", [LDFilterPatterns literalPattern:@"/home/a (1)/x.y" usesRegex:NO]);
  XCTAssertEqualObjects(@"/home/a \\(1\\)/x\\.y", [LDFilterPatterns literalPattern:@"/home/a (1)/x.y" usesRegex:YES]);
  XCTAssertEqualObjects(@"c\\+\\+\\[\\]\\{\\}\\^\\$\\|\\*\\?\\\\", [LDFilterPatterns literalPattern:@"c++[]{}^$|*?\\" usesRegex:YES]);
  XCTAssertTrue([LDFilterPatterns isValidRegularExpression:[LDFilterPatterns literalPattern:@"a(b[c" usesRegex:YES]]);
}

- (void)testLiteralRegexMatchesOnlyTheText
{
  NSString *pattern = [LDFilterPatterns literalPattern:@"/data/a.b (1)" usesRegex:YES];
  LDPathFilter *filter = [[LDPathFilter alloc] initWithPatterns:@[pattern] usesRegex:YES];
  XCTAssertTrue([filter matchesBytes:"/data/a.b (1)"]);
  XCTAssertFalse([filter matchesBytes:"/data/aXb (1)"]);
  XCTAssertFalse([filter matchesBytes:"/data/a.b (1)/below"]);
}

- (void)testExtensionPatternsSelectThatExtension
{
  XCTAssertNil([LDFilterPatterns patternForExtension:@"<none>" usesRegex:NO]);
  XCTAssertNil([LDFilterPatterns patternForExtension:@"" usesRegex:YES]);
  XCTAssertEqualObjects(@"?*.txt", [LDFilterPatterns patternForExtension:@"txt" usesRegex:NO]);
  XCTAssertEqualObjects(@".+\\.c\\+\\+", [LDFilterPatterns patternForExtension:@"c++" usesRegex:YES]);
  for (NSNumber *regex in @[@NO, @YES]) {
    NSString *pattern = [LDFilterPatterns patternForExtension:@"txt" usesRegex:[regex boolValue]];
    LDPathFilter *filter = [[LDPathFilter alloc] initWithPatterns:@[pattern] usesRegex:[regex boolValue]];
    XCTAssertTrue([filter matchesBytes:"notes.txt"]);
    XCTAssertTrue([filter matchesBytes:"a.b.TXT"]);
    // A hidden file named ".txt" has no extension.
    XCTAssertFalse([filter matchesBytes:".txt"]);
    XCTAssertFalse([filter matchesBytes:"notes.txt.gz"]);
  }
}

- (void)testAddingPatternsAppendsLinesOnce
{
  XCTAssertEqualObjects(@"*.o", [LDFilterPatterns string:@"" byAddingPattern:@"*.o"]);
  XCTAssertEqualObjects(@"*.o", [LDFilterPatterns string:nil byAddingPattern:@"*.o"]);
  XCTAssertEqualObjects(@"*.o\n/tmp", [LDFilterPatterns string:@"*.o" byAddingPattern:@"/tmp"]);
  XCTAssertEqualObjects(@"*.o\n/tmp", [LDFilterPatterns string:@"*.o\n" byAddingPattern:@"/tmp"]);
  XCTAssertEqualObjects(@"*.o\r\n/tmp", [LDFilterPatterns string:@"*.o\r\n/tmp" byAddingPattern:@"*.o"]);
}

@end
