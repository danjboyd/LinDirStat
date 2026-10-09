#import <Foundation/Foundation.h>

@class LDFileNode;

// macOS privacy protection (TCC) hides some folders (Mail, Safari, other
// apps' containers...) from apps without Full Disk Access. Reading them fails
// with EPERM, where ordinary Unix permissions fail with EACCES.
@interface LDPrivacyAccess : NSObject

// NO only when macOS reports that this process lacks Full Disk Access. YES
// when it has it, cannot tell, or the platform has no such protection.
+ (BOOL)hasFullDiskAccess;

// The directories under root that could not be read because of EPERM, in
// tree order, at most limit of them.
+ (NSArray *)directoriesDeniedByPrivacyUnder:(LDFileNode *)root limit:(NSUInteger)limit;

@end
