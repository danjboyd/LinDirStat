#import <Foundation/Foundation.h>

#include <regex.h>

@class LDPreferences;

FOUNDATION_EXPORT NSString *const LDScanOptionsErrorDomain;

typedef enum {
  LDScanOptionsErrorInvalidFilter = 1
} LDScanOptionsErrorCode;

// What a scan includes (WinDirStat's Filtering page and the exclusions on
// its Advanced page). The defaults match WinDirStat's: no filters, symlinks
// and mount points excluded, hidden entries included, hard links processed,
// 4 threads.
@interface LDScanOptions : NSObject <NSCopying>
{
  NSArray *_excludedFolderPatterns;
  NSArray *_excludedFilePatterns;
  NSArray *_includedFolderPatterns;
  NSArray *_includedFilePatterns;
  BOOL _usesRegex;
  unsigned long long _minimumFileSize;
  BOOL _excludesLargerFiles;
  NSUInteger _maximumAgeDays;
  BOOL _excludesNewerFiles;
  BOOL _excludeHidden;
  BOOL _excludeSymbolicLinks;
  BOOL _excludeMountPoints;
  BOOL _processHardLinks;
  NSUInteger _threadCount;
  BOOL _findsDuplicates;
}

+ (LDScanOptions *)optionsFromPreferences:(LDPreferences *)preferences;

// Splits a multiline setting into patterns: one per line, with trailing "\r"
// and "/" trimmed and blank (or all-whitespace) lines dropped.
+ (NSArray *)patternsFromString:(NSString *)text;

// WinDirStat 2.6's filtering (Filtering.cpp in its v2.9.0). Folder patterns
// match a folder's full path and everything below it ("/data/cache" also
// matches "/data/cache/x"); file name patterns match the name only. All are
// case-insensitive.
// An excluded folder is left out of the tree with all it holds.
- (NSArray *)excludedFolderPatterns;
- (void)setExcludedFolderPatterns:(NSArray *)patterns;
- (NSArray *)excludedFilePatterns;
- (void)setExcludedFilePatterns:(NSArray *)patterns;
// With folder includes, only files below an included folder are kept, and
// folders are entered only when included or on the way to an include: a
// glob's leading components ("/data/*/src" goes through "/data" and
// "/data/x"), a regex's fixed leading folder and anything below it.
- (NSArray *)includedFolderPatterns;
- (void)setIncludedFolderPatterns:(NSArray *)patterns;
// With file name includes, only files whose name matches are kept.
- (NSArray *)includedFilePatterns;
- (void)setIncludedFilePatterns:(NSArray *)patterns;
// NO: patterns are globs ("*" and "?" stay within one path component).
// YES: patterns are POSIX extended regular expressions.
- (BOOL)usesRegex;
- (void)setUsesRegex:(BOOL)flag;
// The size filter: files whose logical size is below it (or above it, with
// excludesLargerFiles) are left out. 0 keeps everything.
- (unsigned long long)minimumFileSize;
- (void)setMinimumFileSize:(unsigned long long)bytes;
- (BOOL)excludesLargerFiles;
- (void)setExcludesLargerFiles:(BOOL)flag;
// The age filter: files last changed more than this many days ago (or less,
// with excludesNewerFiles) are left out. 0 keeps everything.
- (NSUInteger)maximumAgeDays;
- (void)setMaximumAgeDays:(NSUInteger)days;
- (BOOL)excludesNewerFiles;
- (void)setExcludesNewerFiles:(BOOL)flag;
// Leaves out every entry whose name starts with ".".
- (BOOL)excludeHidden;
- (void)setExcludeHidden:(BOOL)flag;
// YES: links to files are left out and links to directories are shown as
// leaves. NO: links are followed.
- (BOOL)excludeSymbolicLinks;
- (void)setExcludeSymbolicLinks:(BOOL)flag;
// YES: directories on another filesystem than their scan root are shown as
// mount-point leaves and not entered.
- (BOOL)excludeMountPoints;
- (void)setExcludeMountPoints:(BOOL)flag;
// WinDirStat's "Scan drives and display hardlink information" (default
// YES): files with several links are shown under "<Hardlinks>" (see
// LDHardLinks.h). Either way they are counted once.
- (BOOL)processHardLinks;
- (void)setProcessHardLinks:(BOOL)flag;
- (NSUInteger)threadCount;
- (void)setThreadCount:(NSUInteger)count;
// WinDirStat's ScanForDuplicates: the scan also finds duplicate files while
// it runs (see LDDuplicateCollector). Default NO.
- (BOOL)findsDuplicates;
- (void)setFindsDuplicates:(BOOL)flag;

