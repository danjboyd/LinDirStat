#import "LDSearch.h"
#import "LDNodeRanking.h"

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

- (id)copyWithZone:(NSZone *)zone
{
  LDSearchOptions *copy = [[[self class] allocWithZone:zone] init];
  [copy setTerm:_term];
  [copy setUsesRegex:_usesRegex];
  [copy setCaseSensitive:_caseSensitive];
  [copy setWholePhrase:_wholePhrase];
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

+ (LDNameMatcher *)matcherForOptions:(LDSearchOptions *)options error:(NSError **)error
{
  if ([[options term] length] == 0) {
    if (error) {
      *error = [self errorWithCode:LDSearchErrorEmptyTerm description:@"The search term is empty."];
    }
    return nil;
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
  LDVisitNodes(root, ^(LDFileNode *node) {
    if ([node kind] != LDFileNodeKindDirectory && ![node isSpaceItem] && [matcher matchesName:[node nameBytes]]) {
      [collector offerNode:node size:[node size]];
    }
  });
  return [[LDSearchResult alloc] initWithNodes:[collector sortedNodes] matchCount:[collector offeredCount]];
}

@end
