#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDExtensionStats.h"
#import "LDScanner.h"
#import "LDScanSession.h"

@interface LDScannerTests : XCTestCase
@end

@implementation LDScannerTests

- (NSString *)fixturePath
{
  return [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Tests/Fixtures/basic-tree"];
}

- (void)testScansFixtureTreeDeterministically
{
  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  LDScanSession *session = [[[LDScanSession alloc] init] autorelease];

  LDFileNode *root = [scanner scanPath:[self fixturePath] session:session];

  XCTAssertNotNil(root);
  XCTAssertEqual(LDScanSessionStateComplete, [session state]);
  XCTAssertEqual((unsigned long long)40, [root aggregateSize]);
  XCTAssertEqual((NSUInteger)4, [root fileCount]);
  XCTAssertEqual((NSUInteger)2, [root directoryCount]);
  XCTAssertEqual((NSUInteger)0, [session errorCount]);
}

- (void)testScannedTreeProducesExtensionStats
{
  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  LDScanSession *session = [[[LDScanSession alloc] init] autorelease];
  LDFileNode *root = [scanner scanPath:[self fixturePath] session:session];

  NSArray *stats = [LDExtensionStats sortedStatsForRootNode:root];
  LDExtensionStats *largest = [stats objectAtIndex:0];

  XCTAssertEqualObjects(@"txt", [largest extensionKey]);
  XCTAssertEqual((NSUInteger)2, [largest fileCount]);
  XCTAssertEqual((unsigned long long)22, [largest bytes]);
}

- (void)testMissingPathProducesFailedSession
{
  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  LDScanSession *session = [[[LDScanSession alloc] init] autorelease];
  NSString *missing = [[self fixturePath] stringByAppendingPathComponent:@"does-not-exist"];

  LDFileNode *root = [scanner scanPath:missing session:session];

  XCTAssertNotNil(root);
  XCTAssertEqual(LDScanSessionStateComplete, [session state]);
  XCTAssertEqual((NSUInteger)1, [session errorCount]);
  XCTAssertTrue([[root errorCode] hasPrefix:@"stat_failed:"]);
}

@end
