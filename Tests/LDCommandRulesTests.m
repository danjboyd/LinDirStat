#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDCommandRules.h"
#import "LDPreferences.h"

@interface LDCommandRulesTests : XCTestCase
{
  LDFileNode *_root;
  LDFileNode *_folder;
  LDFileNode *_file;
  LDFileNode *_mount;
}
@end

@implementation LDCommandRulesTests

- (void)setUp
{
  [super setUp];
  _root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  _folder = [LDFileNode nodeWithName:@"photos" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  _file = [LDFileNode nodeWithName:@"a.jpg" kind:LDFileNodeKindFile size:1 allocatedSize:1];
  _mount = [LDFileNode nodeWithName:@"usb" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [_mount setError:LDFileNodeErrorMountPoint errorNumber:0];
  [_folder addChild:_file];
  [_root addChild:_folder];
  [_root addChild:_mount];
}

- (BOOL)command:(LDCommand)command nodes:(NSArray *)nodes busy:(BOOL)busy
{
  return [LDCommandRules isCommand:command enabledForNodes:nodes rootNode:_root busy:busy];
}

- (void)testNothingIsEnabledWithoutSelection
{
  XCTAssertFalse(([self command:LDCommandOpen nodes:@[] busy:NO]));
  XCTAssertFalse(([self command:LDCommandMoveToTrash nodes:@[] busy:NO]));
}

- (void)testNonDestructiveCommandsStayEnabledWhileScanning
{
  for (int command = LDCommandOpen; command <= LDCommandTerminal; command++) {
    XCTAssertTrue(([self command:(LDCommand)command nodes:@[_file, _folder] busy:YES]));
  }
  XCTAssertFalse(([self command:LDCommandMoveToTrash nodes:@[_file] busy:YES]));
  XCTAssertFalse(([self command:LDCommandRefreshSelected nodes:@[_file] busy:YES]));
}

- (void)testRootsAndMountPointsCannotBeDeletedOrMoved
{
  XCTAssertTrue(([self command:LDCommandMoveToTrash nodes:@[_file, _folder] busy:NO]));
  XCTAssertTrue(([self command:LDCommandDeletePermanently nodes:@[_folder] busy:NO]));
  XCTAssertFalse(([self command:LDCommandMoveToTrash nodes:@[_root] busy:NO]));
  XCTAssertFalse(([self command:LDCommandDeletePermanently nodes:@[_file, _mount] busy:NO]));
  XCTAssertFalse(([self command:LDCommandMoveTo nodes:@[_root] busy:NO]));
  XCTAssertTrue(([self command:LDCommandRefreshSelected nodes:@[_root] busy:NO]));
}

- (void)testEmptyFolderNeedsFolders
{
  XCTAssertTrue(([self command:LDCommandEmptyFolder nodes:@[_folder] busy:NO]));
  XCTAssertFalse(([self command:LDCommandEmptyFolder nodes:@[_folder, _file] busy:NO]));
  XCTAssertFalse(([self command:LDCommandEmptyFolder nodes:@[_mount] busy:NO]));
}

- (void)testComputeHashNeedsExactlyOneFile
{
  XCTAssertTrue(([self command:LDCommandComputeHash nodes:@[_file] busy:NO]));
  XCTAssertFalse(([self command:LDCommandComputeHash nodes:@[_folder] busy:NO]));
  XCTAssertFalse(([self command:LDCommandComputeHash nodes:@[_file, _file] busy:NO]));
}

- (void)testCleanupsMatchEveryNodeKind
{
  LDCustomCleanup *cleanup = [[LDCustomCleanup alloc] init];
  [cleanup setEnabled:YES];
  [cleanup setCommandLine:@"echo %p"];
  [cleanup setWorksForFiles:YES];
  XCTAssertTrue(([LDCommandRules isCleanup:cleanup enabledForNodes:@[_file] rootNode:_root busy:NO]));
  XCTAssertFalse(([LDCommandRules isCleanup:cleanup enabledForNodes:@[_file, _folder] rootNode:_root busy:NO]));
  [cleanup setWorksForDirectories:YES];
  XCTAssertTrue(([LDCommandRules isCleanup:cleanup enabledForNodes:@[_file, _folder] rootNode:_root busy:NO]));
  XCTAssertFalse(([LDCommandRules isCleanup:cleanup enabledForNodes:@[_root] rootNode:_root busy:NO]));
  [cleanup setWorksForMountPoints:YES];
  XCTAssertTrue(([LDCommandRules isCleanup:cleanup enabledForNodes:@[_root, _mount] rootNode:_root busy:NO]));
  XCTAssertFalse(([LDCommandRules isCleanup:cleanup enabledForNodes:@[_root] rootNode:_root busy:YES]));
}

- (void)testTopmostNodesDropDescendants
{
  NSArray *topmost = [LDCommandRules topmostNodes:@[_file, _folder, _file]];
  NSArray *folders = [LDCommandRules folderNodesForNodes:@[_file, _folder, _root]];
  XCTAssertEqualObjects((@[_folder]), topmost);
  XCTAssertEqualObjects((@[_folder, _root]), folders);
}

- (void)testEmptyTrashTitleCountsItemsAndSize
{
  XCTAssertTrue([[LDCommandRules emptyTrashTitleForItems:1 bytes:0 complete:YES] hasPrefix:@"Empty Trash (1 Item, "]);
  // A trash that could not be read is not shown as empty.
  XCTAssertEqualObjects(@"Empty Trash…", [LDCommandRules emptyTrashTitleForItems:NSNotFound bytes:0 complete:NO]);
  NSString *title = [LDCommandRules emptyTrashTitleForItems:3 bytes:2048 complete:NO];
  XCTAssertTrue([title hasPrefix:@"Empty Trash (3 Items, "]);
  XCTAssertTrue([title hasSuffix:@"+)…"]);
}

@end
