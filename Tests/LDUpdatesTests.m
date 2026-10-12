#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDUpdates.h"

@interface LDUpdatesTests : XCTestCase
@end

@implementation LDUpdatesTests
{
  NSString *_directory;
}

- (void)setUp
{
  [super setUp];
  _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"lindirstat-updates-%@", [[NSProcessInfo processInfo] globallyUniqueString]]];
  [[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
  [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
  [super tearDown];
}

- (NSDictionary *)manifest
{
  NSString *path = [[[NSFileManager defaultManager] currentDirectoryPath]
                    stringByAppendingPathComponent:@"package.manifest.json"];
  NSData *data = [NSData dataWithContentsOfFile:path];
  XCTAssertNotNil(data, @"run from the repository root");
  return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
}

- (NSString *)writeJSON:(id)object named:(NSString *)name
{
  NSString *path = [_directory stringByAppendingPathComponent:name];
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
  XCTAssertTrue([data writeToFile:path atomically:YES]);
  return path;
}

// A build run from the tree (or these tests) has no packaged configuration,
// so it never checks for or installs updates.
- (void)testUnpackagedBuildHasNoUpdater
{
  XCTAssertNil([LDUpdates packagedUpdates]);
}

// What packaging builds into the AppImage: the published feed, signed
// payloads, the public releases repository.
- (void)testManifestPublishesSignedUpdatesForTheAppImageOnly
{
  NSDictionary *manifest = [self manifest];
  NSDictionary *updates = manifest[@"updates"];
  XCTAssertEqualObjects(updates[@"enabled"], @YES);
  XCTAssertEqualObjects(updates[@"channel"], @"stable");
  XCTAssertEqualObjects(updates[@"github"][@"owner"], @"danjboyd");
  XCTAssertEqualObjects(updates[@"github"][@"repo"], @"LinDirStat-releases");
  XCTAssertEqualObjects(updates[@"github"][@"tagPattern"], @"v{version}");
  NSData *publicKey = [[NSData alloc] initWithBase64EncodedString:updates[@"publicEDKey"] options:0];
  XCTAssertEqual([publicKey length], (NSUInteger)32);

  NSDictionary *appImage = manifest[@"backends"][@"appimage"][@"updates"];
  XCTAssertEqualObjects(appImage[@"feedUrl"],
                        @"https://danjboyd.github.io/LinDirStat-releases/updates/linux/stable.json");
  XCTAssertEqualObjects(appImage[@"embedUpdateInformation"], @YES);
  XCTAssertEqualObjects(manifest[@"platformOverrides"][@"macos"][@"updates"][@"enabled"], @NO);
}

#if defined(GNUSTEP)

// The packaged configuration's shape (metadata/updates/
// gnustep-packager-update.json), for version 0.1.0 with its feed at feedPath.
- (LDUpdates *)updatesForVersion:(NSString *)version feed:(NSString *)feedPath
{
  NSDictionary *configuration = @{
    @"formatVersion": @1,
    @"package": @{@"id": @"org.lindirstat.LinDirStat", @"name": @"LinDirStat", @"displayName": @"LinDirStat",
                  @"version": version, @"backend": @"appimage", @"platform": @"linux-x64"},
    @"updates": @{@"enabled": @YES, @"provider": @"github-release-feed", @"channel": @"stable",
                  @"feedUrl": [[NSURL fileURLWithPath:feedPath] absoluteString],
                  @"minimumCheckIntervalHours": @24, @"startupDelaySeconds": @15}
  };
  NSError *error = nil;
  LDUpdates *updates = [LDUpdates updatesWithConfigurationFile:[self writeJSON:configuration named:@"config.json"]
                                                          error:&error];
  XCTAssertNotNil(updates, @"%@", error);
  return updates;
}

- (NSString *)feedOffering:(NSArray *)versions
{
  NSMutableArray *releases = [NSMutableArray array];
  for (NSString *version in versions) {
    NSString *name = [NSString stringWithFormat:@"LinDirStat-%@-x86_64.AppImage", version];
    [releases addObject:@{
      @"version": version,
      @"tag": [@"v" stringByAppendingString:version],
      @"assets": @[@{@"backend": @"appimage", @"platform": @"linux-x64", @"kind": @"appimage", @"name": name,
                     @"url": [@"https://example.invalid/" stringByAppendingString:name]}]
    }];
  }
  return [self writeJSON:@{@"formatVersion": @1, @"channel": @"stable", @"releases": releases} named:@"feed.json"];
}

- (void)testReadsThePackagedConfiguration
{
  LDUpdates *updates = [self updatesForVersion:@"0.1.0" feed:[self feedOffering:@[]]];
  XCTAssertEqualObjects([updates currentVersion], @"0.1.0");
}

- (void)testOffersTheNewestNewerRelease
{
  LDUpdates *updates = [self updatesForVersion:@"0.1.0" feed:[self feedOffering:@[@"0.1.1", @"0.2.0", @"0.0.9"]]];
  NSError *error = nil;
  XCTAssertEqualObjects([updates newerVersionFromFeedWithError:&error], @"0.2.0", @"%@", error);
}

- (void)testCurrentOrOlderReleasesAreNoUpdate
{
  LDUpdates *updates = [self updatesForVersion:@"0.1.0" feed:[self feedOffering:@[@"0.1.0", @"0.0.9"]]];
  NSError *error = nil;
  XCTAssertNil([updates newerVersionFromFeedWithError:&error]);
  XCTAssertNil(error);
}

- (void)testMissingFeedIsAnErrorNotAnUpdate
{
  LDUpdates *updates = [self updatesForVersion:@"0.1.0"
                                          feed:[_directory stringByAppendingPathComponent:@"missing.json"]];
  NSError *error = nil;
  XCTAssertNil([updates newerVersionFromFeedWithError:&error]);
  XCTAssertNotNil(error);
}

#else

- (void)testThisBuildHasNoUpdater
{
  NSError *error = nil;
  XCTAssertNil([LDUpdates updatesWithConfigurationFile:@"/nonexistent" error:&error]);
  XCTAssertNotNil(error);
}

#endif

@end
