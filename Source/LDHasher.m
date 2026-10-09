#import "LDHasher.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#if defined(__APPLE__)
// CommonCrypto behind Nettle's names, so the code below is shared. Like
// Nettle, a digest shorter than the full size is truncated.
#include <CommonCrypto/CommonDigest.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#define LD_CC_DIGEST(name, ctx, prefix, size)                                     \
  struct name##_ctx { ctx c; };                                                   \
  static inline void name##_init(struct name##_ctx *x) { prefix##_Init(&x->c); }  \
  static inline void name##_update(struct name##_ctx *x, size_t n, const uint8_t *b) \
  {                                                                               \
    while (n > 0) {                                                               \
      CC_LONG chunk = n > 0x40000000 ? 0x40000000 : (CC_LONG)n;                   \
      prefix##_Update(&x->c, b, chunk);                                           \
      b += chunk;                                                                 \
      n -= chunk;                                                                 \
    }                                                                             \
  }                                                                               \
  static inline void name##_digest(struct name##_ctx *x, size_t n, uint8_t *out)  \
  {                                                                               \
    uint8_t full[size];                                                           \
    prefix##_Final(full, &x->c);                                                  \
    memcpy(out, full, n < size ? n : size);                                       \
  }
#define MD5_DIGEST_SIZE CC_MD5_DIGEST_LENGTH
#define SHA1_DIGEST_SIZE CC_SHA1_DIGEST_LENGTH
#define SHA256_DIGEST_SIZE CC_SHA256_DIGEST_LENGTH
#define SHA384_DIGEST_SIZE CC_SHA384_DIGEST_LENGTH
#define SHA512_DIGEST_SIZE CC_SHA512_DIGEST_LENGTH
LD_CC_DIGEST(md5, CC_MD5_CTX, CC_MD5, CC_MD5_DIGEST_LENGTH)
LD_CC_DIGEST(sha1, CC_SHA1_CTX, CC_SHA1, CC_SHA1_DIGEST_LENGTH)
LD_CC_DIGEST(sha256, CC_SHA256_CTX, CC_SHA256, CC_SHA256_DIGEST_LENGTH)
LD_CC_DIGEST(sha384, CC_SHA512_CTX, CC_SHA384, CC_SHA384_DIGEST_LENGTH)
LD_CC_DIGEST(sha512, CC_SHA512_CTX, CC_SHA512, CC_SHA512_DIGEST_LENGTH)
#pragma clang diagnostic pop
#else
#include <nettle/md5.h>
#include <nettle/sha1.h>
#include <nettle/sha2.h>
#endif

enum { LDHashReadSize = 64 * 1024 };
enum { LDDuplicateDigestLength = 16 };

static NSError *LDPOSIXError(int code, NSData *path)
{
  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  [info setObject:[NSString stringWithUTF8String:strerror(code)] forKey:NSLocalizedDescriptionKey];
  NSString *displayPath = [[NSString alloc] initWithData:path encoding:NSUTF8StringEncoding];
  if (displayPath) {
    [info setObject:displayPath forKey:NSFilePathErrorKey];
  }
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:info];
}

static int LDOpenPath(NSData *path)
{
  NSUInteger length = [path length];
  char *terminated = malloc(length + 1);
  memcpy(terminated, [path bytes], length);
  terminated[length] = '\0';
  int descriptor = open(terminated, O_RDONLY | O_CLOEXEC);
  int savedErrno = errno;
  free(terminated);
  errno = savedErrno;
  return descriptor;
}

// Feeds up to limit bytes of the file to consume in 64 KiB chunks.
static BOOL LDReadFile(NSData *path,
                       unsigned long long limit,
                       const int *cancelled,
                       void (^consume)(const uint8_t *bytes, size_t length),
                       NSError **error)
{
  int descriptor = LDOpenPath(path);
  if (descriptor < 0) {
    if (error) {
      *error = LDPOSIXError(errno, path);
    }
    return NO;
  }
  uint8_t *buffer = malloc(LDHashReadSize);
  unsigned long long remaining = limit;
  int failure = 0;
  while (remaining > 0) {
    if (cancelled && __atomic_load_n(cancelled, __ATOMIC_RELAXED)) {
      failure = ECANCELED;
      break;
    }
    size_t wanted = remaining < LDHashReadSize ? (size_t)remaining : LDHashReadSize;
    ssize_t got = read(descriptor, buffer, wanted);
    if (got < 0) {
      if (errno == EINTR) {
        continue;
      }
      failure = errno;
      break;
    }
    if (got == 0) {
      break;
    }
    consume(buffer, (size_t)got);
    remaining -= (unsigned long long)got;
  }
  free(buffer);
  close(descriptor);
  if (failure != 0) {
    if (error) {
      *error = LDPOSIXError(failure, path);
    }
    return NO;
  }
  return YES;
}

