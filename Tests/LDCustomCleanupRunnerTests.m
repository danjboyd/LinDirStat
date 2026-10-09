#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDCustomCleanupRunner.h"
#import "LDPreferences.h"

#include <unistd.h>

@interface LDCustomCleanupRunnerTests : XCTestCase
{
  NSString *_root;
}
@end

@implementation LDCustomCleanupRunnerTests

- (void)setUp
{
  [super setUp];
  NSString *name = [NSString stringWithFormat:@"lindirstat-cleanup-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
  _root = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
  [[NSFileManager defaultManager] createDirectoryAtPath:[_root stringByAppendingPathComponent:@"top/a/deep"]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
  [[NSFileManager defaultManager] createDirectoryAtPath:[_root stringByAppendingPathComponent:@"top/b"]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
  [[NSFileManager defaultManager] removeItemAtPath:_root error:NULL];
  [super tearDown];
}

- (NSData *)bytes:(NSString *)string
{
  return [string dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)testPlaceholdersBecomeQuotedShellParameters
{
  XCTAssertEqualObjects(@"gzip \"${1}\" # \"${2}\" \"${3}\" \"${4}\" 100%",
                        [LDCustomCleanupRunner scriptForTemplate:@"gzip %p # %n %sp %sn 100%"]);
  // WinDirStat users quote the placeholder themselves.
  XCTAssertEqualObjects(@"rm -rf \"${1}\"", [LDCustomCleanupRunner scriptForTemplate:@"rm -rf \"%p\""]);

  NSData *path = [NSData dataWithBytes:"/d/50%n\xe9" length:8];
  NSArray *command = [LDCustomCleanupRunner commandForTemplate:@"x %p" path:path subfolderPath:nil];
  XCTAssertEqualObjects(@"/bin/sh", [command objectAtIndex:0]);
  XCTAssertEqualObjects(path, [command objectAtIndex:4]);
  XCTAssertEqualObjects([NSData dataWithBytes:"50%n\xe9" length:5], [command objectAtIndex:5]);
  XCTAssertEqualObjects(path, [command objectAtIndex:6]);
}

- (void)testNamesAreNeverRunAsShellCode
{
  // A Linux name may contain quotes and command substitutions.
  NSString *hostile = [_root stringByAppendingPathComponent:@"a\" ; touch INJECTED ; \"$(touch INJECTED2)"];
  [[@"x" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:hostile atomically:NO];
  LDCustomCleanup *cleanup = [[LDCustomCleanup alloc] init];
  [cleanup setEnabled:YES];
  [cleanup setWorksForFiles:YES];
  [cleanup setWaitForCompletion:YES];
  [cleanup setCommandLine:@"cat \"%p\" > \"%p.copy\""];
  __block NSArray *ran = nil;
  [LDCustomCleanupRunner runCleanup:cleanup onPaths:@[[self bytes:hostile]] directories:@[@NO] completion:^(NSArray *ranPaths, NSArray *failures) {
    (void)failures;
    ran = ranPaths;
  }];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
  while (!ran && [deadline timeIntervalSinceNow] > 0) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  NSFileManager *files = [NSFileManager defaultManager];
  XCTAssertTrue([files fileExistsAtPath:[hostile stringByAppendingString:@".copy"]]);
  XCTAssertFalse([files fileExistsAtPath:[_root stringByAppendingPathComponent:@"top/INJECTED"]]);
  XCTAssertFalse([files fileExistsAtPath:[_root stringByAppendingPathComponent:@"INJECTED2"]]);
  XCTAssertFalse([files fileExistsAtPath:[_root stringByAppendingPathComponent:@"INJECTED"]]);
}

- (void)testRecursionVisitsChildrenBeforeParents
{
  NSArray *order = [LDCustomCleanupRunner recursionOrderForFolder:[self bytes:[_root stringByAppendingPathComponent:@"top"]]];
  NSMutableArray *relative = [NSMutableArray array];
  for (NSData *folder in order) {
    NSString *path = [[NSString alloc] initWithData:folder encoding:NSUTF8StringEncoding];
    [relative addObject:[path substringFromIndex:[_root length]]];
  }
  XCTAssertEqualObjects((@[@"/top/a/deep", @"/top/a", @"/top/b", @"/top"]), relative);
}

- (void)testRunsCommandInEachFolderWhenRecursing
{
  LDCustomCleanup *cleanup = [[LDCustomCleanup alloc] init];
  [cleanup setEnabled:YES];
  [cleanup setWorksForDirectories:YES];
  [cleanup setRecurseIntoSubdirectories:YES];
  [cleanup setCommandLine:@"touch marker-%sn"];
  __block NSArray *ran = nil;
  __block NSArray *failed = nil;
  NSData *top = [self bytes:[_root stringByAppendingPathComponent:@"top"]];
  [LDCustomCleanupRunner runCleanup:cleanup onPaths:@[top] directories:@[@YES] completion:^(NSArray *ranPaths, NSArray *failures) {
    ran = ranPaths;
    failed = failures;
  }];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
  while (!ran && [deadline timeIntervalSinceNow] > 0) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  XCTAssertEqualObjects((@[top]), ran);
  XCTAssertEqual((NSUInteger)0, [failed count]);
  NSFileManager *files = [NSFileManager defaultManager];
  XCTAssertTrue([files fileExistsAtPath:[_root stringByAppendingPathComponent:@"top/a/deep/marker-deep"]]);
  XCTAssertTrue([files fileExistsAtPath:[_root stringByAppendingPathComponent:@"top/b/marker-b"]]);
  XCTAssertTrue([files fileExistsAtPath:[_root stringByAppendingPathComponent:@"top/marker-top"]]);
}

- (void)testFailingCommandIsReported
{
  LDCustomCleanup *cleanup = [[LDCustomCleanup alloc] init];
  [cleanup setEnabled:YES];
  [cleanup setWorksForFiles:YES];
  [cleanup setWaitForCompletion:YES];
  [cleanup setCommandLine:@"exit 3"];
  __block NSArray *failed = nil;
  NSData *path = [self bytes:[_root stringByAppendingPathComponent:@"top/x.txt"]];
  [LDCustomCleanupRunner runCleanup:cleanup onPaths:@[path] directories:@[@NO] completion:^(NSArray *ranPaths, NSArray *failures) {
    (void)ranPaths;
    failed = failures;
  }];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
  while (!failed && [deadline timeIntervalSinceNow] > 0) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  XCTAssertEqualObjects((@[path]), failed);
}

@end
