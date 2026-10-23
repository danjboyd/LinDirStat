#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDSearch.h"

@interface LDSearchTests : XCTestCase
{
  LDFileNode *_root;
}
@end

@implementation LDSearchTests

- (LDFileNode *)addFile:(NSString *)name size:(unsigned long long)size to:(LDFileNode *)parent
{
  LDFileNode *node = [LDFileNode nodeWithName:name kind:LDFileNodeKindFile size:size allocatedSize:size];
  [parent addChild:node];
  return node;
}

- (void)setUp
{
  [super setUp];
  _root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  LDFileNode *photos = [LDFileNode nodeWithName:@"photos" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [_root addChild:photos];
  [self addFile:@"Holiday.JPG" size:300 to:photos];
  [self addFile:@"beach.jpg" size:200 to:photos];
  [self addFile:@"notes.txt" size:50 to:_root];
  [self addFile:@"a+b(1).txt" size:10 to:_root];
  [self addFile:@"jpg-list.md" size:5 to:_root];
  LDFileNode *linked = [self addFile:@"linked.jpg" size:1 to:_root];
  [linked setError:LDFileNodeErrorHardLinkDuplicate errorNumber:0];
}

- (void)tearDown
{
  _root = nil;
  [super tearDown];
}

- (NSArray *)search:(NSString *)term configure:(void (^)(LDSearchOptions *options))configure
{
  LDSearchOptions *options = [LDSearchOptions optionsWithTerm:term];
  if (configure) {
    configure(options);
  }
  LDSearchResult *result = [LDSearch searchNode:_root options:options maxResults:0];
  NSMutableArray *names = [NSMutableArray array];
  for (LDFileNode *node in [result nodes]) {
    [names addObject:[node displayName]];
  }
  return names;
}

- (void)testSubstringSearchIsCaseInsensitiveByDefault
{
  NSArray *expected = [NSArray arrayWithObjects:@"Holiday.JPG", @"beach.jpg", @"jpg-list.md", @"linked.jpg", nil];
  XCTAssertEqualObjects(expected, [self search:@"jpg" configure:nil]);
}

- (void)testCaseSensitiveSearch
{
  NSArray *expected = [NSArray arrayWithObject:@"Holiday.JPG"];
  XCTAssertEqualObjects(expected, [self search:@"JPG" configure:^(LDSearchOptions *options) {
    [options setCaseSensitive:YES];
  }]);
}

// Before WinDirStat 2.7 only files matched; now folders do unless left out.
- (void)testDirectoryNamesMatchUnlessFoldersAreLeftOut
{
  XCTAssertEqual((NSUInteger)1, [[self search:@"photos" configure:nil] count]);
  XCTAssertEqual((NSUInteger)0, [[self search:@"photos" configure:^(LDSearchOptions *options) {
    [options setIncludesFolders:NO];
  }] count]);
}

- (void)testGlobWithWholePhrase
{
  NSArray *expected = [NSArray arrayWithObjects:@"Holiday.JPG", @"beach.jpg", @"linked.jpg", nil];
  XCTAssertEqualObjects(expected, [self search:@"*.jpg" configure:^(LDSearchOptions *options) {
    [options setWholePhrase:YES];
  }]);
}

- (void)testGlobQuestionMarkMatchesOneCharacter
{
  NSArray *expected = [NSArray arrayWithObject:@"beach.jpg"];
  XCTAssertEqualObjects(expected, [self search:@"b?ach.jpg" configure:^(LDSearchOptions *options) {
    [options setWholePhrase:YES];
  }]);
  XCTAssertEqual((NSUInteger)0, [[self search:@"b?each.jpg" configure:nil] count]);
}

- (void)testWholePhraseRequiresFullMatch
{
  XCTAssertEqual((NSUInteger)0, [[self search:@"beach" configure:^(LDSearchOptions *options) {
    [options setWholePhrase:YES];
  }] count]);
  XCTAssertEqual((NSUInteger)1, [[self search:@"beach" configure:nil] count]);
}

- (void)testGlobTreatsRegexCharactersLiterally
{
  NSArray *expected = [NSArray arrayWithObject:@"a+b(1).txt"];
  XCTAssertEqualObjects(expected, [self search:@"a+b(1)" configure:nil]);
  XCTAssertEqual((NSUInteger)0, [[self search:@"n.tes" configure:nil] count]);
}

- (void)testRegexSearch
{
  NSArray *expected = [NSArray arrayWithObjects:@"notes.txt", @"a+b(1).txt", @"jpg-list.md", nil];
  XCTAssertEqualObjects(expected, [self search:@"^[a-z].*\\.(txt|md)$" configure:^(LDSearchOptions *options) {
    [options setUsesRegex:YES];
  }]);
  NSArray *whole = [NSArray arrayWithObject:@"notes.txt"];
  XCTAssertEqualObjects(whole, [self search:@"n.tes\\.txt|zzz" configure:^(LDSearchOptions *options) {
    [options setUsesRegex:YES];
    [options setWholePhrase:YES];
  }]);
}

- (void)testNonUTF8NamesMatchByBytes
{
  const char latin1[] = "caf\xe9.dat";
  LDFileNode *node = [LDFileNode nodeWithNameBytes:latin1 length:strlen(latin1) arena:nil kind:LDFileNodeKindFile size:7 allocatedSize:7];
  [_root addChild:node];

  LDSearchResult *result = [LDSearch searchNode:_root options:[LDSearchOptions optionsWithTerm:@"caf?.dat"] maxResults:0];
  XCTAssertEqual((NSUInteger)1, [[result nodes] count]);
  XCTAssertTrue([[result nodes] objectAtIndex:0] == node);
  result = [LDSearch searchNode:_root options:[LDSearchOptions optionsWithTerm:@".DAT"] maxResults:0];
  XCTAssertEqual((NSUInteger)1, [[result nodes] count]);
}

- (void)testUTF8NamesMatchByCharacter
{
  [self addFile:@"café.bin" size:3 to:_root];
  [self addFile:@"Ärger.bin" size:2 to:_root];

  // ? covers the two-byte é, and case folding reaches non-ASCII letters.
  NSArray *expected = [NSArray arrayWithObject:@"café.bin"];
  XCTAssertEqualObjects(expected, [self search:@"caf?.bin" configure:^(LDSearchOptions *options) {
    [options setWholePhrase:YES];
  }]);
  expected = [NSArray arrayWithObject:@"Ärger.bin"];
  XCTAssertEqualObjects(expected, [self search:@"ärger" configure:nil]);
}

- (void)testCapKeepsLargestMatches
{
  LDSearchOptions *options = [LDSearchOptions optionsWithTerm:@"."];
  LDSearchResult *result = [LDSearch searchNode:_root options:options maxResults:2];
  XCTAssertTrue([result isCapped]);
  XCTAssertEqual((NSUInteger)6, [result matchCount]);
  XCTAssertEqual((NSUInteger)2, [[result nodes] count]);
  XCTAssertEqualObjects(@"Holiday.JPG", [[[result nodes] objectAtIndex:0] displayName]);
  XCTAssertEqualObjects(@"beach.jpg", [[[result nodes] objectAtIndex:1] displayName]);

  result = [LDSearch searchNode:_root options:options maxResults:6];
  XCTAssertFalse([result isCapped]);
  XCTAssertEqual((NSUInteger)6, [[result nodes] count]);
}

- (void)testValidation
{
  NSError *error = nil;
  // WinDirStat 2.7: an empty term matches every name.
  XCTAssertTrue([LDSearch validateOptions:[LDSearchOptions optionsWithTerm:@""] error:&error]);
  LDSearchOptions *none = [LDSearchOptions optionsWithTerm:@"x"];
  [none setIncludesFiles:NO];
  [none setIncludesFolders:NO];
  XCTAssertFalse([LDSearch validateOptions:none error:&error]);
  XCTAssertEqual((NSInteger)LDSearchErrorNoItemTypes, [error code]);
  LDSearchOptions *range = [LDSearchOptions optionsWithTerm:@"x"];
  [range setPhysicalMinimum:@100];
  [range setPhysicalMaximum:@10];
  XCTAssertFalse([LDSearch validateOptions:range error:&error]);
  XCTAssertEqual((NSInteger)LDSearchErrorInvalidRange, [error code]);

  LDSearchOptions *bad = [LDSearchOptions optionsWithTerm:@"([a-"];
  [bad setUsesRegex:YES];
  error = nil;
  XCTAssertFalse([LDSearch validateOptions:bad error:&error]);
  XCTAssertEqualObjects(LDSearchErrorDomain, [error domain]);
  XCTAssertEqual((NSInteger)LDSearchErrorInvalidRegex, [error code]);
  XCTAssertNil([LDSearch searchNode:_root options:bad maxResults:0]);

  // The same text is a valid glob.
  [bad setUsesRegex:NO];
  XCTAssertTrue([LDSearch validateOptions:bad error:NULL]);
}

- (void)testGlobPattern
{
  LDSearchOptions *options = [LDSearchOptions optionsWithTerm:@"*.t?t"];
  XCTAssertEqualObjects(@"[^/]*\\.t[^/]t", [LDSearch regexPatternForOptions:options]);
  [options setWholePhrase:YES];
  XCTAssertEqualObjects(@"^([^/]*\\.t[^/]t)$", [LDSearch regexPatternForOptions:options]);
}

- (void)testStarImpliesWholePhrase
{
  XCTAssertTrue([LDSearch termImpliesWholePhrase:@"*.iso"]);
  XCTAssertFalse([LDSearch termImpliesWholePhrase:@"backup?.iso"]);
}

#pragma mark - WinDirStat 2.6-2.7

- (void)testFoldersMatchButNeverTheRoot
{
  [_root recalculateAggregateSize];
  XCTAssertEqualObjects(@[@"photos"], [self search:@"PHOTO" configure:nil]);
  XCTAssertEqualObjects(@[], [self search:@"data" configure:nil]);
  XCTAssertEqualObjects(@[], [self search:@"photos" configure:^(LDSearchOptions *options) {
    [options setIncludesFolders:NO];
  }]);
  XCTAssertEqualObjects((@[@"Holiday.JPG", @"beach.jpg", @"linked.jpg"]), [self search:@".jpg" configure:^(LDSearchOptions *options) {
    [options setIncludesFolders:NO];
  }]);
}

- (void)testSizeRangesAndEmptyTerm
{
  [_root recalculateAggregateSize];
  // Everything from 50 to 300 bytes: a folder counts its subtree (500).
  XCTAssertEqualObjects((@[@"Holiday.JPG", @"beach.jpg", @"notes.txt"]), [self search:@"" configure:^(LDSearchOptions *options) {
    [options setLogicalMinimum:@50];
    [options setLogicalMaximum:@300];
  }]);
  XCTAssertEqualObjects(@[@"photos"], [self search:@"" configure:^(LDSearchOptions *options) {
    [options setPhysicalMinimum:@400];
  }]);
}

- (void)testTotalsCountNestedMatchesOnce
{
  [_root recalculateAggregateSize];
  LDSearchOptions *options = [LDSearchOptions optionsWithTerm:@""];
  [options setLogicalMinimum:@200];
  LDSearchResult *result = [LDSearch searchNode:_root options:options maxResults:0];
  // photos (500) holds Holiday.JPG (300) and beach.jpg (200).
  XCTAssertEqual((NSUInteger)3, [[result nodes] count]);
  XCTAssertEqual((unsigned long long)500, [result totalLogicalSize]);
  XCTAssertEqual((unsigned long long)500, [result totalPhysicalSize]);
}

- (void)testOwnerIsAPartOfTheUserName
{
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];
  [@"x" writeToFile:[root stringByAppendingPathComponent:@"mine.txt"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
  LDFileNode *tree = [LDFileNode nodeWithPath:root kind:LDFileNodeKindDirectory size:0];
  [tree addChild:[LDFileNode nodeWithName:@"mine.txt" kind:LDFileNodeKindFile size:1 allocatedSize:1]];
  NSString *user = NSUserName();
  NSString *part = [[user substringToIndex:MIN((NSUInteger)3, [user length])] uppercaseString];
  LDSearchOptions *options = [LDSearchOptions optionsWithTerm:@"mine"];
  [options setOwner:part];
  XCTAssertEqual((NSUInteger)1, [[[LDSearch searchNode:tree options:options maxResults:0] nodes] count]);
  [options setOwner:@"no-such-user-here"];
  XCTAssertEqual((NSUInteger)0, [[[LDSearch searchNode:tree options:options maxResults:0] nodes] count]);
  [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}

- (void)testHistoryPutsTheNewestFirstOnce
{
  LDSearchOptions *options = [LDSearchOptions optionsWithTerm:@"*.iso"];
  [options setWholePhrase:YES];
  NSArray *old = @[@{@"Term": @"log", @"Regex": @NO, @"WholePhrase": @NO, @"Case": @NO},
                   @{@"Term": @"*.iso", @"Regex": @NO, @"WholePhrase": @NO, @"Case": @NO},
                   @{@"Term": @"tmp", @"Regex": @YES, @"WholePhrase": @NO, @"Case": @NO}];
  NSArray *history = [LDSearch history:old byAdding:options limit:3];
  XCTAssertEqual((NSUInteger)3, [history count]);
  XCTAssertEqualObjects(@"*.iso", [[history objectAtIndex:0] objectForKey:@"Term"]);
  XCTAssertEqualObjects(@YES, [[history objectAtIndex:0] objectForKey:@"WholePhrase"]);
  XCTAssertEqualObjects(@"log", [[history objectAtIndex:1] objectForKey:@"Term"]);
  XCTAssertEqualObjects(@"tmp", [[history objectAtIndex:2] objectForKey:@"Term"]);
  XCTAssertEqual((NSUInteger)0, [[LDSearch history:old byAdding:options limit:0] count]);
  // An empty term is not remembered.
  XCTAssertEqual((NSUInteger)2, [[LDSearch history:old byAdding:[LDSearchOptions optionsWithTerm:@""] limit:2] count]);
}

- (void)testSizeFields
{
  XCTAssertNil([LDSearch bytesForSizeField:@"" unit:2]);
  XCTAssertNil([LDSearch bytesForSizeField:@"  " unit:0]);
  XCTAssertEqualObjects(@(5ULL << 20), [LDSearch bytesForSizeField:@"5" unit:2]);
  XCTAssertEqualObjects([NSNull null], [LDSearch bytesForSizeField:@"5.5" unit:2]);
  XCTAssertEqualObjects([NSNull null], [LDSearch bytesForSizeField:@"-1" unit:0]);
  XCTAssertEqualObjects([NSNull null], [LDSearch bytesForSizeField:@"99999999999999" unit:4]);
}

- (void)testScanRootsUnderThisComputerNeverMatch
{
  LDFileNode *computer = [LDFileNode computerNode];
  LDFileNode *volume = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  [volume addChild:[LDFileNode nodeWithName:@"data-notes.txt" kind:LDFileNodeKindFile size:1 allocatedSize:1]];
  [computer addChild:volume];
  LDSearchResult *result = [LDSearch searchNode:computer options:[LDSearchOptions optionsWithTerm:@"data"] maxResults:0];
  XCTAssertEqual((NSUInteger)1, [[result nodes] count]);
  XCTAssertEqualObjects(@"data-notes.txt", [[[result nodes] firstObject] displayName]);
}

@end
