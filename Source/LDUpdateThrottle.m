#import "LDUpdateThrottle.h"

@implementation LDUpdateThrottle
{
  double _busyShare;
  NSTimeInterval _minimumInterval;
  NSTimeInterval _next;
}

- (instancetype)initWithBusyShare:(double)busyShare minimumInterval:(NSTimeInterval)minimumInterval
{
  self = [super init];
  if (self) {
    _busyShare = busyShare;
    _minimumInterval = minimumInterval;
  }
  return self;
}

- (NSTimeInterval)waitAt:(NSTimeInterval)now
{
  return MAX(0.0, _next - now);
}

- (void)didUpdateAt:(NSTimeInterval)started duration:(NSTimeInterval)duration
{
  _next = started + MAX(_minimumInterval, duration / _busyShare);
}

@end
