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

@end
