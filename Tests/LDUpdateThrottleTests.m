#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDUpdateThrottle.h"

@interface LDUpdateThrottleTests : XCTestCase
@end

@implementation LDUpdateThrottleTests

- (void)testTheFirstUpdateRunsAtOnce
{
  LDUpdateThrottle *throttle = [[LDUpdateThrottle alloc] initWithBusyShare:0.05 minimumInterval:0.5];
  XCTAssertEqualWithAccuracy(0.0, [throttle waitAt:1000.0], 0.0001);
}

- (void)testACheapUpdateWaitsTheMinimum
{
  LDUpdateThrottle *throttle = [[LDUpdateThrottle alloc] initWithBusyShare:0.05 minimumInterval:0.5];
  [throttle didUpdateAt:1000.0 duration:0.001];
  XCTAssertEqualWithAccuracy(0.3, [throttle waitAt:1000.2], 0.0001);
  XCTAssertEqualWithAccuracy(0.0, [throttle waitAt:1000.5], 0.0001);
}

// The share holds however slow updates get: 200 ms at 5% is one every 4 s.
- (void)testASlowUpdateWaitsInProportion
{
  LDUpdateThrottle *throttle = [[LDUpdateThrottle alloc] initWithBusyShare:0.05 minimumInterval:0.5];
  [throttle didUpdateAt:1000.0 duration:0.2];
  XCTAssertEqualWithAccuracy(3.5, [throttle waitAt:1000.5], 0.0001);
  XCTAssertEqualWithAccuracy(0.0, [throttle waitAt:1004.0], 0.0001);
}

@end
