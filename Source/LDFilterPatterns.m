#import "LDFilterPatterns.h"

#include <regex.h>

@implementation LDFilterPatterns

+ (NSArray *)patternsFromString:(NSString *)string
{
  NSMutableArray *patterns = [NSMutableArray array];
  for (NSString *line in [string ?: @"" componentsSeparatedByString:@"\n"]) {
    NSString *pattern = [line hasSuffix:@"\r"] ? [line substringToIndex:[line length] - 1] : line;
    if ([pattern length] > 0) {
      [patterns addObject:pattern];
    }
  }
  return patterns;
}

+ (BOOL)isValidRegularExpression:(NSString *)pattern
{
  const char *utf8 = [pattern UTF8String];
  if (!utf8) {
    return NO;
  }
  regex_t regex;
  if (regcomp(&regex, utf8, REG_EXTENDED | REG_ICASE | REG_NOSUB) != 0) {
    return NO;
  }
  regfree(&regex);
  return YES;
}

+ (NSString *)firstInvalidPatternInString:(NSString *)string usesRegex:(BOOL)usesRegex
{
  if (!usesRegex) {
    return nil;
  }
  for (NSString *pattern in [self patternsFromString:string]) {
    if (![self isValidRegularExpression:pattern]) {
      return pattern;
    }
  }
  return nil;
}

+ (NSString *)literalPattern:(NSString *)text usesRegex:(BOOL)usesRegex
{
  if (!usesRegex) {
    return text;
  }
  NSMutableString *escaped = [NSMutableString stringWithCapacity:[text length]];
  NSCharacterSet *special = [NSCharacterSet characterSetWithCharactersInString:@".^$|()[]{}*+?\\"];
  for (NSUInteger i = 0; i < [text length]; i++) {
    unichar c = [text characterAtIndex:i];
    if ([special characterIsMember:c]) {
      [escaped appendString:@"\\"];
    }
    [escaped appendFormat:@"%C", c];
  }
  return escaped;
}

+ (NSString *)patternForExtension:(NSString *)key usesRegex:(BOOL)usesRegex
{
  if ([key length] == 0 || [key isEqualToString:@"<none>"]) {
    return nil;
  }
  NSString *suffix = [@"." stringByAppendingString:key];
  return usesRegex ? [@".+" stringByAppendingString:[self literalPattern:suffix usesRegex:YES]]
                   : [@"?*" stringByAppendingString:suffix];
}

+ (NSString *)string:(NSString *)string byAddingPattern:(NSString *)pattern
{
  if ([[self patternsFromString:string] containsObject:pattern]) {
    return string;
  }
  NSString *current = string ?: @"";
  if ([current length] == 0 || [current hasSuffix:@"\n"]) {
    return [current stringByAppendingString:pattern];
  }
  return [NSString stringWithFormat:@"%@\n%@", current, pattern];
}

@end
