#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDTabCycle.h"

@interface LDTabCycleTests : XCTestCase
@end

@implementation LDTabCycleTests

- (NSInteger)from:(NSInteger)current tabs:(NSUInteger)tabs extensions:(BOOL)extensions forward:(BOOL)forward
{
  return [LDTabCycle nextFocusFrom:current visibleTabs:tabs extensionListVisible:extensions forward:forward];
}

- (void)testTabWalksTheTabsThenTheExtensionListThenBack
{
  // All Files, Largest, Duplicates, Search.
  XCTAssertEqual((NSInteger)1, [self from:0 tabs:4 extensions:YES forward:YES]);
  XCTAssertEqual((NSInteger)3, [self from:2 tabs:4 extensions:YES forward:YES]);
  XCTAssertEqual((NSInteger)LDFocusExtensionList, [self from:3 tabs:4 extensions:YES forward:YES]);
  XCTAssertEqual((NSInteger)0, [self from:LDFocusExtensionList tabs:4 extensions:YES forward:YES]);
}

- (void)testShiftTabWalksBackwards
{
  XCTAssertEqual((NSInteger)LDFocusExtensionList, [self from:0 tabs:2 extensions:YES forward:NO]);
  XCTAssertEqual((NSInteger)1, [self from:LDFocusExtensionList tabs:2 extensions:YES forward:NO]);
  XCTAssertEqual((NSInteger)0, [self from:1 tabs:2 extensions:YES forward:NO]);
}

- (void)testWithoutTheExtensionListTabsWrap
{
  XCTAssertEqual((NSInteger)0, [self from:1 tabs:2 extensions:NO forward:YES]);
  XCTAssertEqual((NSInteger)1, [self from:0 tabs:2 extensions:NO forward:NO]);
}

- (void)testFromElsewhereTabGoesToTheTree
{
  XCTAssertEqual((NSInteger)0, [self from:LDFocusOther tabs:3 extensions:YES forward:YES]);
  XCTAssertEqual((NSInteger)0, [self from:LDFocusOther tabs:3 extensions:YES forward:NO]);
}

@end
