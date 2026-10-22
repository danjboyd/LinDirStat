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

// The high bit marks a suspended clock; the rest holds the scan time it
// stopped at, or while running the total time spent suspended.
#define LDScanClockSuspendedBit (UINT64_C(1) << 63)
static uint64_t LDScanClockState = 0;

uint64_t LDScanClockActiveMillisecondsAt(uint64_t now)
{
  uint64_t state = __atomic_load_n(&LDScanClockState, __ATOMIC_RELAXED);
  if (state & LDScanClockSuspendedBit) {
    return state & ~LDScanClockSuspendedBit;
  }
  return now > state ? now - state : 0;
}

void LDScanClockSuspendAt(uint64_t now)
{
  uint64_t state = __atomic_load_n(&LDScanClockState, __ATOMIC_RELAXED);
  if (!(state & LDScanClockSuspendedBit)) {
    __atomic_store_n(&LDScanClockState, LDScanClockSuspendedBit | LDScanClockActiveMillisecondsAt(now), __ATOMIC_RELAXED);
  }
}

void LDScanClockResumeAt(uint64_t now)
{
  uint64_t state = __atomic_load_n(&LDScanClockState, __ATOMIC_RELAXED);
  if (state & LDScanClockSuspendedBit) {
    uint64_t active = state & ~LDScanClockSuspendedBit;
    __atomic_store_n(&LDScanClockState, now > active ? now - active : 0, __ATOMIC_RELAXED);
  }
}

uint64_t LDScanClockActiveMilliseconds(void) { return LDScanClockActiveMillisecondsAt(LDScanClockMilliseconds()); }
void LDScanClockSuspend(void) { LDScanClockSuspendAt(LDScanClockMilliseconds()); }
void LDScanClockResume(void) { LDScanClockResumeAt(LDScanClockMilliseconds()); }

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
