#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDSizeFormatter.h"

@interface LDSizeFormatterTests : XCTestCase
@end

@implementation LDSizeFormatterTests

- (void)setUp
{
  [LDSizeFormatter setLocaleForTesting:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
}

- (void)tearDown
{
  [LDSizeFormatter setLocaleForTesting:nil];
  [LDSizeFormatter setHumanReadable:YES];
}

- (void)testFormatsByteValuesForDisplay
{
  XCTAssertEqualObjects(@"40 bytes", [LDSizeFormatter stringForBytes:40]);
  XCTAssertEqualObjects(@"1.50 KiB", [LDSizeFormatter stringForBytes:1536]);
  XCTAssertEqualObjects(@"10.00 KiB", [LDSizeFormatter stringForBytes:10240]);
}

// WinDirStat's FormatSizeSuffixes: two decimals always, rounded half away
// from zero, and each unit from half a step below it.
- (void)testFollowsWinDirStatUnitsAndRounding
{
  XCTAssertEqualObjects(@"1023 bytes", [LDSizeFormatter stringForBytes:1023]);
  XCTAssertEqualObjects(@"1.00 KiB", [LDSizeFormatter stringForBytes:1024]);
  XCTAssertEqualObjects(@"1.01 KiB", [LDSizeFormatter stringForBytes:1030]);
  XCTAssertEqualObjects(@"123.46 KiB", [LDSizeFormatter stringForBytes:126422]);
  XCTAssertEqualObjects(@"1023.50 KiB", [LDSizeFormatter stringForBytes:1048063]);
  XCTAssertEqualObjects(@"1.00 MiB", [LDSizeFormatter stringForBytes:1048064]);
  XCTAssertEqualObjects(@"2.50 GiB", [LDSizeFormatter stringForBytes:2684354560ULL]);
  XCTAssertEqualObjects(@"1.00 GiB", [LDSizeFormatter stringForBytes:(1ULL << 30) - (1ULL << 19)]);
  XCTAssertEqualObjects(@"1023.50 MiB", [LDSizeFormatter stringForBytes:(1ULL << 30) - (1ULL << 19) - 1]);
  XCTAssertEqualObjects(@"2048.00 TiB", [LDSizeFormatter stringForBytes:1ULL << 51]);
}

// WinDirStat's GetLocaleDecimalSeparator: the user's locale decides.
- (void)testUsesTheLocalesDecimalSeparator
{
  [LDSizeFormatter setLocaleForTesting:[NSLocale localeWithLocaleIdentifier:@"de_DE"]];
  XCTAssertEqualObjects(@"1,50 KiB", [LDSizeFormatter stringForBytes:1536]);
  XCTAssertEqualObjects(@"2,50 GiB", [LDSizeFormatter stringForBytes:2684354560ULL]);
  XCTAssertEqualObjects(@"40 bytes", [LDSizeFormatter stringForBytes:40]);
}

// Percentages are WinDirStat's FormatDouble plus "%" (Item.Extended.cpp,
// ExtensionListControl.cpp, SelectDrivesDlg.cpp).
- (void)testFormatsPercentagesAsWinDirStatDoes
{
  XCTAssertEqualObjects(@"89.60%", [LDSizeFormatter stringForPercent:89.6]);
  XCTAssertEqualObjects(@"100.00%", [LDSizeFormatter stringForPercent:100.0]);
  XCTAssertEqualObjects(@"0.00%", [LDSizeFormatter stringForPercent:0.0]);
  XCTAssertEqualObjects(@"33.33%", [LDSizeFormatter stringForPercent:100.0 / 3.0]);
  XCTAssertEqualObjects(@"0.01%", [LDSizeFormatter stringForPercent:0.005]);
  [LDSizeFormatter setLocaleForTesting:[NSLocale localeWithLocaleIdentifier:@"de_DE"]];
  XCTAssertEqualObjects(@"89,60%", [LDSizeFormatter stringForPercent:89.6]);
}

// With the human-readable format off, the count is digit-grouped and the
// same from every thread, including several asking for the first time at once.
- (void)testFormatsExactByteCountsFromConcurrentThreads
{
  [LDSizeFormatter setHumanReadable:NO];
  NSUInteger count = 64;
  NSMutableArray *results = [NSMutableArray arrayWithCapacity:count];
  NSLock *lock = [[NSLock alloc] init];
  dispatch_apply(count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
    NSString *result = [LDSizeFormatter stringForBytes:1234567];
    [lock lock];
    [results addObject:result ?: @""];
    [lock unlock];
  });
  XCTAssertEqual(count, [results count]);
  NSString *first = [results objectAtIndex:0];
  NSString *digits = [[first componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]]
                         componentsJoinedByString:@""];
  XCTAssertEqualObjects(@"1234567", digits);
  XCTAssertTrue([first hasSuffix:@" bytes"]);
  XCTAssertEqual((NSUInteger)1, [[NSSet setWithArray:results] count]);
}

@end
