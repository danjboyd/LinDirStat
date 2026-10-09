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

- (void)testDirectoryNamesDoNotMatch
{
  XCTAssertEqual((NSUInteger)0, [[self search:@"photos" configure:nil] count]);
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
  XCTAssertFalse([LDSearch validateOptions:[LDSearchOptions optionsWithTerm:@""] error:&error]);
  XCTAssertEqual((NSInteger)LDSearchErrorEmptyTerm, [error code]);

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

@end
