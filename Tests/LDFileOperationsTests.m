#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDDesktop.h"
#import "LDFileOperations.h"

#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

@interface LDFileOperationsTests : XCTestCase
{
  NSString *_temporaryRoot;
  NSString *_savedDataHome;
}
@end

@implementation LDFileOperationsTests

- (void)setUp
{
  [super setUp];
  NSString *name = [NSString stringWithFormat:@"lindirstat-ops-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
  _temporaryRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
  [[NSFileManager defaultManager] createDirectoryAtPath:[_temporaryRoot stringByAppendingPathComponent:@"data"]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
  // The home trash goes to a private $XDG_DATA_HOME on the same filesystem.
  const char *saved = getenv("XDG_DATA_HOME");
  _savedDataHome = saved ? [NSString stringWithUTF8String:saved] : nil;
  setenv("XDG_DATA_HOME", [[_temporaryRoot stringByAppendingPathComponent:@"xdg"] fileSystemRepresentation], 1);
  mkdir([[_temporaryRoot stringByAppendingPathComponent:@"xdg"] fileSystemRepresentation], 0700);
}

- (void)tearDown
{
  if (_savedDataHome) {
    setenv("XDG_DATA_HOME", [_savedDataHome fileSystemRepresentation], 1);
  } else {
    unsetenv("XDG_DATA_HOME");
  }
  [[NSFileManager defaultManager] removeItemAtPath:_temporaryRoot error:NULL];
  [super tearDown];
}

- (NSData *)bytesOf:(NSString *)path
{
  const char *bytes = [path fileSystemRepresentation];
  return [NSData dataWithBytes:bytes length:strlen(bytes)];
}

- (NSString *)dataPath:(NSString *)name
{
  return [[_temporaryRoot stringByAppendingPathComponent:@"data"] stringByAppendingPathComponent:name];
}

- (NSString *)trashPath:(NSString *)relative
{
  return [[_temporaryRoot stringByAppendingPathComponent:@"xdg/Trash"] stringByAppendingPathComponent:relative];
}

- (void)writeFile:(NSString *)path
{
  [[@"hello" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:NO];
}

#if !defined(__APPLE__)
// freedesktop.org trash and file manager; macOS uses its own.
- (void)testTrashMovesItemAndWritesInfo
{
  NSString *file = [self dataPath:@"report 1.txt"];
  [self writeFile:file];
  NSError *error = nil;

  XCTAssertTrue([LDFileOperations moveToTrash:[self bytesOf:file] error:&error]);
  XCTAssertNil(error);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:file]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[self trashPath:@"files/report 1.txt"]]);

  NSString *info = [NSString stringWithContentsOfFile:[self trashPath:@"info/report 1.txt.trashinfo"]
                                             encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertTrue([info hasPrefix:@"[Trash Info]\nPath="]);
  XCTAssertTrue([info rangeOfString:@"/data/report%201.txt\n"].location != NSNotFound);
  XCTAssertTrue([info rangeOfString:@"\nDeletionDate="].location != NSNotFound);
}
#endif

#if !defined(__APPLE__)
// freedesktop.org trash and file manager; macOS uses its own.
- (void)testTrashDoesNotOverwriteEarlierItemWithTheSameName
{
  NSString *file = [self dataPath:@"same.txt"];
  [self writeFile:file];
  XCTAssertTrue([LDFileOperations moveToTrash:[self bytesOf:file] error:NULL]);
  [self writeFile:file];
  XCTAssertTrue([LDFileOperations moveToTrash:[self bytesOf:file] error:NULL]);

  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[self trashPath:@"files/same.txt"]]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[self trashPath:@"files/same.txt.2"]]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[self trashPath:@"info/same.txt.2.trashinfo"]]);
}
#endif

