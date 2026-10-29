#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDSizeFormatter.h"

@interface LDSizeFormatterTests : XCTestCase
@end

@implementation LDSizeFormatterTests

- (void)testFormatsByteValuesForDisplay
{
  XCTAssertEqualObjects(@"40 B", [LDSizeFormatter stringForBytes:40]);
  XCTAssertEqualObjects(@"1.50 KB", [LDSizeFormatter stringForBytes:1536]);
  XCTAssertEqualObjects(@"10.00 KB", [LDSizeFormatter stringForBytes:10240]);
}

// WinDirStat's FormatSizeSuffixes: two decimals always, rounded half away
// from zero, and each unit from half a step below it.
- (void)testFollowsWinDirStatUnitsAndRounding
{
  XCTAssertEqualObjects(@"1023 B", [LDSizeFormatter stringForBytes:1023]);
  XCTAssertEqualObjects(@"1.00 KB", [LDSizeFormatter stringForBytes:1024]);
  XCTAssertEqualObjects(@"1.01 KB", [LDSizeFormatter stringForBytes:1030]);
  XCTAssertEqualObjects(@"123.46 KB", [LDSizeFormatter stringForBytes:126422]);
  XCTAssertEqualObjects(@"1023.50 KB", [LDSizeFormatter stringForBytes:1048063]);
  XCTAssertEqualObjects(@"1.00 MB", [LDSizeFormatter stringForBytes:1048064]);
  XCTAssertEqualObjects(@"2.50 GB", [LDSizeFormatter stringForBytes:2684354560ULL]);
  XCTAssertEqualObjects(@"1.00 GB", [LDSizeFormatter stringForBytes:(1ULL << 30) - (1ULL << 19)]);
  XCTAssertEqualObjects(@"1023.50 MB", [LDSizeFormatter stringForBytes:(1ULL << 30) - (1ULL << 19) - 1]);
  XCTAssertEqualObjects(@"2048.00 TB", [LDSizeFormatter stringForBytes:1ULL << 51]);
}

@end
