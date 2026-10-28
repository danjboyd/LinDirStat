#import "LDSearch.h"
#import "LDNodeRanking.h"
#import "LDFileAttributes.h"

#include <limits.h>
#include <locale.h>
#include <regex.h>
#include <string.h>

NSString *const LDSearchErrorDomain = @"LDSearchErrorDomain";

static BOOL LDIsValidUTF8(const unsigned char *bytes)
{
  while (*bytes) {
    unsigned char lead = *bytes++;
    NSUInteger continuation;
    if (lead < 0x80) {
      continue;
    } else if (lead >= 0xC2 && lead <= 0xDF) {
      continuation = 1;
    } else if (lead >= 0xE0 && lead <= 0xEF) {
      continuation = 2;
    } else if (lead >= 0xF0 && lead <= 0xF4) {
      continuation = 3;
    } else {
      return NO;
    }
    for (NSUInteger index = 0; index < continuation; index++) {
      if ((*bytes++ & 0xC0) != 0x80) {
        return NO;
      }
    }
  }
  return YES;
}

// glibc's regex will not match an invalid UTF-8 byte with "." or a bracket
// under a UTF-8 locale, so names that are not UTF-8 are matched byte-wise
// under the C locale instead. Valid names use C.UTF-8 so ? matches one
// character and case folding covers non-ASCII letters.
@interface LDNameMatcher : NSObject
{
  regex_t _textRegex;
  regex_t _byteRegex;
  locale_t _textLocale;
  locale_t _byteLocale;
  BOOL _hasTextRegex;
  BOOL _hasByteRegex;
}

- (id)initWithPattern:(NSString *)pattern caseSensitive:(BOOL)caseSensitive errorMessage:(NSString **)message;
- (BOOL)matchesName:(const char *)name;

@end

@implementation LDNameMatcher

+ (BOOL)compile:(const char *)pattern
          flags:(int)flags
         locale:(locale_t)locale
           into:(regex_t *)regex
   errorMessage:(NSString **)message
{
  locale_t previous = uselocale(locale);
  int status = regcomp(regex, pattern, flags);
  if (status != 0 && message) {
    char buffer[256];
    regerror(status, regex, buffer, sizeof(buffer));
    *message = [NSString stringWithUTF8String:buffer];
  }
  uselocale(previous);
  return status == 0;
}

- (id)initWithPattern:(NSString *)pattern caseSensitive:(BOOL)caseSensitive errorMessage:(NSString **)message
{
  self = [super init];
  if (!self) {
    return nil;
  }
  int flags = REG_EXTENDED | REG_NOSUB;
  if (!caseSensitive) {
    flags |= REG_ICASE;
  }
  const char *bytes = [pattern UTF8String];
  _byteLocale = newlocale(LC_ALL_MASK, "C", (locale_t)0);
  _textLocale = newlocale(LC_ALL_MASK, "C.UTF-8", (locale_t)0);
  _hasByteRegex = _byteLocale && [LDNameMatcher compile:bytes flags:flags locale:_byteLocale into:&_byteRegex errorMessage:message];
  if (!_hasByteRegex) {
    return nil;
  }
  if (_textLocale) {
    _hasTextRegex = [LDNameMatcher compile:bytes flags:flags locale:_textLocale into:&_textRegex errorMessage:message];
    if (!_hasTextRegex) {
      return nil;
    }
  }
  return self;
}

- (void)dealloc
{
  if (_hasTextRegex) {
    regfree(&_textRegex);
  }
  if (_hasByteRegex) {
    regfree(&_byteRegex);
  }
  if (_textLocale) {
    freelocale(_textLocale);
  }
  if (_byteLocale) {
    freelocale(_byteLocale);
  }
}

- (BOOL)matchesName:(const char *)name
{
  BOOL text = _hasTextRegex && LDIsValidUTF8((const unsigned char *)name);
  locale_t previous = uselocale(text ? _textLocale : _byteLocale);
  int status = regexec(text ? &_textRegex : &_byteRegex, name, 0, NULL, 0);
  uselocale(previous);
  return status == 0;
}

