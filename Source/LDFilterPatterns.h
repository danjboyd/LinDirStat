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

// Add to Exclusion Filter (WinDirStat 2.5.8, a874bcf4 and later): a pattern
// that matches `text` (a file's name or a folder's path) literally. Regular
// expressions escape the special characters; globs take the text as it is.
+ (NSString *)literalPattern:(NSString *)text usesRegex:(BOOL)usesRegex;

// A file name pattern for every file with the extension key `key` (as
// LDExtensionStats gives it: "txt", no dot): "?*.txt", or ".+\.txt" as a
// regular expression. The name needs a character before the dot, since a
// leading dot marks a hidden file, not an extension. Nil for "<none>",
// which no pattern can select.
+ (NSString *)patternForExtension:(NSString *)key usesRegex:(BOOL)usesRegex;

// `string` with `pattern` added as a new last line, or unchanged when the
// pattern is already one of its lines.
+ (NSString *)string:(NSString *)string byAddingPattern:(NSString *)pattern;

@end
