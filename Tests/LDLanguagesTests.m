#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDLanguages.h"

@interface LDLanguagesTests : XCTestCase
@end

@implementation LDLanguagesTests

- (void)tearDown
{
  [LDLanguages setChosenLanguage:nil];
  [super tearDown];
}

- (void)testChoosingALanguageSetsThePlatformsLanguageLists
{
  [LDLanguages setChosenLanguage:@"de"];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  XCTAssertEqualObjects(@"de", [LDLanguages chosenLanguage]);
  XCTAssertEqualObjects(@[@"de"], [defaults objectForKey:@"AppleLanguages"]);
  XCTAssertEqualObjects(@[@"de"], [defaults objectForKey:@"NSLanguages"]);

  [LDLanguages setChosenLanguage:nil];
  XCTAssertNil([LDLanguages chosenLanguage]);
  XCTAssertNil([[defaults persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier] ?: @""] objectForKey:@"Language"]);
}

- (void)testNativeNames
{
  XCTAssertTrue([[LDLanguages nativeNameOfLanguage:@"de"] length] > 0);
  // A name starts with a capital where the language has them.
  NSString *french = [LDLanguages nativeNameOfLanguage:@"fr"];
  XCTAssertEqualObjects([[french substringToIndex:1] uppercaseString], [french substringToIndex:1]);
}

@end