#if !defined(__APPLE__)
// freedesktop.org trash and file manager; macOS uses its own.
- (void)testTrashMovesDirectoriesAndNamesThatAreNotUTF8
{
  NSMutableData *directory = [[self bytesOf:[self dataPath:@""]] mutableCopy];
  [directory appendBytes:"/caf\xe9\0" length:6];
  XCTAssertEqual(0, mkdir([directory bytes], 0755));
  [directory setLength:[directory length] - 1];

  XCTAssertTrue([LDFileOperations moveToTrash:directory error:NULL]);
  NSMutableData *trashed = [[self bytesOf:[self trashPath:@"files/"]] mutableCopy];
  [trashed appendBytes:"/caf\xe9\0" length:6];
  struct stat info;
  XCTAssertEqual(0, lstat([trashed bytes], &info));
  XCTAssertTrue(S_ISDIR(info.st_mode));
  NSString *infoText = [NSString stringWithContentsOfFile:[self trashPath:@"info/café.trashinfo"]
                                                 encoding:NSUTF8StringEncoding error:NULL];
  (void)infoText; // The info name is the raw bytes too, checked below.
  NSMutableData *infoPath = [[self bytesOf:[self trashPath:@"info/"]] mutableCopy];
  [infoPath appendBytes:"/caf\xe9.trashinfo\0" length:16];
  XCTAssertEqual(0, lstat([infoPath bytes], &info));
}
#endif

- (void)testTrashOfMissingItemFails
{
  NSError *error = nil;
  XCTAssertFalse([LDFileOperations moveToTrash:[self bytesOf:[self dataPath:@"missing"]] error:&error]);
  XCTAssertEqual((NSInteger)ENOENT, [error code]);
}

#if !defined(__APPLE__)
// freedesktop.org trash and file manager; macOS uses its own.
- (void)testTrashKeepsSymlinkAndItsTarget
{
  NSString *target = [self dataPath:@"target.txt"];
  NSString *link = [self dataPath:@"link"];
  [self writeFile:target];
  XCTAssertEqual(0, symlink([target fileSystemRepresentation], [link fileSystemRepresentation]));

  XCTAssertTrue([LDFileOperations moveToTrash:[self bytesOf:link] error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:target]);
  struct stat info;
  XCTAssertEqual(0, lstat([[self trashPath:@"files/link"] fileSystemRepresentation], &info));
  XCTAssertTrue(S_ISLNK(info.st_mode));
}
#endif

- (void)testPermanentDeleteRemovesTreeButNotSymlinkTargets
{
  NSString *outside = [self dataPath:@"keep.txt"];
  [self writeFile:outside];
  NSString *tree = [self dataPath:@"tree"];
  [[NSFileManager defaultManager] createDirectoryAtPath:[tree stringByAppendingPathComponent:@"a/b"]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
  [self writeFile:[tree stringByAppendingPathComponent:@"a/b/c.txt"]];
  XCTAssertEqual(0, symlink([[self dataPath:@""] fileSystemRepresentation],
                            [[tree stringByAppendingPathComponent:@"a/up"] fileSystemRepresentation]));

  NSError *error = nil;
  XCTAssertTrue([LDFileOperations deletePermanently:[self bytesOf:tree] error:&error]);
  XCTAssertNil(error);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:tree]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:outside]);
}

- (void)testPermanentDeleteReportsWhatItCouldNotRemove
{
  if (getuid() == 0) {
    return; // root ignores permissions
  }
  NSString *tree = [self dataPath:@"locked"];
  NSString *inner = [tree stringByAppendingPathComponent:@"inner"];
  [[NSFileManager defaultManager] createDirectoryAtPath:inner withIntermediateDirectories:YES attributes:nil error:NULL];
  [self writeFile:[inner stringByAppendingPathComponent:@"stuck.txt"]];
  [self writeFile:[tree stringByAppendingPathComponent:@"free.txt"]];
  chmod([inner fileSystemRepresentation], 0555);

  NSError *error = nil;
  XCTAssertFalse([LDFileOperations deletePermanently:[self bytesOf:tree] error:&error]);
  XCTAssertEqual((NSInteger)EACCES, [error code]);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[tree stringByAppendingPathComponent:@"free.txt"]]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[inner stringByAppendingPathComponent:@"stuck.txt"]]);
  chmod([inner fileSystemRepresentation], 0755);
}

- (void)testPercentEncodingKeepsUnreservedBytes
{
  NSData *path = [NSData dataWithBytes:"/a b/%c\xe9,d" length:10];
  XCTAssertEqualObjects(@"/a%20b/%25c%E9%2Cd", [LDFileOperations percentEncodedPath:path]);
  XCTAssertEqualObjects(@"file:///a%20b/%25c%E9%2Cd", [LDDesktop fileURIForPath:path]);
}

