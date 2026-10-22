#import <Foundation/Foundation.h>

#include <stdint.h>

// Cheap timing for the live tree: when a folder's read started, how long it
// took and when anything below it last progressed. Directory nodes keep
// these as two 16-bit stamps in spare padding, so no node grows; the stamps
// wrap, and differences are taken modulo 2^16 (correct for read times under
// 18 hours and activity gaps under 10 minutes).

// WinDirStat's CPacman HIDE_THRESHOLD: a pacman with no update for longer
// stops and sleeps (PacMan.cpp).
#define LDPacmanSleepMilliseconds 750

// Monotonic milliseconds (a coarse clock where there is one).
FOUNDATION_EXPORT uint64_t LDScanClockMilliseconds(void);

// Scan time: LDScanClockMilliseconds less the time scans spent suspended,
// so it stands still while one is (WinDirStat 2.6's GetScanTickCount,
// e451d346). Folders' time spent is measured in it; activity stamps stay on
// LDScanClockMilliseconds. Suspend and resume are idempotent.
FOUNDATION_EXPORT uint64_t LDScanClockActiveMilliseconds(void);
FOUNDATION_EXPORT void LDScanClockSuspend(void);
FOUNDATION_EXPORT void LDScanClockResume(void);
// The same at a given LDScanClockMilliseconds time.
FOUNDATION_EXPORT uint64_t LDScanClockActiveMillisecondsAt(uint64_t now);
FOUNDATION_EXPORT void LDScanClockSuspendAt(uint64_t now);
FOUNDATION_EXPORT void LDScanClockResumeAt(uint64_t now);

static inline uint16_t LDScanClockSecondsStamp(uint64_t milliseconds)
{
  return (uint16_t)(milliseconds / 1000);
}

static inline uint16_t LDScanClockActivityStamp(uint64_t milliseconds)
{
  return (uint16_t)(milliseconds / 10);
}

// Whole seconds from a seconds stamp to now.
static inline NSUInteger LDScanClockSecondsSince(uint16_t stamp, uint64_t now)
{
  return (uint16_t)(LDScanClockSecondsStamp(now) - stamp);
}

// Milliseconds (10 ms steps) from an activity stamp to now.
static inline uint64_t LDScanClockMillisecondsSince(uint16_t stamp, uint64_t now)
{
  return (uint64_t)(uint16_t)(LDScanClockActivityStamp(now) - stamp) * 10;
}

// YES when a pending folder's pacman should stop and draw its "z"s: nothing
// below it progressed for LDPacmanSleepMilliseconds. A suspended scan
// freezes the pacmen instead, and after a resume they get the threshold
// again before sleeping (WinDirStat rebases their clocks while suspended).
FOUNDATION_EXPORT BOOL LDPacmanIsAsleep(uint64_t millisecondsSinceActivity,
                                        uint64_t millisecondsSinceResume,
                                        BOOL suspended);

// WinDirStat's FormatMilliseconds for whole seconds: "m:ss", or "h:mm:ss"
// from an hour on.
FOUNDATION_EXPORT NSString *LDFormatScanDuration(NSUInteger seconds);
