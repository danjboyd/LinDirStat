#import <Foundation/Foundation.h>
#import "LDFileNode.h"

// WinDirStat's Largest Files tab (FileTopControl.cpp).
@interface LDLargestFiles : NSObject

// Up to count files below root ranked by logical size, largest first, ties by
// path bytes. Directories, special files, hard-link duplicates and entries
// that failed to stat are left out. O(n log count).
+ (NSArray *)largestFilesUnderNode:(LDFileNode *)root count:(NSUInteger)count;

// Whether node can appear in the list.
+ (BOOL)isRankableFile:(LDFileNode *)node;

@end
