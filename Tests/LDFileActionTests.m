#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileActionPlan.h"
#import "LDFileActions.h"

@interface LDFileActionTests : XCTestCase
@end

@implementation LDFileActionTests

- (NSString *)fixturePath
{
  return [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Tests/Fixtures/basic-tree/readme.txt"];
}

- (void)testRevealAndOpenPlansAreNonDestructive
{
  LDFileActionPlan *reveal = [LDFileActions revealPlanForPath:[self fixturePath]];
  LDFileActionPlan *open = [LDFileActions openPlanForPath:[self fixturePath]];

  XCTAssertTrue([reveal isAllowed]);
  XCTAssertFalse([reveal isDestructive]);
  XCTAssertFalse([reveal requiresConfirmation]);
  XCTAssertTrue([open isAllowed]);
  XCTAssertFalse([open isDestructive]);
}

- (void)testTrashPlanRequiresConfirmation
{
  LDFileActionPlan *trash = [LDFileActions trashPlanForPath:[self fixturePath]];

  XCTAssertTrue([trash isAllowed]);
  XCTAssertTrue([trash isDestructive]);
  XCTAssertTrue([trash requiresConfirmation]);
}

- (void)testPermanentDeleteIsNotAllowedByDefault
{
  LDFileActionPlan *deletePlan = [LDFileActions permanentDeletePlanForPath:[self fixturePath]];

  XCTAssertFalse([deletePlan isAllowed]);
  XCTAssertTrue([deletePlan isDestructive]);
  XCTAssertTrue([deletePlan requiresConfirmation]);
}

- (void)testMissingPathPlanIsRejected
{
  LDFileActionPlan *plan = [LDFileActions openPlanForPath:[[self fixturePath] stringByAppendingString:@".missing"]];

  XCTAssertFalse([plan isAllowed]);
  XCTAssertEqualObjects(@"The selected path no longer exists.", [plan message]);
}

@end
