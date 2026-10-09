#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDDesktopEntry.h"
#import "LDFileTypeDescriptions.h"
#import "LDMimeApps.h"
#import "LDOpenWith.h"
#import "LDOpenWithLinux.h"

#include <string.h>
#include <unistd.h>

@interface LDOpenWithTests : XCTestCase
{
  NSString *_temporaryRoot;
}
@end

@implementation LDOpenWithTests

- (NSString *)fixture:(NSString *)relative
{
  return [[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Tests/Fixtures"]
          stringByAppendingPathComponent:relative];
}

- (NSDictionary *)environmentWithDesktop:(NSString *)desktop
{
  NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:@{
    @"HOME": @"/nonexistent-home",
    @"XDG_DATA_HOME": [self fixture:@"openwith/data-home"],
    @"XDG_DATA_DIRS": [NSString stringWithFormat:@"%@:%@", [self fixture:@"openwith/data-dirs/system"], [self fixture:@"openwith/data-dirs/extra"]],
    @"XDG_CONFIG_HOME": [self fixture:@"openwith/config-home"],
    @"XDG_CONFIG_DIRS": [self fixture:@"openwith/no-config-dirs"],
  }];
  if (desktop) {
    [environment setObject:desktop forKey:@"XDG_CURRENT_DESKTOP"];
  }
  return environment;
}

- (LDMimeApps *)mimeAppsWithDesktop:(NSString *)desktop
{
  NSDictionary *environment = [self environmentWithDesktop:desktop];
  return [[LDMimeApps alloc] initWithApplicationDirectories:[LDMimeApps applicationDirectoriesForEnvironment:environment]
                                         mimeappsListPaths:[LDMimeApps mimeappsListPathsForEnvironment:environment]
                                             mimeDirectory:[self fixture:@"mime"]];
}

- (NSArray *)identifiersOf:(NSArray *)objects
{
  NSMutableArray *identifiers = [NSMutableArray array];
  for (id object in objects) {
    [identifiers addObject:[object identifier]];
  }
  return identifiers;
}

#pragma mark - XDG locations

- (void)testDefaultLocations
{
  NSDictionary *environment = @{@"HOME": @"/home/u"};
  XCTAssertEqualObjects((@[@"/home/u/.local/share/applications", @"/usr/local/share/applications", @"/usr/share/applications"]),
                        [LDMimeApps applicationDirectoriesForEnvironment:environment]);
  NSArray *expected = @[@"/home/u/.config/mimeapps.list", @"/etc/xdg/mimeapps.list",
                        @"/home/u/.local/share/applications/mimeapps.list",
                        @"/usr/local/share/applications/mimeapps.list", @"/usr/share/applications/mimeapps.list"];
  XCTAssertEqualObjects(expected, [LDMimeApps mimeappsListPathsForEnvironment:environment]);
}

- (void)testDesktopSpecificListsComeFirstInEachFolder
{
  NSArray *paths = [LDMimeApps mimeappsListPathsForEnvironment:@{@"HOME": @"/h", @"XDG_CURRENT_DESKTOP": @"ubuntu:GNOME",
                                                                 @"XDG_CONFIG_DIRS": @"/c1:/c2", @"XDG_DATA_DIRS": @"/d"}];
  NSArray *expected = @[@"/h/.config/ubuntu-mimeapps.list", @"/h/.config/gnome-mimeapps.list", @"/h/.config/mimeapps.list",
                        @"/c1/ubuntu-mimeapps.list", @"/c1/gnome-mimeapps.list", @"/c1/mimeapps.list",
                        @"/c2/ubuntu-mimeapps.list", @"/c2/gnome-mimeapps.list", @"/c2/mimeapps.list",
                        @"/h/.local/share/applications/ubuntu-mimeapps.list", @"/h/.local/share/applications/gnome-mimeapps.list",
                        @"/h/.local/share/applications/mimeapps.list",
                        @"/d/applications/ubuntu-mimeapps.list", @"/d/applications/gnome-mimeapps.list", @"/d/applications/mimeapps.list"];
  XCTAssertEqualObjects(expected, paths);
}

#pragma mark - Database

- (void)testDesktopFileIdentifiersAndPrecedence
{
  LDMimeApps *apps = [self mimeAppsWithDesktop:nil];
  // Subfolders become dashes; the user's folder hides the system's, and an
  // earlier XDG_DATA_DIRS entry hides a later one.
  XCTAssertEqualObjects(@"KDE Files", [[apps entryForIdentifier:@"kde-files.desktop"] name]);
  XCTAssertEqualObjects(@"User Shadowed", [[apps entryForIdentifier:@"shadowed.desktop"] name]);
  XCTAssertEqualObjects(@"Text Editor", [[apps entryForIdentifier:@"text-editor.desktop"] name]);
  XCTAssertEqualObjects(@"Extra Tool", [[apps entryForIdentifier:@"extra-only.desktop"] name]);
}

- (void)testMimeappsPrecedence
{
  LDMimeApps *apps = [self mimeAppsWithDesktop:nil];
  // The user's default skips an uninstalled entry and beats the system's;
  // added associations come next; removed ones (writer) and unusable entries
  // (hidden, no field code, missing programs) are left out.
  NSArray *expected = @[@"viewer.desktop", @"user-tool.desktop", @"shadowed.desktop", @"text-editor.desktop", @"extra-only.desktop"];
  XCTAssertEqualObjects(expected, [self identifiersOf:[apps entriesForType:@"text/plain"]]);
  XCTAssertEqualObjects(@"viewer.desktop", [[apps defaultEntryForType:@"text/plain"] identifier]);
  XCTAssertEqualObjects(@"kde-files.desktop", [[apps defaultEntryForType:@"inode/directory"] identifier]);
}

