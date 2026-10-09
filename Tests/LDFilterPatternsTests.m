#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFilterPatterns.h"

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

@end
