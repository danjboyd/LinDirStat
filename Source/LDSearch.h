#import <Foundation/Foundation.h>
#import "LDFileNode.h"

FOUNDATION_EXPORT NSString *const LDSearchErrorDomain;

typedef enum {
  LDSearchErrorEmptyTerm = 1,
  LDSearchErrorInvalidRegex = 2
} LDSearchErrorCode;

// The Search dialog's settings (SearchDlg.cpp).
@interface LDSearchOptions : NSObject <NSCopying>
{
  NSString *_term;
  BOOL _usesRegex;
  BOOL _caseSensitive;
  BOOL _wholePhrase;
}

+ (LDSearchOptions *)optionsWithTerm:(NSString *)term;
- (NSString *)term;
- (void)setTerm:(NSString *)term;
// The term is a POSIX extended regular expression (regcomp REG_EXTENDED),
// not WinDirStat's ECMAScript std::regex: no \d, lookarounds or lazy
// quantifiers. Otherwise it is a glob where * and ? match within a name and
// every other character is literal.
- (BOOL)usesRegex;
- (void)setUsesRegex:(BOOL)flag;
- (BOOL)caseSensitive;
- (void)setCaseSensitive:(BOOL)flag;
// YES: the whole name must match. NO: any part of it may.
- (BOOL)wholePhrase;
- (void)setWholePhrase:(BOOL)flag;

@end

@interface LDSearchResult : NSObject
{
  NSArray *_nodes;
  NSUInteger _matchCount;
}

- (id)initWithNodes:(NSArray *)nodes matchCount:(NSUInteger)matchCount;
// Matching files, largest logical size first, ties by path.
- (NSArray *)nodes;
// Every match found, including those dropped by the cap.
- (NSUInteger)matchCount;
// YES when matches were dropped: WinDirStat shows "Search Results (N+)".
- (BOOL)isCapped;

@end

@interface LDSearch : NSObject

// The ERE the options compile to.
+ (NSString *)regexPatternForOptions:(LDSearchOptions *)options;
// NO for an empty term or a regex that does not compile; OK stays disabled.
+ (BOOL)validateOptions:(LDSearchOptions *)options error:(NSError **)error;
// Typing * in glob mode ticks Whole Phrase in WinDirStat's dialog.
+ (BOOL)termImpliesWholePhrase:(NSString *)term;

// Matches the names (not paths) of every non-directory below root, using
// the raw name bytes so names that are not UTF-8 work. Beyond maxResults
// (0 = no limit) only the largest by logical size are kept. Returns nil for
// options that do not validate.
+ (LDSearchResult *)searchNode:(LDFileNode *)root
                       options:(LDSearchOptions *)options
                    maxResults:(NSUInteger)maxResults;

@end
