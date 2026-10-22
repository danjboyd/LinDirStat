#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// The standard info panel (About LinDirStat) reads its fields from the app
// bundle's Info-gnustep.plist and shows "Unknown" for any it lacks. GNUstep
// only: the macOS build's panel reads macos/Info.plist, and there is no
// Source/LinDirStat.app.
#if !defined(__APPLE__)

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

// The panel, the window and the AppImage show LinDirStat's own icon, not the
// GNUstep logo (which an info panel scales up when NSIcon is missing).
- (void)testBundleDeclaresItsIcon
{
  NSDictionary *info = [self builtInfo];
  XCTAssertEqualObjects(info[@"NSIcon"], @"LinDirStat.png");
  NSString *path = [self repositoryPath:@"Source/LinDirStat.app/Resources/LinDirStat.png"];
  NSData *png = [NSData dataWithContentsOfFile:path];
  XCTAssertTrue([png length] > 24);
  if ([png length] > 24) {
    const unsigned char *bytes = [png bytes];
    XCTAssertEqual(0, memcmp(bytes, "\x89PNG", 4));
    // IHDR width and height, big-endian: at least 128 px.
    uint32_t width = ((uint32_t)bytes[16] << 24) | ((uint32_t)bytes[17] << 16) | ((uint32_t)bytes[18] << 8) | bytes[19];
    uint32_t height = ((uint32_t)bytes[20] << 24) | ((uint32_t)bytes[21] << 16) | ((uint32_t)bytes[22] << 8) | bytes[23];
    XCTAssertTrue(width >= 128 && width == height);
  }
}

// The release shown is the packaged version, so the panel and the AppImage
// agree: GP_PACKAGE_VERSION_OVERRIDE when the build was run with it set,
// else the manifest's package.version.
- (void)testInfoPanelReleaseIsThePackageVersion
{
  NSString *version = [[NSProcessInfo processInfo] environment][@"GP_PACKAGE_VERSION_OVERRIDE"];
  if ([version length] == 0) {
    NSData *data = [NSData dataWithContentsOfFile:[self repositoryPath:@"package.manifest.json"]];
    XCTAssertNotNil(data);
    NSDictionary *manifest = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    version = manifest[@"package"][@"version"];
  }
  XCTAssertTrue([version length] > 0);
  XCTAssertEqualObjects([self builtInfo][@"ApplicationRelease"], version);
}

@end

#endif
