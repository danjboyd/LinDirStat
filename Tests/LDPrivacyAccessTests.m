#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDPrivacyAccess.h"

#include <errno.h>

@interface LDPrivacyAccessTests : XCTestCase
@end

@implementation LDPrivacyAccessTests

- (LDFileNode *)directory:(const char *)name
{
  return [LDFileNode nodeWithNameBytes:name length:strlen(name) arena:nil
                                  kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
}

- (void)testFindsDirectoriesDeniedWithEPERMInTreeOrder
{
  LDFileNode *root = [self directory:"/root"];
  LDFileNode *library = [self directory:"Library"];
  LDFileNode *mail = [self directory:"Mail"];
  LDFileNode *safari = [self directory:"Safari"];
  LDFileNode *locked = [self directory:"locked"];
  [root addChild:library];
  [root addChild:locked];
  [library addChild:mail];
  [library addChild:safari];
  [mail setError:LDFileNodeErrorDirectoryUnreadable errorNumber:EPERM];
  [safari setError:LDFileNodeErrorDirectoryUnreadable errorNumber:EPERM];
  // Ordinary Unix permissions are not privacy protection.
  [locked setError:LDFileNodeErrorDirectoryUnreadable errorNumber:EACCES];

  NSArray *denied = [LDPrivacyAccess directoriesDeniedByPrivacyUnder:root limit:10];
  XCTAssertEqual((NSUInteger)2, [denied count]);
  XCTAssertEqual(mail, [denied objectAtIndex:0]);
  XCTAssertEqual(safari, [denied objectAtIndex:1]);
  XCTAssertEqual(EPERM, [mail errorNumber]);
}

- (void)testStopsAtTheLimit
{
  LDFileNode *root = [self directory:"/root"];
  for (int i = 0; i < 5; i++) {
    LDFileNode *child = [self directory:"denied"];
    [child setError:LDFileNodeErrorDirectoryUnreadable errorNumber:EPERM];
    [root addChild:child];
  }
  XCTAssertEqual((NSUInteger)3, [[LDPrivacyAccess directoriesDeniedByPrivacyUnder:root limit:3] count]);
  XCTAssertEqual((NSUInteger)0, [[LDPrivacyAccess directoriesDeniedByPrivacyUnder:nil limit:3] count]);
}

- (void)testFullDiskAccessCheckDoesNotFailOffMacOS
{
#if !defined(__APPLE__)
  XCTAssertTrue([LDPrivacyAccess hasFullDiskAccess]);
#else
  (void)[LDPrivacyAccess hasFullDiskAccess];
#endif
}

@end