#if !defined(__APPLE__)
// freedesktop.org trash and file manager; macOS uses its own.
- (void)testRevealUsesFileManagerInterfaceThenParentFolder
{
  NSArray *commands = [LDDesktop revealCommandsForPath:[NSData dataWithBytes:"/srv/x y" length:8]];
  XCTAssertEqualObjects(@"gdbus", [[commands objectAtIndex:0] objectAtIndex:0]);
  XCTAssertTrue([[commands objectAtIndex:0] containsObject:@"['file:///srv/x%20y']"]);
  NSArray *fallback = [commands lastObject];
  XCTAssertEqualObjects(@"xdg-open", [fallback objectAtIndex:0]);
  XCTAssertEqualObjects([NSData dataWithBytes:"/srv" length:4], [fallback objectAtIndex:1]);
}
#else
- (void)testRevealUsesFinder
{
  NSArray *commands = [LDDesktop revealCommandsForPath:[NSData dataWithBytes:"/srv/x y" length:8]];
  XCTAssertEqualObjects((@[@[@"open", @"-R", [NSData dataWithBytes:"/srv/x y" length:8]]]), commands);
}

- (void)testNoFreedesktopTrashOnMacOS
{
  XCTAssertEqual((NSUInteger)0, [[LDFileOperations existingTrashDirectories] count]);
}
#endif

- (void)testCommandsRunUntilOneSucceeds
{
  __block BOOL finished = NO;
  __block BOOL result = NO;
  NSArray *commands = @[@[@"lindirstat-no-such-program"], @[@"false"], @[@"true"]];
  [LDDesktop runFirstSuccessfulCommand:commands inDirectory:nil completion:^(BOOL succeeded) {
    result = succeeded;
    finished = YES;
  }];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!finished && [deadline timeIntervalSinceNow] > 0) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  XCTAssertTrue(finished);
  XCTAssertTrue(result);
}

- (void)testMoveRefusesToReplaceAndMovesIntoFolder
{
  NSString *file = [self dataPath:@"move-me.txt"];
  NSString *destination = [self dataPath:@"dest"];
  [self writeFile:file];
  [[NSFileManager defaultManager] createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:NULL];
  [self writeFile:[destination stringByAppendingPathComponent:@"move-me.txt"]];

  NSError *error = nil;
  XCTAssertFalse([LDFileOperations moveItem:[self bytesOf:file] toDirectory:[self bytesOf:destination] error:&error]);
  XCTAssertEqual((NSInteger)EEXIST, [error code]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:file]);

  [[NSFileManager defaultManager] removeItemAtPath:[destination stringByAppendingPathComponent:@"move-me.txt"] error:NULL];
  XCTAssertTrue([LDFileOperations moveItem:[self bytesOf:file] toDirectory:[self bytesOf:destination] error:NULL]);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:file]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[destination stringByAppendingPathComponent:@"move-me.txt"]]);
}

#if !defined(__APPLE__)
// freedesktop.org trash and file manager; macOS uses its own.
- (void)testEmptyTrashRemovesTrashedItems
{
  NSString *file = [self dataPath:@"old.log"];
  [self writeFile:file];
  XCTAssertTrue([LDFileOperations moveToTrash:[self bytesOf:file] error:NULL]);
  NSData *trash = [self bytesOf:[_temporaryRoot stringByAppendingPathComponent:@"xdg/Trash"]];
  XCTAssertTrue([[LDFileOperations existingTrashDirectories] containsObject:trash]);

  XCTAssertTrue([LDFileOperations emptyTrashDirectories:@[trash] error:NULL]);
  XCTAssertEqual((NSUInteger)0, [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self trashPath:@"files"] error:NULL] count]);
  XCTAssertEqual((NSUInteger)0, [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self trashPath:@"info"] error:NULL] count]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[self trashPath:@"files"]]);
}
#endif

- (void)testTrashDirectoriesMustNotBeSymlinks
{
  // A home trash reached through a symlink is not emptied: the link could
  // point anywhere (spec: trash directories must not be symlinks).
  NSString *elsewhere = [self dataPath:@"elsewhere"];
  for (NSString *part in @[@"files", @"info"]) {
    [[NSFileManager defaultManager] createDirectoryAtPath:[elsewhere stringByAppendingPathComponent:part]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
  }
  [self writeFile:[elsewhere stringByAppendingPathComponent:@"files/precious.txt"]];
  NSString *trash = [_temporaryRoot stringByAppendingPathComponent:@"xdg/Trash"];
  XCTAssertEqual(0, symlink([elsewhere fileSystemRepresentation], [trash fileSystemRepresentation]));

  XCTAssertFalse([[LDFileOperations existingTrashDirectories] containsObject:[self bytesOf:trash]]);
}

@end
