#import <Foundation/Foundation.h>

// Paces a slow update of something on screen: how long the last one took sets
// how long until the next, so it costs the main thread a bounded share of its
// time however large the data grows (#170).
@interface LDUpdateThrottle : NSObject

// busyShare is the most of the main thread's time updates may take (0.05 is
// 5%); minimumInterval the shortest wait between updates, in seconds.
- (instancetype)initWithBusyShare:(double)busyShare minimumInterval:(NSTimeInterval)minimumInterval;
// Seconds from now until an update may run; 0 when it may run now.
- (NSTimeInterval)waitAt:(NSTimeInterval)now;
// An update that ran from started for duration seconds.
- (void)didUpdateAt:(NSTimeInterval)started duration:(NSTimeInterval)duration;

@end
