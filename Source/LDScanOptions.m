#import "LDScanOptions.h"
#import "LDLocalization.h"
#import "LDPreferences.h"

#include <locale.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

NSString *const LDScanOptionsErrorDomain = @"LDScanOptionsErrorDomain";

static const NSUInteger LDDefaultScanOptionThreads = 4;

@implementation LDScanOptions

+ (LDScanOptions *)optionsFromPreferences:(LDPreferences *)preferences
{
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludedFolderPatterns:[self patternsFromString:[preferences excludedFolderPatterns]]];
  [options setExcludedFilePatterns:[self patternsFromString:[preferences excludedFilePatterns]]];
  [options setIncludedFolderPatterns:[self patternsFromString:[preferences includedFolderPatterns]]];
  [options setIncludedFilePatterns:[self patternsFromString:[preferences includedFilePatterns]]];
  [options setUsesRegex:[preferences filterUsesRegex]];
  [options setMinimumFileSize:[preferences minimumFileSizeInBytes]];
  [options setExcludesLargerFiles:[preferences filterExcludesLargerFiles]];
  [options setMaximumAgeDays:[preferences filterMaximumAgeDays]];
  [options setExcludesNewerFiles:[preferences filterExcludesNewerFiles]];
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
    _includedFolderPatterns = [NSArray array];
    _includedFilePatterns = [NSArray array];
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
  [copy setIncludedFolderPatterns:_includedFolderPatterns];
  [copy setIncludedFilePatterns:_includedFilePatterns];
  [copy setUsesRegex:_usesRegex];
  [copy setMinimumFileSize:_minimumFileSize];
  [copy setExcludesLargerFiles:_excludesLargerFiles];
  [copy setMaximumAgeDays:_maximumAgeDays];
  [copy setExcludesNewerFiles:_excludesNewerFiles];
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
- (NSArray *)includedFolderPatterns { return _includedFolderPatterns; }
- (void)setIncludedFolderPatterns:(NSArray *)patterns { _includedFolderPatterns = patterns ? [patterns copy] : [NSArray array]; }
- (NSArray *)includedFilePatterns { return _includedFilePatterns; }
- (void)setIncludedFilePatterns:(NSArray *)patterns { _includedFilePatterns = patterns ? [patterns copy] : [NSArray array]; }
- (BOOL)excludesLargerFiles { return _excludesLargerFiles; }
- (void)setExcludesLargerFiles:(BOOL)flag { _excludesLargerFiles = flag; }
- (NSUInteger)maximumAgeDays { return _maximumAgeDays; }
- (void)setMaximumAgeDays:(NSUInteger)days { _maximumAgeDays = days; }
- (BOOL)excludesNewerFiles { return _excludesNewerFiles; }
- (void)setExcludesNewerFiles:(BOOL)flag { _excludesNewerFiles = flag; }
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
  NSString *invalid = nil;
  for (NSArray *patterns in @[_excludedFolderPatterns, _excludedFilePatterns, _includedFolderPatterns, _includedFilePatterns]) {
    invalid = [[[LDPathFilter alloc] initWithPatterns:patterns usesRegex:_usesRegex] invalidPattern];
    if (invalid) {
      break;
    }
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
  return [self regexForPattern:pattern usesRegex:usesRegex descendants:NO];
}

// A trailing "$" that is not escaped ends a regex pattern; with descendants
// it would stop "pattern/..." from matching, so it is dropped.
static BOOL LDHasUnescapedTrailingDollar(const char *bytes, size_t length)
{
  if (length == 0 || bytes[length - 1] != '$') {
    return NO;
  }
  size_t backslashes = 0;
  while (backslashes + 1 < length && bytes[length - 2 - backslashes] == '\\') {
    backslashes++;
  }
  return backslashes % 2 == 0;
}

