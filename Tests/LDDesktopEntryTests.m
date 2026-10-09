#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDDesktop.h"
#import "LDDesktopEntry.h"

#include <string.h>

@interface LDDesktopEntryTests : XCTestCase
@end

static NSData *LDBytes(const char *bytes)
{
  return [NSData dataWithBytes:bytes length:strlen(bytes)];
}

@implementation LDDesktopEntryTests

- (LDDesktopEntry *)entryWithExec:(NSString *)exec
{
  NSString *text = [NSString stringWithFormat:@"[Desktop Entry]\nType=Application\nName=Some App\nIcon=some-icon\nExec=%@\n", exec];
  return [LDDesktopEntry entryWithString:text filePath:@"/apps/some.desktop" identifier:@"some.desktop"];
}

- (void)testParsesTheDesktopEntryGroupOnly
{
  NSString *text = @"# comment\n[Desktop Entry]\nType=Application\nName=Viewer\nName[de]=Betrachter\n"
                   @"Comment=Line one\\nLine two\\sand\\ttab\\\\\nMimeType=text/plain; image/png;;\nTerminal=true\n"
                   @"Name=Second Name Ignored\n\n[Desktop Action new]\nName=New Window\nExec=other\n";
  LDDesktopEntry *entry = [LDDesktopEntry entryWithString:text filePath:@"/a/viewer.desktop" identifier:@"viewer.desktop"];
  XCTAssertEqualObjects(@"Viewer", [entry name]);
  XCTAssertEqualObjects(@"Line one\nLine two and\ttab\\", [entry stringForKey:@"Comment"]);
  XCTAssertEqualObjects((@[@"text/plain", @"image/png"]), [entry mimeTypes]);
  XCTAssertTrue([entry runsInTerminal]);
  XCTAssertTrue([entry isApplication]);
  XCTAssertNil([entry exec]);
  XCTAssertEqualObjects(@"viewer.desktop", [entry identifier]);
  XCTAssertNil([LDDesktopEntry entryWithString:@"[Something Else]\nName=x\n" filePath:nil identifier:@"x.desktop"]);
}

- (void)testSplitsExecByTheQuotingRules
{
  XCTAssertEqualObjects((@[@"app", @"--title", @"My \"App\" $1 `x` \\", @"%f"]),
                        [LDDesktopEntry argumentsForExec:@"app --title \"My \\\"App\\\" \\$1 \\`x\\` \\\\\" %f"]);
  XCTAssertEqualObjects((@[@"/opt/My App/bin/app", @"%U"]),
                        [LDDesktopEntry argumentsForExec:@"\"/opt/My App/bin/app\"   %U"]);
  XCTAssertEqualObjects((@[@"a", @"b"]), [LDDesktopEntry argumentsForExec:@"a\tb "]);
  XCTAssertNil([LDDesktopEntry argumentsForExec:@"app \"unterminated %f"]);
}

- (void)testExecEscapesAreUnescapedTwice
{
  // In the file a literal backslash in a quoted argument is written as four.
  LDDesktopEntry *entry = [LDDesktopEntry entryWithString:@"[Desktop Entry]\nType=Application\nExec=app \"a\\\\\\\\b\" %f\n"
                                                 filePath:nil
                                               identifier:@"a.desktop"];
  XCTAssertEqualObjects((@[@"app", @"a\\b", @"%f"]), [LDDesktopEntry argumentsForExec:[entry exec]]);
}

- (void)testLowercaseFileCodesRunOncePerPath
{
  NSArray *paths = @[LDBytes("/x/one.txt"), LDBytes("/x/two\xff.txt")];
  NSArray *commands = [[self entryWithExec:@"app --open %f"] commandsForPaths:paths];
  XCTAssertEqual(2U, [commands count]);
  XCTAssertEqualObjects((@[@"app", @"--open", LDBytes("/x/one.txt")]), [commands objectAtIndex:0]);
  // Paths stay exact bytes, even when they are not UTF-8.
  XCTAssertEqualObjects((@[@"app", @"--open", LDBytes("/x/two\xff.txt")]), [commands objectAtIndex:1]);
}

- (void)testUppercaseCodesTakeEveryPathAtOnce
{
  NSArray *paths = @[LDBytes("/x/a b.txt"), LDBytes("/x/c%d.txt")];
  NSArray *files = [[self entryWithExec:@"app %F"] commandsForPaths:paths];
  XCTAssertEqualObjects((@[@[@"app", LDBytes("/x/a b.txt"), LDBytes("/x/c%d.txt")]]), files);
  NSArray *uris = [[self entryWithExec:@"app %U"] commandsForPaths:paths];
  XCTAssertEqualObjects((@[@[@"app", @"file:///x/a%20b.txt", @"file:///x/c%25d.txt"]]), uris);
  NSArray *single = [[self entryWithExec:@"app %u"] commandsForPaths:@[LDBytes("/x/caf\xc3\xa9")]];
  XCTAssertEqualObjects((@[@[@"app", [LDDesktop fileURIForPath:LDBytes("/x/caf\xc3\xa9")]]]), single);
}

- (void)testOtherFieldCodes
{
  NSArray *commands = [[self entryWithExec:@"app %i --name=%c --from %k 100%% %d %D %n %N %v %m --file=%f"]
                       commandsForPaths:@[LDBytes("/x/a.txt")]];
  NSArray *expected = @[@"app", @"--icon", @"some-icon", @"--name=Some App", @"--from", @"/apps/some.desktop", @"100%",
                        LDBytes("--file=/x/a.txt")];
  XCTAssertEqualObjects(@[expected], commands);
}

- (void)testMalformedExecGivesNoCommands
{
  XCTAssertEqualObjects(@[], [[self entryWithExec:@"app \"broken %f"] commandsForPaths:@[LDBytes("/x")]]);
  XCTAssertFalse([[self entryWithExec:@"app \"broken %f"] acceptsFiles]);
}

- (void)testUsableForOpening
{
  XCTAssertTrue([[self entryWithExec:@"true %f"] isUsableForOpening]);
  XCTAssertFalse([[self entryWithExec:@"true"] isUsableForOpening], @"no file field code");
  XCTAssertFalse([[self entryWithExec:@"ldtest-not-installed %f"] isUsableForOpening]);
  LDDesktopEntry *tryExec = [LDDesktopEntry entryWithString:@"[Desktop Entry]\nType=Application\nTryExec=ldtest-not-installed\nExec=true %f\n"
                                                   filePath:nil
                                                 identifier:@"t.desktop"];
  XCTAssertFalse([tryExec isUsableForOpening]);
  LDDesktopEntry *hidden = [LDDesktopEntry entryWithString:@"[Desktop Entry]\nType=Application\nHidden=true\nExec=true %f\n"
                                                  filePath:nil
                                                identifier:@"h.desktop"];
  XCTAssertFalse([hidden isUsableForOpening]);
  LDDesktopEntry *link = [LDDesktopEntry entryWithString:@"[Desktop Entry]\nType=Link\nExec=true %f\n" filePath:nil identifier:@"l.desktop"];
  XCTAssertFalse([link isUsableForOpening]);
}

@end
