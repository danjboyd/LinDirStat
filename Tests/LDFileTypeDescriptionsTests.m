#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileTypeDescriptions.h"

@interface LDFileTypeDescriptionsTests : XCTestCase
@end

@implementation LDFileTypeDescriptionsTests

- (LDFileTypeDescriptions *)descriptions
{
  NSString *directory = [[[NSFileManager defaultManager] currentDirectoryPath]
                         stringByAppendingPathComponent:@"Tests/Fixtures/mime"];
  return [[LDFileTypeDescriptions alloc] initWithMimeDirectory:directory];
}

- (void)testUsesTheUntranslatedComment
{
  XCTAssertEqualObjects(@"Plain text document", [[self descriptions] descriptionForExtensionKey:@"txt"]);
}

- (void)testLowercaseGlobWinsOverCaseFoldedOne
{
  // "*.C" is C++; "*.c" is C. Extension keys are lowercase.
  XCTAssertEqualObjects(@"C source code", [[self descriptions] descriptionForExtensionKey:@"c"]);
}

- (void)testHigherWeightWinsAndEntitiesAreDecoded
{
  XCTAssertEqualObjects(@"Data & settings", [[self descriptions] descriptionForExtensionKey:@"dat"]);
}

- (void)testMimeTypeForExtension
{
  LDFileTypeDescriptions *descriptions = [self descriptions];
  XCTAssertEqualObjects(@"text/plain", [descriptions mimeTypeForExtensionKey:@"txt"]);
  XCTAssertEqualObjects(@"application/x-high", [descriptions mimeTypeForExtensionKey:@"dat"]);
  XCTAssertNil([descriptions mimeTypeForExtensionKey:@"zzz"]);
  XCTAssertNil([descriptions mimeTypeForExtensionKey:nil]);
  XCTAssertNil([[[LDFileTypeDescriptions alloc] initWithMimeDirectory:nil] mimeTypeForExtensionKey:@"txt"]);
}

// Group Unregistered Types: an extension is registered when a simple glob
// names it; files without one never group, and nothing does without a
// database.
- (void)testRegisteredExtensions
{
  LDFileTypeDescriptions *descriptions = [self descriptions];
  XCTAssertTrue([descriptions isExtensionKeyRegistered:@"txt"]);
  XCTAssertTrue([descriptions isExtensionKeyRegistered:@"dat"]);
  XCTAssertFalse([descriptions isExtensionKeyRegistered:@"zzz"]);
  XCTAssertFalse([descriptions isExtensionKeyRegistered:@"gz"]);
  XCTAssertTrue([descriptions isExtensionKeyRegistered:@"<none>"]);
  XCTAssertTrue([descriptions isExtensionKeyRegistered:@""]);
  LDFileTypeDescriptions *missing = [[LDFileTypeDescriptions alloc] initWithMimeDirectory:@"/nonexistent/lindirstat-mime"];
  XCTAssertTrue([missing isExtensionKeyRegistered:@"zzz"]);
}

- (void)testUnknownAndMissingExtensions
{
  LDFileTypeDescriptions *descriptions = [self descriptions];
  XCTAssertNil([descriptions descriptionForExtensionKey:@"zzz"]);
  XCTAssertNil([descriptions descriptionForExtensionKey:@"<none>"]);
  // Compound globs are not simple extensions; the type file is missing anyway.
  XCTAssertNil([descriptions descriptionForExtensionKey:@"tar.gz"]);
}

#if defined(__APPLE__)
- (void)testSystemDescriptionsComeFromUniformTypes
{
  LDFileTypeDescriptions *system = [[LDFileTypeDescriptions alloc] initWithMimeDirectory:nil];
  XCTAssertTrue([[[system descriptionForExtensionKey:@"pdf"] uppercaseString] rangeOfString:@"PDF"].location != NSNotFound);
  XCTAssertNil([system descriptionForExtensionKey:@"lindirstatnosuchtype"]);
  XCTAssertNil([system descriptionForExtensionKey:@"<none>"]);
}

- (void)testRegisteredExtensionsComeFromUniformTypes
{
  LDFileTypeDescriptions *system = [[LDFileTypeDescriptions alloc] initWithMimeDirectory:nil];
  XCTAssertTrue([system isExtensionKeyRegistered:@"pdf"]);
  XCTAssertFalse([system isExtensionKeyRegistered:@"lindirstatnosuchtype"]);
}
#endif

@end
