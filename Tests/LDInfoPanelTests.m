#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// The standard info panel (About LinDirStat) reads its fields from the app
// bundle's Info-gnustep.plist and shows "Unknown" for any it lacks.
@interface LDInfoPanelTests : XCTestCase
@end

@implementation LDInfoPanelTests

- (NSString *)repositoryPath:(NSString *)relativePath
{
  return [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:relativePath];
}

- (NSDictionary *)builtInfo
{
  NSString *path = [self repositoryPath:@"Source/LinDirStat.app/Resources/Info-gnustep.plist"];
  NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:path];
  XCTAssertNotNil(info, @"build the app first (make -C Source), and run from the repository root");
  return info;
}

- (void)testInfoPanelNamesTheAuthorAndCopyright
{
  NSDictionary *info = [self builtInfo];
  XCTAssertEqualObjects(info[@"Authors"], @[@"Daniel Boyd"]);
  XCTAssertEqualObjects(info[@"Copyright"], @"Copyright © 2026 Daniel Boyd");
  XCTAssertTrue([info[@"CopyrightDescription"] containsString:@"GNU General Public License"]);
}

// The release shown is the packaged version, so the panel and the AppImage
// or DMG agree.
- (void)testInfoPanelReleaseIsThePackageVersion
{
  NSData *data = [NSData dataWithContentsOfFile:[self repositoryPath:@"package.manifest.json"]];
  XCTAssertNotNil(data);
  NSDictionary *manifest = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
  NSString *version = manifest[@"package"][@"version"];
  XCTAssertTrue([version length] > 0);
  XCTAssertEqualObjects([self builtInfo][@"ApplicationRelease"], version);
}

@end