@implementation LDHasher

+ (NSArray *)hashAlgorithmNames
{
  return [NSArray arrayWithObjects:@"MD5", @"SHA1", @"SHA256", @"SHA384", @"SHA512", nil];
}

+ (NSDictionary *)hashesForFileAtPath:(NSData *)path error:(NSError **)error
{
  __block struct md5_ctx md5;
  __block struct sha1_ctx sha1;
  __block struct sha256_ctx sha256;
  __block struct sha384_ctx sha384;
  __block struct sha512_ctx sha512;
  md5_init(&md5);
  sha1_init(&sha1);
  sha256_init(&sha256);
  sha384_init(&sha384);
  sha512_init(&sha512);
  BOOL read = LDReadFile(path, ULLONG_MAX, NULL, ^(const uint8_t *bytes, size_t length) {
    md5_update(&md5, length, bytes);
    sha1_update(&sha1, length, bytes);
    sha256_update(&sha256, length, bytes);
    sha384_update(&sha384, length, bytes);
    sha512_update(&sha512, length, bytes);
  }, error);
  if (!read) {
    return nil;
  }
  uint8_t md5Digest[MD5_DIGEST_SIZE];
  uint8_t sha1Digest[SHA1_DIGEST_SIZE];
  uint8_t sha256Digest[SHA256_DIGEST_SIZE];
  uint8_t sha384Digest[SHA384_DIGEST_SIZE];
  uint8_t sha512Digest[SHA512_DIGEST_SIZE];
  md5_digest(&md5, sizeof(md5Digest), md5Digest);
  sha1_digest(&sha1, sizeof(sha1Digest), sha1Digest);
  sha256_digest(&sha256, sizeof(sha256Digest), sha256Digest);
  sha384_digest(&sha384, sizeof(sha384Digest), sha384Digest);
  sha512_digest(&sha512, sizeof(sha512Digest), sha512Digest);
  NSArray *digests = [NSArray arrayWithObjects:
    [NSData dataWithBytes:md5Digest length:sizeof(md5Digest)],
    [NSData dataWithBytes:sha1Digest length:sizeof(sha1Digest)],
    [NSData dataWithBytes:sha256Digest length:sizeof(sha256Digest)],
    [NSData dataWithBytes:sha384Digest length:sizeof(sha384Digest)],
    [NSData dataWithBytes:sha512Digest length:sizeof(sha512Digest)],
    nil];
  NSArray *names = [self hashAlgorithmNames];
  NSMutableDictionary *hashes = [NSMutableDictionary dictionaryWithCapacity:[names count]];
  for (NSUInteger index = 0; index < [names count]; index++) {
    [hashes setObject:[self hexStringForData:[digests objectAtIndex:index]] forKey:[names objectAtIndex:index]];
  }
  return hashes;
}

+ (NSData *)duplicateDigestForFileAtPath:(NSData *)path
                               byteLimit:(unsigned long long)limit
                                   error:(NSError **)error
{
  return [self duplicateDigestForFileAtPath:path byteLimit:limit cancelled:NULL error:error];
}

+ (NSData *)duplicateDigestForFileAtPath:(NSData *)path
                               byteLimit:(unsigned long long)limit
                               cancelled:(const int *)cancelled
                                   error:(NSError **)error
{
  __block struct sha512_ctx context;
  sha512_init(&context);
  BOOL read = LDReadFile(path, limit, cancelled, ^(const uint8_t *bytes, size_t length) {
    sha512_update(&context, length, bytes);
  }, error);
  if (!read) {
    return nil;
  }
  uint8_t digest[LDDuplicateDigestLength];
  // Nettle truncates when asked for fewer bytes than the full digest.
  sha512_digest(&context, sizeof(digest), digest);
  return [NSData dataWithBytes:digest length:sizeof(digest)];
}

+ (NSString *)hexStringForData:(NSData *)data
{
  static const char digits[] = "0123456789abcdef";
  NSUInteger length = [data length];
  const uint8_t *bytes = [data bytes];
  char *hex = malloc(length * 2 + 1);
  for (NSUInteger index = 0; index < length; index++) {
    hex[index * 2] = digits[bytes[index] >> 4];
    hex[index * 2 + 1] = digits[bytes[index] & 0x0f];
  }
  hex[length * 2] = '\0';
  NSString *string = [NSString stringWithUTF8String:hex];
  free(hex);
  return string;
}

@end
