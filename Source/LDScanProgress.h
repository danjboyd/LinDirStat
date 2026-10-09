#import <Foundation/Foundation.h>

@class LDScanOptions;

// WinDirStat's scan progress (MainFrame.cpp CreateProgress/UpdateProgress,
// Item.cpp GetProgressRange): a scan of volumes measures itself against the
// space they use and shows "NN%" in the status bar and window title; any
// other scan shows that it is busy ("Scanning").
@interface LDScanProgress : NSObject

// YES if path is where a filesystem is mounted: "/", or a folder whose device
// differs from its parent's (statfs's mount point on macOS).
+ (BOOL)isVolumeRootPath:(NSString *)path;

// Bytes in use on the filesystem holding path (total - free, statvfs), or 0.
+ (unsigned long long)usedBytesOfVolumeAtPath:(NSString *)path;

// The progress range in bytes: the used space of the scanned volumes, or 0
// (no percentage) when any path is not a volume root, or when the options
// let the scan leave a volume (mount points or symbolic links followed).
+ (unsigned long long)rangeForScanPaths:(NSArray *)paths options:(LDScanOptions *)options;

// The same rule with the volume facts given: usedBytes holds each path's
// used bytes, or 0 for a path that is not a volume root.
+ (unsigned long long)rangeForUsedBytes:(NSArray *)usedBytes
                     excludeMountPoints:(BOOL)excludeMountPoints
                   excludeSymbolicLinks:(BOOL)excludeSymbolicLinks;

// position * 100 / range, capped at 100 (hard links can count twice).
+ (NSInteger)percentForPosition:(unsigned long long)position range:(unsigned long long)range;

// The window title prefix while scanning: "NN%" with a range, "Scanning"
// without one, followed by " (Suspended)" when suspended.
+ (NSString *)titlePrefixForPosition:(unsigned long long)position
                               range:(unsigned long long)range
                           suspended:(BOOL)suspended;

@end
