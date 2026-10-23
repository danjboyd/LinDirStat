#import <Foundation/Foundation.h>
#import "LDFileNode.h"

FOUNDATION_EXPORT NSString *const LDSearchErrorDomain;

typedef enum {
  LDSearchErrorEmptyTerm = 1,      // no longer reported: an empty term matches every name
  LDSearchErrorInvalidRegex = 2,
  LDSearchErrorNoItemTypes = 3,    // neither files nor folders
  LDSearchErrorInvalidRange = 4    // a size minimum above its maximum
} LDSearchErrorCode;

// The Search dialog's settings (SearchDlg.cpp).
@interface LDSearchOptions : NSObject <NSCopying>
{
  NSString *_term;
  BOOL _usesRegex;
  BOOL _caseSensitive;
  BOOL _wholePhrase;
  BOOL _includesFiles;
  BOOL _includesFolders;
  NSString *_owner;
  NSNumber *_logicalMinimum;
  NSNumber *_logicalMaximum;
  NSNumber *_physicalMinimum;
  NSNumber *_physicalMaximum;
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
// WinDirStat 2.6-2.7 (7bfc8ccb, b7edc158): files and folders (both YES by
// default) can match, never a scan root (the root searched, or each one
// under "This Computer"); an owner (a case-insensitive
// part of the owning user's name, empty for any); and logical and physical
// size ranges in bytes (nil: no bound), a folder's being its subtree's.
- (BOOL)includesFiles;
- (void)setIncludesFiles:(BOOL)flag;
- (BOOL)includesFolders;
- (void)setIncludesFolders:(BOOL)flag;
- (NSString *)owner;
- (void)setOwner:(NSString *)owner;
- (NSNumber *)logicalMinimum;
- (void)setLogicalMinimum:(NSNumber *)bytes;
- (NSNumber *)logicalMaximum;
- (void)setLogicalMaximum:(NSNumber *)bytes;
- (NSNumber *)physicalMinimum;
- (void)setPhysicalMinimum:(NSNumber *)bytes;
- (NSNumber *)physicalMaximum;
- (void)setPhysicalMaximum:(NSNumber *)bytes;

@end

@interface LDSearchResult : NSObject
{
  NSArray *_nodes;
  NSUInteger _matchCount;
  unsigned long long _totalLogicalSize;
  unsigned long long _totalPhysicalSize;
}

- (id)initWithNodes:(NSArray *)nodes matchCount:(NSUInteger)matchCount;
// The kept matches' sizes, a match inside another counted once (WinDirStat's
// CItemSearch::CalculateTotals).
- (unsigned long long)totalLogicalSize;
- (unsigned long long)totalPhysicalSize;
// Matching items, largest logical size first, ties by path.
- (NSArray *)nodes;
// Every match found, including those dropped by the cap.
- (NSUInteger)matchCount;
// YES when matches were dropped: WinDirStat shows "Search Results (N+)".
- (BOOL)isCapped;

@end

@interface LDSearch : NSObject

// The ERE the options compile to.
+ (NSString *)regexPatternForOptions:(LDSearchOptions *)options;
// NO for a regex that does not compile, no item type, or a size range whose
// minimum is above its maximum; OK stays disabled. An empty term matches
// every name.
+ (BOOL)validateOptions:(LDSearchOptions *)options error:(NSError **)error;
// The search history after a search (WinDirStat's SaveSearchHistory):
// options' term with its Regex/WholePhrase/Case first, an older entry with
// the same term dropped, at most limit entries. Entries are dictionaries
// as LDPreferences -searchHistory keeps them.
+ (NSArray *)history:(NSArray *)history byAdding:(LDSearchOptions *)options limit:(NSUInteger)limit;
// A size field as typed: nil (no bound) when empty, NSNull when it is not
// a whole number that fits, else the bytes (value << 10 * unit).
+ (id)bytesForSizeField:(NSString *)text unit:(NSInteger)unit;
// Typing * in glob mode ticks Whole Phrase in WinDirStat's dialog.
+ (BOOL)termImpliesWholePhrase:(NSString *)term;

// Matches the names (not paths) of the files and folders below root, using
// the raw name bytes so names that are not UTF-8 work; the size ranges are
// checked first and the owner last (it means an lstat). Beyond maxResults
// (0 = no limit) only the largest by logical size are kept. Returns nil for
// options that do not validate.
+ (LDSearchResult *)searchNode:(LDFileNode *)root
                       options:(LDSearchOptions *)options
                    maxResults:(NSUInteger)maxResults;

@end
