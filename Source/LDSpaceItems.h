#import <Foundation/Foundation.h>
#import "LDFileNode.h"

// Reads the size and free space of the volume whose root is volume. Returns
// NO when they cannot be read (a loaded tree from another machine).
typedef BOOL (^LDVolumeUsageQuery)(LDFileNode *volume, unsigned long long *totalBytes, unsigned long long *freeBytes);

// WinDirStat's "<Free Space>" and "<Unknown>" pseudo-files (Options › Show
// Free Space / Show Unknown; Item.Extended.cpp CreateFreeSpaceItem,
// UpdateFreeSpaceItem, CreateUnknownItem, UpdateUnknownItem). They are real
// children of each volume root, so totals and percentages include them.
@interface LDSpaceItems : NSObject

// The volume roots of a tree: each folder below a "This Computer" root, or
// else the root itself when it is the root of a filesystem. Volumes that
// already hold space items (a loaded CSV) are included too.
+ (NSArray *)volumeNodesOfRoot:(LDFileNode *)root;
// As above, deciding for a plain root with isVolumeRoot.
+ (NSArray *)volumeNodesOfRoot:(LDFileNode *)root isVolumeRoot:(BOOL (^)(LDFileNode *node))isVolumeRoot;

// The volume's <Free Space> (LDFileNodeKindFreeSpace) or <Unknown> child.
+ (LDFileNode *)spaceItemOfKind:(LDFileNodeKind)kind inVolume:(LDFileNode *)volume;

// Removes the items that are turned off and creates the ones turned on with
// fresh sizes: free space is the volume's free bytes, unknown is the used
// bytes (total - free) the tree does not account for, never below 0. Items
// of a volume whose usage cannot be read are left as they are. Totals are
// updated upward and children re-sorted for metric. Returns the removed
// items: views may still hold them until they reload.
+ (NSArray *)updateVolumes:(NSArray *)volumes
             showFreeSpace:(BOOL)showFreeSpace
               showUnknown:(BOOL)showUnknown
                     usage:(LDVolumeUsageQuery)usage
                    metric:(LDSizeMetric)metric;

// statvfs on the volume's path (+[LDVolumes getTotalBytes:freeBytes:forPathData:]).
+ (LDVolumeUsageQuery)diskUsageQuery;

@end
