#import "LDScanClock.h"

#include <time.h>

uint64_t LDScanClockMilliseconds(void)
{
  struct timespec now;
#if defined(CLOCK_MONOTONIC_COARSE)
  clock_gettime(CLOCK_MONOTONIC_COARSE, &now);
#else
  clock_gettime(CLOCK_MONOTONIC, &now);
#endif
  return (uint64_t)now.tv_sec * 1000 + (uint64_t)now.tv_nsec / 1000000;
}

BOOL LDPacmanIsAsleep(uint64_t millisecondsSinceActivity, uint64_t millisecondsSinceResume, BOOL suspended)
{
  return !suspended
    && millisecondsSinceActivity > LDPacmanSleepMilliseconds
    && millisecondsSinceResume > LDPacmanSleepMilliseconds;
}

NSString *LDFormatScanDuration(NSUInteger seconds)
{
  NSUInteger minutes = seconds / 60;
  if (minutes < 60) {
    return [NSString stringWithFormat:@"%lu:%02lu", (unsigned long)minutes, (unsigned long)(seconds % 60)];
  }
  return [NSString stringWithFormat:@"%lu:%02lu:%02lu", (unsigned long)(minutes / 60), (unsigned long)(minutes % 60),
          (unsigned long)(seconds % 60)];
}