@end

@implementation LDSearchOptions

+ (LDSearchOptions *)optionsWithTerm:(NSString *)term
{
  LDSearchOptions *options = [[self alloc] init];
  [options setTerm:term];
  return options;
}

+ (LDSearchOptions *)optionsForExtensionKey:(NSString *)extensionKey
{
  NSString *term;
  if ([extensionKey isEqualToString:@"<none>"]) {
    // No dot after the first character, or a dot at the end (".profile",
    // "README", "notes.").
    term = @"^(\\.?[^.]*|.*\\.)$";
  } else {
    NSMutableString *escaped = [NSMutableString string];
    NSCharacterSet *special = [NSCharacterSet characterSetWithCharactersInString:@"\\.[]{}()*+?^$|"];
    for (NSUInteger i = 0; i < [extensionKey length]; i++) {
      unichar c = [extensionKey characterAtIndex:i];
      if ([special characterIsMember:c]) {
        [escaped appendString:@"\\"];
      }
      [escaped appendFormat:@"%C", c];
    }
    // A character before the dot: ".txt" alone is a hidden file.
    term = [NSString stringWithFormat:@".\\.%@$", escaped];
  }
  LDSearchOptions *options = [self optionsWithTerm:term];
  [options setUsesRegex:YES];
  [options setCaseSensitive:NO];
  [options setWholePhrase:NO];
  [options setIncludesFolders:NO];
  return options;
}

