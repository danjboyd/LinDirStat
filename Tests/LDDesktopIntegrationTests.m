#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDDesktopEntry.h"
#import "LDDesktopIntegration.h"
#import "LDPreferences.h"

#if !defined(__APPLE__)

@interface LDDesktopIntegrationTests : XCTestCase
{
  NSString *_root;
}
@end

@implementation LDDesktopIntegrationTests

- (void)setUp
{
  _root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  [[NSFileManager defaultManager] createDirectoryAtPath:[_root stringByAppendingPathComponent:@"appdir"]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
  [[@"icon" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[_root stringByAppendingPathComponent:@"appdir/lindirstat.png"] atomically:NO];
}

- (void)tearDown
{
  [[NSFileManager defaultManager] removeItemAtPath:_root error:NULL];
}

- (LDDesktopIntegration *)integrationAt:(NSString *)appImage
{
  NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:@{
    @"HOME": _root,
    @"XDG_DATA_HOME": [_root stringByAppendingPathComponent:@"home"],
    @"XDG_DATA_DIRS": [_root stringByAppendingPathComponent:@"system"],
    @"APPDIR": [_root stringByAppendingPathComponent:@"appdir"],
  }];
  if (appImage) {
    [environment setObject:appImage forKey:@"APPIMAGE"];
  }
  return [LDDesktopIntegration integrationForEnvironment:environment];
}

- (void)writeEntry:(NSString *)text named:(NSString *)name inData:(NSString *)data
{
  NSString *directory = [_root stringByAppendingPathComponent:[data stringByAppendingPathComponent:@"applications"]];
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  [text writeToFile:[directory stringByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
}

- (void)testUnavailableOutsideAnAppImage
{
  XCTAssertEqual(LDDesktopIntegrationUnavailable, [[self integrationAt:nil] state]);
  XCTAssertEqual(LDDesktopIntegrationUnavailable, [[self integrationAt:@""] state]);
}

- (void)testInstallWritesTheEntryAndIcon
{
  LDDesktopIntegration *integration = [self integrationAt:@"/apps/LinDirStat.AppImage"];
  XCTAssertEqual(LDDesktopIntegrationNotInstalled, [integration state]);
  XCTAssertTrue([integration install:NULL]);
  XCTAssertEqual(LDDesktopIntegrationInstalled, [integration state]);
  XCTAssertEqualObjects([_root stringByAppendingPathComponent:@"home/applications/lindirstat.desktop"], [integration entryPath]);
  XCTAssertEqualObjects([_root stringByAppendingPathComponent:@"home/icons/hicolor/256x256/apps/lindirstat.png"], [integration iconPath]);
  XCTAssertEqualObjects([@"icon" dataUsingEncoding:NSUTF8StringEncoding], [NSData dataWithContentsOfFile:[integration iconPath]]);
  LDDesktopEntry *entry = [LDDesktopEntry entryWithContentsOfFile:[integration entryPath] identifier:@"lindirstat.desktop"];
  XCTAssertTrue([entry isApplication]);
  XCTAssertEqualObjects(@"LinDirStat", [entry stringForKey:@"StartupWMClass"]);
  XCTAssertEqualObjects(@"lindirstat", [entry iconName]);
  XCTAssertEqualObjects((@[@"inode/directory"]), [entry mimeTypes]);
  XCTAssertTrue([entry acceptsFiles]);
}

// The path comes back as one argument, whatever it holds.
- (void)testExecKeepsAnAwkwardPathIntact
{
  for (NSString *path in @[@"/my apps/LinDirStat.AppImage", @"/a\"b/c$d`e\\f/LinDirStat.AppImage", @"/100%/x%Fy/LinDirStat.AppImage"]) {
    LDDesktopIntegration *integration = [self integrationAt:path];
    LDDesktopEntry *entry = [LDDesktopEntry entryWithString:[integration entryText] filePath:@"/x" identifier:@"x.desktop"];
    NSArray *commands = [entry commandsForPaths:@[[@"/folder" dataUsingEncoding:NSUTF8StringEncoding]]];
    XCTAssertEqual((NSUInteger)1, [commands count], @"%@", path);
    NSArray *command = [commands firstObject];
    XCTAssertEqualObjects(path, [command objectAtIndex:0]);
    XCTAssertEqual((NSUInteger)2, [command count], @"%@", path);
    XCTAssertEqualObjects(path, [entry stringForKey:@"TryExec"]);
  }
}

- (void)testAMovedAppImageIsNoticedAndRefreshed
{
  XCTAssertTrue([[self integrationAt:@"/old/LinDirStat.AppImage"] install:NULL]);
  LDDesktopIntegration *moved = [self integrationAt:@"/new/LinDirStat.AppImage"];
  XCTAssertEqual(LDDesktopIntegrationMoved, [moved state]);
  XCTAssertTrue([moved install:NULL]);
  XCTAssertEqual(LDDesktopIntegrationInstalled, [moved state]);
  LDDesktopEntry *entry = [LDDesktopEntry entryWithContentsOfFile:[moved entryPath] identifier:@"lindirstat.desktop"];
  XCTAssertEqualObjects(@"/new/LinDirStat.AppImage", [entry stringForKey:@"TryExec"]);
}

- (void)testAnIntegratorsEntryCountsAsIntegrated
{
  NSArray *entries = @[
    // AppImageLauncher
    @"[Desktop Entry]\nType=Application\nName=LinDirStat\nExec=/home/u/Applications/lindirstat-0.1.7-x86_64_abc.appimage %F\n",
    // Gear Lever keeps the AppImage's own keys
    @"[Desktop Entry]\nType=Application\nName=LinDirStat\nExec=/a/b %F\nStartupWMClass=LinDirStat\n",
    @"[Desktop Entry]\nType=Application\nName=Disk\nExec=/a/b %F\nX-AppImage-Name=LinDirStat\n",
  ];
  NSUInteger index = 0;
  for (NSString *text in entries) {
    NSString *name = [NSString stringWithFormat:@"integrated%lu.desktop", (unsigned long)index++];
    [self writeEntry:text named:name inData:@"home"];
    XCTAssertEqual(LDDesktopIntegrationExternal, [[self integrationAt:@"/apps/LinDirStat.AppImage"] state], @"%@", text);
    [[NSFileManager defaultManager] removeItemAtPath:[_root stringByAppendingPathComponent:[@"home/applications" stringByAppendingPathComponent:name]] error:NULL];
  }
  // A system package counts too.
  [self writeEntry:entries[1] named:@"org.lindirstat.desktop" inData:@"system"];
  XCTAssertEqual(LDDesktopIntegrationExternal, [[self integrationAt:@"/apps/LinDirStat.AppImage"] state]);
}

- (void)testOtherAppsAndHiddenEntriesDontCount
{
  [self writeEntry:@"[Desktop Entry]\nType=Application\nName=Editor\nExec=gedit %F\nStartupWMClass=gedit\n" named:@"gedit.desktop" inData:@"home"];
  [self writeEntry:@"[Desktop Entry]\nType=Application\nName=LinDirStat\nExec=/a %F\nStartupWMClass=LinDirStat\nHidden=true\n" named:@"old.desktop" inData:@"home"];
  XCTAssertEqual(LDDesktopIntegrationNotInstalled, [[self integrationAt:@"/apps/LinDirStat.AppImage"] state]);
}

// Same file name, not ours: never overwritten or removed.
- (void)testSomeoneElsesEntryOfOurNameIsLeftAlone
{
  NSString *text = @"[Desktop Entry]\nType=Application\nName=My Own\nExec=/mine %F\n";
  [self writeEntry:text named:@"lindirstat.desktop" inData:@"home"];
  LDDesktopIntegration *integration = [self integrationAt:@"/apps/LinDirStat.AppImage"];
  XCTAssertEqual(LDDesktopIntegrationExternal, [integration state]);
  XCTAssertTrue([integration remove:NULL]);
  XCTAssertEqualObjects(text, [NSString stringWithContentsOfFile:[integration entryPath] encoding:NSUTF8StringEncoding error:NULL]);
}

- (void)testRemoveTakesOurEntryAndIcon
{
  LDDesktopIntegration *integration = [self integrationAt:@"/apps/LinDirStat.AppImage"];
  XCTAssertTrue([integration install:NULL]);
  XCTAssertTrue([integration remove:NULL]);
  NSFileManager *manager = [NSFileManager defaultManager];
  XCTAssertFalse([manager fileExistsAtPath:[integration entryPath]]);
  XCTAssertFalse([manager fileExistsAtPath:[integration iconPath]]);
  XCTAssertEqual(LDDesktopIntegrationNotInstalled, [integration state]);
  XCTAssertTrue([integration remove:NULL]);
}

- (void)testNotNowWaitsSevenDaysAndDontAskAgainStays
{
  LDPreferences *preferences = [[LDPreferences alloc] initWithUserDefaults:[NSUserDefaults standardUserDefaults]];
  [preferences resetAll];
  NSDate *start = [NSDate dateWithTimeIntervalSince1970:1000000000.0];
  NSTimeInterval week = 7.0 * 24.0 * 60.0 * 60.0;
  XCTAssertTrue([LDDesktopIntegration mayOfferWithPreferences:preferences now:start]);
  [preferences setDesktopIntegrationSnoozedAt:start];
  XCTAssertEqualObjects(start, [preferences desktopIntegrationSnoozedAt]);
  XCTAssertFalse([LDDesktopIntegration mayOfferWithPreferences:preferences now:start]);
  XCTAssertFalse([LDDesktopIntegration mayOfferWithPreferences:preferences now:[start dateByAddingTimeInterval:week - 1.0]]);
  XCTAssertTrue([LDDesktopIntegration mayOfferWithPreferences:preferences now:[start dateByAddingTimeInterval:week]]);
  // A clock set back doesn't silence it for good.
  XCTAssertTrue([LDDesktopIntegration mayOfferWithPreferences:preferences now:[start dateByAddingTimeInterval:-1.0]]);
  [preferences setDesktopIntegrationDeclined:YES];
  XCTAssertFalse([LDDesktopIntegration mayOfferWithPreferences:preferences now:[start dateByAddingTimeInterval:10.0 * week]]);
  [preferences resetAll];
  XCTAssertNil([preferences desktopIntegrationSnoozedAt]);
  XCTAssertTrue([LDDesktopIntegration mayOfferWithPreferences:preferences now:start]);
}

- (void)writeIcon:(NSString *)text atPath:(NSString *)path
{
  [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
  [[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:NO];
}

// An icon of our name that we didn't write survives both Add and Remove.
- (void)testSomeoneElsesIconIsLeftAlone
{
  LDDesktopIntegration *integration = [self integrationAt:@"/apps/LinDirStat.AppImage"];
  [self writeIcon:@"theirs" atPath:[integration iconPath]];
  NSData *theirs = [@"theirs" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertTrue([integration install:NULL]);
  XCTAssertEqualObjects(theirs, [NSData dataWithContentsOfFile:[integration iconPath]]);
  XCTAssertEqual(LDDesktopIntegrationInstalled, [integration state]);
  // Reinstalling doesn't turn it into ours.
  XCTAssertTrue([[self integrationAt:@"/new/LinDirStat.AppImage"] install:NULL]);
  XCTAssertEqualObjects(theirs, [NSData dataWithContentsOfFile:[integration iconPath]]);
  XCTAssertTrue([integration remove:NULL]);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[integration entryPath]]);
  XCTAssertEqualObjects(theirs, [NSData dataWithContentsOfFile:[integration iconPath]]);
}

// A later AppImage's different icon replaces ours, and Remove still takes it.
- (void)testOurIconFollowsANewAppImage
{
  LDDesktopIntegration *integration = [self integrationAt:@"/apps/LinDirStat.AppImage"];
  XCTAssertTrue([integration install:NULL]);
  [[@"new icon" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[_root stringByAppendingPathComponent:@"appdir/lindirstat.png"] atomically:NO];
  XCTAssertTrue([integration install:NULL]);
  XCTAssertEqualObjects([@"new icon" dataUsingEncoding:NSUTF8StringEncoding], [NSData dataWithContentsOfFile:[integration iconPath]]);
  XCTAssertTrue([integration remove:NULL]);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[integration iconPath]]);
}

@end

#endif
