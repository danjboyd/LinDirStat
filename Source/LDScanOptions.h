#import <Foundation/Foundation.h>

#include <regex.h>

@class LDPreferences;

FOUNDATION_EXPORT NSString *const LDScanOptionsErrorDomain;

typedef enum {
  LDScanOptionsErrorInvalidFilter = 1
} LDScanOptionsErrorCode;

// What a scan includes (WinDirStat's Filtering page and the exclusions on
// its Advanced page). The defaults match WinDirStat's: no filters, symlinks
// and mount points excluded, hidden entries included, 4 threads.
@interface LDScanOptions : NSObject <NSCopying>
{
  NSArray *_excludedFolderPatterns;
  NSArray *_excludedFilePatterns;
  BOOL _usesRegex;
  unsigned long long _minimumFileSize;
  BOOL _excludeHidden;
  BOOL _excludeSymbolicLinks;
  BOOL _excludeMountPoints;
  NSUInteger _threadCount;
}

+ (LDScanOptions *)optionsFromPreferences:(LDPreferences *)preferences;

// Splits a multiline setting into patterns: one per line, with trailing "\r"
// and "/" trimmed and blank (or all-whitespace) lines dropped.
+ (NSArray *)patternsFromString:(NSString *)text;

// Matched case-insensitively against a directory's full path; a match leaves
// the directory out of the tree.
- (NSArray *)excludedFolderPatterns;
- (void)setExcludedFolderPatterns:(NSArray *)patterns;
// Matched case-insensitively against a file's name only.
- (NSArray *)excludedFilePatterns;
- (void)setExcludedFilePatterns:(NSArray *)patterns;
// NO: patterns are globs ("*" and "?" stay within one path component).
// YES: patterns are POSIX extended regular expressions.
- (BOOL)usesRegex;
- (void)setUsesRegex:(BOOL)flag;
// Files with a smaller logical size are left out. 0 keeps everything.
- (unsigned long long)minimumFileSize;
- (void)setMinimumFileSize:(unsigned long long)bytes;
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
- (NSUInteger)threadCount;
- (void)setThreadCount:(NSUInteger)count;

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
// The anchored extended regex a pattern compiles to, as bytes (no NUL).
+ (NSData *)regexForPattern:(NSString *)pattern usesRegex:(BOOL)usesRegex;

- (NSUInteger)count;
- (NSString *)invalidPattern;
// YES if a pattern matches the whole of the NUL-terminated bytes.
- (BOOL)matchesBytes:(const char *)bytes;

@end
