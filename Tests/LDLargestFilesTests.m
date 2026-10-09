#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDLargestFiles.h"
#import "LDNodeRanking.h"

@interface LDLargestFilesTests : XCTestCase
@end

@implementation LDLargestFilesTests

- (LDFileNode *)addFile:(NSString *)name size:(unsigned long long)size to:(LDFileNode *)parent
{
  LDFileNode *node = [LDFileNode nodeWithName:name kind:LDFileNodeKindFile size:size allocatedSize:size];
  [parent addChild:node];
  return node;
}

- (LDFileNode *)addDirectory:(NSString *)name to:(LDFileNode *)parent
{
  LDFileNode *node = [LDFileNode nodeWithName:name kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [parent addChild:node];
  return node;
}

- (NSArray *)namesOf:(NSArray *)nodes
{
  NSMutableArray *names = [NSMutableArray array];
  for (LDFileNode *node in nodes) {
    [names addObject:[node displayName]];
  }
  return names;
}

- (void)testRanksByLogicalSizeAcrossDirectories
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  LDFileNode *sub = [self addDirectory:@"sub" to:root];
  [self addFile:@"small" size:10 to:root];
  [self addFile:@"big" size:1000 to:sub];
  [self addFile:@"medium" size:500 to:root];
  // A sparse file: tiny on disk but large logically, so it ranks by logical size.
  LDFileNode *sparse = [LDFileNode nodeWithName:@"sparse" kind:LDFileNodeKindFile size:800 allocatedSize:4];
  [sub addChild:sparse];

  NSArray *largest = [LDLargestFiles largestFilesUnderNode:root count:3];
  NSArray *expected = [NSArray arrayWithObjects:@"big", @"sparse", @"medium", nil];
  XCTAssertEqualObjects(expected, [self namesOf:largest]);
}

- (void)testCountZeroReturnsEmpty
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  [self addFile:@"a" size:10 to:root];
  XCTAssertEqual((NSUInteger)0, [[LDLargestFiles largestFilesUnderNode:root count:0] count]);
}

- (void)testCountLargerThanFilesReturnsAll
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  [self addFile:@"a" size:10 to:root];
  [self addFile:@"b" size:20 to:root];
  NSArray *expected = [NSArray arrayWithObjects:@"b", @"a", nil];
  XCTAssertEqualObjects(expected, [self namesOf:[LDLargestFiles largestFilesUnderNode:root count:50]]);
}

- (void)testTiesAreOrderedByPathBytes
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  LDFileNode *a = [self addDirectory:@"a" to:root];
  LDFileNode *dotted = [self addDirectory:@"a.b" to:root];
  [self addFile:@"z" size:5 to:dotted];
  [self addFile:@"y" size:5 to:a];
  [self addFile:@"x" size:5 to:root];
  [self addFile:@"w" size:5 to:root];

  // Byte order of full paths: "/data/a.b/z" < "/data/a/y" < "/data/w" < "/data/x".
  NSArray *largest = [LDLargestFiles largestFilesUnderNode:root count:3];
  NSArray *expected = [NSArray arrayWithObjects:@"z", @"y", @"w", nil];
  XCTAssertEqualObjects(expected, [self namesOf:largest]);
}

- (void)testExcludesDirectoriesSpecialFailedAndHardLinkDuplicates
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  [self addFile:@"plain" size:1 to:root];
  LDFileNode *linked = [self addFile:@"linked" size:100 to:root];
  [linked setError:LDFileNodeErrorHardLinkDuplicate errorNumber:0];
  LDFileNode *failed = [self addFile:@"failed" size:100 to:root];
  [failed setError:LDFileNodeErrorStatFailed errorNumber:13];
  LDFileNode *fifo = [LDFileNode nodeWithName:@"fifo" kind:LDFileNodeKindSpecial size:100 allocatedSize:0];
  [root addChild:fifo];
  LDFileNode *directory = [self addDirectory:@"dir" to:root];
  [directory setSize:100 allocatedSize:100];

  NSArray *expected = [NSArray arrayWithObject:@"plain"];
  XCTAssertEqualObjects(expected, [self namesOf:[LDLargestFiles largestFilesUnderNode:root count:10]]);
}

- (void)testHeapKeepsTopEntriesFromManyFiles
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  // Sizes in a scrambled order so the heap has to replace entries.
  for (NSUInteger index = 0; index < 1000; index++) {
    unsigned long long size = (index * 7919) % 1000;
    [self addFile:[NSString stringWithFormat:@"f%04lu", (unsigned long)size] size:size to:root];
  }
  NSArray *largest = [LDLargestFiles largestFilesUnderNode:root count:5];
  NSArray *expected = [NSArray arrayWithObjects:@"f0999", @"f0998", @"f0997", @"f0996", @"f0995", nil];
  XCTAssertEqualObjects(expected, [self namesOf:largest]);
}

- (void)testPathComparisonMatchesPathData
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/" kind:LDFileNodeKindDirectory size:0];
  LDFileNode *a = [self addDirectory:@"a" to:root];
  LDFileNode *dotted = [self addDirectory:@"a.b" to:root];
  LDFileNode *deep = [self addFile:@"deep" size:0 to:a];
  LDFileNode *shallow = [self addFile:@"c" size:0 to:dotted];

  XCTAssertEqual(NSOrderedDescending, LDCompareNodePaths(deep, shallow));
  XCTAssertEqual(NSOrderedAscending, LDCompareNodePaths(shallow, deep));
  XCTAssertEqual(NSOrderedAscending, LDCompareNodePaths(a, deep));
  XCTAssertEqual(NSOrderedSame, LDCompareNodePaths(deep, deep));
  LDFileNode *other = [LDFileNode nodeWithPath:@"/b" kind:LDFileNodeKindFile size:0];
  XCTAssertEqual(NSOrderedAscending, LDCompareNodePaths(deep, other));
}

@end
