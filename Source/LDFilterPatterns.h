#import <Foundation/Foundation.h>

// Parsing and validation of the Filtering page's exclusion lists
// (PageFiltering.cpp, Options.cpp:201-227). Patterns are one per line; a
// trailing carriage return is trimmed and blank lines are ignored. Regular
// expressions are POSIX extended and case-insensitive.
@interface LDFilterPatterns : NSObject

// The non-blank lines of `string`, in order.
+ (NSArray *)patternsFromString:(NSString *)string;

// YES if `pattern` compiles with regcomp(REG_EXTENDED | REG_ICASE).
+ (BOOL)isValidRegularExpression:(NSString *)pattern;

// The first pattern that cannot be used, or nil when all are valid. Every
// glob pattern is valid.
+ (NSString *)firstInvalidPatternInString:(NSString *)string usesRegex:(BOOL)usesRegex;

@end
