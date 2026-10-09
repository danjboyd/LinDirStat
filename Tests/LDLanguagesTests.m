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
  // The saved values, for the next launch: gnustep-base shadows NSLanguages
  // with the languages it computed at launch.
  NSString *domain = [[NSBundle mainBundle] bundleIdentifier] ?: [[NSProcessInfo processInfo] processName];
  NSDictionary *saved = [defaults persistentDomainForName:domain];
  XCTAssertEqualObjects(@"de", [LDLanguages chosenLanguage]);
  XCTAssertEqualObjects(@[@"de"], [saved objectForKey:@"AppleLanguages"]);
  XCTAssertEqualObjects(@[@"de"], [saved objectForKey:@"NSLanguages"]);

  [LDLanguages setChosenLanguage:nil];
  saved = [defaults persistentDomainForName:domain];
  XCTAssertNil([LDLanguages chosenLanguage]);
  XCTAssertNil([saved objectForKey:@"Language"]);
  XCTAssertNil([saved objectForKey:@"NSLanguages"]);
}

- (void)testNativeNames
{
  XCTAssertTrue([[LDLanguages nativeNameOfLanguage:@"de"] length] > 0);
  // A name starts with a capital where the language has them.
  NSString *french = [LDLanguages nativeNameOfLanguage:@"fr"];
  XCTAssertEqualObjects([[french substringToIndex:1] uppercaseString], [french substringToIndex:1]);
}

@end
