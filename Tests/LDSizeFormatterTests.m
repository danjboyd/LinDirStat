#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDSizeFormatter.h"

@interface LDSizeFormatterTests : XCTestCase
@end

@implementation LDSizeFormatterTests

- (void)testFormatsByteValuesForDisplay
{
  XCTAssertEqualObjects(@"40 B", [LDSizeFormatter stringForBytes:40]);
  XCTAssertEqualObjects(@"1.5 KB", [LDSizeFormatter stringForBytes:1536]);
  XCTAssertEqualObjects(@"10 KB", [LDSizeFormatter stringForBytes:10240]);
}

@end