- (id)init
{
  self = [super init];
  if (self) {
    _includesFiles = YES;
    _includesFolders = YES;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  LDSearchOptions *copy = [[[self class] allocWithZone:zone] init];
  [copy setTerm:_term];
  [copy setUsesRegex:_usesRegex];
  [copy setCaseSensitive:_caseSensitive];
  [copy setWholePhrase:_wholePhrase];
  [copy setIncludesFiles:_includesFiles];
  [copy setIncludesFolders:_includesFolders];
  [copy setOwner:_owner];
  [copy setLogicalMinimum:_logicalMinimum];
  [copy setLogicalMaximum:_logicalMaximum];
  [copy setPhysicalMinimum:_physicalMinimum];
  [copy setPhysicalMaximum:_physicalMaximum];
  return copy;
}

- (NSString *)term { return _term ? _term : @""; }
- (void)setTerm:(NSString *)term { _term = [term copy]; }
- (BOOL)usesRegex { return _usesRegex; }
- (void)setUsesRegex:(BOOL)flag { _usesRegex = flag; }
- (BOOL)caseSensitive { return _caseSensitive; }
- (void)setCaseSensitive:(BOOL)flag { _caseSensitive = flag; }
- (BOOL)wholePhrase { return _wholePhrase; }
- (void)setWholePhrase:(BOOL)flag { _wholePhrase = flag; }
- (BOOL)includesFiles { return _includesFiles; }
- (void)setIncludesFiles:(BOOL)flag { _includesFiles = flag; }
- (BOOL)includesFolders { return _includesFolders; }
- (void)setIncludesFolders:(BOOL)flag { _includesFolders = flag; }
- (NSString *)owner { return _owner ? _owner : @""; }
- (void)setOwner:(NSString *)owner { _owner = [owner copy]; }
- (NSNumber *)logicalMinimum { return _logicalMinimum; }
- (void)setLogicalMinimum:(NSNumber *)bytes { _logicalMinimum = bytes; }
- (NSNumber *)logicalMaximum { return _logicalMaximum; }
- (void)setLogicalMaximum:(NSNumber *)bytes { _logicalMaximum = bytes; }
- (NSNumber *)physicalMinimum { return _physicalMinimum; }
- (void)setPhysicalMinimum:(NSNumber *)bytes { _physicalMinimum = bytes; }
- (NSNumber *)physicalMaximum { return _physicalMaximum; }
- (void)setPhysicalMaximum:(NSNumber *)bytes { _physicalMaximum = bytes; }

@end

@interface LDSearchResult (Totals)
- (void)setTotalLogicalSize:(unsigned long long)logical physical:(unsigned long long)physical;
@end

@implementation LDSearchResult

- (id)initWithNodes:(NSArray *)nodes matchCount:(NSUInteger)matchCount
{
  self = [super init];
  if (self) {
    _nodes = [nodes copy];
    _matchCount = matchCount;
  }
  return self;
}

- (NSArray *)nodes { return _nodes; }
- (NSUInteger)matchCount { return _matchCount; }
- (unsigned long long)totalLogicalSize { return _totalLogicalSize; }
- (unsigned long long)totalPhysicalSize { return _totalPhysicalSize; }
- (void)setTotalLogicalSize:(unsigned long long)logical physical:(unsigned long long)physical
{
  _totalLogicalSize = logical;
  _totalPhysicalSize = physical;
}
- (BOOL)isCapped { return _matchCount > [_nodes count]; }

@end

@implementation LDSearch

+ (NSString *)globPatternForTerm:(NSString *)term
{
  NSMutableString *pattern = [NSMutableString string];
  NSUInteger length = [term length];
  for (NSUInteger index = 0; index < length; index++) {
    unichar character = [term characterAtIndex:index];
    if (character == '*') {
      [pattern appendString:@"[^/]*"];
    } else if (character == '?') {
      [pattern appendString:@"[^/]"];
    } else {
      if (character < 128 && strchr(".[]()+{}|^$\\", (int)character)) {
        [pattern appendString:@"\\"];
      }
      [pattern appendFormat:@"%C", character];
    }
  }
  return pattern;
}

+ (NSString *)regexPatternForOptions:(LDSearchOptions *)options
{
  NSString *body = [options usesRegex] ? [options term] : [self globPatternForTerm:[options term]];
  if ([options wholePhrase]) {
    return [NSString stringWithFormat:@"^(%@)$", body];
  }
  return body;
}

+ (NSError *)errorWithCode:(LDSearchErrorCode)code description:(NSString *)description
{
  NSDictionary *info = [NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey];
  return [NSError errorWithDomain:LDSearchErrorDomain code:code userInfo:info];
}

// Upstream: an empty term is ".*", so the other conditions alone decide.
+ (LDNameMatcher *)matcherForOptions:(LDSearchOptions *)options error:(NSError **)error
{
  if (![options includesFiles] && ![options includesFolders]) {
    if (error) {
      *error = [self errorWithCode:LDSearchErrorNoItemTypes description:@"Choose files, folders or both."];
    }
    return nil;
  }
  NSNumber *ranges[2][2] = {{[options logicalMinimum], [options logicalMaximum]},
                            {[options physicalMinimum], [options physicalMaximum]}};
  for (int i = 0; i < 2; i++) {
    if (ranges[i][0] && ranges[i][1] && [ranges[i][0] unsignedLongLongValue] > [ranges[i][1] unsignedLongLongValue]) {
      if (error) {
        *error = [self errorWithCode:LDSearchErrorInvalidRange description:@"A size minimum is above its maximum."];
      }
      return nil;
    }
  }
  if ([[options term] length] == 0) {
    return [[LDNameMatcher alloc] initWithPattern:@".*" caseSensitive:NO errorMessage:NULL];
  }
  NSString *message = nil;
  LDNameMatcher *matcher = [[LDNameMatcher alloc] initWithPattern:[self regexPatternForOptions:options]
                                                    caseSensitive:[options caseSensitive]
                                                     errorMessage:&message];
  if (!matcher && error) {
    *error = [self errorWithCode:LDSearchErrorInvalidRegex description:message];
  }
  return matcher;
}

+ (BOOL)validateOptions:(LDSearchOptions *)options error:(NSError **)error
{
  return [self matcherForOptions:options error:error] != nil;
}

+ (NSArray *)history:(NSArray *)history byAdding:(LDSearchOptions *)options limit:(NSUInteger)limit
{
  NSMutableArray *result = [NSMutableArray array];
  NSString *term = [options term];
  if ([term length] > 0 && limit > 0) {
    [result addObject:@{@"Term": term, @"Regex": @([options usesRegex]),
                        @"WholePhrase": @([options wholePhrase]), @"Case": @([options caseSensitive])}];
  }
  for (NSDictionary *entry in history) {
    if ([result count] >= limit) {
      break;
    }
    NSString *old = [entry isKindOfClass:[NSDictionary class]] ? [entry objectForKey:@"Term"] : nil;
    if ([old isKindOfClass:[NSString class]] && [old length] > 0 && ![old isEqualToString:term]) {
      [result addObject:entry];
    }
  }
  return result;
}

+ (id)bytesForSizeField:(NSString *)text unit:(NSInteger)unit
{
  NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if ([trimmed length] == 0) {
    return nil;
  }
  int shift = 10 * (int)MAX(0, MIN(4, unit));
  unsigned long long limit = ULLONG_MAX >> shift;
  unsigned long long value = 0;
  for (NSUInteger i = 0; i < [trimmed length]; i++) {
    unichar c = [trimmed characterAtIndex:i];
    if (c < '0' || c > '9' || value > (limit - (c - '0')) / 10) {
      return [NSNull null];
    }
    value = value * 10 + (c - '0');
  }
  return @(value << shift);
}

+ (BOOL)termImpliesWholePhrase:(NSString *)term
{
  return [term rangeOfString:@"*"].location != NSNotFound;
}

+ (LDSearchResult *)searchNode:(LDFileNode *)root
                       options:(LDSearchOptions *)options
                    maxResults:(NSUInteger)maxResults
{
  LDNameMatcher *matcher = [self matcherForOptions:options error:NULL];
  if (!matcher) {
    return nil;
  }
  LDTopNodeCollector *collector = [[LDTopNodeCollector alloc] initWithLimit:maxResults == 0 ? NSUIntegerMax : maxResults];
  BOOL files = [options includesFiles];
  BOOL folders = [options includesFolders];
  NSString *owner = [options owner];
  NSNumber *logicalMinimum = [options logicalMinimum], *logicalMaximum = [options logicalMaximum];
  NSNumber *physicalMinimum = [options physicalMinimum], *physicalMaximum = [options physicalMaximum];
  LDVisitNodes(root, ^(LDFileNode *node) {
    // Never a scan root: the one searched, or each under "This Computer".
    if (node == root || [node isSpaceItem] || [node isComputer] || [[node parent] isComputer]) {
      return;
    }
    BOOL folder = [node kind] == LDFileNodeKindDirectory;
    if (folder ? !folders : !files) {
      return;
    }
    unsigned long long logical = [node aggregateSize];
    unsigned long long physical = [node aggregateAllocatedSize];
    if ((logicalMinimum && logical < [logicalMinimum unsignedLongLongValue])
        || (logicalMaximum && logical > [logicalMaximum unsignedLongLongValue])
        || (physicalMinimum && physical < [physicalMinimum unsignedLongLongValue])
        || (physicalMaximum && physical > [physicalMaximum unsignedLongLongValue])) {
      return;
    }
    if (![matcher matchesName:[node nameBytes]]) {
      return;
    }
    if ([owner length] > 0) {
      NSString *nodeOwner = [LDFileAttributes ownerOfPath:[node pathData]];
      if (!nodeOwner || [nodeOwner rangeOfString:owner options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return;
      }
    }
    [collector offerNode:node size:logical];
  });
  NSArray *nodes = [collector sortedNodes];
  LDSearchResult *result = [[LDSearchResult alloc] initWithNodes:nodes matchCount:[collector offeredCount]];
  // Only the outermost matches count toward the totals.
  NSSet *matched = [NSSet setWithArray:nodes];
  unsigned long long logicalTotal = 0, physicalTotal = 0;
  for (LDFileNode *node in nodes) {
    LDFileNode *ancestor = [node parent];
    while (ancestor && ![matched containsObject:ancestor]) {
      ancestor = [ancestor parent];
    }
    if (!ancestor) {
      logicalTotal += [node aggregateSize];
      physicalTotal += [node aggregateAllocatedSize];
    }
  }
  [result setTotalLogicalSize:logicalTotal physical:physicalTotal];
  return result;
}

@end
