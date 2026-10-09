#import <Foundation/Foundation.h>

// File digests via GNU Nettle. Paths are exact filesystem bytes (as from
// -[LDFileNode pathData], no terminating NUL); symlinks are followed, so the
// file the path names is hashed. Errors are NSPOSIXErrorDomain with errno.
@interface LDHasher : NSObject

// WinDirStat's Compute Hash order: MD5, SHA1, SHA256, SHA384, SHA512.
+ (NSArray *)hashAlgorithmNames;

// Every algorithm in one streaming pass, keyed by the names above, as
// lowercase hex.
+ (NSDictionary *)hashesForFileAtPath:(NSData *)path error:(NSError **)error;

// WinDirStat's duplicate hash: SHA-512 of the first limit bytes
// (ULLONG_MAX for the whole file), truncated to 16 bytes.
+ (NSData *)duplicateDigestForFileAtPath:(NSData *)path
                               byteLimit:(unsigned long long)limit
                                   error:(NSError **)error;
// As above, giving up with ECANCELED between reads once *cancelled is
// non-zero, so huge files do not delay cancellation.
+ (NSData *)duplicateDigestForFileAtPath:(NSData *)path
                               byteLimit:(unsigned long long)limit
                               cancelled:(const int *)cancelled
                                   error:(NSError **)error;

+ (NSString *)hexStringForData:(NSData *)data;

@end
