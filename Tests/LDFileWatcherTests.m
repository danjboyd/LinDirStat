#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileWatcher.h"
#import "LDFileWatcherLinux.h"

#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#if !defined(__APPLE__)
#include <sys/inotify.h>
#endif

@interface LDFileWatcherTests : XCTestCase
{
  NSString *_temporaryRoot;
}
@end

static NSData *LDBytes(NSString *path)
{
  const char *bytes = [path fileSystemRepresentation];
  return [NSData dataWithBytes:bytes length:strlen(bytes)];
}

@implementation LDFileWatcherTests

- (void)setUp
{
  [super setUp];
  NSString *name = [NSString stringWithFormat:@"lindirstat-watch-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
  _temporaryRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
  [[NSFileManager defaultManager] createDirectoryAtPath:_temporaryRoot withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
  [[NSFileManager defaultManager] removeItemAtPath:_temporaryRoot error:NULL];
  [super tearDown];
}

- (void)testActionTitlesAreWinDirStats
{
  XCTAssertEqualObjects(@"Created", [LDFileWatcherEvent titleForAction:LDFileWatcherActionCreated]);
  XCTAssertEqualObjects(@"Deleted", [LDFileWatcherEvent titleForAction:LDFileWatcherActionDeleted]);
  XCTAssertEqualObjects(@"Modified", [LDFileWatcherEvent titleForAction:LDFileWatcherActionModified]);
  XCTAssertEqualObjects(@"Renamed (Old)", [LDFileWatcherEvent titleForAction:LDFileWatcherActionRenamedOld]);
  XCTAssertEqualObjects(@"Renamed (New)", [LDFileWatcherEvent titleForAction:LDFileWatcherActionRenamedNew]);
}

// WinDirStat 2.7's quick filter (329f9c91): a case-insensitive expression
// found anywhere in the path; empty matches everything, invalid is refused.
- (void)testPathFilter
{
  LDFileWatcherEvent *log = [LDFileWatcherEvent eventWithPathData:LDBytes(@"/srv/Logs/app.LOG") action:LDFileWatcherActionModified
                                                             time:1 logicalSize:1 isDirectory:NO];
  LDFileWatcherEvent *tmp = [LDFileWatcherEvent eventWithPathData:LDBytes(@"/srv/tmp/x.tmp") action:LDFileWatcherActionCreated
                                                             time:2 logicalSize:1 isDirectory:NO];
  const char raw[] = {'/', 's', 'r', 'v', '/', (char)0xff, '.', 'b', 'i', 'n'};
  LDFileWatcherEvent *latin = [LDFileWatcherEvent eventWithPathData:[NSData dataWithBytes:raw length:sizeof(raw)]
                                                             action:LDFileWatcherActionDeleted time:3 logicalSize:0 isDirectory:NO];

  LDFileWatcherPathFilter *all = [LDFileWatcherPathFilter filterWithPattern:@""];
  XCTAssertNotNil(all);
  XCTAssertTrue([all matchesEvent:log]);
  XCTAssertTrue([all matchesEvent:latin]);

  LDFileWatcherPathFilter *logs = [LDFileWatcherPathFilter filterWithPattern:@"\\.log$"];
  XCTAssertTrue([logs matchesEvent:log]);
  XCTAssertFalse([logs matchesEvent:tmp]);

  LDFileWatcherPathFilter *folder = [LDFileWatcherPathFilter filterWithPattern:@"logs|tmp"];
  XCTAssertTrue([folder matchesEvent:log]);
  XCTAssertTrue([folder matchesEvent:tmp]);
  XCTAssertTrue([[LDFileWatcherPathFilter filterWithPattern:@"bin$"] matchesEvent:latin]);

  XCTAssertNil([LDFileWatcherPathFilter filterWithPattern:@"("]);
  XCTAssertNil([LDFileWatcherPathFilter filterWithPattern:@"[a-"]);
}

- (void)testEventKeepsExactBytes
{
  const char raw[] = "/tmp/caf\xe9";
  NSData *path = [NSData dataWithBytes:raw length:strlen(raw)];
  LDFileWatcherEvent *event = [LDFileWatcherEvent eventWithPathData:path action:LDFileWatcherActionDeleted time:5 logicalSize:7 isDirectory:NO];
  XCTAssertEqualObjects(path, [event pathData]);
  XCTAssertTrue([[event path] hasPrefix:@"/tmp/caf"]);
  XCTAssertEqual(7ULL, [event logicalSize]);
}

#if !defined(__APPLE__)

#pragma mark - Translation

// Appends one raw inotify event, padded as the kernel pads names.
- (void)append:(NSMutableData *)buffer watch:(int)watch mask:(uint32_t)mask cookie:(uint32_t)cookie name:(const char *)name
{
  size_t nameLength = name ? strlen(name) + 1 : 0;
  size_t padded = nameLength ? (nameLength + 15) / 16 * 16 : 0;
  struct inotify_event header;
  memset(&header, 0, sizeof(header));
  header.wd = watch;
  header.mask = mask;
  header.cookie = cookie;
  header.len = (uint32_t)padded;
  [buffer appendBytes:&header length:sizeof(header)];
  NSMutableData *nameBytes = [NSMutableData dataWithLength:padded];
  if (name) {
    memcpy([nameBytes mutableBytes], name, strlen(name));
  }
  [buffer appendData:nameBytes];
}

- (LDInotifyTranslator *)translator
{
  LDInotifyTranslator *translator = [[LDInotifyTranslator alloc] initWithRootPaths:@[LDBytes(@"/w")]];
  [translator setPath:LDBytes(@"/w") forWatch:1];
  [translator setPath:LDBytes(@"/w/sub") forWatch:2];
  [translator setPath:LDBytes(@"/w/sub/deeper") forWatch:3];
  return translator;
}

- (void)testTranslatesCreateModifyDelete
{
  LDInotifyTranslator *translator = [self translator];
  NSMutableData *buffer = [NSMutableData data];
  [self append:buffer watch:1 mask:IN_CREATE cookie:0 name:"a.txt"];
  [self append:buffer watch:2 mask:IN_MODIFY cookie:0 name:"b.txt"];
  [self append:buffer watch:2 mask:IN_MODIFY | IN_ISDIR cookie:0 name:"deeper"];
  [self append:buffer watch:1 mask:IN_DELETE cookie:0 name:"c.txt"];
  [self append:buffer watch:9 mask:IN_CREATE cookie:0 name:"unknown-watch"];
  NSArray *events = [translator eventsForBuffer:[buffer bytes] length:[buffer length] time:1];
  NSArray *expected = @[@"Created /w/a.txt", @"Modified /w/sub/b.txt", @"Deleted /w/c.txt"];
  XCTAssertEqualObjects(expected, [self describe:events]);
}

- (void)testPairsRenamesAndMovesWatchesOfRenamedFolders
{
  LDInotifyTranslator *translator = [self translator];
  NSMutableData *buffer = [NSMutableData data];
  [self append:buffer watch:1 mask:IN_MOVED_FROM | IN_ISDIR cookie:7 name:"sub"];
  [self append:buffer watch:1 mask:IN_MOVED_TO | IN_ISDIR cookie:7 name:"renamed"];
  NSArray *events = [translator eventsForBuffer:[buffer bytes] length:[buffer length] time:1];
  NSArray *expected = @[@"Renamed (Old) /w/sub", @"Renamed (New) /w/renamed"];
  XCTAssertEqualObjects(expected, [self describe:events]);
  XCTAssertEqualObjects(LDBytes(@"/w/renamed"), [translator pathForWatch:2]);
  XCTAssertEqualObjects(LDBytes(@"/w/renamed/deeper"), [translator pathForWatch:3]);
  XCTAssertEqualObjects(LDBytes(@"/w"), [translator pathForWatch:1]);
}

- (void)testUnpairedMovesAreDeletionsAndCreations
{
  LDInotifyTranslator *translator = [self translator];
  NSMutableData *buffer = [NSMutableData data];
  [self append:buffer watch:1 mask:IN_MOVED_FROM | IN_ISDIR cookie:3 name:"sub"];
  [self append:buffer watch:1 mask:IN_MOVED_TO | IN_ISDIR cookie:4 name:"incoming"];
  NSArray *events = [translator eventsForBuffer:[buffer bytes] length:[buffer length] time:1];
  // The moved-from half is held until its moved-to arrives or time runs out.
  XCTAssertEqualObjects(@[@"Created /w/incoming"], [self describe:events]);
  XCTAssertEqualObjects(@[LDBytes(@"/w/incoming")], [translator directoriesMovedIn]);
  XCTAssertEqual(0U, [[translator directoriesCreated] count]);
  XCTAssertTrue([translator hasPendingMoves]);
  XCTAssertEqual(0U, [[translator flushPendingMovesBefore:1] count]);

  NSArray *flushed = [translator flushPendingMovesBefore:2];
  XCTAssertEqualObjects(@[@"Deleted /w/sub"], [self describe:flushed]);
  XCTAssertFalse([translator hasPendingMoves]);
  // The folder that left keeps no watches.
  NSArray *removed = [[translator watchesToRemove] sortedArrayUsingSelector:@selector(compare:)];
  XCTAssertEqualObjects((@[@2, @3]), removed);
  XCTAssertNil([translator pathForWatch:2]);
}

- (void)testRenameSplitAcrossReadsIsStillARename
{
  LDInotifyTranslator *translator = [self translator];
  NSMutableData *first = [NSMutableData data];
  [self append:first watch:1 mask:IN_MOVED_FROM | IN_ISDIR cookie:7 name:"sub"];
  NSMutableData *second = [NSMutableData data];
  [self append:second watch:1 mask:IN_MOVED_TO | IN_ISDIR cookie:7 name:"renamed"];

  XCTAssertEqual(0U, [[translator eventsForBuffer:[first bytes] length:[first length] time:1] count]);
  NSArray *events = [translator eventsForBuffer:[second bytes] length:[second length] time:1];
  NSArray *expected = @[@"Renamed (Old) /w/sub", @"Renamed (New) /w/renamed"];
  XCTAssertEqualObjects(expected, [self describe:events]);
  XCTAssertFalse([translator hasPendingMoves]);
  XCTAssertEqualObjects(LDBytes(@"/w/renamed"), [translator pathForWatch:2]);
}

- (void)testNewFoldersOverflowAndRemovedRoot
{
  LDInotifyTranslator *translator = [self translator];
  NSMutableData *buffer = [NSMutableData data];
  [self append:buffer watch:1 mask:IN_CREATE | IN_ISDIR cookie:0 name:"new"];
  [self append:buffer watch:-1 mask:IN_Q_OVERFLOW cookie:0 name:NULL];
  [self append:buffer watch:1 mask:IN_DELETE_SELF cookie:0 name:NULL];
  [self append:buffer watch:3 mask:IN_IGNORED cookie:0 name:NULL];
  NSArray *events = [translator eventsForBuffer:[buffer bytes] length:[buffer length] time:1];
  XCTAssertEqualObjects(@[@"Created /w/new"], [self describe:events]);
  XCTAssertEqualObjects(@[LDBytes(@"/w/new")], [translator directoriesCreated]);
  XCTAssertEqual(2U, [[translator messages] count]);
  XCTAssertTrue([[[translator messages] objectAtIndex:0] rangeOfString:@"Too many changes"].location != NSNotFound);
  XCTAssertTrue([[[translator messages] objectAtIndex:1] rangeOfString:@"/w was removed"].location != NSNotFound);
  XCTAssertNil([translator pathForWatch:3]);
}

- (void)testIgnoresTruncatedBuffers
{
  LDInotifyTranslator *translator = [self translator];
  NSMutableData *buffer = [NSMutableData data];
  [self append:buffer watch:1 mask:IN_CREATE cookie:0 name:"a-long-file-name.txt"];
  NSArray *events = [translator eventsForBuffer:[buffer bytes] length:[buffer length] - 8 time:1];
  XCTAssertEqual(0U, [events count]);
}

#endif

#pragma mark - Watching a folder

- (NSArray *)describe:(NSArray *)events
{
  NSMutableArray *lines = [NSMutableArray array];
  for (LDFileWatcherEvent *event in events) {
    [lines addObject:[event description]];
  }
  return lines;
}


// Starts watcher, collecting its events into received, and returns once
// it is watching everything already there: -startWithError: sets the
// watches up in the background, the root's and every folder's below it, so
// a change made at once can be missed (#96). A probe file in each existing
// folder of the first root is rewritten until the watcher has reported every
// one; probe events are left out of received.
- (BOOL)start:(LDFileWatcher *)watcher collectingInto:(NSMutableArray *)received
{
  NSData *rootBytes = [[watcher rootPaths] firstObject];
  NSFileManager *manager = [NSFileManager defaultManager];
  NSString *root = [manager stringWithFileSystemRepresentation:[rootBytes bytes] length:[rootBytes length]];
  NSMutableSet *pending = [NSMutableSet setWithObject:root];
  NSDirectoryEnumerator *walk = [manager enumeratorAtPath:root];
  for (NSString *relative in walk) {
    if ([[[walk fileAttributes] fileType] isEqualToString:NSFileTypeDirectory]) {
      [pending addObject:[root stringByAppendingPathComponent:relative]];
    }
  }
  NSArray *folders = [pending allObjects];
  [watcher setEventHandler:^(NSArray *events) {
    for (LDFileWatcherEvent *event in events) {
      if ([[[event path] lastPathComponent] isEqualToString:@".lindirstat-watch-probe"]) {
        [pending removeObject:[[event path] stringByDeletingLastPathComponent]];
      } else {
        [received addObject:event];
      }
    }
  }];
  NSError *error = nil;
  if (![watcher startWithError:&error]) {
    XCTFail(@"%@", error);
    return NO;
  }
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
  for (NSUInteger i = 0; [pending count] > 0 && [deadline timeIntervalSinceNow] > 0; i++) {
    for (NSString *folder in folders) {
      if ([pending containsObject:folder]) {
        NSString *probe = [folder stringByAppendingPathComponent:@".lindirstat-watch-probe"];
        [[NSString stringWithFormat:@"%lu", (unsigned long)i] writeToFile:probe atomically:NO encoding:NSUTF8StringEncoding error:NULL];
      }
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  }
  XCTAssertEqual((NSUInteger)0, [pending count], @"not watching yet: %@", pending);
  return [pending count] == 0;
}

- (NSArray *)eventsWhileRunning:(void (^)(void))changes watcher:(LDFileWatcher *)watcher until:(BOOL (^)(NSArray *events))done
{
  NSMutableArray *received = [NSMutableArray array];
  if (![self start:watcher collectingInto:received]) {
    [watcher stop];
    return @[];
  }
  changes();
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
  while (!done(received) && [deadline timeIntervalSinceNow] > 0) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  }
  [watcher stop];
  return [self describe:received];
}

- (NSString *)write:(NSString *)text to:(NSString *)relative
{
  NSString *path = [_temporaryRoot stringByAppendingPathComponent:relative];
  [text writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
  return path;
}

- (void)testReportsChangesBelowTheRootRecursively
{
  NSFileManager *manager = [NSFileManager defaultManager];
  [manager createDirectoryAtPath:[_temporaryRoot stringByAppendingPathComponent:@"existing/deep"] withIntermediateDirectories:YES attributes:nil error:NULL];
  [self write:@"old" to:@"existing/deep/file.txt"];
  LDFileWatcher *watcher = [[LDFileWatcher alloc] initWithRootPaths:@[LDBytes(_temporaryRoot)]];
  NSString *root = _temporaryRoot;
  NSArray *lines = [self eventsWhileRunning:^{
    [self write:@"hello" to:@"existing/deep/file.txt"];
    [manager moveItemAtPath:[root stringByAppendingPathComponent:@"existing/deep/file.txt"]
                     toPath:[root stringByAppendingPathComponent:@"existing/renamed.txt"]
                      error:NULL];
    [manager createDirectoryAtPath:[root stringByAppendingPathComponent:@"fresh"] withIntermediateDirectories:NO attributes:nil error:NULL];
    [self write:@"inside" to:@"fresh/inner.txt"];
    [manager removeItemAtPath:[root stringByAppendingPathComponent:@"existing/renamed.txt"] error:NULL];
  } watcher:watcher until:^BOOL(NSArray *events) {
    for (LDFileWatcherEvent *event in events) {
      if ([event action] == LDFileWatcherActionDeleted) {
        return YES;
      }
    }
    return NO;
  }];
  NSString *deep = [root stringByAppendingPathComponent:@"existing/deep/file.txt"];
  NSString *renamed = [root stringByAppendingPathComponent:@"existing/renamed.txt"];
  XCTAssertTrue([lines containsObject:[@"Modified " stringByAppendingString:deep]], @"%@", lines);
  XCTAssertTrue([lines containsObject:[@"Renamed (Old) " stringByAppendingString:deep]], @"%@", lines);
  XCTAssertTrue([lines containsObject:[@"Renamed (New) " stringByAppendingString:renamed]], @"%@", lines);
  XCTAssertTrue([lines containsObject:[@"Created " stringByAppendingString:[root stringByAppendingPathComponent:@"fresh"]]], @"%@", lines);
  XCTAssertTrue([lines containsObject:[@"Created " stringByAppendingString:[root stringByAppendingPathComponent:@"fresh/inner.txt"]]], @"%@", lines);
  XCTAssertTrue([lines containsObject:[@"Deleted " stringByAppendingString:renamed]], @"%@", lines);
  // Repeated writes collapse into one row per batch.
  NSUInteger modified = [[lines indexesOfObjectsPassingTest:^BOOL(NSString *line, NSUInteger index, BOOL *stop) {
    (void)index;
    (void)stop;
    return [line isEqualToString:[@"Modified " stringByAppendingString:deep]];
  }] count];
  XCTAssertEqual(1U, modified);
}

- (void)testReportsTheSizeOfCreatedFiles
{
  LDFileWatcher *watcher = [[LDFileWatcher alloc] initWithRootPaths:@[LDBytes(_temporaryRoot)]];
  NSMutableArray *received = [NSMutableArray array];
  if (![self start:watcher collectingInto:received]) {
    [watcher stop];
    return;
  }
  [self write:@"0123456789" to:@"ten.txt"];
  LDFileWatcherEvent *created = nil;
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
  while (!created && [deadline timeIntervalSinceNow] > 0) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    for (LDFileWatcherEvent *event in received) {
      if ([event action] == LDFileWatcherActionCreated) {
        created = event;
      }
    }
  }
  [watcher stop];
  XCTAssertEqual(10ULL, [created logicalSize]);
  XCTAssertFalse([created isDirectory]);
  XCTAssertTrue([created time] > 0);
}

- (void)testNothingArrivesAfterStop
{
  LDFileWatcher *watcher = [[LDFileWatcher alloc] initWithRootPaths:@[LDBytes(_temporaryRoot)]];
  __block NSUInteger count = 0;
  [watcher setEventHandler:^(NSArray *events) {
    count += [events count];
  }];
  XCTAssertTrue([watcher startWithError:NULL]);
  XCTAssertTrue([watcher isRunning]);
  [self write:@"x" to:@"late.txt"];
  [watcher stop];
  XCTAssertFalse([watcher isRunning]);
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
  XCTAssertEqual(0U, count);
}

- (void)testFailsWhenNoRootCanBeWatched
{
  NSData *missing = LDBytes([_temporaryRoot stringByAppendingPathComponent:@"missing"]);
  LDFileWatcher *watcher = [[LDFileWatcher alloc] initWithRootPaths:@[missing]];
  NSError *error = nil;
  XCTAssertFalse([watcher startWithError:&error]);
  XCTAssertNotNil(error);
  XCTAssertFalse([watcher isRunning]);
}

- (void)testMovesInAndOutOfTheRootAreCreationsAndDeletions
{
  NSFileManager *manager = [NSFileManager defaultManager];
  NSString *watched = [_temporaryRoot stringByAppendingPathComponent:@"watched"];
  NSString *outside = [_temporaryRoot stringByAppendingPathComponent:@"outside"];
  [manager createDirectoryAtPath:watched withIntermediateDirectories:YES attributes:nil error:NULL];
  [manager createDirectoryAtPath:outside withIntermediateDirectories:YES attributes:nil error:NULL];
  [self write:@"in" to:@"outside/incoming.txt"];
  [self write:@"out" to:@"watched/leaving.txt"];
  LDFileWatcher *watcher = [[LDFileWatcher alloc] initWithRootPaths:@[LDBytes(watched)]];
  NSString *incoming = [watched stringByAppendingPathComponent:@"incoming.txt"];
  NSString *leaving = [watched stringByAppendingPathComponent:@"leaving.txt"];
  NSArray *lines = [self eventsWhileRunning:^{
    [manager moveItemAtPath:[outside stringByAppendingPathComponent:@"incoming.txt"] toPath:incoming error:NULL];
    [manager moveItemAtPath:leaving toPath:[outside stringByAppendingPathComponent:@"leaving.txt"] error:NULL];
  } watcher:watcher until:^BOOL(NSArray *events) {
    return [events count] >= 2;
  }];
  XCTAssertTrue([lines containsObject:[@"Created " stringByAppendingString:incoming]], @"%@", lines);
  XCTAssertTrue([lines containsObject:[@"Deleted " stringByAppendingString:leaving]], @"%@", lines);
  // A move is not a creation of the item that left. (FSEvents may also
  // report the write made just before watching began as Modified.)
  XCTAssertFalse([lines containsObject:[@"Created " stringByAppendingString:leaving]], @"%@", lines);
  XCTAssertFalse([lines containsObject:[@"Deleted " stringByAppendingString:incoming]], @"%@", lines);
}

- (void)testIsSupported
{
  XCTAssertTrue([LDFileWatcher isSupported]);
}

@end
