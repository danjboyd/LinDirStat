#import "LDProfiling.h"

#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static const NSTimeInterval LDStallThreshold = 0.1;
static const useconds_t LDStallProbeInterval = 10000;

static volatile int64_t LDLongestStallMicros = 0;
static volatile int64_t LDStallCount = 0;

@implementation LDProfiling

+ (BOOL)isEnabled
{
  static int enabled = -1;
  if (enabled < 0) {
    const char *value = getenv("LINDIRSTAT_PROFILE");
    enabled = (value && *value && strcmp(value, "0") != 0) ? 1 : 0;
  }
  return enabled == 1;
}

+ (NSTimeInterval)now
{
  struct timespec time;
  clock_gettime(CLOCK_MONOTONIC, &time);
  return (NSTimeInterval)time.tv_sec + (NSTimeInterval)time.tv_nsec / 1e9;
}

+ (void)log:(NSString *)message
{
  if ([self isEnabled]) {
    fprintf(stderr, "[profile] %s\n", [message UTF8String]);
    fflush(stderr);
  }
}

+ (void)logStep:(NSString *)label since:(NSTimeInterval)started
{
  if ([self isEnabled]) {
    [self log:[NSString stringWithFormat:@"%@ %.1f ms", label, ([self now] - started) * 1000.0]];
  }
}

+ (NSTimeInterval)stopAfter
{
  const char *value = getenv("LINDIRSTAT_PROFILE_STOP_AFTER");
  return value ? MAX(0.0, atof(value)) : 0.0;
}

+ (void)startStallMonitor
{
  static dispatch_once_t once;
  if (![self isEnabled]) {
    return;
  }
  dispatch_once(&once, ^{
    [NSThread detachNewThreadSelector:@selector(monitorStalls) toTarget:self withObject:nil];
  });
}

// Each probe is answered by the main queue; the time until it is answered is
// how long the main thread was busy.
+ (void)monitorStalls
{
  while (YES) {
    @autoreleasepool {
      __block volatile int answered = 0;
      NSTimeInterval posted = [self now];
      dispatch_async(dispatch_get_main_queue(), ^{
        answered = 1;
      });
      while (!__atomic_load_n(&answered, __ATOMIC_ACQUIRE)) {
        usleep(1000);
      }
      NSTimeInterval stall = [self now] - posted;
      if (stall > LDStallThreshold) {
        int64_t micros = (int64_t)(stall * 1e6);
        __atomic_add_fetch(&LDStallCount, 1, __ATOMIC_RELAXED);
        int64_t longest = __atomic_load_n(&LDLongestStallMicros, __ATOMIC_RELAXED);
        while (micros > longest
               && !__atomic_compare_exchange_n(&LDLongestStallMicros, &longest, micros, YES,
                                               __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
        }
        [self log:[NSString stringWithFormat:@"main thread stalled %.0f ms", stall * 1000.0]];
      }
      usleep(LDStallProbeInterval);
    }
  }
}

+ (NSTimeInterval)takeLongestStall:(NSUInteger *)count
{
  if (count) {
    *count = (NSUInteger)__atomic_exchange_n(&LDStallCount, 0, __ATOMIC_RELAXED);
  }
  return (NSTimeInterval)__atomic_exchange_n(&LDLongestStallMicros, 0, __ATOMIC_RELAXED) / 1e6;
}

@end
