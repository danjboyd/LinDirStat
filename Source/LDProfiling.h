#import <Foundation/Foundation.h>

// Opt-in timing for performance work (docs/performance.md). With
// LINDIRSTAT_PROFILE=1 in the environment the app logs the steps of a scan's
// completion and every main-thread stall to stderr; otherwise all of this is
// a no-op.
@interface LDProfiling : NSObject

+ (BOOL)isEnabled;
// Seconds since an arbitrary fixed point.
+ (NSTimeInterval)now;
// Logs "[profile] <label> <milliseconds since started> ms".
+ (void)logStep:(NSString *)label since:(NSTimeInterval)started;
+ (void)log:(NSString *)message;

// From LINDIRSTAT_PROFILE_STOP_AFTER: seconds after which a scan is stopped
// as if Stop had been pressed, 0 if unset.
+ (NSTimeInterval)stopAfter;

// Starts a watchdog thread that posts to the main queue every 10 ms and logs
// each time the main thread took longer than 100 ms to answer. Does nothing
// unless enabled; starting twice is harmless.
+ (void)startStallMonitor;
// The longest main-thread stall seen since the last call, in seconds; the
// count of stalls over 100 ms is returned in count.
+ (NSTimeInterval)takeLongestStall:(NSUInteger *)count;

@end
