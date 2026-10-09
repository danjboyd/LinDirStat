#import <Foundation/Foundation.h>

@class LDFileNode;

// WinDirStat's Attributes and Owner columns, mapped to Linux.
@interface LDFileAttributes : NSObject

// WinDirStat's attribute letters, in its order RHSACEOZ. On Linux only R
// (owner-write bit clear, files and folders only) and H (name starts with
// '.') can appear. Empty when the node's mode is unknown (0).
+ (NSString *)attributeStringForNode:(LDFileNode *)node;

// The owning user's name for path (lstat, so a symlink's own owner), or the
// numeric uid when it has no passwd entry; nil if lstat fails. Uid lookups
// are cached; safe to call from any thread.
+ (NSString *)ownerOfPath:(NSData *)pathData;

@end
