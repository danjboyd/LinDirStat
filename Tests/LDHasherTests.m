#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDHasher.h"

#include <errno.h>
#include <unistd.h>

@interface LDHasherTests : XCTestCase
{
  NSString *_temporaryRoot;
}
@end

@implementation LDHasherTests

- (NSString *)temporaryRoot
{
  if (!_temporaryRoot) {
    NSString *name = [NSString stringWithFormat:@"lindirstat-hasher-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
    _temporaryRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:_temporaryRoot withIntermediateDirectories:YES attributes:nil error:NULL];
  }
  return _temporaryRoot;
}

- (void)tearDown
{
  if (_temporaryRoot) {
    [[NSFileManager defaultManager] removeItemAtPath:_temporaryRoot error:NULL];
    _temporaryRoot = nil;
  }
  [super tearDown];
}

- (NSData *)pathDataForFile:(NSString *)name contents:(NSData *)contents
{
  NSString *path = [[self temporaryRoot] stringByAppendingPathComponent:name];
  [contents writeToFile:path atomically:NO];
  const char *bytes = [path fileSystemRepresentation];
  return [NSData dataWithBytes:bytes length:strlen(bytes)];
}

- (void)testAlgorithmNamesFollowWinDirStatOrder
{
  NSArray *expected = [NSArray arrayWithObjects:@"MD5", @"SHA1", @"SHA256", @"SHA384", @"SHA512", nil];
  XCTAssertEqualObjects(expected, [LDHasher hashAlgorithmNames]);
}

- (void)testKnownDigestsOfABC
{
  NSData *path = [self pathDataForFile:@"abc.txt" contents:[@"abc" dataUsingEncoding:NSASCIIStringEncoding]];
  NSError *error = nil;
  NSDictionary *hashes = [LDHasher hashesForFileAtPath:path error:&error];

  XCTAssertNil(error);
  XCTAssertEqualObjects(@"900150983cd24fb0d6963f7d28e17f72", [hashes objectForKey:@"MD5"]);
  XCTAssertEqualObjects(@"a9993e364706816aba3e25717850c26c9cd0d89d", [hashes objectForKey:@"SHA1"]);
  XCTAssertEqualObjects(@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", [hashes objectForKey:@"SHA256"]);
  XCTAssertEqualObjects(@"cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed"
                        @"8086072ba1e7cc2358baeca134c825a7",
                        [hashes objectForKey:@"SHA384"]);
  XCTAssertEqualObjects(@"ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
                        @"2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
                        [hashes objectForKey:@"SHA512"]);
}

- (void)testEmptyFileDigests
{
  NSData *path = [self pathDataForFile:@"empty" contents:[NSData data]];
  NSDictionary *hashes = [LDHasher hashesForFileAtPath:path error:NULL];
  XCTAssertEqualObjects(@"d41d8cd98f00b204e9800998ecf8427e", [hashes objectForKey:@"MD5"]);
}

- (void)testMultiChunkFileMatchesKnownDigest
{
  // One million 'a's: the classic SHA-1 vector, spanning many 64 KiB reads.
  NSMutableData *contents = [NSMutableData dataWithLength:1000000];
  memset([contents mutableBytes], 'a', [contents length]);
  NSData *path = [self pathDataForFile:@"million-a" contents:contents];
  NSDictionary *hashes = [LDHasher hashesForFileAtPath:path error:NULL];
  XCTAssertEqualObjects(@"34aa973cd4c4daa4f61eeb2bdbad27316534016f", [hashes objectForKey:@"SHA1"]);
}

- (void)testMissingFileReportsPOSIXError
{
  NSString *missing = [[self temporaryRoot] stringByAppendingPathComponent:@"missing"];
  const char *bytes = [missing fileSystemRepresentation];
  NSError *error = nil;
  NSDictionary *hashes = [LDHasher hashesForFileAtPath:[NSData dataWithBytes:bytes length:strlen(bytes)] error:&error];
  XCTAssertNil(hashes);
  XCTAssertEqualObjects(NSPOSIXErrorDomain, [error domain]);
  XCTAssertEqual((NSInteger)ENOENT, [error code]);
}

- (void)testDuplicateDigestIsTruncatedSHA512
{
  NSData *path = [self pathDataForFile:@"abc.txt" contents:[@"abc" dataUsingEncoding:NSASCIIStringEncoding]];
  NSData *digest = [LDHasher duplicateDigestForFileAtPath:path byteLimit:ULLONG_MAX error:NULL];
  XCTAssertEqual((NSUInteger)16, [digest length]);
  XCTAssertEqualObjects(@"ddaf35a193617abacc417349ae204131", [LDHasher hexStringForData:digest]);
}

- (void)testDuplicateDigestHonoursByteLimit
{
  NSData *path = [self pathDataForFile:@"abcdef.txt" contents:[@"abcdef" dataUsingEncoding:NSASCIIStringEncoding]];
  NSData *prefix = [LDHasher duplicateDigestForFileAtPath:path byteLimit:3 error:NULL];
  NSData *whole = [LDHasher duplicateDigestForFileAtPath:path byteLimit:ULLONG_MAX error:NULL];
  XCTAssertEqualObjects(@"ddaf35a193617abacc417349ae204131", [LDHasher hexStringForData:prefix]);
  XCTAssertFalse([prefix isEqualToData:whole]);
}

- (void)testCancelledDigestFails
{
  NSData *path = [self pathDataForFile:@"abc.txt" contents:[@"abc" dataUsingEncoding:NSASCIIStringEncoding]];
  int cancelled = 1;
  NSError *error = nil;
  NSData *digest = [LDHasher duplicateDigestForFileAtPath:path byteLimit:ULLONG_MAX cancelled:&cancelled error:&error];
  XCTAssertNil(digest);
  XCTAssertEqual((NSInteger)ECANCELED, [error code]);
}

- (void)testHexStringIsLowercase
{
  const uint8_t bytes[] = { 0x00, 0xab, 0xff, 0x10 };
  XCTAssertEqualObjects(@"00abff10", [LDHasher hexStringForData:[NSData dataWithBytes:bytes length:sizeof(bytes)]]);
  XCTAssertEqualObjects(@"", [LDHasher hexStringForData:[NSData data]]);
}

@end
