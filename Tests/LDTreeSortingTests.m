#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDTreeSorting.h"

@interface LDTreeSortingTests : XCTestCase
@end

@implementation LDTreeSortingTests

- (NSArray *)nodes
{
  LDFileNode *alpha = [LDFileNode nodeWithName:@"alpha" kind:LDFileNodeKindFile size:300 allocatedSize:4096];
  LDFileNode *beta = [LDFileNode nodeWithName:@"Beta" kind:LDFileNodeKindFile size:900 allocatedSize:8192];
  LDFileNode *gamma = [LDFileNode nodeWithName:@"gamma" kind:LDFileNodeKindFile size:100 allocatedSize:4096];
  [alpha setModificationTime:300];
  [beta setModificationTime:100];
  [gamma setModificationTime:200];
  return @[alpha, beta, gamma];
}

- (NSArray *)namesOf:(NSArray *)nodes
{
  NSMutableArray *names = [NSMutableArray array];
  for (LDFileNode *node in nodes) {
    [names addObject:[node displayName]];
  }
  return names;
}

- (void)testNameSortIgnoresCase
{
  NSArray *sorted = [LDTreeSorting sortedNodes:[self nodes] byKey:LDTreeSortKeyName ascending:YES];
  XCTAssertEqualObjects((@[@"alpha", @"Beta", @"gamma"]), [self namesOf:sorted]);
}

- (void)testSizeSortsBreakTiesByPhysicalSizeThenName
{
  NSArray *sorted = [LDTreeSorting sortedNodes:[self nodes] byKey:LDTreeSortKeyPhysicalSize ascending:NO];
  // alpha and gamma share 4096 physical bytes; names break the tie.
  XCTAssertEqualObjects((@[@"Beta", @"alpha", @"gamma"]), [self namesOf:sorted]);
}

- (void)testLogicalSizeAndLastChange
{
  XCTAssertEqualObjects((@[@"gamma", @"alpha", @"Beta"]),
                        [self namesOf:[LDTreeSorting sortedNodes:[self nodes] byKey:LDTreeSortKeyLogicalSize ascending:YES]]);
  XCTAssertEqualObjects((@[@"alpha", @"gamma", @"Beta"]),
                        [self namesOf:[LDTreeSorting sortedNodes:[self nodes] byKey:LDTreeSortKeyLastChange ascending:NO]]);
}

- (void)testDefaultDirections
{
  XCTAssertTrue([LDTreeSorting defaultAscendingForKey:LDTreeSortKeyName]);
  XCTAssertTrue([LDTreeSorting defaultAscendingForKey:LDTreeSortKeyLastChange]);
  XCTAssertFalse([LDTreeSorting defaultAscendingForKey:LDTreeSortKeyPhysicalSize]);
}

@end