// YES if every pattern compiles. Otherwise error describes the first bad
// pattern as "Invalid filter: <pattern>". Scans skip patterns that do not
// compile, so callers should validate before scanning.
- (BOOL)validateWithError:(NSError **)error;

@end

// A compiled set of exclusion patterns. Matching is on raw bytes, so names
// that are not valid UTF-8 can match; it is thread-safe.
@interface LDPathFilter : NSObject
{
  regex_t *_expressions;
  NSUInteger _count;
  NSString *_invalidPattern;
}

// Compiles every valid pattern; -invalidPattern names the first one that did
// not compile.
- (id)initWithPatterns:(NSArray *)patterns usesRegex:(BOOL)usesRegex;
// With descendants, each pattern also matches every path below what it
// matches (WinDirStat's folder filters): "pattern" and "pattern/...".
- (id)initWithPatterns:(NSArray *)patterns usesRegex:(BOOL)usesRegex descendants:(BOOL)descendants;
// The anchored extended regex a pattern compiles to, as bytes (no NUL).
+ (NSData *)regexForPattern:(NSString *)pattern usesRegex:(BOOL)usesRegex;
+ (NSData *)regexForPattern:(NSString *)pattern usesRegex:(BOOL)usesRegex descendants:(BOOL)descendants;

- (NSUInteger)count;
- (NSString *)invalidPattern;
// YES if a pattern matches the whole of the NUL-terminated bytes.
- (BOOL)matchesBytes:(const char *)bytes;

@end

// The filters of one scan, compiled from its options (WinDirStat's
// CFiltering). Thread-safe; paths and names are raw bytes.
@interface LDScanFilter : NSObject
{
  LDPathFilter *_excludedFolders;
  LDPathFilter *_excludedFiles;
  LDPathFilter *_includedFolders;
  LDPathFilter *_includedFiles;
  LDPathFilter *_includePrefixes;  // globs: the leading components of each folder include
  NSArray *_includeAnchors;  // regexes: NSData, the fixed leading folder of each folder include
  BOOL _anchorlessInclude;   // a regex folder include starts with a wildcard: enter every folder
  unsigned long long _sizeThreshold;
  BOOL _excludesLarger;
  time_t _ageCutoff;         // 0: no age filter
  BOOL _excludesNewer;
}

// now is the time the age filter counts from (the scan's start).
- (id)initWithOptions:(LDScanOptions *)options now:(time_t)now;

// The deepest folder an include pattern's matches all lie in: its text up to
// the last "/" before the first wildcard ("/data/proj*" -> "/data"; "/*" ->
// "/"; "*/x" -> ""). In regex mode a leading "^" and a trailing "$" are
// dropped and escaped characters taken literally.
+ (NSString *)anchorForIncludePattern:(NSString *)pattern usesRegex:(BOOL)usesRegex;
// The paths of the folders a glob include passes through: its leading
// components, "/data/*/src" -> "/", "/data", "/data/*".
+ (NSArray *)prefixesOfIncludeGlob:(NSString *)pattern;

// YES when any filter is set.
- (BOOL)isActive;
// Whether a folder (full path) is left out: excluded, or with folder includes
// neither included nor on the way to one. Scan roots are never filtered.
- (BOOL)excludesFolderAtPath:(const char *)path;
// Whether files directly in this folder pass the folder includes without
// their own check (no folder includes, or the folder itself is included).
- (BOOL)includesFilesInFolderAtPath:(const char *)path;
// Whether a file is left out by name, folder includes (skipped when
// folderIncluded), size or age. A file that could not be stat'ed passes
// size 0 and mtime 0 with checkSizeAndAge NO.
- (BOOL)excludesFileNamed:(const char *)name
                   atPath:(const char *)path
           folderIncluded:(BOOL)folderIncluded
                     size:(unsigned long long)size
                    mtime:(time_t)mtime
          checkSizeAndAge:(BOOL)checkSizeAndAge;

@end
