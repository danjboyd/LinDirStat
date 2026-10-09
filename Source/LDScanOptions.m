#import "LDScanOptions.h"
#import "LDLocalization.h"
#import "LDPreferences.h"

#include <locale.h>
#include <stdlib.h>
#include <string.h>

NSString *const LDScanOptionsErrorDomain = @"LDScanOptionsErrorDomain";

static const NSUInteger LDDefaultScanOptionThreads = 4;

@implementation LDScanOptions

+ (LDScanOptions *)optionsFromPreferences:(LDPreferences *)preferences
{
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludedFolderPatterns:[self patternsFromString:[preferences excludedFolderPatterns]]];
  [options setExcludedFilePatterns:[self patternsFromString:[preferences excludedFilePatterns]]];
  [options setUsesRegex:[preferences filterUsesRegex]];
  [options setMinimumFileSize:[preferences minimumFileSizeInBytes]];
  [options setExcludeHidden:[preferences excludeHiddenEntries]];
  [options setExcludeSymbolicLinks:[preferences excludeSymbolicLinks]];
  [options setExcludeMountPoints:[preferences excludeMountPoints]];
  [options setProcessHardLinks:[preferences processHardLinks]];
  [options setThreadCount:[preferences scanningThreads]];
  [options setFindsDuplicates:[preferences scanForDuplicates]];
  return options;
}

static NSString *LDTrimmingTrailing(NSString *text, unichar character)
{
  NSUInteger length = [text length];
  while (length > 0 && [text characterAtIndex:length - 1] == character) {
    length--;
  }
  return [text substringToIndex:length];
}

+ (NSArray *)patternsFromString:(NSString *)text
{
  NSMutableArray *patterns = [NSMutableArray array];
  for (NSString *line in [(text ? text : @"") componentsSeparatedByString:@"\n"]) {
    NSString *pattern = LDTrimmingTrailing(LDTrimmingTrailing(line, '\r'), '/');
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    if ([[pattern stringByTrimmingCharactersInSet:whitespace] length] > 0) {
      [patterns addObject:pattern];
    }
  }
  return patterns;
}