- (void)testDesktopSpecificDefaultWins
{
  LDMimeApps *apps = [self mimeAppsWithDesktop:@"Test"];
  XCTAssertEqualObjects(@"text-editor.desktop", [[apps defaultEntryForType:@"text/plain"] identifier]);
}

- (void)testSubclassesAndAliasesInheritApplications
{
  LDMimeApps *apps = [self mimeAppsWithDesktop:nil];
  XCTAssertEqualObjects((@[@"text/x-csrc", @"text/plain"]), [apps typeWithAncestors:@"text/x-c"]);
  XCTAssertEqualObjects((@[@"application/x-high", @"application/x-low"]), [apps typeWithAncestors:@"application/x-high"]);
  XCTAssertEqualObjects((@[@"text/x-other", @"text/plain"]), [apps typeWithAncestors:@"text/x-other"]);
  NSArray *forC = [self identifiersOf:[apps entriesForType:@"text/x-csrc"]];
  // No default of its own: text/plain's applies.
  XCTAssertEqualObjects(@"viewer.desktop", [forC firstObject]);
  XCTAssertEqualObjects(@"c-editor.desktop", [forC objectAtIndex:1]);
  XCTAssertTrue([forC containsObject:@"extra-only.desktop"]);
  XCTAssertEqual(0U, [[apps entriesForType:@"application/x-nothing"] count]);
}

#if !defined(__APPLE__)

#pragma mark - Open With (Linux)

- (void)setUp
{
  [super setUp];
  NSString *name = [NSString stringWithFormat:@"lindirstat-openwith-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
  _temporaryRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
  [[NSFileManager defaultManager] createDirectoryAtPath:[_temporaryRoot stringByAppendingPathComponent:@"folder"]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
  [[NSFileManager defaultManager] removeItemAtPath:_temporaryRoot error:NULL];
  [super tearDown];
}

- (NSData *)file:(NSString *)name contents:(NSData *)contents
{
  NSString *path = [_temporaryRoot stringByAppendingPathComponent:name];
  [contents writeToFile:path atomically:NO];
  const char *bytes = [path fileSystemRepresentation];
  return [NSData dataWithBytes:bytes length:strlen(bytes)];
}

- (LDOpenWith *)openWith
{
  LDFileTypeDescriptions *types = [[LDFileTypeDescriptions alloc] initWithMimeDirectory:[self fixture:@"mime"]];
  return [[LDOpenWith alloc] initWithMimeApps:[self mimeAppsWithDesktop:nil] typeDescriptions:types];
}

- (void)testMimeTypesOfPaths
{
  LDOpenWith *openWith = [self openWith];
  NSData *text = [@"plain words\n" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(@"text/plain", [openWith mimeTypeForPath:[self file:@"notes.TXT" contents:text]]);
  XCTAssertEqualObjects(@"text/x-csrc", [openWith mimeTypeForPath:[self file:@"main.c" contents:text]]);
  XCTAssertEqualObjects(@"text/plain", [openWith mimeTypeForPath:[self file:@"README" contents:text]]);
  unsigned char binary[] = {0x7f, 'E', 'L', 'F', 0, 1, 2};
  XCTAssertEqualObjects(@"application/octet-stream",
                        [openWith mimeTypeForPath:[self file:@"program" contents:[NSData dataWithBytes:binary length:sizeof(binary)]]]);
  XCTAssertEqualObjects(@"application/octet-stream", [openWith mimeTypeForPath:[self file:@".hidden" contents:[NSData dataWithBytes:"\xff\xfe" length:2]]]);
  const char *folder = [[_temporaryRoot stringByAppendingPathComponent:@"folder"] fileSystemRepresentation];
  XCTAssertEqualObjects(@"inode/directory", [openWith mimeTypeForPath:[NSData dataWithBytes:folder length:strlen(folder)]]);
}

- (void)testApplicationsForASelection
{
  LDOpenWith *openWith = [self openWith];
  NSData *text = [self file:@"a.txt" contents:[NSData data]];
  NSArray *applications = [openWith applicationsForPaths:@[text]];
  // The default first, then by name.
  XCTAssertEqualObjects((@[@"viewer.desktop", @"extra-only.desktop", @"text-editor.desktop", @"shadowed.desktop", @"user-tool.desktop"]),
                        [self identifiersOf:applications]);
  XCTAssertTrue([[applications objectAtIndex:0] isDefault]);
  XCTAssertFalse([[applications objectAtIndex:1] isDefault]);
  XCTAssertEqualObjects(@"Extra Tool", [[applications objectAtIndex:1] name]);

  // A mixed selection offers what opens every item, with no default unless
  // all agree.
  const char *folder = [[_temporaryRoot stringByAppendingPathComponent:@"folder"] fileSystemRepresentation];
  NSArray *mixed = [openWith applicationsForPaths:@[text, [NSData dataWithBytes:folder length:strlen(folder)]]];
  XCTAssertEqualObjects(@[@"viewer.desktop"], [self identifiersOf:mixed]);
  XCTAssertFalse([[mixed objectAtIndex:0] isDefault]);

  NSArray *twoTexts = [openWith applicationsForPaths:@[text, [self file:@"b.txt" contents:[NSData data]]]];
  XCTAssertTrue([[twoTexts objectAtIndex:0] isDefault]);
  XCTAssertEqual(0U, [[openWith applicationsForPaths:@[]] count]);
}

#endif

@end