+ (NSData *)regexForPattern:(NSString *)pattern usesRegex:(BOOL)usesRegex descendants:(BOOL)descendants
{
  const char *bytes = [pattern UTF8String];
  size_t length = strlen(bytes);
  NSMutableData *regex = [NSMutableData dataWithBytes:"^((" length:3];
  if (usesRegex) {
    if (descendants && LDHasUnescapedTrailingDollar(bytes, length)) {
      length--;
    }
    [regex appendBytes:bytes length:length];
  } else {
    [self appendGlob:bytes toRegex:regex];
  }
  // POSIX "." also matches newlines, so names holding one stay below.
  const char *tail = descendants ? ")(/.*)?)$" : "))$";
  [regex appendBytes:tail length:strlen(tail)];
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
  return [self initWithPatterns:patterns usesRegex:usesRegex descendants:NO];
}

- (id)initWithPatterns:(NSArray *)patterns usesRegex:(BOOL)usesRegex descendants:(BOOL)descendants
{
  self = [super init];
  if (self) {
    _expressions = calloc(MAX((NSUInteger)1, [patterns count]), sizeof(regex_t));
    for (NSString *pattern in patterns) {
      if (LDCompileRegex(&_expressions[_count], [LDPathFilter regexForPattern:pattern usesRegex:usesRegex descendants:descendants])) {
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

@implementation LDScanFilter

static LDPathFilter *LDCompiledFilter(NSArray *patterns, BOOL usesRegex, BOOL descendants)
{
  if ([patterns count] == 0) {
    return nil;
  }
  LDPathFilter *filter = [[LDPathFilter alloc] initWithPatterns:patterns usesRegex:usesRegex descendants:descendants];
  return [filter count] > 0 ? filter : nil;
}

+ (NSString *)anchorForIncludePattern:(NSString *)pattern usesRegex:(BOOL)usesRegex
{
  NSString *literalEscapes = @"\\.+*?^$|()[]{}/";
  NSString *regexSpecials = @".+*?^$|()[]{}";
  NSMutableString *literal = [NSMutableString string];
  BOOL truncated = NO;
  NSUInteger length = [pattern length];
  for (NSUInteger i = 0; i < length; i++) {
    unichar c = [pattern characterAtIndex:i];
    if (usesRegex) {
      if (i == 0 && c == '^') {
        continue;
      }
      if (c == '\\' && i + 1 < length
          && [literalEscapes rangeOfString:[NSString stringWithFormat:@"%C", [pattern characterAtIndex:i + 1]]].location != NSNotFound) {
        [literal appendFormat:@"%C", [pattern characterAtIndex:++i]];
        continue;
      }
      if (c == '$' && i + 1 == length) {
        break;
      }
      if (c == '\\' || [regexSpecials rangeOfString:[NSString stringWithFormat:@"%C", c]].location != NSNotFound) {
        truncated = YES;
        break;
      }
    } else if (c == '*' || c == '?') {
      truncated = YES;
      break;
    }
    [literal appendFormat:@"%C", c];
  }
  if (truncated) {
    // What follows the last "/" belongs to the wildcarded component.
    NSRange slash = [literal rangeOfString:@"/" options:NSBackwardsSearch];
    [literal setString:slash.location == NSNotFound ? @"" : [literal substringToIndex:MAX(slash.location, (NSUInteger)1)]];
  }
  while ([literal length] > 1 && [literal hasSuffix:@"/"]) {
    [literal deleteCharactersInRange:NSMakeRange([literal length] - 1, 1)];
  }
  return literal;
}

+ (NSArray *)prefixesOfIncludeGlob:(NSString *)pattern
{
  NSMutableArray *prefixes = [NSMutableArray array];
  if ([pattern hasPrefix:@"/"] && [pattern length] > 1) {
    [prefixes addObject:@"/"];
  }
  NSArray *components = [pattern componentsSeparatedByString:@"/"];
  NSMutableString *prefix = [NSMutableString string];
  for (NSUInteger i = 0; i + 1 < [components count]; i++) {
    if (i > 0) {
      [prefix appendString:@"/"];
    }
    [prefix appendString:[components objectAtIndex:i]];
    if ([prefix length] > 0) {
      [prefixes addObject:[prefix copy]];
    }
  }
  return prefixes;
}

- (id)initWithOptions:(LDScanOptions *)options now:(time_t)now
{
  self = [super init];
  if (self) {
    BOOL regex = [options usesRegex];
    _excludedFolders = LDCompiledFilter([options excludedFolderPatterns], regex, YES);
    _excludedFiles = LDCompiledFilter([options excludedFilePatterns], regex, NO);
    _includedFolders = LDCompiledFilter([options includedFolderPatterns], regex, YES);
    _includedFiles = LDCompiledFilter([options includedFilePatterns], regex, NO);
    NSMutableArray *anchors = [NSMutableArray array];
    NSMutableArray *prefixes = [NSMutableArray array];
    if (_includedFolders) {
      for (NSString *pattern in [options includedFolderPatterns]) {
        if (!regex) {
          [prefixes addObjectsFromArray:[LDScanFilter prefixesOfIncludeGlob:pattern]];
          continue;
        }
        NSString *anchor = [LDScanFilter anchorForIncludePattern:pattern usesRegex:YES];
        if ([anchor length] == 0) {
          _anchorlessInclude = YES;
        } else {
          const char *bytes = [anchor fileSystemRepresentation];
          [anchors addObject:[NSData dataWithBytes:bytes length:strlen(bytes)]];
        }
      }
    }
    _includePrefixes = LDCompiledFilter(prefixes, NO, NO);
    _includeAnchors = anchors;
    _sizeThreshold = [options minimumFileSize];
    _excludesLarger = [options excludesLargerFiles];
    _ageCutoff = [options maximumAgeDays] > 0 ? now - (time_t)[options maximumAgeDays] * 86400 : 0;
    _excludesNewer = [options excludesNewerFiles];
  }
  return self;
}

- (BOOL)isActive
{
  return _excludedFolders || _excludedFiles || _includedFolders || _includedFiles || _sizeThreshold > 0 || _ageCutoff != 0;
}

// path is anchor itself, a folder above it or one below it.
static BOOL LDIsOnTheWayTo(const char *path, NSData *anchor)
{
  size_t anchorLength = [anchor length];
  const char *anchorBytes = [anchor bytes];
  // Below the anchor: a regex include cannot be ruled out there.
  if (strlen(path) > anchorLength && strncasecmp(path, anchorBytes, anchorLength) == 0
      && (path[anchorLength] == '/' || (anchorLength == 1 && anchorBytes[0] == '/'))) {
    return YES;
  }
  size_t pathLength = strlen(path);
  while (pathLength > 1 && path[pathLength - 1] == '/') {
    pathLength--;
  }
  if (pathLength > anchorLength || strncasecmp(path, anchorBytes, pathLength) != 0) {
    return NO;
  }
  return pathLength == anchorLength || anchorBytes[pathLength] == '/' || (pathLength == 1 && path[0] == '/');
}

- (BOOL)excludesFolderAtPath:(const char *)path
{
  if (_excludedFolders && [_excludedFolders matchesBytes:path]) {
    return YES;
  }
  if (!_includedFolders || _anchorlessInclude || [_includedFolders matchesBytes:path]) {
    return NO;
  }
  if (_includePrefixes && [_includePrefixes matchesBytes:path]) {
    return NO;
  }
  for (NSData *anchor in _includeAnchors) {
    if (LDIsOnTheWayTo(path, anchor)) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)includesFilesInFolderAtPath:(const char *)path
{
  return !_includedFolders || [_includedFolders matchesBytes:path];
}

- (BOOL)excludesFileNamed:(const char *)name
                   atPath:(const char *)path
           folderIncluded:(BOOL)folderIncluded
                     size:(unsigned long long)size
                    mtime:(time_t)mtime
          checkSizeAndAge:(BOOL)checkSizeAndAge
{
  if (checkSizeAndAge) {
    if (_sizeThreshold > 0 && (_excludesLarger ? size > _sizeThreshold : size < _sizeThreshold)) {
      return YES;
    }
    if (_ageCutoff != 0 && (_excludesNewer ? mtime > _ageCutoff : mtime < _ageCutoff)) {
      return YES;
    }
  }
  if (_excludedFiles && [_excludedFiles matchesBytes:name]) {
    return YES;
  }
  if (!folderIncluded && _includedFolders && ![_includedFolders matchesBytes:path]) {
    return YES;
  }
  if (_includedFiles && ![_includedFiles matchesBytes:name]) {
    return YES;
  }
  return NO;
}

@end