- (id)init
{
  self = [super init];
  if (self) {
    _excludedFolderPatterns = [NSArray array];
    _excludedFilePatterns = [NSArray array];
    _excludeSymbolicLinks = YES;
    _excludeMountPoints = YES;
    _processHardLinks = YES;
    _threadCount = LDDefaultScanOptionThreads;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  LDScanOptions *copy = [[LDScanOptions allocWithZone:zone] init];
  [copy setExcludedFolderPatterns:_excludedFolderPatterns];
  [copy setExcludedFilePatterns:_excludedFilePatterns];
  [copy setUsesRegex:_usesRegex];
  [copy setMinimumFileSize:_minimumFileSize];
  [copy setExcludeHidden:_excludeHidden];
  [copy setExcludeSymbolicLinks:_excludeSymbolicLinks];
  [copy setExcludeMountPoints:_excludeMountPoints];
  [copy setProcessHardLinks:_processHardLinks];
  [copy setThreadCount:_threadCount];
  [copy setFindsDuplicates:_findsDuplicates];
  return copy;
}

- (NSArray *)excludedFolderPatterns { return _excludedFolderPatterns; }
- (void)setExcludedFolderPatterns:(NSArray *)patterns { _excludedFolderPatterns = patterns ? [patterns copy] : [NSArray array]; }
- (NSArray *)excludedFilePatterns { return _excludedFilePatterns; }
- (void)setExcludedFilePatterns:(NSArray *)patterns { _excludedFilePatterns = patterns ? [patterns copy] : [NSArray array]; }
- (BOOL)usesRegex { return _usesRegex; }
- (void)setUsesRegex:(BOOL)flag { _usesRegex = flag; }
- (unsigned long long)minimumFileSize { return _minimumFileSize; }
- (void)setMinimumFileSize:(unsigned long long)bytes { _minimumFileSize = bytes; }
- (BOOL)excludeHidden { return _excludeHidden; }
- (void)setExcludeHidden:(BOOL)flag { _excludeHidden = flag; }
- (BOOL)processHardLinks { return _processHardLinks; }
- (void)setProcessHardLinks:(BOOL)flag { _processHardLinks = flag; }
- (BOOL)excludeSymbolicLinks { return _excludeSymbolicLinks; }
- (void)setExcludeSymbolicLinks:(BOOL)flag { _excludeSymbolicLinks = flag; }
- (BOOL)excludeMountPoints { return _excludeMountPoints; }
- (void)setExcludeMountPoints:(BOOL)flag { _excludeMountPoints = flag; }
- (NSUInteger)threadCount { return _threadCount; }
- (void)setThreadCount:(NSUInteger)count { _threadCount = MAX((NSUInteger)1, count); }
- (BOOL)findsDuplicates { return _findsDuplicates; }
- (void)setFindsDuplicates:(BOOL)flag { _findsDuplicates = flag; }

- (BOOL)validateWithError:(NSError **)error
{
  NSString *invalid = [[[LDPathFilter alloc] initWithPatterns:_excludedFolderPatterns usesRegex:_usesRegex] invalidPattern];
  if (!invalid) {
    invalid = [[[LDPathFilter alloc] initWithPatterns:_excludedFilePatterns usesRegex:_usesRegex] invalidPattern];
  }
  if (!invalid) {
    return YES;
  }
  if (error) {
    NSString *description = [NSString stringWithFormat:LDLocalized(@"Invalid filter: %@"), invalid];
    *error = [NSError errorWithDomain:LDScanOptionsErrorDomain
                                 code:LDScanOptionsErrorInvalidFilter
                             userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
  }
  return NO;
}

@end

// "?" in a glob is one character: a whole UTF-8 sequence, or any other byte.
static const char LDGlobAnyCharacter[] =
  "([\xc2-\xdf][\x80-\xbf]|[\xe0-\xef][\x80-\xbf][\x80-\xbf]"
  "|[\xf0-\xf4][\x80-\xbf][\x80-\xbf][\x80-\xbf]|[^/])";

@implementation LDPathFilter

+ (void)appendGlob:(const char *)glob toRegex:(NSMutableData *)regex
{
  for (const char *cursor = glob; *cursor; cursor++) {
    char c = *cursor;
    if (c == '*') {
      [regex appendBytes:"[^/]*" length:5];
    } else if (c == '?') {
      [regex appendBytes:LDGlobAnyCharacter length:strlen(LDGlobAnyCharacter)];
    } else {
      if (strchr(".^$+()[]{}|\\", c)) {
        [regex appendBytes:"\\" length:1];
      }
      [regex appendBytes:&c length:1];
    }
  }
}

+ (NSData *)regexForPattern:(NSString *)pattern usesRegex:(BOOL)usesRegex
{
  const char *bytes = [pattern UTF8String];
  NSMutableData *regex = [NSMutableData dataWithBytes:"^(" length:2];
  if (usesRegex) {
    [regex appendBytes:bytes length:strlen(bytes)];
  } else {
    [self appendGlob:bytes toRegex:regex];
  }
  [regex appendBytes:")$" length:2];
  return regex;
}

// Compiles in the C locale so the regex works on bytes: in a UTF-8 locale
// glibc never matches bytes that are not valid UTF-8, so such names could
// not be excluded.
static BOOL LDCompileRegex(regex_t *expression, NSData *regex)
{
  NSMutableData *terminated = [regex mutableCopy];
  [terminated appendBytes:"\0" length:1];
  locale_t cLocale = newlocale(LC_ALL_MASK, "C", (locale_t)0);
  locale_t previous = cLocale ? uselocale(cLocale) : (locale_t)0;
  int status = regcomp(expression, [terminated bytes], REG_EXTENDED | REG_ICASE | REG_NOSUB);
  if (cLocale) {
    uselocale(previous);
    freelocale(cLocale);
  }
  return status == 0;
}

- (id)initWithPatterns:(NSArray *)patterns usesRegex:(BOOL)usesRegex
{
  self = [super init];
  if (self) {
    _expressions = calloc(MAX((NSUInteger)1, [patterns count]), sizeof(regex_t));
    for (NSString *pattern in patterns) {
      if (LDCompileRegex(&_expressions[_count], [LDPathFilter regexForPattern:pattern usesRegex:usesRegex])) {
        _count++;
      } else if (!_invalidPattern) {
        _invalidPattern = [pattern copy];
      }
    }
  }
  return self;
}

- (void)dealloc
{
  for (NSUInteger i = 0; i < _count; i++) {
    regfree(&_expressions[i]);
  }
  free(_expressions);
}

- (NSUInteger)count { return _count; }
- (NSString *)invalidPattern { return _invalidPattern; }

- (BOOL)matchesBytes:(const char *)bytes
{
  for (NSUInteger i = 0; i < _count; i++) {
    if (regexec(&_expressions[i], bytes, 0, NULL, 0) == 0) {
      return YES;
    }
  }
  return NO;
}

@end
